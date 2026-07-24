defmodule Dunda.Market.Listing do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  schema "resale_listings" do
    field :asking_price_cents, :integer
    field :face_value_cents, :integer
    field :status, :string, default: "active"
    field :sold_at, :utc_datetime
    belongs_to :ticket, Dunda.Ticketing.Ticket, type: :binary_id
    belongs_to :seller, Dunda.Accounts.User
    belongs_to :buyer, Dunda.Accounts.User, foreign_key: :buyer_id
    belongs_to :payment_order, Dunda.Billing.Order, foreign_key: :payment_order_id

    timestamps()
  end

  def changeset(listing, attrs) do
    listing
    |> cast(attrs, [
      :asking_price_cents,
      :face_value_cents,
      :status,
      :sold_at,
      :payment_order_id,
      :ticket_id,
      :seller_id,
      :buyer_id
    ])
    |> validate_required([
      :asking_price_cents,
      :face_value_cents,
      :status,
      :ticket_id,
      :seller_id
    ])
    |> validate_number(:asking_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:face_value_cents, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, ["active", "pending", "sold", "cancelled"])
    |> validate_price_cap()
    |> unique_constraint(:ticket_id, name: :resale_listings_active_ticket_unique)
  end

  defp validate_price_cap(changeset) do
    asking = get_field(changeset, :asking_price_cents)
    face = get_field(changeset, :face_value_cents)

    if is_integer(asking) and is_integer(face) and asking > face,
      do: add_error(changeset, :asking_price_cents, "cannot exceed immutable face value"),
      else: changeset
  end
end
