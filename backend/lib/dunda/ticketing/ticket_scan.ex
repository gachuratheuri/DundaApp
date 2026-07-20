defmodule Dunda.Ticketing.TicketScan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "ticket_scans" do
    field :result, :string
    field :gate, :string
    field :reason, :string
    field :scanned_at, :utc_datetime

    belongs_to :ticket, Dunda.Ticketing.Ticket, type: :binary_id
    belongs_to :event, Dunda.Events.Event
    belongs_to :scanner, Dunda.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(ticket_scan, attrs) do
    ticket_scan
    |> cast(attrs, [:result, :gate, :reason, :scanned_at, :ticket_id, :event_id, :scanner_id])
    |> validate_required([:result, :scanned_at, :ticket_id, :event_id])
    |> validate_inclusion(:result, ["admitted", "rejected", "duplicate"])
  end
end
