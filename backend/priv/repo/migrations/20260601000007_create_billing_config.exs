defmodule Dunda.Repo.Migrations.CreateBillingConfig do
  use Ecto.Migration

  def change do
    create table(:billing_config) do
      add :key, :string, null: false
      add :value, :string, null: false
      timestamps()
    end

    # Single-row-per-key store (Priority 3 in the IPN id resolution chain).
    create unique_index(:billing_config, [:key])
  end
end
