defmodule Dunda.Checkout.ProviderEvent do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "provider_events" do
    field :provider, :string
    field :provider_event_id, :string
    field :provider_checkout_id, :string
    field :payload, :map, default: %{}
    field :outcome, :string
    field :retry_count, :integer, default: 0
    field :received_at, :utc_datetime
    field :processed_at, :utc_datetime
    belongs_to :payment_intent, Dunda.Checkout.PaymentIntent, type: :binary_id
    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :provider,
      :provider_event_id,
      :provider_checkout_id,
      :payload,
      :outcome,
      :retry_count,
      :received_at,
      :processed_at,
      :payment_intent_id
    ])
    |> validate_required([:provider, :provider_event_id, :payload, :received_at])
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
    |> assoc_constraint(:payment_intent)
    |> unique_constraint(:provider_event_id, name: :provider_events_provider_event_unique)
  end
end
