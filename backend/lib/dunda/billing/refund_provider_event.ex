defmodule Dunda.Billing.RefundProviderEvent do
  @moduledoc "Redacted, deduplicated provider evidence for refund reconciliation."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}

  schema "refund_provider_events" do
    field :provider_event_id, :string
    field :payload, :map, default: %{}
    field :outcome, :string
    field :received_at, :utc_datetime

    belongs_to :refund, Dunda.Billing.Refund
    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:provider_event_id, :payload, :outcome, :received_at, :refund_id])
    |> validate_required([:provider_event_id, :received_at, :refund_id])
    |> validate_length(:provider_event_id, min: 3, max: 255)
    |> assoc_constraint(:refund)
    |> unique_constraint(:provider_event_id)
  end
end
