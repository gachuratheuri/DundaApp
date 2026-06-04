defmodule Dunda.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :phone_msisdn, :binary, null: false
      add :phone_msisdn_hash, :binary, null: false
      add :kyc_status, :string, null: false, default: "unverified"
      add :device_fingerprint, :binary
      timestamps()
    end

    # Blind index over the deterministic HMAC enables equality lookups without
    # ever exposing the plaintext MSISDN.
    create unique_index(:users, [:phone_msisdn_hash])
  end
end
