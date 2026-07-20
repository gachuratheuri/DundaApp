defmodule Dunda.Organisations.PayoutItem do
  @moduledoc "One payable order assigned to exactly one payout batch."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  @statuses ~w(queued paid failed manual_review)

  schema "payout_items" do
    field :amount_cents, :integer
    field :currency, :string, default: "KES"
    field :status, :string, default: "queued"
    field :failure_reason, :string

    belongs_to :batch, Dunda.Organisations.PayoutBatch, foreign_key: :payout_batch_id
    belongs_to :order, Dunda.Billing.Order

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:amount_cents, :currency, :status, :failure_reason, :payout_batch_id, :order_id])
    |> validate_required([:amount_cents, :currency, :status, :payout_batch_id, :order_id])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:batch)
    |> assoc_constraint(:order)
    |> unique_constraint(:order_id, name: :payout_items_order_unique)
  end
end
