defmodule DundaWeb.PayoutController do
  @moduledoc "Authenticated Daraja B2C result reconciliation endpoint."

  use DundaWeb, :controller

  def result(conn, params) do
    if Dunda.Containment.blocked?(:payouts) do
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: %{code: "phase_0_containment"}})
    else
      with true <- Dunda.Security.Webhook.valid?(conn, :daraja),
           conversation_id when is_binary(conversation_id) <- params["ConversationID"],
           result_code when not is_nil(result_code) <-
             params["ResultCode"] || get_in(params, ["Result", "ResultCode"]) do
        result =
          reconcile(conversation_id, result_code, params["TransactionID"] || params["Receipt"])

        case result do
          {:ok, %Dunda.Organisations.PayoutBatch{} = batch} ->
            json(conn, %{status: "accepted", payout_batch_id: batch.id})

          {:error, reason} ->
            handle_reconciliation_error(conn, reason)
        end
      else
        false ->
          conn
          |> put_status(:unauthorized)
          |> json(%{error: %{code: "invalid_webhook_signature"}})

        {:error, :payout_not_found} ->
          conn |> put_status(:not_found) |> json(%{error: %{code: "payout_not_found"}})

        _ ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: %{code: "invalid_payout_result"}})
      end
    end
  end

  defp reconcile(conversation_id, result_code, receipt) do
    Dunda.Organisations.Payouts.reconcile_batch_provider_result(
      conversation_id,
      result_code,
      receipt
    )
  end

  defp handle_reconciliation_error(conn, :payout_not_found),
    do: conn |> put_status(:not_found) |> json(%{error: %{code: "payout_not_found"}})

  defp handle_reconciliation_error(conn, :payout_batch_not_found),
    do: conn |> put_status(:not_found) |> json(%{error: %{code: "payout_not_found"}})

  defp handle_reconciliation_error(conn, _),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: %{code: "invalid_payout_result"}})
end
