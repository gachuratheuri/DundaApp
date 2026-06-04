defmodule Dunda.Repo.Migrations.CreateLedgerEntries do
  use Ecto.Migration

  def change do
    create table(:ledger_entries) do
      add :transaction_id, :string, null: false
      add :mpesa_receipt, :string, null: false
      add :amount_cents, :integer
      add :status, :string, null: false, default: "settled"
      timestamps(updated_at: false)
    end

    # Idempotency guarantees: a receipt or transaction can settle exactly once,
    # so a duplicated callback + dead-letter poll cannot double-credit.
    create unique_index(:ledger_entries, [:mpesa_receipt])
    create unique_index(:ledger_entries, [:transaction_id])
  end
end
