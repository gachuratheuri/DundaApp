defmodule Dunda.Organisations do
  @moduledoc """
  Write/read context for `Organisation` rows — the keystone that the scraper,
  the catalogue and payouts all read from.

  Writes go to the primary `Repo`; the scraper dispatcher reads through the
  replica (`ReadRepo`) since dispatch is a read-only fan-out.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Organisations.Organisation
  alias Dunda.Organisations.OrganisationMember
  alias Dunda.{ReadRepo, Repo}

  @permission_roles %{
    manage_organisation: ~w(owner),
    manage_members: ~w(owner admin),
    manage_payouts: ~w(owner),
    manage_events: ~w(owner admin manager),
    manage_inventory: ~w(owner admin manager),
    configure_scraper: ~w(owner admin),
    view_reports: ~w(owner admin manager member),
    admission: ~w(owner admin scanner)
  }

  @portal_roles ~w(owner admin manager)

  @spec list_organisations() :: [Organisation.t()]
  def list_organisations do
    Organisation |> from(order_by: [asc: :name]) |> ReadRepo.all()
  end

  @doc "Lists only organisations for which the user has an accepted membership."
  @spec list_organisations_for_user(integer()) :: [Organisation.t()]
  def list_organisations_for_user(user_id) do
    from(o in Organisation,
      join: m in OrganisationMember,
      on: m.organisation_id == o.id,
      where: m.user_id == ^user_id and not is_nil(m.accepted_at),
      order_by: [asc: o.name],
      distinct: true
    )
    |> ReadRepo.all()
  end

  @doc "Lists organisations for which the user holds one of the supplied active roles."
  def list_organisations_for_user(user_id, roles) when is_list(roles) do
    from(o in Organisation,
      join: m in OrganisationMember,
      on: m.organisation_id == o.id,
      where: m.user_id == ^user_id and not is_nil(m.accepted_at) and m.role in ^roles,
      order_by: [asc: o.name],
      distinct: true
    )
    |> Repo.all()
  end

  @doc "Roles permitted to enter the current mutation-capable organiser portal."
  def portal_roles, do: @portal_roles

  @doc "Authorises a domain action against one explicit organisation tenant."
  @spec authorised?(integer(), integer(), atom()) :: boolean()
  def authorised?(user_id, organisation_id, permission) do
    case Map.fetch(@permission_roles, permission) do
      {:ok, roles} -> member?(user_id, organisation_id, roles)
      :error -> false
    end
  end

  @doc "Returns whether a user has an accepted membership with the requested role."
  @spec member?(integer(), integer(), [String.t()]) :: boolean()
  def member?(user_id, organisation_id, roles \\ ~w(owner admin manager)) do
    from(m in OrganisationMember,
      where:
        m.user_id == ^user_id and m.organisation_id == ^organisation_id and
          not is_nil(m.accepted_at) and m.role in ^roles
    )
    |> Repo.exists?()
  end

  @doc "Creates an organisation and its owner membership atomically."
  @spec create_organisation_for_user(integer(), map()) ::
          {:ok, Organisation.t()} | {:error, term()}
  def create_organisation_for_user(user_id, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :organisation,
      Organisation.changeset(%Organisation{}, Map.put(attrs, :owner_user_id, user_id))
    )
    |> Ecto.Multi.insert(:membership, fn %{organisation: org} ->
      OrganisationMember.changeset(%OrganisationMember{}, %{
        organisation_id: org.id,
        user_id: user_id,
        role: "owner",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organisation: org}} -> {:ok, org}
      {:error, _operation, value, _changes} -> {:error, value}
    end
  end

  @doc "Organisations that are eligible for scraping (master switch on)."
  @spec scrapable_organisations() :: [Organisation.t()]
  def scrapable_organisations do
    Organisation
    |> from(where: [scraper_enabled: true])
    |> ReadRepo.all()
  end

  @spec get_organisation(integer() | String.t()) :: Organisation.t() | nil
  def get_organisation(id), do: Repo.get(Organisation, id)

  @spec get_organisation_by_slug(String.t()) :: Organisation.t() | nil
  def get_organisation_by_slug(slug), do: Repo.get_by(Organisation, slug: slug)

  @spec create_organisation(map()) :: {:ok, Organisation.t()} | {:error, Ecto.Changeset.t()}
  def create_organisation(attrs) do
    %Organisation{}
    |> Organisation.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_organisation(Organisation.t(), map()) ::
          {:ok, Organisation.t()} | {:error, Ecto.Changeset.t()}
  def update_organisation(%Organisation{} = org, attrs) do
    changeset = Organisation.changeset(org, attrs)
    step_up_token = Map.get(attrs, :step_up_token) || Map.get(attrs, "step_up_token")
    step_up = Dunda.Security.StepUp.verify(step_up_token || "", "payout_destination")

    if payout_phone_change?(attrs) and match?({:error, _}, step_up) do
      {:error,
       Ecto.Changeset.add_error(changeset, :mpesa_phone, "step-up authentication is required")}
    else
      case Repo.update(changeset) do
        {:ok, updated} = result ->
          if payout_phone_change?(attrs) do
            {:ok, actor_id} = step_up

            _ =
              Dunda.Audit.record(%{
                actor_user_id: actor_id,
                action: "organisation.payout_destination_changed",
                resource_type: "organisation",
                resource_id: to_string(updated.id),
                metadata: %{step_up_verified: true}
              })
          end

          result

        error ->
          error
      end
    end
  end

  @doc "Tenant- and permission-scoped organisation update."
  def update_organisation_for_user(user_id, %Organisation{} = org, attrs) do
    permission = if payout_phone_change?(attrs), do: :manage_payouts, else: :configure_scraper

    if authorised?(user_id, org.id, permission) do
      update_organisation(org, attrs)
    else
      {:error, :forbidden}
    end
  end

  @spec change_organisation(Organisation.t(), map()) :: Ecto.Changeset.t()
  def change_organisation(%Organisation{} = org, attrs \\ %{}) do
    Organisation.changeset(org, attrs)
  end

  defp payout_phone_change?(attrs),
    do: Map.has_key?(attrs, :mpesa_phone) or Map.has_key?(attrs, "mpesa_phone")
end
