defmodule Dunda.Phase6SettlementTest do
  use ExUnit.Case, async: true

  alias Dunda.Billing.{Order, Refund}
  alias Dunda.Market.Listing
  alias Dunda.Organisations.PayoutBatch
  alias Dunda.Ticketing.Ticket

  test "resale listings require a non-negative face-value-capped price" do
    changeset =
      Listing.changeset(%Listing{}, %{
        asking_price_kes: 101,
        face_value_kes: 100,
        status: "active",
        ticket_id: Ecto.UUID.generate(),
        seller_id: 1
      })

    refute changeset.valid?
  end

  test "resale order kind must be linked to a listing" do
    changeset =
      Order.create_changeset(%Order{}, %{
        merchant_reference: "primary-order",
        amount_cents: 100,
        event_id: 1,
        user_id: 1,
        idempotency_key: String.duplicate("a", 16),
        kind: "resale"
      })

    refute changeset.valid?
  end

  test "refund and payout state machines reject backward terminal transitions" do
    refund = %Refund{status: "succeeded"}
    payout = %PayoutBatch{status: "paid"}

    refute Refund.changeset(refund, %{status: "pending"}).valid?
    refute PayoutBatch.changeset(payout, %{status: "pending"}).valid?
  end

  test "manual review can only be closed by an explicit provider result" do
    payout = %PayoutBatch{status: "manual_review", organisation_id: 1, amount_cents: 100, currency: "KES", idempotency_key: "batch-key"}
    refund = %Refund{status: "manual_review", order_id: 1, amount_cents: 100, currency: "KES", reason: "provider review", idempotency_key: "refund-key"}
    assert PayoutBatch.changeset(payout, %{status: "paid"}).valid?
    assert Refund.changeset(refund, %{status: "failed"}).valid?
    assert Order.status_changeset(%Order{status: "manual_review"}, %{status: "refunded"}).valid?
  end

  test "revoked tickets require a revocation timestamp" do
    changeset =
      Ticket.changeset(%Ticket{}, %{
        tier_label: "VIP",
        price_kes: 100,
        status: "refunded",
        user_id: 1,
        event_id: 1
      })

    refute changeset.valid?
  end
end
