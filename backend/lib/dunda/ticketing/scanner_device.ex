defmodule Dunda.Ticketing.ScannerDevice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "scanner_devices" do
    field :device_name, :string
    field :device_public_key, :binary
    field :key_fingerprint, :string
    field :status, :string, default: "active"
    field :last_seen_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :revocation_reason, :string
    belongs_to :organisation, Dunda.Organisations.Organisation
    belongs_to :event, Dunda.Events.Event
    belongs_to :operator, Dunda.Accounts.User, foreign_key: :operator_user_id
    has_many :admissions, Dunda.Ticketing.ScannerAdmission
    timestamps()
  end

  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :organisation_id,
      :event_id,
      :operator_user_id,
      :device_name,
      :device_public_key,
      :key_fingerprint,
      :status,
      :last_seen_at,
      :revoked_at,
      :revocation_reason
    ])
    |> validate_required([
      :organisation_id,
      :operator_user_id,
      :device_name,
      :device_public_key,
      :key_fingerprint,
      :status
    ])
    |> validate_length(:device_name, min: 1, max: 120)
    |> validate_length(:key_fingerprint, min: 16, max: 128)
    |> validate_inclusion(:status, ~w(active suspended revoked))
    |> validate_change(:device_public_key, fn :device_public_key, key ->
      if is_binary(key) and byte_size(key) == 32,
        do: [],
        else: [device_public_key: "must be a 32-byte Ed25519 key"]
    end)
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:operator)
    |> assoc_constraint(:event)
    |> unique_constraint(:key_fingerprint)
  end
end
