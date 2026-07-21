defmodule Dunda.Organisations.Organisation do
  @moduledoc """
  The structural keystone of the Dunda Unified Architecture.

  A single `organisations` row simultaneously:

    * configures the scraper — the `*_id` columns are read on every cron tick by
      `Dunda.Workers.DispatchWorker.dynamic_targets_from_orgs/0`;
    * owns the events scraped/ingested under it (`events.organisation_id`);
    * holds the encrypted M-Pesa payout destination used by
      `Dunda.Workers.PayoutWorker` for B2C settlements.

  Editing a row in the Organiser Portal therefore reconfigures the live system
  with no deploy and no restart.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "organisations" do
    field :name, :string
    field :slug, :string

    # Scraper source configuration. A nil/blank id means "this source is not
    # connected" and the dispatcher skips it for this org.
    field :facebook_page_id, :string
    field :instagram_account_id, :string
    field :eventbrite_org_id, :string
    field :html_scrape_url, :string

    # Master switch — when false the org is excluded from dispatch entirely.
    field :scraper_enabled, :boolean, default: true

    # B2C payout destination is encrypted at rest. `mpesa_phone` is virtual so
    # forms may accept/display the value without persisting plaintext.
    field :mpesa_phone, :string, virtual: true
    field :mpesa_phone_encrypted, Dunda.Encrypted.Binary

    field :description, :string
    field :logo_url, :string
    field :support_email, :string
    field :mpesa_till_number, :string
    field :verification_status, :string, default: "pending"
    field :agreement_accepted_at, :utc_datetime
    field :country, :string, default: "KE"

    belongs_to :owner_user, Dunda.Accounts.User, foreign_key: :owner_user_id

    has_many :events, Dunda.Events.Event
    has_many :members, Dunda.Organisations.OrganisationMember
    has_many :payouts, Dunda.Organisations.Payout
    has_many :payout_batches, Dunda.Organisations.PayoutBatch

    timestamps()
  end

  @sources [:facebook_page_id, :instagram_account_id, :eventbrite_org_id, :html_scrape_url]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(org, attrs) do
    org
    |> cast(attrs, [
      :name,
      :slug,
      :facebook_page_id,
      :instagram_account_id,
      :eventbrite_org_id,
      :html_scrape_url,
      :scraper_enabled,
      :mpesa_phone_encrypted,
      :description,
      :logo_url,
      :support_email,
      :mpesa_till_number,
      :verification_status,
      :agreement_accepted_at,
      :country,
      :owner_user_id
    ])
    |> validate_required([:name, :slug, :verification_status, :country])
    |> update_change(:slug, &normalise_slug/1)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "lowercase letters, digits and hyphens only"
    )
    |> put_payout_phone(attrs)
    |> validate_format(:mpesa_phone, ~r/^2547\d{8}$/,
      message: "must be a Safaricom MSISDN like 2547XXXXXXXX"
    )
    |> validate_inclusion(:verification_status, ["pending", "verified", "suspended"])
    |> normalise_blanks(@sources)
    |> unique_constraint(:slug)
  end

  defp normalise_slug(nil), do: nil

  defp normalise_slug(slug) do
    slug
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  # Coerce empty strings to nil so "not connected" is represented consistently.
  defp normalise_blanks(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      case get_change(acc, field) do
        "" -> put_change(acc, field, nil)
        value when is_binary(value) -> put_change(acc, field, String.trim(value))
        _ -> acc
      end
    end)
  end

  defp put_payout_phone(changeset, attrs) do
    supplied = Map.get(attrs, :mpesa_phone) || Map.get(attrs, "mpesa_phone")
    current = get_field(changeset, :mpesa_phone_encrypted)
    phone = if is_nil(supplied), do: current, else: supplied

    if is_binary(phone) do
      put_change(changeset, :mpesa_phone, String.trim(phone))
      |> put_change(:mpesa_phone_encrypted, String.trim(phone))
    else
      changeset
    end
  end
end
