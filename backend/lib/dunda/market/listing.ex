defmodule Dunda.Market.Listing do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "resale_listings" do
    field :asking_price_kes, :integer
    field :status, :string, default: "active"

    belongs_to :ticket, Dunda.Ticketing.Ticket, type: :binary_id
    belongs_to :seller, Dunda.Accounts.User

    timestamps()
  end

  def changeset(listing, attrs) do
    listing
    |> cast(attrs, [:asking_price_kes, :status, :ticket_id, :seller_id])
    |> validate_required([:asking_price_kes, :status, :ticket_id, :seller_id])
    |> validate_inclusion(:status, ["active", "pending", "sold", "cancelled"])
  end
end
