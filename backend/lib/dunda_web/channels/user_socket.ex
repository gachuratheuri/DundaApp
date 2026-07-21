defmodule DundaWeb.UserSocket do
  @moduledoc """
  Authenticated client socket for live settlement telemetry (QA FI-01).

  Clients connect with their auth token and subscribe to a per-checkout topic
  (`settlement:<internal_payment_intent_id>`). The channel verifies that the
  authenticated user owns the payment intent before revealing state. The server
  pushes settlement updates as soon
  as the asynchronous M-Pesa callback resolves, so the app no longer depends
  solely on HTTP status polling that can drop under callback-queue latency.
  """
  use Phoenix.Socket

  alias DundaWeb.Auth.Token

  channel("settlement:*", DundaWeb.SettlementChannel)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Token.verify(token) do
      {:ok, user_id} -> {:ok, assign(socket, :user_id, user_id)}
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
