defmodule Dunda.Billing.Pesapal.HTTP do
  @moduledoc """
  Live Pesapal API 3.0 (JSON) client.

  Auth is a short-lived bearer token from `POST /api/Auth/RequestToken`, cached
  in `:persistent_term` for its advertised lifetime minus a safety margin. All
  config is read from `:dunda, :pesapal` (see `config/runtime.exs`).
  """
  @behaviour Dunda.Billing.Pesapal

  require Logger

  alias Dunda.Billing.Setup

  @token_safety_margin_s 60

  @impl true
  def request_token do
    body = %{
      "consumer_key" => config!(:consumer_key),
      "consumer_secret" => config!(:consumer_secret)
    }

    case Req.post(base_req(), url: "/api/Auth/RequestToken", json: body) do
      {:ok, %{status: 200, body: %{"token" => token} = b}} when is_binary(token) ->
        cache_token(token, expiry_seconds(b))
        {:ok, token}

      {:ok, %{status: status, body: b}} ->
        {:error, {:auth_failed, status, b}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def register_ipn(url) do
    with {:ok, token} <- token() do
      body = %{"url" => url, "ipn_notification_type" => "GET"}

      case post("/api/URLSetup/RegisterIPN", token, body) do
        {:ok, %{"ipn_id" => ipn_id}} when is_binary(ipn_id) -> {:ok, ipn_id}
        {:ok, other} -> {:error, {:unexpected_response, other}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def list_ipns do
    with {:ok, token} <- token() do
      case get("/api/URLSetup/GetIpnList", token) do
        {:ok, list} when is_list(list) -> {:ok, list}
        {:ok, other} -> {:error, {:unexpected_response, other}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def submit_order(order) do
    with {:ok, token} <- token(),
         ipn_id when is_binary(ipn_id) <- Setup.ipn_id() do
      body = %{
        "id" => Map.fetch!(order, :merchant_reference),
        "currency" => Map.get(order, :currency) || "KES",
        "amount" => Map.fetch!(order, :amount_cents) / 100,
        "description" => Map.get(order, :description, "Dunda ticket purchase"),
        "callback_url" => config!(:callback_url),
        "notification_id" => ipn_id,
        "billing_address" => %{
          "phone_number" => Map.get(order, :phone),
          "email_address" => Map.get(order, :email),
          "country_code" => "KE"
        }
      }

      case post("/api/Transactions/SubmitOrderRequest", token, body) do
        {:ok, %{"order_tracking_id" => otid, "redirect_url" => url}} ->
          {:ok, %{order_tracking_id: otid, redirect_url: url}}

        {:ok, other} ->
          {:error, {:unexpected_response, other}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      nil -> {:error, :ipn_not_registered}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def transaction_status(order_tracking_id) do
    with {:ok, token} <- token() do
      path = "/api/Transactions/GetTransactionStatus?orderTrackingId=#{order_tracking_id}"

      case get(path, token) do
        {:ok, %{} = status} -> {:ok, status}
        {:ok, other} -> {:error, {:unexpected_response, other}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # ── Auth / token cache ───────────────────────────────────────────────────────

  defp token do
    case :persistent_term.get({__MODULE__, :token}, nil) do
      {tok, expiry} ->
        if System.monotonic_time(:second) < expiry, do: {:ok, tok}, else: request_token()

      nil ->
        request_token()
    end
  end

  defp cache_token(token, ttl) do
    expiry = System.monotonic_time(:second) + max(ttl - @token_safety_margin_s, 0)
    :persistent_term.put({__MODULE__, :token}, {token, expiry})
  end

  # Pesapal returns an absolute expiry timestamp; default to 5 minutes if absent.
  defp expiry_seconds(%{"expiryDate" => iso}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> max(DateTime.diff(dt, DateTime.utc_now()), 60)
      _ -> 300
    end
  end

  defp expiry_seconds(_), do: 300

  # ── HTTP plumbing ─────────────────────────────────────────────────────────────

  defp post(path, token, body) do
    case Req.post(base_req(), url: path, headers: bearer(token), json: body) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> log_and_return(path, status, body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp get(path, token) do
    case Req.get(base_req(), url: path, headers: bearer(token)) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> log_and_return(path, status, body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp log_and_return(path, status, body) do
    Logger.warning("[Pesapal] #{path} returned #{status}: #{inspect(Dunda.Logging.Redactor.redact(body))}")
    {:error, {:http_status, status, body}}
  end

  defp bearer(token), do: [{"authorization", "Bearer #{token}"}, {"accept", "application/json"}]

  defp base_req do
    Req.new(base_url: config!(:base_url), retry: :transient, max_retries: 2, receive_timeout: 20_000)
  end

  defp config!(key), do: Application.fetch_env!(:dunda, :pesapal) |> Keyword.fetch!(key)
end
