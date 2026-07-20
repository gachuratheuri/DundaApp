defmodule Dunda.Organisations.OrganisationMember do
  @moduledoc """
  A team member of an organisation, representing RBAC (owner, admin, manager, scanner).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @roles ~w(owner admin manager scanner member)

  schema "organisation_members" do
    field :role, :string, default: "member"
    field :invited_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :organisation, Dunda.Organisations.Organisation
    belongs_to :user, Dunda.Accounts.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:role, :invited_at, :accepted_at, :organisation_id, :user_id])
    |> validate_required([:role, :organisation_id, :user_id])
    |> validate_inclusion(:role, @roles)
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:user)
    |> unique_constraint([:organisation_id, :user_id])
  end
end
