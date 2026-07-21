defmodule Dunda.PaymentIntentTransitionPropertyTest do
  @moduledoc """
  Characterises and property-tests `Dunda.Checkout.PaymentIntent`'s state
  machine (`validate_transition/1`) against the transition graph documented
  in `docs/phase_3_5_checkout_authority.md` and the root remediation plan's
  Invariant 8 ("terminal states cannot be overwritten except by an explicit
  compensating transaction").

  Two complementary checks:

    1. An exhaustive pairwise table match (every `{current, next}` pair over
       the full, small, finite state set) against a hand-transcribed oracle
       of the allowed graph — deterministic, complete coverage, and fails
       loudly if the two drift apart.
    2. A StreamData property over random walks: `refunded` — the one state
       whose allowed-transition set is only itself — can never be left once
       entered, for any generated sequence of proposed next states.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Dunda.Checkout.PaymentIntent

  @states ~w(created inventory_reserved provider_submission_pending provider_pending confirmed fulfilled failed expired_pending_reconciliation confirmed_late manual_review refund_pending refunded)

  # Hand-transcribed from Dunda.Checkout.PaymentIntent.validate_transition/1.
  # Keep this in sync with the module — that is the point of the test.
  @allowed %{
    "created" => ~w(created inventory_reserved failed manual_review),
    "inventory_reserved" =>
      ~w(inventory_reserved provider_submission_pending failed expired_pending_reconciliation manual_review),
    "provider_submission_pending" =>
      ~w(provider_submission_pending provider_pending failed manual_review),
    "provider_pending" =>
      ~w(provider_pending confirmed failed expired_pending_reconciliation confirmed_late manual_review refund_pending),
    "confirmed" => ~w(confirmed fulfilled refund_pending manual_review),
    "fulfilled" => ~w(fulfilled refund_pending manual_review),
    "failed" => ~w(failed manual_review),
    "expired_pending_reconciliation" =>
      ~w(expired_pending_reconciliation confirmed_late manual_review refund_pending),
    "confirmed_late" => ~w(confirmed_late fulfilled refund_pending manual_review),
    "manual_review" => ~w(manual_review confirmed_late refund_pending),
    "refund_pending" => ~w(refund_pending refunded manual_review),
    "refunded" => ~w(refunded)
  }

  defp base_intent(state) do
    %PaymentIntent{
      state: state,
      quote_id: Ecto.UUID.generate(),
      user_id: 1,
      event_id: 1,
      quantity: 1,
      amount_cents: 100,
      currency: "KES",
      phone_encrypted: "254712345678",
      idempotency_key: String.duplicate("x", 16),
      expires_at: DateTime.utc_now(),
      version: 1
    }
  end

  test "every {current, next} pair matches the documented allowed-transition graph exactly" do
    for current <- @states, next <- @states do
      changeset = PaymentIntent.changeset(base_intent(current), %{state: next, version: 2})
      expected_valid = next in Map.fetch!(@allowed, current)

      assert changeset.valid? == expected_valid,
             "transition #{current} -> #{next}: expected valid?=#{expected_valid}, got #{changeset.valid?}"
    end
  end

  property "refunded, once entered, can never be left by any subsequent proposed transition" do
    check all(
            attempts <-
              StreamData.list_of(StreamData.member_of(@states), min_length: 1, max_length: 10),
            max_runs: 100
          ) do
      intent = base_intent("refunded")

      Enum.each(attempts, fn next ->
        changeset = PaymentIntent.changeset(intent, %{state: next, version: 2})
        assert changeset.valid? == (next == "refunded")
      end)
    end
  end

  property "a changeset that does not change :state is always valid regardless of current state (no spurious rejection)" do
    check all(current <- StreamData.member_of(@states), max_runs: 20) do
      changeset =
        PaymentIntent.changeset(base_intent(current), %{failure_reason: "unrelated_update"})

      assert changeset.valid?
    end
  end

  property "PaymentIntent.transition_allowed?/2 agrees with the changeset's own validation for every pair" do
    check all(
            current <- StreamData.member_of(@states),
            next <- StreamData.member_of(@states),
            max_runs: 200
          ) do
      changeset = PaymentIntent.changeset(base_intent(current), %{state: next, version: 2})
      assert changeset.valid? == PaymentIntent.transition_allowed?(current, next)
    end
  end
end
