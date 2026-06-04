defmodule DundaWeb.BillingController do
  @moduledoc """
  Consumer checkout via Pesapal hosted payment page.

  `POST /api/billing/orders` creates a pending order, submits it to Pesapal and
  returns the `redirect_url` the mobile app opens for the customer to pay.
  """
  use DundaWeb, :controller

  alias Dunda.Billing

  def create(conn, params) do
    attrs = %{
      event_id: params["event_id"],
      organisation_id: params["organisation_id"],
      user_id: params["user_id"],
      amount_cents: params["amount_cents"],
      currency: params["currency"] || "KES",
      quantity: params["quantity"] || 1,
      phone: params["phone"],
      email: params["email"]
    }

    case Billing.create_order(attrs) do
      {:ok, %{order: order, redirect_url: redirect_url}} ->
        conn
        |> put_status(:created)
        |> json(%{
          merchant_reference: order.merchant_reference,
          order_tracking_id: order.order_tracking_id,
          redirect_url: redirect_url,
          status: order.status
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "checkout_failed", detail: inspect(reason)})
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
