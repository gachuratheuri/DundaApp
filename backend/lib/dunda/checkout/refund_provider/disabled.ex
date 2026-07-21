defmodule Dunda.Checkout.RefundProvider.Disabled do
  @moduledoc "Fail-closed adapter used until a contracted provider refund API is configured."
  @behaviour Dunda.Checkout.RefundProvider

  @impl true
  def submit(_intent, _idempotency_key), do: {:manual_review, :refund_provider_not_configured}
end
