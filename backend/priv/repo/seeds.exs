# Seed an organisation (the keystone), its events, and their Redis inventory.
#
#     mix run priv/repo/seeds.exs
#
alias Dunda.Repo
alias Dunda.Events.Event
alias Dunda.Organisations
alias Dunda.Organisations.Organisation

# Idempotent keystone organisation that owns the seeded events.
organisation =
  Organisations.get_organisation_by_slug("carnivore-grounds") ||
    (%Organisation{}
     |> Organisation.changeset(%{
       name: "Carnivore Grounds",
       slug: "carnivore-grounds",
       eventbrite_org_id: "123456789",
       scraper_enabled: true,
       mpesa_phone: "254700000000"
     })
     |> Repo.insert!())

IO.puts("Seeded organisation #{organisation.id}: #{organisation.name}")

events = [
  %{name: "Blankets & Wine Nairobi", venue: "Carnivore Grounds", price_cents: 300_000, capacity: 5000, in_days: 30, hour: 14, minute: 0},
  %{name: "Sol Fest 2026", venue: "KICC Expo Hall", price_cents: 200_000, capacity: 10000, in_days: 45, hour: 18, minute: 30},
  %{name: "Nairobi Raving (Alchemist Live)", venue: "The Alchemist Bar", price_cents: 150_000, capacity: 800, in_days: 5, hour: 21, minute: 0},
  %{name: "Jimi Vibes Acoustic Solo", venue: "Muze Club Westlands", price_cents: 250_000, capacity: 400, in_days: 12, hour: 20, minute: 0}
]

today = DateTime.utc_now() |> DateTime.to_date()

for attrs <- events do
  target_date = Date.add(today, attrs.in_days)
  target_time = Time.new!(attrs.hour, attrs.minute, 0)
  {:ok, starts_at} = DateTime.new(target_date, target_time, "Etc/UTC")

  event =
    %Event{}
    |> Event.changeset(%{
      name: attrs.name,
      venue: attrs.venue,
      starts_at: starts_at,
      price_cents: attrs.price_cents,
      capacity: attrs.capacity,
      organisation_id: organisation.id
    })
    |> Repo.insert!()

  # Seed live inventory in Redis for this event's single tier.
  Redix.command(:redix, ["SET", "inventory:#{event.id}", Integer.to_string(event.capacity)])

  IO.puts("Seeded event #{event.id}: #{event.name} (#{event.capacity} tickets)")
end

# ── Seed a Test Consumer & Wallet ─────────────────────────────────────────────
alias Dunda.Accounts

# Clean up existing test user
if user = Accounts.get_user_by_email("david@dunda.ke") do
  Repo.delete(user)
end

{:ok, user} = Accounts.register_user(%{
  email: "david@dunda.ke",
  phone: "254711223344",
  full_name: "David M.",
  password: "password123"
})
IO.puts("Seeded test consumer: #{user.email}")

# Fetch the seeded events
events = Repo.all(Event)

# Issue tickets to the test user
if length(events) >= 2 do
  [event1, event2 | _] = events
  
  # 2 VIP tickets for Event 1
  Dunda.Ticketing.issue_tickets(nil, event1, user, 2, "VIP FRONT ROW")
  
  # 1 Regular ticket for Event 2
  Dunda.Ticketing.issue_tickets(nil, event2, user, 1, "GENERAL")
  
  IO.puts("Seeded 3 tickets into wallet for #{user.email}")
end
