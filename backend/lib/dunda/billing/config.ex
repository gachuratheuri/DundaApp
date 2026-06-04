defmodule Dunda.Billing.Config do
  @moduledoc """
  Tiny key/value table backing durable billing configuration — most importantly
  the Pesapal `ipn_id` (Priority 3 in `Dunda.Billing.Setup.ipn_id/0`). Survives
  pod restarts, unlike the Application-env (ETS) cache at Priority 2.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "billing_config" do
    field :key, :string
    field :value, :string
    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
