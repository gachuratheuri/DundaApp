defmodule Dunda.Audit.Event do
  @moduledoc """Immutable audit event persisted for security and financial review."""

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}

  schema "audit_events" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :metadata, :map, default: %{}
    field :request_id, :string
    field :occurred_at, :utc_datetime

    belongs_to :actor_user, Dunda.Accounts.User

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_user_id, :action, :resource_type, :resource_id, :metadata, :request_id, :occurred_at])
    |> validate_required([:action, :occurred_at])
    |> validate_length(:action, min: 3, max: 120)
    |> validate_length(:resource_type, max: 120)
    |> validate_length(:resource_id, max: 256)
    |> validate_length(:request_id, max: 256)
    |> assoc_constraint(:actor_user)
  end
end
