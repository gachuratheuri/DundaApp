defmodule Dunda.Repo.Migrations.CreateEngagementTables do
  @moduledoc """
  Engagement + retention surfaces that the app already renders but had no
  persistence behind them:

  * `waitlist_entries` — the sold-out waitlist flow (EventDetail `waitlist_*`
    states + Tickets "Waitlist" filter + portal "Unmet Demand" meter, which was
    previously simulated arithmetic in `EventsLive`).
  * `reviews` — the Tickets "Past" tab "Leave Review" action (1–5 stars + body),
    one review per attendee per event.
  * `event_favorites` — the EventDetail heart toggle.
  * `notifications` — the in-app notifications screen + push fan-out payloads.
  """
  use Ecto.Migration

  def change do
    create table(:waitlist_entries) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :tier_id, references(:ticket_tiers, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :quantity, :integer, null: false, default: 1
      # queued -> offered -> converted / expired / cancelled.
      add :status, :string, null: false, default: "queued"
      add :notified_at, :utc_datetime
      add :offer_expires_at, :utc_datetime

      timestamps()
    end

    create unique_index(:waitlist_entries, [:event_id, :user_id])
    # FIFO position scan for offers when inventory frees up.
    create index(:waitlist_entries, [:event_id, :status, :inserted_at])

    create constraint(:waitlist_entries, :waitlist_quantity_positive, check: "quantity > 0")

    create constraint(:waitlist_entries, :waitlist_status_valid,
             check: "status IN ('queued', 'offered', 'converted', 'expired', 'cancelled')"
           )

    create table(:reviews) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :rating, :integer, null: false
      add :body, :text

      timestamps()
    end

    create unique_index(:reviews, [:event_id, :user_id])
    create index(:reviews, [:event_id])

    create constraint(:reviews, :reviews_rating_range, check: "rating BETWEEN 1 AND 5")

    create table(:event_favorites) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:event_favorites, [:user_id, :event_id])
    create index(:event_favorites, [:event_id])

    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text
      # Arbitrary structured payload (deep-link target, event id, …).
      add :data, :map, null: false, default: %{}
      add :read_at, :utc_datetime

      timestamps()
    end

    # Unread-badge query: most-recent unread first.
    create index(:notifications, [:user_id, :read_at])
  end
end
