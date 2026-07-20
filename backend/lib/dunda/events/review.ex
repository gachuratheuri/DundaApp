defmodule Dunda.Events.Review do
  @moduledoc """
  A post-event rating (1–5 stars) and optional written review left by an
  attendee from the Tickets "Past" tab. One review per user per event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "reviews" do
    field :rating, :integer
    field :body, :string

    belongs_to :event, Dunda.Events.Event
    belongs_to :user, Dunda.Accounts.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(review, attrs) do
    review
    |> cast(attrs, [:rating, :body, :event_id, :user_id])
    |> validate_required([:rating, :event_id, :user_id])
    |> validate_inclusion(:rating, 1..5)
    |> assoc_constraint(:event)
    |> assoc_constraint(:user)
    |> unique_constraint([:event_id, :user_id])
  end
end
