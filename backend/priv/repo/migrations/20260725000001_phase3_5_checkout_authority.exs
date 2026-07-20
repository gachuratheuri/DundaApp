defmodule Dunda.Repo.Migrations.Phase3To5CheckoutAuthority do
  use Ecto.Migration

  @moduledoc """
  Additive Phase 3–5 authority model. Existing payment tables are retained for
  historical reconciliation; new checkout writes use these durable aggregates.
  """

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto"

    create table(:quotes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :ticket_tier_id, references(:ticket_tiers, on_delete: :restrict)
      add :quantity, :integer, null: false
      add :unit_price_cents, :integer, null: false
      add :fee_cents, :integer, null: false, default: 0
      add :total_cents, :integer, null: false
      add :currency, :string, null: false
      add :price_version, :string, null: false
      add :signature, :string, null: false
      add :status, :string, null: false, default: "active"
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime
      timestamps()
    end

    create index(:quotes, [:user_id, :status, :expires_at])
    create constraint(:quotes, :quotes_amounts_valid,
             check: "quantity > 0 AND unit_price_cents > 0 AND fee_cents >= 0 AND total_cents = (unit_price_cents * quantity) + fee_cents"
           )
    create constraint(:quotes, :quotes_status_valid,
             check: "status IN ('active', 'consumed', 'expired', 'cancelled')"
           )
    execute """
    CREATE OR REPLACE FUNCTION dunda_quote_immutable_guard() RETURNS trigger AS $$
    BEGIN
      IF NEW.user_id <> OLD.user_id OR NEW.event_id <> OLD.event_id OR NEW.ticket_tier_id IS DISTINCT FROM OLD.ticket_tier_id OR
         NEW.quantity <> OLD.quantity OR NEW.unit_price_cents <> OLD.unit_price_cents OR NEW.fee_cents <> OLD.fee_cents OR
         NEW.total_cents <> OLD.total_cents OR NEW.currency <> OLD.currency OR NEW.price_version <> OLD.price_version OR
         NEW.signature <> OLD.signature OR NEW.expires_at <> OLD.expires_at THEN
        RAISE EXCEPTION 'quote % immutable pricing/binding fields cannot change', OLD.id;
      END IF;
      IF OLD.status = 'consumed' AND NEW.status <> OLD.status THEN
        RAISE EXCEPTION 'consumed quote % cannot be reopened', OLD.id;
      END IF;
      RETURN NEW;
    END; $$ LANGUAGE plpgsql;
    CREATE TRIGGER quote_immutable_guard BEFORE UPDATE ON quotes
      FOR EACH ROW EXECUTE FUNCTION dunda_quote_immutable_guard();
    """

    create table(:payment_intents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :quote_id, references(:quotes, on_delete: :restrict), null: false
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :ticket_tier_id, references(:ticket_tiers, on_delete: :restrict)
      add :quantity, :integer, null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false
      add :phone, :string, null: false
      add :idempotency_key, :string, null: false
      add :state, :string, null: false, default: "created"
      add :provider, :string
      add :provider_checkout_id, :string
      add :redirect_url, :string
      add :provider_receipt, :string
      add :failure_reason, :string
      add :manual_review_reason, :string
      add :expires_at, :utc_datetime, null: false
      add :confirmed_at, :utc_datetime
      add :fulfilled_at, :utc_datetime
      add :version, :integer, null: false, default: 1
      timestamps()
    end

    create unique_index(:payment_intents, [:user_id, :idempotency_key], name: :payment_intents_user_idempotency_unique)
    create unique_index(:payment_intents, [:provider_checkout_id], where: "provider_checkout_id IS NOT NULL", name: :payment_intents_provider_checkout_unique)
    create unique_index(:payment_intents, [:provider_receipt], where: "provider_receipt IS NOT NULL", name: :payment_intents_provider_receipt_unique)
    create index(:payment_intents, [:state, :inserted_at])
    create constraint(:payment_intents, :payment_intents_state_valid,
             check: "state IN ('created', 'inventory_reserved', 'provider_submission_pending', 'provider_pending', 'confirmed', 'fulfilled', 'failed', 'expired_pending_reconciliation', 'confirmed_late', 'manual_review', 'refund_pending', 'refunded')"
           )
    create constraint(:payment_intents, :payment_intents_amount_valid, check: "quantity > 0 AND amount_cents > 0 AND version > 0")
    execute """
    CREATE OR REPLACE FUNCTION dunda_payment_intent_state_guard() RETURNS trigger AS $$
    BEGIN
      IF NEW.state = OLD.state THEN RETURN NEW; END IF;
      IF NOT (
        (OLD.state = 'created' AND NEW.state IN ('inventory_reserved','failed','manual_review')) OR
        (OLD.state = 'inventory_reserved' AND NEW.state IN ('provider_submission_pending','failed','expired_pending_reconciliation','manual_review')) OR
        (OLD.state = 'provider_submission_pending' AND NEW.state IN ('provider_pending','failed','manual_review')) OR
        (OLD.state = 'provider_pending' AND NEW.state IN ('confirmed','failed','expired_pending_reconciliation','confirmed_late','manual_review','refund_pending')) OR
        (OLD.state = 'confirmed' AND NEW.state IN ('fulfilled','refund_pending','manual_review')) OR
        (OLD.state = 'fulfilled' AND NEW.state IN ('refund_pending','refunded','manual_review')) OR
        (OLD.state = 'failed' AND NEW.state = 'manual_review') OR
        (OLD.state = 'expired_pending_reconciliation' AND NEW.state IN ('confirmed_late','manual_review','refund_pending')) OR
        (OLD.state = 'confirmed_late' AND NEW.state IN ('fulfilled','refund_pending','manual_review')) OR
        (OLD.state = 'manual_review' AND NEW.state IN ('confirmed_late','refund_pending','refunded')) OR
        (OLD.state = 'refund_pending' AND NEW.state IN ('refunded','manual_review'))
      ) THEN RAISE EXCEPTION 'invalid payment intent state transition % -> %', OLD.state, NEW.state; END IF;
      IF NEW.version <= OLD.version THEN RAISE EXCEPTION 'payment intent version must increase'; END IF;
      RETURN NEW;
    END; $$ LANGUAGE plpgsql;
    CREATE TRIGGER payment_intent_state_guard BEFORE UPDATE ON payment_intents
      FOR EACH ROW EXECUTE FUNCTION dunda_payment_intent_state_guard();
    """
    execute """
    CREATE OR REPLACE FUNCTION dunda_payment_quote_guard() RETURNS trigger AS $$
    DECLARE quote_quantity bigint; quote_total bigint; quote_currency text;
    BEGIN
      SELECT quantity, total_cents, currency INTO quote_quantity, quote_total, quote_currency
        FROM quotes WHERE id = NEW.quote_id;
      IF quote_quantity IS NULL OR NEW.quantity <> quote_quantity OR NEW.amount_cents <> quote_total OR NEW.currency <> quote_currency THEN
        RAISE EXCEPTION 'payment intent % does not match immutable quote %', NEW.id, NEW.quote_id;
      END IF;
      RETURN NEW;
    END; $$ LANGUAGE plpgsql;
    CREATE CONSTRAINT TRIGGER payment_intent_quote_guard
      AFTER INSERT OR UPDATE ON payment_intents
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION dunda_payment_quote_guard();
    """

    create table(:payment_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_intent_id, references(:payment_intents, on_delete: :restrict), null: false
      add :provider, :string, null: false
      add :attempt_key, :string, null: false
      add :provider_checkout_id, :string
      add :status, :string, null: false, default: "pending"
      add :request_payload, :map, null: false, default: %{}
      add :response_payload, :map
      add :failure_reason, :string
      add :submitted_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps()
    end

    create unique_index(:payment_attempts, [:attempt_key])
    create unique_index(:payment_attempts, [:provider, :provider_checkout_id], where: "provider_checkout_id IS NOT NULL", name: :payment_attempts_provider_checkout_unique)
    create index(:payment_attempts, [:payment_intent_id, :status])
    create constraint(:payment_attempts, :payment_attempt_status_valid,
             check: "status IN ('pending', 'submitted', 'succeeded', 'failed', 'manual_review')"
           )

    create table(:provider_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :provider_event_id, :string, null: false
      add :payment_intent_id, references(:payment_intents, on_delete: :nilify_all)
      add :provider_checkout_id, :string
      add :payload, :map, null: false, default: %{}
      add :outcome, :string
      add :retry_count, :integer, null: false, default: 0
      add :received_at, :utc_datetime, null: false
      add :processed_at, :utc_datetime
      timestamps(updated_at: false)
    end

    create unique_index(:provider_events, [:provider, :provider_event_id], name: :provider_events_provider_event_unique)
    create index(:provider_events, [:payment_intent_id, :received_at])

    create table(:inventory_pools, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pool_key, :string, null: false
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :ticket_tier_id, references(:ticket_tiers, on_delete: :restrict)
      add :capacity, :integer, null: false
      add :reserved, :integer, null: false, default: 0
      add :sold, :integer, null: false, default: 0
      add :version, :integer, null: false, default: 1
      timestamps()
    end

    create unique_index(:inventory_pools, [:pool_key])
    create unique_index(:inventory_pools, [:ticket_tier_id], where: "ticket_tier_id IS NOT NULL", name: :inventory_pools_tier_unique)
    create unique_index(:inventory_pools, [:event_id], where: "ticket_tier_id IS NULL", name: :inventory_pools_event_unique)
    create constraint(:inventory_pools, :inventory_pool_counts_valid,
             check: "capacity > 0 AND reserved >= 0 AND sold >= 0 AND reserved + sold <= capacity AND version > 0"
           )

    execute """
    INSERT INTO inventory_pools (id, pool_key, event_id, ticket_tier_id, capacity, reserved, sold, version, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'tier:' || t.id, t.event_id, t.id, t.capacity,
           0, (SELECT count(*) FROM tickets x WHERE x.tier_id = t.id AND x.status IN ('valid', 'scanned')), 1, now(), now()
    FROM ticket_tiers t
    ON CONFLICT DO NOTHING
    """

    execute """
    INSERT INTO inventory_pools (id, pool_key, event_id, ticket_tier_id, capacity, reserved, sold, version, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'event:' || e.id, e.id, NULL, e.capacity,
           0, (SELECT count(*) FROM tickets x WHERE x.event_id = e.id AND x.tier_id IS NULL AND x.status IN ('valid', 'scanned')), 1, now(), now()
    FROM events e
    ON CONFLICT DO NOTHING
    """

    create table(:inventory_reservations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_intent_id, references(:payment_intents, on_delete: :restrict), null: false
      add :inventory_pool_id, references(:inventory_pools, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :status, :string, null: false, default: "active"
      add :expires_at, :utc_datetime, null: false
      add :released_at, :utc_datetime
      add :consumed_at, :utc_datetime
      timestamps()
    end

    create unique_index(:inventory_reservations, [:payment_intent_id], where: "status IN ('active', 'uncertain')", name: :inventory_reservations_active_intent_unique)
    create index(:inventory_reservations, [:inventory_pool_id, :status, :expires_at])
    create constraint(:inventory_reservations, :inventory_reservation_status_valid,
             check: "status IN ('active', 'consumed', 'released', 'uncertain')"
           )
    create constraint(:inventory_reservations, :inventory_reservation_quantity_valid,
             check: "quantity > 0"
           )

    create table(:payment_line_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_intent_id, references(:payment_intents, on_delete: :restrict), null: false
      add :line_number, :integer, null: false
      add :ticket_tier_id, references(:ticket_tiers, on_delete: :restrict)
      add :quantity, :integer, null: false
      add :unit_price_cents, :integer, null: false
      add :currency, :string, null: false
      add :price_version, :string, null: false
      timestamps()
    end

    create unique_index(:payment_line_items, [:payment_intent_id, :line_number], name: :payment_line_items_intent_line_unique)
    create constraint(:payment_line_items, :payment_line_item_amount_valid,
             check: "line_number > 0 AND quantity > 0 AND unit_price_cents > 0"
           )

    create table(:ticket_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_line_item_id, references(:payment_line_items, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :status, :string, null: false, default: "created"
      timestamps()
    end

    create unique_index(:ticket_batches, [:payment_line_item_id], name: :ticket_batches_line_unique)
    create constraint(:ticket_batches, :ticket_batch_quantity_valid, check: "quantity > 0")
    create constraint(:ticket_batches, :ticket_batch_status_valid, check: "status IN ('created', 'fulfilled', 'failed', 'manual_review')")
    alter table(:tickets) do
      add :ticket_batch_id, references(:ticket_batches, on_delete: :restrict)
    end
    create index(:tickets, [:ticket_batch_id])
    execute """
    CREATE OR REPLACE FUNCTION dunda_ticket_batch_quantity_guard() RETURNS trigger AS $$
    DECLARE batch_id uuid; expected bigint; issued bigint; batch_status text; line_quantity bigint;
    BEGIN
      IF TG_TABLE_NAME = 'tickets' THEN
        batch_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.ticket_batch_id ELSE NEW.ticket_batch_id END;
      ELSE
        batch_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
      END IF;
      IF batch_id IS NULL THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
      END IF;
      SELECT b.quantity, b.status, li.quantity
        INTO expected, batch_status, line_quantity
        FROM ticket_batches b JOIN payment_line_items li ON li.id = b.payment_line_item_id
        WHERE b.id = batch_id;
      IF batch_status = 'fulfilled' THEN
        SELECT count(*) INTO issued FROM tickets WHERE ticket_batch_id = batch_id;
        IF issued <> expected OR expected <> line_quantity THEN
          RAISE EXCEPTION 'ticket batch % quantity mismatch: issued %, expected %, line %', batch_id, issued, expected, line_quantity;
        END IF;
      END IF;
      IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END; $$ LANGUAGE plpgsql;
    CREATE CONSTRAINT TRIGGER ticket_batch_quantity_guard
      AFTER INSERT OR UPDATE OR DELETE ON tickets
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION dunda_ticket_batch_quantity_guard();
    CREATE CONSTRAINT TRIGGER ticket_batch_status_quantity_guard
      AFTER INSERT OR UPDATE OR DELETE ON ticket_batches
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION dunda_ticket_batch_quantity_guard();
    """

    create table(:outbox_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_key, :string, null: false
      add :event_type, :string, null: false
      add :aggregate_type, :string, null: false
      add :aggregate_id, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :available_at, :utc_datetime, null: false
      add :published_at, :utc_datetime
      add :last_error, :string
      timestamps()
    end

    create unique_index(:outbox_events, [:event_key])
    create index(:outbox_events, [:status, :available_at])
    create constraint(:outbox_events, :outbox_status_valid,
             check: "status IN ('pending', 'processing', 'published', 'failed') AND attempts >= 0"
           )

    create table(:payment_intent_transitions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_intent_id, references(:payment_intents, on_delete: :restrict), null: false
      add :from_state, :string, null: false
      add :to_state, :string, null: false
      add :prior_version, :integer, null: false
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :reason, :string
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: false)
    end
    create index(:payment_intent_transitions, [:payment_intent_id, :inserted_at])

    create table(:journal_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reference, :string, null: false
      add :currency, :string, null: false
      add :total_debits_cents, :integer, null: false, default: 0
      add :total_credits_cents, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: false)
    end

    create unique_index(:journal_transactions, [:reference])
    create constraint(:journal_transactions, :journal_transaction_totals_nonnegative,
             check: "total_debits_cents >= 0 AND total_credits_cents >= 0"
           )

    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :kind, :string, null: false
      add :currency, :string, null: false
      add :active, :boolean, null: false, default: true
      timestamps(updated_at: false)
    end

    create unique_index(:accounts, [:code, :currency], name: :accounts_code_currency_unique)

    create table(:journal_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :journal_transaction_id, references(:journal_transactions, on_delete: :restrict), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :debit_cents, :integer, null: false, default: 0
      add :credit_cents, :integer, null: false, default: 0
      add :currency, :string, null: false
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: false)
    end

    create index(:journal_lines, [:journal_transaction_id])
    create constraint(:journal_lines, :journal_line_amounts_valid,
             check: "debit_cents >= 0 AND credit_cents >= 0 AND ((debit_cents > 0 AND credit_cents = 0) OR (credit_cents > 0 AND debit_cents = 0))"
           )

    create table(:account_balances, primary_key: false) do
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :currency, :string, null: false
      add :balance_cents, :bigint, null: false, default: 0
      add :updated_at, :utc_datetime, null: false
    end

    create unique_index(:account_balances, [:account_id, :currency], name: :account_balances_account_currency_unique)

    execute """
    CREATE OR REPLACE FUNCTION dunda_assert_journal_balanced() RETURNS trigger AS $$
    DECLARE debit_total bigint; credit_total bigint; expected_debit bigint; expected_credit bigint; tx_id uuid; tx_currency text;
    BEGIN
      IF TG_TABLE_NAME = 'journal_transactions' THEN tx_id := NEW.id; ELSE tx_id := NEW.journal_transaction_id; END IF;
      SELECT COALESCE(SUM(debit_cents), 0), COALESCE(SUM(credit_cents), 0)
        INTO debit_total, credit_total
        FROM journal_lines WHERE journal_transaction_id = tx_id;
      SELECT total_debits_cents, total_credits_cents
        INTO expected_debit, expected_credit
        FROM journal_transactions WHERE id = tx_id;
      SELECT currency INTO tx_currency FROM journal_transactions WHERE id = tx_id;
      IF EXISTS (SELECT 1 FROM journal_lines WHERE journal_transaction_id = tx_id AND currency <> tx_currency) THEN
        RAISE EXCEPTION 'journal transaction % contains a line with a different currency', tx_id;
      END IF;
      IF debit_total <> credit_total OR debit_total <> expected_debit OR credit_total <> expected_credit THEN
        RAISE EXCEPTION 'unbalanced journal transaction %: debits %, credits %, expected %, %', tx_id, debit_total, credit_total, expected_debit, expected_credit;
      END IF;
      RETURN NEW;
    END; $$ LANGUAGE plpgsql;
    CREATE CONSTRAINT TRIGGER journal_lines_balanced
      AFTER INSERT OR UPDATE ON journal_lines
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION dunda_assert_journal_balanced();
    CREATE CONSTRAINT TRIGGER journal_transactions_balanced
      AFTER INSERT OR UPDATE ON journal_transactions
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION dunda_assert_journal_balanced();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS journal_lines_balanced ON journal_lines"
    execute "DROP TRIGGER IF EXISTS journal_transactions_balanced ON journal_transactions"
    execute "DROP FUNCTION IF EXISTS dunda_assert_journal_balanced()"
    execute "DROP TRIGGER IF EXISTS ticket_batch_quantity_guard ON tickets"
    execute "DROP TRIGGER IF EXISTS ticket_batch_status_quantity_guard ON ticket_batches"
    execute "DROP FUNCTION IF EXISTS dunda_ticket_batch_quantity_guard()"
    execute "DROP TRIGGER IF EXISTS payment_intent_state_guard ON payment_intents"
    execute "DROP FUNCTION IF EXISTS dunda_payment_intent_state_guard()"
    execute "DROP TRIGGER IF EXISTS quote_immutable_guard ON quotes"
    execute "DROP FUNCTION IF EXISTS dunda_quote_immutable_guard()"
    execute "DROP TRIGGER IF EXISTS payment_intent_quote_guard ON payment_intents"
    execute "DROP FUNCTION IF EXISTS dunda_payment_quote_guard()"
    alter table(:tickets), do: remove(:ticket_batch_id)
    drop table(:account_balances)
    drop table(:payment_intent_transitions)
    drop table(:journal_lines)
    drop table(:accounts)
    drop table(:journal_transactions)
    drop table(:outbox_events)
    drop table(:ticket_batches)
    drop table(:payment_line_items)
    drop table(:inventory_reservations)
    drop table(:inventory_pools)
    drop table(:provider_events)
    drop table(:payment_attempts)
    drop table(:payment_intents)
    drop table(:quotes)
  end
end
