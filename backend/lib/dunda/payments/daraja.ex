defmodule Dunda.Payments.Daraja do
  @moduledoc """
  Behaviour describing the Safaricom Daraja (M-Pesa) integration surface that
  Dunda depends on. Coding to a behaviour lets us swap in `Dunda.Payments.Daraja.Sandbox`
  during tests and the real HTTP client (`Dunda.Payments.Daraja.HTTP`) in prod.

  The concrete implementation is selected at runtime:

      config :dunda, :daraja, adapter: Dunda.Payments.Daraja.HTTP
  """

  @type phone :: String.t()
  @type amount :: pos_integer()
  @type idempotency_key :: String.t()
  @type checkout_request_id :: String.t()
  @type result :: %{String.t() => term()}

  @callback stk_push(phone, amount, idempotency_key) ::
              {:ok, checkout_request_id} | {:error, term()}

  @callback query_status(checkout_request_id) ::
              {:ok, result} | {:error, :pending | term()}

  @callback b2c(phone, amount, remarks :: String.t()) ::
              {:ok, conversation_id :: String.t()} | {:error, term()}

  @doc "Initiate an STK push (Lipa na M-Pesa Online) request."
  @spec stk_push(phone, amount, idempotency_key) ::
          {:ok, checkout_request_id} | {:error, term()}
  def stk_push(phone, amount, idempotency_key),
    do: adapter().stk_push(phone, amount, idempotency_key)

  @doc "Poll the status of a previously initiated STK push (dead-letter path)."
  @spec query_status(checkout_request_id) :: {:ok, result} | {:error, :pending | term()}
  def query_status(checkout_request_id),
    do: adapter().query_status(checkout_request_id)

  @doc "Send a Business-to-Customer payment (organiser payout)."
  @spec b2c(phone, amount, String.t()) :: {:ok, String.t()} | {:error, term()}
  def b2c(phone, amount, remarks), do: adapter().b2c(phone, amount, remarks)

  defp adapter do
    Application.get_env(:dunda, :daraja, [])
    |> Keyword.get(:adapter, Dunda.Payments.Daraja.HTTP)
  end
end
