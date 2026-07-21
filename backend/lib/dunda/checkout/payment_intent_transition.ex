defmodule Dunda.Checkout.PaymentIntentTransition do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payment_intent_transitions" do
    field :from_state, :string
    field :to_state, :string
    field :prior_version, :integer
    field :actor_user_id, :integer
    field :reason, :string
    field :metadata, :map, default: %{}
    belongs_to :payment_intent, Dunda.Checkout.PaymentIntent, type: :binary_id
    timestamps(updated_at: false)
  end
end
