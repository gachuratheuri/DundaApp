defmodule Dunda.Repo.Migrations.Phase11Consents do
  use Ecto.Migration

  def up do
    create table(:consents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :purpose, :string, null: false
      add :version, :string, null: false
      add :granted_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      timestamps()
    end

    create index(:consents, [:user_id, :purpose])

    # An account may have granted the same purpose more than once across
    # versions (re-consent after a policy change), but never two
    # simultaneously-active (not-yet-revoked) grants for the same purpose —
    # that would make "is this purpose currently consented to" ambiguous.
    create index(:consents, [:user_id, :purpose],
             unique: true,
             where: "revoked_at IS NULL",
             name: :consents_one_active_grant_per_purpose
           )
  end
end
