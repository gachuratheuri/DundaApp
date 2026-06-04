defmodule Dunda.Repo.Migrations.AddAuthToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :email, :string
      add :hashed_password, :string
      add :name, :string
      add :avatar_url, :string
      # "phone" | "email" | "google" | "apple" | ...
      add :auth_provider, :string, null: false, default: "phone"
      add :provider_uid, :string
      add :confirmed_at, :utc_datetime
    end

    # Independent (email/OAuth) users may have no phone yet.
    execute(
      "ALTER TABLE users ALTER COLUMN phone_msisdn DROP NOT NULL",
      "ALTER TABLE users ALTER COLUMN phone_msisdn SET NOT NULL"
    )

    execute(
      "ALTER TABLE users ALTER COLUMN phone_msisdn_hash DROP NOT NULL",
      "ALTER TABLE users ALTER COLUMN phone_msisdn_hash SET NOT NULL"
    )

    create unique_index(:users, [:email])
    create unique_index(:users, [:auth_provider, :provider_uid], where: "provider_uid IS NOT NULL")
  end
end
