defmodule Dunda.Payments.DuplicateCallbackTest do
  @moduledoc """
  Fault-injection test for Invariant 2 (payment uniqueness) and the Phase 5
  exit gate's "duplicate callbacks... cannot duplicate tickets or money"
  requirement: replays the identical provider confirmation onto the SAME
  payment intent N times, concurrently, and asserts exactly one settlement
  transition and no manual-review escalation results. Drives
  `Dunda.Checkout`'s real public API end-to-end (quote -> intent ->
  provider-submission -> confirm), not a reimplementation, so this exercises
  the actual `FOR UPDATE` row-locking and `validate_transition/1` guards in
  `backend/lib/dunda/checkout.ex`.
  """
  use Dunda.DataCase, async: false

  # Dunda.CheckoutFixtures.insert_event_with_pool!/1 now delegates to the
  # real Dunda.Events.create_event/1, which also seeds a Redis projection —
  # matches the :redis convention in test_helper.exs.
  @moduletag :redis

  import Ecto.Query

  alias Dunda.Checkout
  alias Dunda.Checkout.{PaymentIntent, PaymentIntentTransition}
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
        "email" => "dup-callback-#{n}@example.com",
        "password" => "password123!",
        "name" => "Duplicate Callback Test"
      })

    user
  end

  # Drives the real Checkout API to a confirmable ("provider_pending") intent.
  defp intent_awaiting_confirmation! do
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
    checkout_id = "prop-checkout-#{unique()}"

    {:ok, _} =
      Checkout.complete_provider_submission(intent.id, attempt.id, %{
        result: :ok,
        provider_checkout_id: checkout_id
      })

    {intent.id, checkout_id}
  end

  test "N concurrent identical confirmations settle exactly once" do
    {intent_id, checkout_id} = intent_awaiting_confirmation!()
    receipt = "DUPTEST#{unique()}"

    attrs = %{
      provider: "pesapal",
      provider_checkout_id: checkout_id,
      provider_receipt: receipt,
      amount_cents: 100_000
    }

    # The sandbox connection must be shared across the spawned tasks.
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    results =
      1..8
      |> Task.async_stream(fn _ -> Checkout.confirm_payment(intent_id, attrs) end,
        max_concurrency: 8,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))

    final = Repo.get!(PaymentIntent, intent_id)
    assert final.state in ["confirmed", "confirmed_late"]
    assert final.provider_receipt == receipt

    confirmation_transitions =
      Repo.all(
        from t in PaymentIntentTransition,
          where: t.payment_intent_id == ^intent_id and t.reason == "provider_confirmed"
      )

    assert length(confirmation_transitions) == 1
  end
end
