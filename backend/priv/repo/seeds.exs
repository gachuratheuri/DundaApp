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
  %{name: "Blankets & Wine", venue: "Lugogo Cricket Oval", price_cents: 350_000, capacity: 5000, in_days: 10},
  %{name: "Koroga Festival", venue: "Carnivore Grounds", price_cents: 250_000, capacity: 6000, in_days: 14},
  %{name: "Thrift Social", venue: "Alchemist Bar", price_cents: 50_000, capacity: 600, in_days: 2},
  %{name: "Nairobi Nights", venue: "KICC Rooftop", price_cents: 150_000, capacity: 400, in_days: 8}
]

now = DateTime.utc_now() |> DateTime.truncate(:second)

for attrs <- events do
  starts_at = DateTime.add(now, attrs.in_days * 24 * 3600, :second)

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
