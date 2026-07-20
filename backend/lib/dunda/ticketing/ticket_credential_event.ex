defmodule Dunda.Ticketing.TicketCredentialEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "ticket_credential_events" do
    field :event_type, :string
    field :credential_epoch, :integer
    field :public_key_fingerprint, :string
    field :metadata, :map, default: %{}
    field :occurred_at, :utc_datetime
    belongs_to :ticket, Dunda.Ticketing.Ticket, type: :binary_id
    belongs_to :actor, Dunda.Accounts.User, foreign_key: :actor_user_id
    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:ticket_id, :event_type, :credential_epoch, :public_key_fingerprint, :actor_user_id, :metadata, :occurred_at])
    |> validate_required([:ticket_id, :event_type, :credential_epoch, :metadata, :occurred_at])
    |> validate_inclusion(:event_type, ~w(bound rebound revoked recovered))
    |> validate_number(:credential_epoch, greater_than_or_equal_to: 0)
    |> assoc_constraint(:ticket)
    |> assoc_constraint(:actor)
    |> unique_constraint([:ticket_id, :credential_epoch, :event_type])
  end
end
