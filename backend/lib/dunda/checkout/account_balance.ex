defmodule Dunda.Checkout.AccountBalance do
  use Ecto.Schema
  @primary_key false
  schema "account_balances" do
    field :account_id, :binary_id, primary_key: true
    field :currency, :string, primary_key: true
    field :balance_cents, :integer, default: 0
    field :updated_at, :utc_datetime
  end
end
