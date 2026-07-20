defmodule Dunda.Events.Extra do
  @moduledoc """
  A non-admission upsell attached to an event (secured parking, merch, locker,
  fast-track). Surfaced in the portal "Extras" step and the checkout upsell.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "event_extras" do
    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :available, :boolean, default: true

    belongs_to :event, Dunda.Events.Event

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(extra, attrs) do
    extra
    |> cast(attrs, [:name, :description, :price_cents, :available, :event_id])
    |> validate_required([:name, :price_cents, :event_id])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> assoc_constraint(:event)
  end
end
