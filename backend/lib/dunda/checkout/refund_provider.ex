defmodule Dunda.Checkout.RefundProvider do
  @moduledoc """
  Provider-neutral refund boundary.

  Implementations must treat the supplied idempotency key as stable for the
  lifetime of the payment intent. A transport timeout must never be interpreted
  as provider success.
  """

  alias Dunda.Checkout.PaymentIntent

  @type result ::
          {:ok, %{status: :succeeded, provider_reference: String.t()}}
          | {:ok, %{status: :pending, provider_reference: String.t()}}
          | {:manual_review, term()}
          | {:error, term()}

  @callback submit(PaymentIntent.t(), idempotency_key :: String.t()) :: result()

  @spec submit(PaymentIntent.t(), String.t()) :: result()
  def submit(%PaymentIntent{} = intent, idempotency_key) do
    adapter().submit(intent, idempotency_key)
  end

  defp adapter do
    Application.get_env(:dunda, :checkout_refund_provider, [])
    |> Keyword.get(:adapter, Dunda.Checkout.RefundProvider.Disabled)
  end
end
