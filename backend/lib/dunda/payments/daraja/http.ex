defmodule Dunda.Payments.Daraja.HTTP do
  @moduledoc """
  Live Daraja 3.0 client.

  Authentication is OAuth 2.0 (Consumer Key + Secret -> short-lived bearer
  token). Tokens are cached in-process for their advertised lifetime minus a
  safety margin. All endpoints, credentials and the callback URL are read from
  application config so the same code runs against sandbox and production.

  Config shape (see `config/runtime.exs`):

      config :dunda, :daraja,
        base_url: "https://api.safaricom.co.ke",
        consumer_key: "...",
        consumer_secret: "...",
        shortcode: "174379",
        passkey: "...",
        callback_url: "https://api.dunda.app/mpesa/callback"
  """
  @behaviour Dunda.Payments.Daraja

  require Logger

  @token_safety_margin_s 30

  @impl true
  def stk_push(phone, amount, idempotency_key) do
    with {:ok, token} <- access_token(),
         {:ok, %{timestamp: ts, password: password}} <- stk_credentials() do
      body = %{
        "BusinessShortCode" => config!(:shortcode),
        "Password" => password,
        "Timestamp" => ts,
        "TransactionType" => "CustomerPayBillOnline",
        "Amount" => amount,
        "PartyA" => normalize_msisdn(phone),
        "PartyB" => config!(:shortcode),
        "PhoneNumber" => normalize_msisdn(phone),
        "CallBackURL" => config!(:callback_url),
        "AccountReference" => String.slice(idempotency_key, 0, 12),
        "TransactionDesc" => "Dunda ticket purchase"
      }

      case post("/mpesa/stkpush/v1/processrequest", token, body) do
        {:ok, %{"CheckoutRequestID" => id, "ResponseCode" => "0"}} ->
          {:ok, id}

        {:ok, %{"errorMessage" => msg}} ->
          {:error, {:daraja_error, msg}}

        {:ok, other} ->
          {:error, {:unexpected_response, other}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def query_status(checkout_request_id) do
    with {:ok, token} <- access_token(),
         {:ok, %{timestamp: ts, password: password}} <- stk_credentials() do
      body = %{
        "BusinessShortCode" => config!(:shortcode),
        "Password" => password,
        "Timestamp" => ts,
        "CheckoutRequestID" => checkout_request_id
      }

      case post("/mpesa/stkpushquery/v1/query", token, body) do
        {:ok, %{"ResultCode" => code} = result} when is_binary(code) ->
          {:ok, result}

        # 1032 = request cancelled by user / still processing on some tiers
        {:ok, %{"errorCode" => "500.001.1001"}} ->
          {:error, :pending}

        {:ok, other} ->
          {:error, {:unexpected_response, other}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def b2c(phone, amount, remarks) do
    with {:ok, token} <- access_token() do
      body = %{
        "InitiatorName" => config(:b2c_initiator),
        "SecurityCredential" => config(:b2c_security_credential),
        "CommandID" => "BusinessPayment",
        "Amount" => amount,
        "PartyA" => config(:b2c_shortcode),
        "PartyB" => normalize_msisdn(phone),
        "Remarks" => String.slice(remarks, 0, 100),
        "QueueTimeOutURL" => config(:b2c_result_url),
        "ResultURL" => config(:b2c_result_url),
        "Occasion" => "DundaPayout"
      }

      case post("/mpesa/b2c/v3/paymentrequest", token, body) do
        {:ok, %{"ConversationID" => id, "ResponseCode" => "0"}} -> {:ok, id}
        {:ok, %{"errorMessage" => msg}} -> {:error, {:daraja_error, msg}}
        {:ok, other} -> {:error, {:unexpected_response, other}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # ── Auth ────────────────────────────────────────────────────────────────────

  defp access_token do
    case cached_token() do
      {:ok, token} ->
        {:ok, token}

      :miss ->
        fetch_and_cache_token()
    end
  end

  defp fetch_and_cache_token do
    auth = Base.encode64("#{config!(:consumer_key)}:#{config!(:consumer_secret)}")

    req =
      base_req()
      |> Req.merge(
        url: "/oauth/v1/generate?grant_type=client_credentials",
        headers: [{"authorization", "Basic #{auth}"}]
      )

    case Req.get(req) do
      {:ok, %{status: 200, body: %{"access_token" => token, "expires_in" => expires}}} ->
        ttl = String.to_integer(to_string(expires)) - @token_safety_margin_s
        cache_token(token, ttl)
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:auth_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cached_token do
    case :persistent_term.get({__MODULE__, :token}, nil) do
      {token, expiry} ->
        if System.monotonic_time(:second) < expiry, do: {:ok, token}, else: :miss

      nil ->
        :miss
    end
  end

  defp cache_token(token, ttl) do
    expiry = System.monotonic_time(:second) + max(ttl, 0)
    :persistent_term.put({__MODULE__, :token}, {token, expiry})
  end

  defp stk_credentials do
    ts = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    password = Base.encode64("#{config!(:shortcode)}#{config!(:passkey)}#{ts}")
    {:ok, %{timestamp: ts, password: password}}
  end

  # ── HTTP plumbing ─────────────────────────────────────────────────────────────

  defp post(path, token, body) do
    req =
      base_req()
      |> Req.merge(
        url: path,
        headers: [{"authorization", "Bearer #{token}"}],
        json: body
      )

    case Req.post(req) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Daraja] #{path} returned #{status}: #{inspect(body)}")
        {:ok, body}

      {:error, reason} ->
        Logger.error("[Daraja] #{path} transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp base_req do
    Req.new(
      base_url: config!(:base_url),
      retry: :transient,
      max_retries: 2,
      receive_timeout: 15_000
    )
  end

  defp normalize_msisdn(phone) do
    digits = String.replace(phone, ~r/\D/, "")

    cond do
      String.starts_with?(digits, "254") -> digits
      String.starts_with?(digits, "0") -> "254" <> String.slice(digits, 1..-1//1)
      String.starts_with?(digits, "7") or String.starts_with?(digits, "1") -> "254" <> digits
      true -> digits
    end
  end

  defp config!(key) do
    Application.fetch_env!(:dunda, :daraja)
    |> Keyword.fetch!(key)
  end

  # Non-raising variant for optional (B2C) config.
  defp config(key) do
    Application.get_env(:dunda, :daraja, [])
    |> Keyword.get(key)
  end
end
