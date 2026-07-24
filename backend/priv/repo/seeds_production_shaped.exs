# Seeds a synthetic dataset at a realistic scale for `mix dunda.migration_drill`
# (backend/lib/mix/tasks/dunda.migration_drill.ex) — thousands of orders,
# tickets, and ledger entries, built through the SAME schemas/changesets the
# application uses (never raw SQL), so it stays valid as schemas evolve
# instead of rotting the way a hand-written INSERT fixture would.
#
#     mix run priv/repo/seeds_production_shaped.exs
#
# Scale is configurable via SEED_ORGANISATIONS / SEED_EVENTS_PER_ORG /
# SEED_ORDERS_PER_EVENT env vars; defaults produce roughly 2,000 orders,
# 2,000 tickets, and 2,000 balanced ledger transactions.

alias Dunda.Accounts
alias Dunda.Billing.Order
alias Dunda.Checkout.{InventoryPool, Journal}
alias Dunda.Events.Event
alias Dunda.Organisations.Organisation
alias Dunda.Repo
alias Dunda.Ticketing.{Ticket, TicketTier}

organisations_count = String.to_integer(System.get_env("SEED_ORGANISATIONS", "10"))
events_per_org = String.to_integer(System.get_env("SEED_EVENTS_PER_ORG", "5"))
orders_per_event = String.to_integer(System.get_env("SEED_ORDERS_PER_EVENT", "40"))

IO.puts("Seeding #{organisations_count} organisations x #{events_per_org} events x #{orders_per_event} orders/tickets...")

buyer =
  Accounts.get_user_by_email("migration-drill-buyer@dunda.invalid") ||
    (case Accounts.register_user(%{
            "email" => "migration-drill-buyer@dunda.invalid",
            "password" => "password123!",
            "name" => "Migration Drill Buyer"
          }) do
       {:ok, user} -> user
       {:error, _} -> Accounts.get_user_by_email("migration-drill-buyer@dunda.invalid")
     end)

for org_n <- 1..organisations_count do
  {:ok, organisation} =
    %Organisation{}
    |> Organisation.changeset(%{
      name: "Migration Drill Org #{org_n}-#{System.unique_integer([:positive])}",
      slug: "migration-drill-org-#{org_n}-#{System.unique_integer([:positive])}",
      verification_status: "verified",
      country: "KE"
    })
    |> Repo.insert()

  for event_n <- 1..events_per_org do
    {:ok, event} =
      Event.changeset(%Event{}, %{
        name: "Migration Drill Event #{org_n}.#{event_n}",
        venue: "Drill Venue #{event_n}",
        starts_at: DateTime.utc_now() |> DateTime.add(30 + event_n, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: orders_per_event * 3,
        status: "published",
        city: "Nairobi",
        currency: "KES",
        organisation_id: organisation.id
      })
      |> Repo.insert()

    {:ok, tier} =
      TicketTier.changeset(%TicketTier{}, %{
        name: "Regular",
        price_cents: 100_000,
        capacity: orders_per_event * 3,
        event_id: event.id
      })
      |> Repo.insert()

    # Production-shaped: a real event's tier now always has a pool (see
    # Dunda.Events.create_event/1 and finding F0 in
    # docs/phase_12_verification_observability_rollout.md). This script
    # doesn't route through Dunda.Checkout (it writes orders/tickets
    # directly for seeding speed), so it provisions the pool itself,
    # matching the migration backfill's `'tier:' || tier.id` convention —
    # sold reflects the tickets this loop is about to issue.
    {:ok, _pool} =
      %InventoryPool{}
      |> InventoryPool.changeset(%{
        pool_key: "tier:#{tier.id}",
        capacity: tier.capacity,
        reserved: 0,
        sold: orders_per_event,
        version: 1,
        event_id: event.id,
        ticket_tier_id: tier.id
      })
      |> Repo.insert()

    for order_n <- 1..orders_per_event do
      merchant_reference = "drill-#{organisation.id}-#{event.id}-#{order_n}-#{System.unique_integer([:positive])}"

      {:ok, order} =
        Order.create_changeset(%Order{}, %{
          merchant_reference: merchant_reference,
          amount_cents: tier.price_cents,
          currency: "KES",
          quantity: 1,
          event_id: event.id,
          ticket_tier_id: tier.id,
          organisation_id: organisation.id,
          user_id: buyer.id,
          idempotency_key: merchant_reference
        })
        |> Repo.insert()

      {:ok, order} = order |> Order.status_changeset(%{status: "completed"}) |> Repo.update()

      {:ok, _ticket} =
        Ticket.changeset(%Ticket{}, %{
          tier_label: "REGULAR",
          price_cents: tier.price_cents,
          status: "valid",
          user_id: buyer.id,
          event_id: event.id,
          order_id: order.id,
          tier_id: tier.id,
          fulfillment_key: "seed:#{order.id}"
        })
        |> Repo.insert()

      Journal.post!(
        "seed-settlement:#{order.id}",
        "KES",
        [{"provider_clearing", :debit, order.amount_cents}, {"organiser_payable", :credit, order.amount_cents}],
        %{seed: true, order_id: order.id}
      )
    end

    IO.puts("  event #{event.id}: #{orders_per_event} orders/tickets seeded")
  end
end

IO.puts("Production-shaped seed complete.")
