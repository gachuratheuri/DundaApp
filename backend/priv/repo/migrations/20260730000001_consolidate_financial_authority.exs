defmodule Dunda.Repo.Migrations.ConsolidateFinancialAuthority do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :auth_version, :integer, null: false, default: 1
    end

    create constraint(:users, :users_auth_version_positive, check: "auth_version > 0")

    create table(:refresh_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :family_id, :binary_id, null: false
      add :token_hash, :binary, null: false
      add :device_id, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :reuse_detected_at, :utc_datetime
      add :replaced_by_id, references(:refresh_tokens, type: :binary_id, on_delete: :nilify_all)
      timestamps()
    end

    create unique_index(:refresh_tokens, [:token_hash])
    create index(:refresh_tokens, [:user_id, :device_id])
    create index(:refresh_tokens, [:family_id])
    create index(:refresh_tokens, [:expires_at], where: "revoked_at IS NULL")
    create constraint(:refresh_tokens, :refresh_tokens_expiry_order, check: "expires_at > inserted_at")

    alter table(:provider_events) do
      add :payload_encrypted, :binary
    end

    create unique_index(:payment_line_items, [:payment_intent_id],
             name: :payment_line_items_single_line_per_intent
           )

    execute """
    CREATE OR REPLACE FUNCTION dunda_payment_intent_state_guard()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.version <= OLD.version THEN
        RAISE EXCEPTION 'payment intent version must increase';
      END IF;

      IF NEW.state = OLD.state OR
        (OLD.state = 'created' AND NEW.state IN ('inventory_reserved','failed','manual_review')) OR
        (OLD.state = 'inventory_reserved' AND NEW.state IN ('provider_submission_pending','failed','expired_pending_reconciliation','manual_review')) OR
        (OLD.state = 'provider_submission_pending' AND NEW.state IN ('provider_pending','failed','manual_review')) OR
        (OLD.state = 'provider_pending' AND NEW.state IN ('confirmed','failed','expired_pending_reconciliation','confirmed_late','manual_review','refund_pending')) OR
        (OLD.state = 'confirmed' AND NEW.state IN ('fulfilled','refund_pending','manual_review')) OR
        (OLD.state = 'fulfilled' AND NEW.state IN ('refund_pending','manual_review')) OR
        (OLD.state = 'failed' AND NEW.state IN ('manual_review')) OR
        (OLD.state = 'expired_pending_reconciliation' AND NEW.state IN ('confirmed_late','manual_review','refund_pending')) OR
        (OLD.state = 'confirmed_late' AND NEW.state IN ('fulfilled','refund_pending','manual_review')) OR
        (OLD.state = 'manual_review' AND NEW.state IN ('confirmed_late','refund_pending')) OR
        (OLD.state = 'refund_pending' AND NEW.state IN ('refunded','manual_review'))
      THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'invalid payment_intent transition: % -> %', OLD.state, NEW.state;
    END;
    $$ LANGUAGE plpgsql;
    """

    alter table(:tickets) do
      add :price_cents, :bigint
    end

    execute "UPDATE tickets SET price_cents = price_kes * 100 WHERE price_cents IS NULL"
    alter table(:tickets), do: modify(:price_cents, :bigint, null: false)
    alter table(:tickets), do: remove(:price_kes)

    alter table(:resale_listings) do
      add :asking_price_cents, :bigint
      add :face_value_cents, :bigint
    end

    execute """
    UPDATE resale_listings
    SET asking_price_cents = asking_price_kes * 100,
        face_value_cents = face_value_kes * 100
    WHERE asking_price_cents IS NULL OR face_value_cents IS NULL
    """

    alter table(:resale_listings) do
      modify :asking_price_cents, :bigint, null: false
      modify :face_value_cents, :bigint, null: false
    end

    create constraint(:resale_listings, :resale_price_cents_valid,
             check:
               "asking_price_cents >= 0 AND face_value_cents >= 0 AND asking_price_cents <= face_value_cents"
           )

    drop constraint(:resale_listings, :resale_asking_non_negative)
    drop constraint(:resale_listings, :resale_price_capped_at_face_value)
    drop constraint(:resale_listings, :resale_face_value_positive)

    alter table(:resale_listings) do
      remove :asking_price_kes
      remove :face_value_kes
    end

    create table(:payable_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :journal_transaction_id,
          references(:journal_transactions, type: :binary_id, on_delete: :restrict),
          null: false

      add :organisation_id, references(:organisations, on_delete: :restrict)
      add :beneficiary_user_id, references(:users, on_delete: :restrict)
      add :source_type, :string, null: false
      add :source_id, :string, null: false
      add :amount_cents, :bigint, null: false
      add :refunded_cents, :bigint, null: false, default: 0
      add :currency, :string, null: false
      add :status, :string, null: false, default: "payable"
      add :paid_at, :utc_datetime
      add :manual_review_reason, :string
      timestamps()
    end

    create unique_index(:payable_entries, [:source_type, :source_id],
             name: :payable_entries_source_unique
           )

    create index(:payable_entries, [:organisation_id, :status])
    create index(:payable_entries, [:beneficiary_user_id, :status])

    create constraint(:payable_entries, :payable_entries_beneficiary_xor,
             check:
               "(organisation_id IS NOT NULL AND beneficiary_user_id IS NULL) OR " <>
                 "(organisation_id IS NULL AND beneficiary_user_id IS NOT NULL)"
           )

    create constraint(:payable_entries, :payable_entries_amount_valid,
             check: "amount_cents > 0 AND refunded_cents >= 0 AND refunded_cents <= amount_cents"
           )

    create constraint(:payable_entries, :payable_entries_source_valid,
             check: "source_type IN ('payment_intent', 'resale_order')"
           )

    create constraint(:payable_entries, :payable_entries_status_valid,
             check: "status IN ('payable', 'queued', 'paid', 'refunded', 'manual_review')"
           )

    alter table(:payout_batches) do
      modify :organisation_id, references(:organisations, on_delete: :restrict), null: true
      add :beneficiary_user_id, references(:users, on_delete: :restrict)
    end

    create index(:payout_batches, [:beneficiary_user_id, :status])

    create constraint(:payout_batches, :payout_batches_beneficiary_xor,
             check:
               "(organisation_id IS NOT NULL AND beneficiary_user_id IS NULL) OR " <>
                 "(organisation_id IS NULL AND beneficiary_user_id IS NOT NULL)"
           )

    alter table(:payout_items) do
      modify :order_id, references(:orders, on_delete: :restrict), null: true
      add :payable_entry_id,
          references(:payable_entries, type: :binary_id, on_delete: :restrict)
    end

    create index(:payout_items, [:payable_entry_id])

    create unique_index(:payout_items, [:payable_entry_id],
             where: "payable_entry_id IS NOT NULL AND status IN ('queued', 'paid')",
             name: :payout_items_payable_entry_unique
           )

    create constraint(:payout_items, :payout_items_source_present,
             check: "order_id IS NOT NULL OR payable_entry_id IS NOT NULL"
           )
  end
end
