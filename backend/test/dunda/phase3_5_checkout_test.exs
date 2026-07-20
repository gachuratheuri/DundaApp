defmodule Dunda.Phase3To5CheckoutTest do
  use ExUnit.Case, async: true

  alias Dunda.Checkout.{InventoryPool, JournalLine, PaymentIntent, Quote, QuoteSigner}

  test "quote signatures bind all server-derived terms" do
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)
    attrs = %{user_id: 1, event_id: 2, ticket_tier_id: 3, quantity: 2, unit_price_cents: 1_000, fee_cents: 0, total_cents: 2_000, currency: "KES", price_version: "v1", expires_at: expires_at}
    signature = QuoteSigner.sign(attrs)
    assert QuoteSigner.valid?(attrs, signature)
    refute QuoteSigner.valid?(Map.put(attrs, :quantity, 3), signature)
    refute QuoteSigner.valid?(Map.put(attrs, :currency, "USD"), signature)
  end

  test "payment state machine rejects backward terminal transitions" do
    intent = %PaymentIntent{state: "fulfilled", quote_id: Ecto.UUID.generate(), user_id: 1, event_id: 1, quantity: 1, amount_cents: 100, currency: "KES", phone_encrypted: "254712345678", idempotency_key: String.duplicate("x", 16), expires_at: DateTime.utc_now(), version: 1}
    refute PaymentIntent.changeset(intent, %{state: "provider_pending", version: 2}).valid?
    assert PaymentIntent.changeset(intent, %{state: "manual_review", version: 2}).valid?
  end

  test "journal line changeset cannot represent a two-sided or zero amount" do
    attrs = %{journal_transaction_id: Ecto.UUID.generate(), account_id: Ecto.UUID.generate(), currency: "KES", debit_cents: 10, credit_cents: 10}
    refute JournalLine.changeset(%JournalLine{}, attrs).valid?
    refute JournalLine.changeset(%JournalLine{}, %{attrs | debit_cents: 0, credit_cents: 0}).valid?
    assert JournalLine.changeset(%JournalLine{}, %{attrs | credit_cents: 0}).valid?
  end

  test "quote changeset rejects inconsistent total" do
    changeset = Quote.changeset(%Quote{}, %{user_id: 1, event_id: 1, quantity: 2, unit_price_cents: 100, fee_cents: 0, total_cents: 99, currency: "KES", price_version: "v1", signature: "sig", status: "active", expires_at: DateTime.utc_now()})
    refute changeset.valid?
  end

  test "inventory changeset rejects a reservation/sale conservation violation" do
    changeset = InventoryPool.changeset(%InventoryPool{}, %{pool_key: "tier:1", event_id: 1, capacity: 10, reserved: 6, sold: 5, version: 1})
    refute changeset.valid?
  end

  test "inventory changeset accepts a conserved pool" do
    changeset = InventoryPool.changeset(%InventoryPool{}, %{pool_key: "tier:1", event_id: 1, capacity: 10, reserved: 4, sold: 6, version: 1})
    assert changeset.valid?
  end
end
