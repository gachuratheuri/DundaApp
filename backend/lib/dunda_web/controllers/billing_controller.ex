defmodule DundaWeb.BillingController do
  @moduledoc """
  Consumer checkout via Pesapal hosted payment page.

  `POST /api/billing/orders` creates a pending order, submits it to Pesapal and
  returns the `redirect_url` the mobile app opens for the customer to pay.
  """
  use DundaWeb, :controller

  alias Dunda.Billing

  def create(conn, params) do
    user = conn.assigns.current_user

    attrs = %{
      event_id: params["event_id"],
      ticket_tier_id: params["tier_id"],
      user_id: user.id,
      quantity: params["quantity"] || 1,
      phone: params["phone"],
      idempotency_key: List.first(get_req_header(conn, "idempotency-key"))
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
        |> put_status(error_status(reason))
        |> json(%{error: %{code: error_code(reason)}})
    end
  end

  defp error_status(reason) when reason in [:not_found], do: :not_found
  defp error_status(reason) when reason in [:idempotency_key_required, :invalid_order, :event_not_on_sale, :tier_not_on_sale, :max_per_order_exceeded, :invalid_quantity], do: :unprocessable_entity
  defp error_status(:idempotency_conflict), do: :conflict
  defp error_status(:idempotency_incomplete), do: :conflict
  defp error_status(_), do: :bad_gateway

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_), do: "checkout_failed"

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
