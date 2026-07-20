defmodule Dunda.Checkout.PaymentAttempt do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @statuses ~w(pending submitted succeeded failed manual_review)
  schema "payment_attempts" do
    field :provider, :string
    field :attempt_key, :string
    field :provider_checkout_id, :string
    field :status, :string, default: "pending"
    field :request_payload, :map, default: %{}
    field :response_payload, :map
    field :failure_reason, :string
    field :submitted_at, :utc_datetime
    field :completed_at, :utc_datetime
    belongs_to :payment_intent, Dunda.Checkout.PaymentIntent
    timestamps()
  end
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:payment_intent_id, :provider, :attempt_key, :provider_checkout_id, :status, :request_payload, :response_payload, :failure_reason, :submitted_at, :completed_at])
    |> validate_required([:payment_intent_id, :provider, :attempt_key, :status])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:payment_intent)
    |> unique_constraint(:attempt_key)
    |> unique_constraint(:provider_checkout_id)
  end
end
