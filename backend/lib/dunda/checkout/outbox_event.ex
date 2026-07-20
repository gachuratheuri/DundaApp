defmodule Dunda.Checkout.OutboxEvent do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "outbox_events" do
    field :event_key, :string
    field :event_type, :string
    field :aggregate_type, :string
    field :aggregate_id, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :available_at, :utc_datetime
    field :published_at, :utc_datetime
    field :last_error, :string
    timestamps()
  end
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_key, :event_type, :aggregate_type, :aggregate_id, :payload, :status, :attempts, :available_at, :published_at, :last_error])
    |> validate_required([:event_key, :event_type, :aggregate_type, :aggregate_id, :payload, :status, :available_at])
    |> validate_inclusion(:status, ~w(pending processing published failed))
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
    |> unique_constraint(:event_key)
  end
end
