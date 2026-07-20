defmodule Dunda.Repo.Migrations.Phase6SettlementResalePayouts do
  use Ecto.Migration

  def up do
    # Do not silently migrate plaintext payout destinations. An operator must
    # encrypt/export them with the configured vault and prove the backfill
    # before this destructive schema hardening is applied.
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM organisations WHERE mpesa_phone IS NOT NULL) OR
         EXISTS (SELECT 1 FROM payouts WHERE mpesa_phone IS NOT NULL) THEN
        RAISE EXCEPTION 'plaintext payout destinations require an audited vault backfill before Phase 6';
      END IF;
    END $$;
    """

    alter table(:organisations) do
      add :mpesa_phone_encrypted, :binary
    end

    alter table(:payouts) do
      add :mpesa_phone_encrypted, :binary
    end

    alter table(:organisations), do: remove(:mpesa_phone)
    alter table(:payouts), do: remove(:mpesa_phone)

    # Establish immutable face value before making the resale cap mandatory.
    execute """
    UPDATE resale_listings AS l
    SET face_value_kes = t.price_kes
    FROM tickets AS t
    WHERE l.ticket_id = t.id AND l.face_value_kes IS NULL
    """

    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM resale_listings WHERE face_value_kes IS NULL) THEN
        RAISE EXCEPTION 'cannot enforce resale face value: unresolved listing rows';
      END IF;
      IF EXISTS (
        SELECT ticket_id FROM resale_listings
        WHERE status = 'active'
        GROUP BY ticket_id HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION 'cannot enforce one active resale listing per ticket';
      END IF;
    END $$;
    """

    alter table(:resale_listings) do
      modify :face_value_kes, :integer, null: false
      add :payment_order_id, references(:orders, on_delete: :nilify_all)
    end

    create unique_index(:resale_listings, [:ticket_id],
             where: "status = 'active'",
             name: :resale_listings_active_ticket_unique
           )
    create unique_index(:resale_listings, [:payment_order_id],
             where: "payment_order_id IS NOT NULL",
             name: :resale_listings_payment_order_unique
           )
    create constraint(:resale_listings, :resale_face_value_positive, check: "face_value_kes >= 0")

    alter table(:orders) do
      add :kind, :string, null: false, default: "primary"
      add :resale_listing_id, references(:resale_listings, on_delete: :nilify_all)
      add :refund_status, :string, null: false, default: "none"
      add :refunded_amount_cents, :integer, null: false, default: 0
      add :refunded_at, :utc_datetime
    end

    create unique_index(:orders, [:resale_listing_id],
             where: "resale_listing_id IS NOT NULL",
             name: :orders_resale_listing_unique
           )
    create constraint(:orders, :orders_kind_valid, check: "kind IN ('primary', 'resale')")
    create constraint(:orders, :orders_resale_link_valid,
             check: "(kind = 'primary' AND resale_listing_id IS NULL) OR (kind = 'resale' AND resale_listing_id IS NOT NULL)"
           )
    create constraint(:orders, :orders_refund_status_valid,
             check: "refund_status IN ('none', 'pending', 'submitted', 'succeeded', 'failed', 'manual_review')"
           )
    create constraint(:orders, :orders_refunded_amount_valid, check: "refunded_amount_cents >= 0 AND refunded_amount_cents <= amount_cents")

    alter table(:tickets) do
      add :revoked_at, :utc_datetime
      add :revocation_reason, :string
      add :supersedes_ticket_id, references(:tickets, type: :binary_id, on_delete: :nilify_all)
      add :replaced_by_ticket_id, references(:tickets, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:tickets, [:supersedes_ticket_id])
    create unique_index(:tickets, [:replaced_by_ticket_id],
             where: "replaced_by_ticket_id IS NOT NULL",
             name: :tickets_replaced_by_unique
           )
    create constraint(:tickets, :tickets_status_valid,
             check: "status IN ('valid', 'transferred', 'scanned', 'revoked', 'refunded')"
           )
    create constraint(:tickets, :tickets_revoked_state_consistent,
             check: "(status IN ('revoked', 'refunded') AND revoked_at IS NOT NULL) OR status NOT IN ('revoked', 'refunded')"
           )

    create table(:refunds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, on_delete: :restrict), null: false
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :nilify_all)
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "KES"
      add :status, :string, null: false, default: "pending"
      add :reason, :string, null: false
      add :idempotency_key, :string, null: false
      add :provider_reference, :string
      add :failure_reason, :string
      add :submitted_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps()
    end

    create unique_index(:refunds, [:idempotency_key])
    create unique_index(:refunds, [:provider_reference], where: "provider_reference IS NOT NULL")
    create index(:refunds, [:order_id, :status])
    create constraint(:refunds, :refund_status_valid,
             check: "status IN ('pending', 'submitted', 'succeeded', 'failed', 'manual_review')"
           )
    create constraint(:refunds, :refund_amount_positive, check: "amount_cents > 0")

    create table(:refund_provider_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :refund_id, references(:refunds, on_delete: :restrict), null: false
      add :provider_event_id, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :outcome, :string
      add :received_at, :utc_datetime, null: false
      timestamps(updated_at: false)
    end

    create unique_index(:refund_provider_events, [:provider_event_id])
    create index(:refund_provider_events, [:refund_id])

    create table(:payout_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, on_delete: :restrict), null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "KES"
      add :status, :string, null: false, default: "pending"
      add :idempotency_key, :string, null: false
      add :b2c_conversation_id, :string
      add :b2c_receipt, :string
      add :failure_reason, :string
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime
      add :submission_started_at, :utc_datetime
      add :submitted_at, :utc_datetime
      add :paid_at, :utc_datetime
      timestamps()
    end

    create unique_index(:payout_batches, [:idempotency_key])
    create unique_index(:payout_batches, [:b2c_conversation_id], where: "b2c_conversation_id IS NOT NULL")
    create index(:payout_batches, [:organisation_id, :status])
    create constraint(:payout_batches, :payout_batch_status_valid,
             check: "status IN ('pending', 'submitting', 'submitted', 'paid', 'failed', 'manual_review')"
           )
    create constraint(:payout_batches, :payout_batch_amount_positive, check: "amount_cents > 0")

    create table(:payout_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payout_batch_id, references(:payout_batches, on_delete: :restrict), null: false
      add :order_id, references(:orders, on_delete: :restrict), null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "KES"
      add :status, :string, null: false, default: "queued"
      add :failure_reason, :string
      timestamps(updated_at: false)
    end

    # Failed/manual-review attempts remain historical; only an outstanding or
    # paid item blocks another assignment of the same payable order.
    create unique_index(:payout_items, [:order_id],
             where: "status IN ('queued', 'paid')",
             name: :payout_items_order_unique
           )
    create index(:payout_items, [:payout_batch_id, :status])
    create constraint(:payout_items, :payout_item_status_valid,
             check: "status IN ('queued', 'paid', 'failed', 'manual_review')"
           )
    create constraint(:payout_items, :payout_item_amount_positive, check: "amount_cents > 0")
  end

  def down do
    drop table(:payout_items)
    drop table(:payout_batches)
    drop table(:refund_provider_events)
    drop table(:refunds)

    drop constraint(:tickets, :tickets_status_valid)
    drop constraint(:tickets, :tickets_revoked_state_consistent)

    alter table(:tickets) do
      remove :replaced_by_ticket_id
      remove :supersedes_ticket_id
      remove :revocation_reason
      remove :revoked_at
    end

    alter table(:orders) do
      remove :refunded_at
      remove :refunded_amount_cents
      remove :refund_status
      remove :resale_listing_id
      remove :kind
    end

    alter table(:resale_listings) do
      remove :payment_order_id
      modify :face_value_kes, :integer, null: true
    end

    alter table(:organisations) do
      add :mpesa_phone, :string
      remove :mpesa_phone_encrypted
    end

    alter table(:payouts) do
      add :mpesa_phone, :string
      remove :mpesa_phone_encrypted
    end
  end
end
