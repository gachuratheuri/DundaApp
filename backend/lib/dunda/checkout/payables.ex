defmodule Dunda.Checkout.Payables do
  @moduledoc "Creates and compensates beneficiary-specific payable subledger entries."

  import Ecto.Query, only: [from: 2]

  alias Dunda.Checkout.{JournalTransaction, PayableEntry, PaymentIntent}
  alias Dunda.Repo

  def create_organiser!(
        %JournalTransaction{} = journal,
        %PaymentIntent{} = intent,
        organisation_id
      ) do
    insert!(%{
      journal_transaction_id: journal.id,
      organisation_id: organisation_id,
      source_type: "payment_intent",
      source_id: intent.id,
      amount_cents: intent.amount_cents,
      currency: intent.currency
    })
  end

  def create_seller!(%JournalTransaction{} = journal, order, seller_id) do
    insert!(%{
      journal_transaction_id: journal.id,
      beneficiary_user_id: seller_id,
      source_type: "resale_order",
      source_id: to_string(order.id),
      amount_cents: order.amount_cents,
      currency: order.currency
    })
  end

  @doc "Applies a payment-intent refund to its unpaid payable projection."
  def apply_refund!(%PaymentIntent{} = intent, amount_cents) do
    entry =
      Repo.one(
        from p in PayableEntry,
          where: p.source_type == "payment_intent" and p.source_id == ^intent.id,
          lock: "FOR UPDATE"
      )

    case entry do
      nil ->
        raise "payable entry missing for refunded payment intent #{intent.id}"

      %PayableEntry{status: "paid"} ->
        entry
        |> PayableEntry.changeset(%{
          refunded_cents: min(entry.refunded_cents + amount_cents, entry.amount_cents),
          status: "manual_review",
          manual_review_reason: "refund_after_payout_requires_organiser_recovery"
        })
        |> Repo.update!()

      %PayableEntry{status: "queued"} ->
        entry
        |> PayableEntry.changeset(%{
          refunded_cents: min(entry.refunded_cents + amount_cents, entry.amount_cents),
          status: "manual_review",
          manual_review_reason: "refund_while_payout_in_flight_requires_provider_reconciliation"
        })
        |> Repo.update!()

      %PayableEntry{} ->
        refunded = min(entry.refunded_cents + amount_cents, entry.amount_cents)

        entry
        |> PayableEntry.changeset(%{
          refunded_cents: refunded,
          status: if(refunded == entry.amount_cents, do: "refunded", else: "payable")
        })
        |> Repo.update!()
    end
  end

  defp insert!(attrs) do
    inserted =
      %PayableEntry{}
      |> PayableEntry.changeset(Map.put_new(attrs, :refunded_cents, 0))
      |> Repo.insert!(
        on_conflict: :nothing,
        conflict_target: [:source_type, :source_id]
      )

    if inserted.id do
      inserted
    else
      Repo.get_by!(PayableEntry,
        source_type: attrs.source_type,
        source_id: to_string(attrs.source_id)
      )
    end
  end
end
