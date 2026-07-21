defmodule Dunda.Checkout.TicketBatch do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "ticket_batches" do
    field :quantity, :integer
    field :status, :string, default: "created"
    belongs_to :payment_line_item, Dunda.Checkout.PaymentLineItem, type: :binary_id
    has_many :tickets, Dunda.Ticketing.Ticket
    timestamps()
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [:payment_line_item_id, :quantity, :status])
    |> validate_required([:payment_line_item_id, :quantity, :status])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_inclusion(:status, ~w(created fulfilled failed manual_review))
    |> assoc_constraint(:payment_line_item)
    |> unique_constraint(:payment_line_item_id, name: :ticket_batches_line_unique)
  end
end
