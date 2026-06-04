defmodule Dunda.Billing.Order do
  @moduledoc """
  A consumer Pesapal order. `merchant_reference` is our idempotent identity sent
  to Pesapal; `order_tracking_id` is Pesapal's identity returned on submit and
  echoed back on the IPN. Payout grouping uses `organisation_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(pending completed failed invalid)
  @payout_statuses ~w(unpaid queued paid)

  schema "orders" do
    field :merchant_reference, :string
    field :order_tracking_id, :string

    field :amount_cents, :integer
    field :currency, :string, default: "KES"
    field :quantity, :integer, default: 1
    field :phone, :string

    field :status, :string, default: "pending"
    field :payout_status, :string, default: "unpaid"
    field :pesapal_status, :string

    belongs_to :event, Dunda.Events.Event
    belongs_to :organisation, Dunda.Organisations.Organisation
    belongs_to :user, Dunda.Accounts.User

    timestamps()
  end

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :merchant_reference,
      :amount_cents,
      :currency,
      :quantity,
      :phone,
      :event_id,
      :organisation_id,
      :user_id
    ])
    |> validate_required([:merchant_reference, :amount_cents, :event_id])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> unique_constraint(:merchant_reference)
  end

  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(order, attrs) do
    order
    |> cast(attrs, [:order_tracking_id, :status, :payout_status, :pesapal_status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:payout_status, @payout_statuses)
    |> unique_constraint(:order_tracking_id)
  end
end
