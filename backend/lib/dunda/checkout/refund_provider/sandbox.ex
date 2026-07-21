defmodule Dunda.Checkout.RefundProvider.Sandbox do
  @moduledoc "Deterministic test-only refund adapter."
  @behaviour Dunda.Checkout.RefundProvider

  @impl true
  def submit(intent, idempotency_key) do
    reference =
      :crypto.hash(:sha256, "#{intent.id}:#{idempotency_key}")
      |> Base.url_encode64(padding: false)
      |> then(&"sandbox-refund-#{&1}")

    {:ok, %{status: :succeeded, provider_reference: reference}}
  end
end
