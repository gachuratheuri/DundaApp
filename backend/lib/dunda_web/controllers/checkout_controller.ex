defmodule DundaWeb.CheckoutController do
  use DundaWeb, :controller
  alias Dunda.Checkout

  def quote(conn, params) do
    if Dunda.Containment.blocked?(:checkout) do
      DundaWeb.ContainmentController.disabled(conn, params)
    else
      case Checkout.create_quote(conn.assigns.current_user.id, params) do
        {:ok, quote} ->
          json(conn, %{
            data: %{
              quote_id: quote.id,
              signature: quote.signature,
              quantity: quote.quantity,
              unit_price_cents: quote.unit_price_cents,
              total_cents: quote.total_cents,
              currency: quote.currency,
              expires_at: quote.expires_at
            }
          })

        {:error, reason} ->
          error(conn, reason)
      end
    end
  end

  def create(conn, params) do
    if Dunda.Containment.blocked?(:checkout) do
      DundaWeb.ContainmentController.disabled(conn, params)
    else
      key = List.first(get_req_header(conn, "idempotency-key")) || params["idempotency_key"]
      attrs = Map.put(params, "idempotency_key", key)

      case Checkout.create_payment_intent(conn.assigns.current_user.id, attrs) do
        {:ok, intent} ->
          Logger.metadata(payment_intent_id: intent.id)

          conn
          |> put_status(:accepted)
          |> json(%{
            data: %{
              payment_intent_id: intent.id,
              state: intent.state,
              amount_cents: intent.amount_cents,
              currency: intent.currency,
              redirect_url: intent.redirect_url
            }
          })

        {:error, reason} ->
          error(conn, reason)
      end
    end
  end

  def status(conn, %{"id" => id}) do
    case Checkout.get_payment_intent_for_user(id, conn.assigns.current_user.id) do
      nil ->
        error(conn, :payment_intent_not_found)

      intent ->
        Logger.metadata(payment_intent_id: intent.id)

        json(conn, %{
          data: %{
            payment_intent_id: intent.id,
            state: intent.state,
            amount_cents: intent.amount_cents,
            currency: intent.currency,
            provider_checkout_id: intent.provider_checkout_id
          }
        })
    end
  end

  defp error(conn, :phase_0_containment), do: DundaWeb.ContainmentController.disabled(conn, %{})

  defp error(conn, :payment_intent_not_found),
    do: conn |> put_status(:not_found) |> json(%{error: %{code: "payment_intent_not_found"}})

  defp error(conn, %Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          to_string(Map.get(opts, String.to_existing_atom(key), key))
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_error", details: errors}})
  end

  defp error(conn, reason) do
    code = format_error_code(reason)
    conn |> put_status(:unprocessable_entity) |> json(%{error: %{code: code}})
  end

  defp format_error_code(reason) when is_atom(reason), do: to_string(reason)
  defp format_error_code(reason), do: DundaWeb.ErrorCode.code(reason)
end
