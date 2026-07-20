defmodule Dunda.Checkout.Account do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "accounts" do
    field :code, :string
    field :kind, :string
    field :currency, :string
    field :active, :boolean, default: true
    timestamps(updated_at: false)
  end
end
