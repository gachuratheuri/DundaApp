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

    belongs_to :batch, Dunda.Organisations.PayoutBatch,
      foreign_key: :payout_batch_id,
      type: :binary_id

    belongs_to :order, Dunda.Billing.Order
    belongs_to :payable_entry, Dunda.Checkout.PayableEntry, type: :binary_id

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :amount_cents,
      :currency,
      :status,
      :failure_reason,
      :payout_batch_id,
      :order_id,
      :payable_entry_id
    ])
    |> validate_required([:amount_cents, :currency, :status, :payout_batch_id])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> validate_source()
    |> assoc_constraint(:batch)
    |> assoc_constraint(:order)
    |> assoc_constraint(:payable_entry)
    |> unique_constraint(:order_id, name: :payout_items_order_unique)
    |> unique_constraint(:payable_entry_id, name: :payout_items_payable_entry_unique)
  end

  defp validate_source(changeset) do
    if get_field(changeset, :payable_entry_id) || get_field(changeset, :order_id),
      do: changeset,
      else: add_error(changeset, :payable_entry_id, "a payable source is required")
  end
end
