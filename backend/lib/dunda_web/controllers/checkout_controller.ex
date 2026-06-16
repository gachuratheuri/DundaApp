defmodule DundaWeb.CheckoutController do
  use DundaWeb, :controller

  alias Dunda.Events
  alias Dunda.Events.Event
  alias Dunda.Payments

  @doc """
  POST /api/checkout

  Body: `{ "event_id": "1", "user_id": "u_123", "phone": "0712345678", "quantity": 2 }`

  Reserves inventory and initiates an M-Pesa STK push. Returns the
  `transaction_id` the client should poll / await a push notification on.
  """
  def create(conn, params) do
    with {:ok, attrs} <- validate(params),
         %Event{} = event <- fetch_event(attrs.event_id),
         amount <- div(event.price_cents, 100) * attrs.quantity,
         {:ok, transaction_id} <-
           Payments.checkout(%{
             tier_id: attrs.event_id,
             user_id: attrs.user_id,
             quantity: attrs.quantity,
             phone: attrs.phone,
             amount: amount
           }) do
      conn
      |> put_status(:accepted)
      |> json(%{data: %{transaction_id: transaction_id, status: "pending", amount: amount}})
    end
  end

  @doc """
  GET /api/checkout/:id/status

  Polls the status of an M-Pesa STK push checkout.
  """
  def status(conn, %{"id" => transaction_id}) do
    cond do
      Dunda.Ledger.settled?(transaction_id) ->
        json(conn, %{data: %{status: "success"}})

      horde_registry_lookup_active?(transaction_id) ->
        json(conn, %{data: %{status: "pending"}})

      true ->
        json(conn, %{data: %{status: "failure"}})
    end
  end

  defp horde_registry_lookup_active?(transaction_id) do
    case Horde.Registry.lookup(Dunda.Payments.TransactionRegistry, transaction_id) do
      [_ | _] -> true
      [] -> false
    end
  end

  defp validate(params) do
    with {:ok, event_id} <- require(params, "event_id"),
         {:ok, user_id} <- require(params, "user_id"),
         {:ok, phone} <- require(params, "phone") do
      quantity = parse_quantity(params["quantity"])
      {:ok, %{event_id: event_id, user_id: user_id, phone: phone, quantity: quantity}}
    end
  end

  defp fetch_event(event_id) do
    case Events.get_event(event_id) do
      nil -> {:error, :not_found}
      event -> event
    end
  end

  defp require(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :unprocessable_entity}
    end
  end

  defp parse_quantity(q) when is_integer(q) and q > 0, do: q

  defp parse_quantity(q) when is_binary(q) do
    case Integer.parse(q) do
      {n, _rest} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_quantity(_), do: 1
end
