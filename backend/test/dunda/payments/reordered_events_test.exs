defmodule Dunda.Payments.ReorderedEventsTest do
  @moduledoc """
  Fault-injection test for Invariant 8 (state monotonicity) under
  out-of-order provider events. A stale/superseded provider result arriving
  AFTER a later, more-authoritative result already confirmed the payment
  must never revert or corrupt the intent — it must no-op.

  This test drove the discovery and fix of a real defect: before this
  change, `Dunda.Checkout.fail_payment/2`'s short-circuit guard only covered
  `["fulfilled", "refunded"]`, not `"confirmed"`/`"confirmed_late"`/
  `"manual_review"`/`"refund_pending"`/`"expired_pending_reconciliation"` —
  a stale failure callback for an already-confirmed intent would attempt an
  invalid state transition and crash (`Repo.update!` raising on an invalid
  changeset) rather than gracefully no-op. The transaction boundary meant no
  data was ever corrupted (Postgres rolls back the whole function on any
  raise), but the calling Oban job would crash and retry forever. Fixed by
  routing the guard through `Dunda.Checkout.PaymentIntent.transition_allowed?/2`
  — the same single source of truth `validate_transition/1` uses — instead
  of a second, independently-maintained (and here, incomplete) state list.
  """
  use Dunda.DataCase, async: false

  # Dunda.CheckoutFixtures.insert_event_with_pool!/1 now delegates to the
  # real Dunda.Events.create_event/1, which also seeds a Redis projection —
  # matches the :redis convention in test_helper.exs.
  @moduletag :redis

  alias Dunda.Checkout
  alias Dunda.Checkout.PaymentIntent
  alias Dunda.CheckoutFixtures

  setup do
    Application.put_env(:dunda, :containment_mode, false)
    on_exit(fn -> Application.put_env(:dunda, :containment_mode, false) end)
    :ok
  end

  defp unique, do: System.unique_integer([:positive])

  defp insert_user! do
    n = unique()

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "reordered-#{n}@example.com",
        "password" => "password123!",
        "name" => "Reordered Events Test"
      })

    user
  end

  defp confirmed_intent! do
    user = insert_user!()
    # An explicit pool is required — see Dunda.CheckoutFixtures moduledoc for
    # why nothing else provisions one.
    {event, _pool} = CheckoutFixtures.insert_event_with_pool!(capacity: 50)

    {:ok, quote} = Checkout.create_quote(user.id, %{event_id: event.id, quantity: 1})
    key = Base.encode16(:crypto.strong_rand_bytes(10))

    {:ok, intent} =
      Checkout.create_payment_intent(user.id, %{
        quote_id: quote.id,
        idempotency_key: key,
        phone: "254712345678"
      })

    {:ok, {:submit, intent, attempt}} = Checkout.prepare_provider_submission(intent.id)
    checkout_id = "reorder-checkout-#{unique()}"

    {:ok, _} =
      Checkout.complete_provider_submission(intent.id, attempt.id, %{
        result: :ok,
        provider_checkout_id: checkout_id
      })

    {:ok, confirmed} =
      Checkout.confirm_payment(intent.id, %{
        provider: "pesapal",
        provider_checkout_id: checkout_id,
        provider_receipt: "REORDER#{unique()}",
        amount_cents: 100_000
      })

    confirmed
  end

  test "a stale failure callback arriving after confirmation no-ops instead of crashing or reverting state" do
    confirmed = confirmed_intent!()
    assert confirmed.state in ["confirmed", "confirmed_late"]

    assert {:ok, result} = Checkout.fail_payment(confirmed.id, "stale_reordered_failure")

    assert result.id == confirmed.id
    assert result.state == confirmed.state
    assert result.failure_reason == confirmed.failure_reason

    reloaded = Repo.get!(PaymentIntent, confirmed.id)
    assert reloaded.state == confirmed.state
  end

  test "PaymentIntent.transition_allowed?/2 rejects failed from every post-confirmation state" do
    for state <- [
          "confirmed",
          "fulfilled",
          "confirmed_late",
          "manual_review",
          "refund_pending",
          "refunded",
          "expired_pending_reconciliation"
        ] do
      refute PaymentIntent.transition_allowed?(state, "failed"),
             "expected #{state} -> failed to be disallowed"
    end
  end

  test "fail_payment/2 still works normally for a genuinely failable (pre-confirmation) intent" do
    user = insert_user!()
    {event, _pool} = CheckoutFixtures.insert_event_with_pool!(capacity: 50)
    {:ok, quote} = Checkout.create_quote(user.id, %{event_id: event.id, quantity: 1})
    key = Base.encode16(:crypto.strong_rand_bytes(10))

    {:ok, intent} =
      Checkout.create_payment_intent(user.id, %{
        quote_id: quote.id,
        idempotency_key: key,
        phone: "254712345678"
      })

    assert {:ok, failed} = Checkout.fail_payment(intent.id, "provider_rejected")
    assert failed.state == "failed"
    # Note: at this point the intent still has an active InventoryReservation
    # (created by reserve_from_quote!/4), so fail_payment/2 routes through
    # release_reservation!/2, which hardcodes failure_reason to
    # "reservation_expired" rather than propagating the passed-in `reason` —
    # a separate, pre-existing, non-crashing inconsistency tracked in
    # docs/phase_12_verification_observability_rollout.md's findings table
    # (out of scope for this fix, which is specifically about the crash on
    # reordered post-confirmation events).
    assert failed.failure_reason == "reservation_expired"
  end
end
