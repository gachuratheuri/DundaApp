defmodule Dunda.Events.WaitlistEntry do
  @moduledoc """
  A user's place in the sold-out waitlist for an event (optionally a specific
  tier). Entries are served FIFO by `inserted_at`; when inventory frees up the
  head of the queue is `offered` a hold until `offer_expires_at`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(queued offered converted expired cancelled)

  schema "waitlist_entries" do
    field :quantity, :integer, default: 1
    field :status, :string, default: "queued"
    field :notified_at, :utc_datetime
    field :offer_expires_at, :utc_datetime

    belongs_to :event, Dunda.Events.Event
    belongs_to :tier, Dunda.Ticketing.TicketTier
    belongs_to :user, Dunda.Accounts.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :quantity,
      :status,
      :notified_at,
      :offer_expires_at,
      :event_id,
      :tier_id,
      :user_id
    ])
    |> validate_required([:event_id, :user_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:event)
    |> assoc_constraint(:user)
    |> unique_constraint([:event_id, :user_id])
  end
end
