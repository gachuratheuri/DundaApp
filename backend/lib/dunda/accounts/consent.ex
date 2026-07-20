defmodule Dunda.Accounts.Consent do
  @moduledoc """
  A versioned consent record — only for processing whose lawful basis is
  consent (see `docs/data_inventory.md` § Processor register and
  `docs/dpia.md`). Checkout/ticketing processing in this codebase is
  contract-necessity, not consent; today the only consent-basis purpose is
  optional marketing notifications. Revocation is represented by
  `revoked_at`, never a row deletion — the historical grant/revocation record
  is itself the accountability evidence a DPIA/audit needs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}

  schema "consents" do
    field :purpose, :string
    field :version, :string
    field :granted_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, Dunda.Accounts.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [:user_id, :purpose, :version, :granted_at, :revoked_at])
    |> validate_required([:user_id, :purpose, :version, :granted_at])
    |> validate_length(:purpose, min: 1, max: 100)
    |> validate_length(:version, min: 1, max: 40)
    |> assoc_constraint(:user)
  end
end
