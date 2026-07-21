defmodule Dunda.Accounts.DataSubjectRequest do
  @moduledoc """
  ODPC Privacy Portal request (access, rectification, erasure, portability, objection).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}

  @request_types ~w(access rectification erasure portability objection)
  @statuses ~w(received in_progress completed rejected)

  schema "data_subject_requests" do
    field :subject_email, :string
    field :request_type, :string
    field :status, :string, default: "received"
    field :notes, :string
    field :due_by, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :user, Dunda.Accounts.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :subject_email,
      :request_type,
      :status,
      :notes,
      :due_by,
      :completed_at,
      :user_id
    ])
    |> validate_required([:request_type, :status])
    |> validate_inclusion(:request_type, @request_types)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:user)
  end
end
