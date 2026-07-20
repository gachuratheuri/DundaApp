defmodule DundaWeb.TicketCredentialController do
  use DundaWeb, :controller
  alias Dunda.Ticketing.Credentials

  def challenge(conn, %{"id" => ticket_id}) do
    if Dunda.Containment.blocked?(:ticket_credentials), do: DundaWeb.ContainmentController.disabled(conn, %{}), else: challenge_open(conn, ticket_id)
  end

  defp challenge_open(conn, ticket_id) do
    case Credentials.device_challenge(ticket_id, conn.assigns.current_user.id) do
      {:ok, challenge} -> json(conn, %{data: challenge})
      {:error, :ticket_not_found} -> error(conn, :not_found, "ticket_not_found")
      {:error, reason} -> error(conn, :unprocessable_entity, to_string(reason))
    end
  end

  def bind(conn, %{"id" => ticket_id, "token" => token, "public_key" => public_key, "signature" => signature} = params) do
    step_up_token = params["step_up_token"]
    if Dunda.Containment.blocked?(:ticket_credentials), do: DundaWeb.ContainmentController.disabled(conn, %{}), else: bind_open(conn, ticket_id, token, public_key, signature, step_up_token)
  end

  defp bind_open(conn, ticket_id, token, public_key, signature, step_up_token) do
    with {:ok, key} <- Dunda.Ticketing.CredentialProtocol.decode(public_key),
         {:ok, sig} <- Dunda.Ticketing.CredentialProtocol.decode(signature),
         {:ok, ticket} <- Credentials.bind_device(ticket_id, conn.assigns.current_user.id, token, key, sig, step_up_token) do
      json(conn, %{data: %{ticket_id: ticket.id, protocol_version: ticket.credential_version, credential_public_key: public_key, credential_epoch: ticket.credential_epoch, jwt: ticket.jwt}})
    else
      {:error, reason} -> error(conn, :unprocessable_entity, to_string(reason))
    end
  end

  def bind(conn, _), do: error(conn, :unprocessable_entity, "device_binding_parameters_required")

  defp error(conn, status, code), do: conn |> put_status(status) |> json(%{error: %{code: code}})
end
