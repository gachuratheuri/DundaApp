defmodule Dunda.MarketTest do
  use ExUnit.Case, async: true

  test "never transfers a listing without an authoritative payment proof" do
    assert {:error, :resale_payment_required} =
             Dunda.Market.execute_purchase(%Dunda.Market.Listing{}, 123)
  end
end
