defmodule Dunda.Events.EventFavorite do
  @moduledoc """
  A user's saved/favorited event. Powers the "Saved" tab in the Discover feed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "event_favorites" do
    belongs_to :user, Dunda.Accounts.User
    belongs_to :event, Dunda.Events.Event

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:user_id, :event_id])
    |> validate_required([:user_id, :event_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:event)
    |> unique_constraint([:user_id, :event_id])
  end
end
