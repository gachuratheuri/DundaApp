defmodule Dunda.Repo.Migrations.AddTransactionIdToTickets do
  @moduledoc """
  Ties issued tickets to the M-Pesa transaction that paid for them, giving the
  fulfillment worker an exactly-once guard: an Oban retry (or a callback and a
  dead-letter poll racing) can check for existing tickets by `transaction_id`
  instead of guessing from user/event counts.
  """
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :transaction_id, :string
    end

    create index(:tickets, [:transaction_id])
  end
end
