defmodule Dunda.Repo.Migrations.ExtendTicketsAndCreateScans do
  @moduledoc """
  Closes two production gaps in the wallet + gate-entry lifecycle:

  * `tickets` gains a real `tier_id` (replacing the free-text `tier_label`
    crutch), the `holder_name` the Ticket Vault prints (currently hardcoded in
    `TicketJSON`), the `checked_in_at` timestamp set on first admission, and a
    `transferred_from_user_id` provenance pointer for resale transfers.
  * `ticket_scans` is the append-only admission audit log surfaced in the portal
    `TicketsLive` scan log. A partial unique index enforces that a ticket can be
    *admitted* at most once, while still recording every (including rejected and
    duplicate) scan attempt for fraud analysis.
  """
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :tier_id, references(:ticket_tiers, on_delete: :nilify_all)
      add :holder_name, :string
      add :checked_in_at, :utc_datetime
      add :transferred_from_user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:tickets, [:tier_id])
    create constraint(:tickets, :tickets_price_kes_non_negative, check: "price_kes >= 0")

    create table(:ticket_scans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      # Staff/device that performed the scan (nil for offline cached scans).
      add :scanner_id, references(:users, on_delete: :nilify_all)
      add :result, :string, null: false
      add :gate, :string
      add :reason, :string
      add :scanned_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create index(:ticket_scans, [:ticket_id])
    create index(:ticket_scans, [:event_id, :scanned_at])

    # A ticket may be admitted exactly once; rejected/duplicate rows are unbounded.
    create unique_index(:ticket_scans, [:ticket_id],
             where: "result = 'admitted'",
             name: :ticket_scans_single_admission_index
           )

    create constraint(:ticket_scans, :ticket_scans_result_valid,
             check: "result IN ('admitted', 'rejected', 'duplicate')"
           )
  end
end
