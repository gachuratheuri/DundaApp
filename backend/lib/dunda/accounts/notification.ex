defmodule Dunda.Accounts.Notification do
  @moduledoc """
  An in-app notification and push payload record.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}

  schema "notifications" do
    field :type, :string
    field :title, :string
    field :body, :string
    field :data, :map, default: %{}
    field :read_at, :utc_datetime

    belongs_to :user, Dunda.Accounts.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:type, :title, :body, :data, :read_at, :user_id])
    |> validate_required([:type, :title, :data, :user_id])
    |> assoc_constraint(:user)
  end
end
