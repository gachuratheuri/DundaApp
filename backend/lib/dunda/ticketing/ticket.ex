defmodule Dunda.Ticketing.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tickets" do
    field :tier_label, :string
    field :price_kes, :integer
    field :status, :string, default: "valid"
    field :jwt, :string

    belongs_to :user, Dunda.Accounts.User
    belongs_to :event, Dunda.Events.Event
    belongs_to :order, Dunda.Billing.Order

    timestamps()
  end

  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:tier_label, :price_kes, :status, :jwt, :user_id, :event_id, :order_id])
    |> validate_required([:tier_label, :price_kes, :status, :user_id, :event_id])
    |> validate_inclusion(:status, ["valid", "transferred", "scanned"])
  end
end
