defmodule Dunda.CheckoutFixtures do
  @moduledoc """
  Shared test-only fixture helper.

  Originally written to work around finding F0
  (`docs/phase_12_verification_observability_rollout.md` § Findings and
  pen-test tracking): `Dunda.Events.create_event/1` did not provision an
  `Dunda.Checkout.InventoryPool` row, so every test needing
  `Dunda.Checkout.create_payment_intent/2` to succeed had to insert one by
  hand. F0 is now fixed — `create_event/1` provisions the pool itself — so
  `insert_event_with_pool!/1` below now simply delegates to the real
  function instead of duplicating its logic. Kept as a helper (rather than
  inlined at each call site) purely for the convenient `{event, pool}`
  return shape several tests already use.
  """

  alias Dunda.Checkout.InventoryPool
  alias Dunda.Events
  alias Dunda.Events.Event
  alias Dunda.Repo

  @spec insert_event!(keyword()) :: Event.t()
  def insert_event!(opts \\ []) do
    n = System.unique_integer([:positive])

    {:ok, event} =
      Event.changeset(%Event{}, %{
        name: opts[:name] || "Fixture Event #{n}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        price_cents: opts[:price_cents] || 100_000,
        capacity: opts[:capacity] || 100,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })
      |> Repo.insert()

    event
  end

  @doc "Creates an event via the real Dunda.Events.create_event/1 path (which now provisions its untiered inventory pool) and returns both."
  @spec insert_event_with_pool!(keyword()) :: {Event.t(), InventoryPool.t()}
  def insert_event_with_pool!(opts \\ []) do
    n = System.unique_integer([:positive])

    {:ok, event} =
      Events.create_event(%{
        name: opts[:name] || "Fixture Event #{n}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        price_cents: opts[:price_cents] || 100_000,
        capacity: opts[:capacity] || 100,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })

    pool = Repo.get_by!(InventoryPool, event_id: event.id, ticket_tier_id: nil)

    {event, pool}
  end
end
