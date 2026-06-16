defmodule Dunda.Repo.Migrations.CreateLedgerTransfers do
  use Ecto.Migration

  def change do
    create table(:ledger_transfers) do
      add :from_account, :string, null: false
      add :to_account, :string, null: false
      add :amount_cents, :integer, null: false
      add :reference, :string, null: false
      timestamps(updated_at: false)
    end

    # Append-only internal money movement (e.g. resale payouts). The reference is
    # the idempotency key: replaying the same business event records exactly once.
    create unique_index(:ledger_transfers, [:reference])
  end
end
