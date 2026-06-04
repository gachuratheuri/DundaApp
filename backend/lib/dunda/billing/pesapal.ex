defmodule Dunda.Billing.Pesapal do
  @moduledoc """
  Behaviour describing the Pesapal API 3.0 surface Dunda depends on. The concrete
  adapter is selected at runtime so tests/dev use `Pesapal.Sandbox` and prod uses
  `Pesapal.HTTP`:

      config :dunda, :pesapal, adapter: Dunda.Billing.Pesapal.HTTP
  """

  @type token :: String.t()
  @type ipn_id :: String.t()
  @type order_tracking_id :: String.t()

  @callback request_token() :: {:ok, token} | {:error, term()}
  @callback register_ipn(url :: String.t()) :: {:ok, ipn_id} | {:error, term()}
  @callback list_ipns() :: {:ok, [map()]} | {:error, term()}
  @callback submit_order(order :: map()) ::
              {:ok, %{order_tracking_id: order_tracking_id, redirect_url: String.t()}}
              | {:error, term()}
  @callback transaction_status(order_tracking_id) :: {:ok, map()} | {:error, term()}

  @spec request_token() :: {:ok, token} | {:error, term()}
  def request_token, do: adapter().request_token()

  @spec register_ipn(String.t()) :: {:ok, ipn_id} | {:error, term()}
  def register_ipn(url), do: adapter().register_ipn(url)

  @spec list_ipns() :: {:ok, [map()]} | {:error, term()}
  def list_ipns, do: adapter().list_ipns()

  @spec submit_order(map()) ::
          {:ok, %{order_tracking_id: order_tracking_id, redirect_url: String.t()}}
          | {:error, term()}
  def submit_order(order), do: adapter().submit_order(order)

  @spec transaction_status(order_tracking_id) :: {:ok, map()} | {:error, term()}
  def transaction_status(id), do: adapter().transaction_status(id)

  defp adapter do
    Application.get_env(:dunda, :pesapal, [])
    |> Keyword.get(:adapter, Dunda.Billing.Pesapal.HTTP)
  end
end
