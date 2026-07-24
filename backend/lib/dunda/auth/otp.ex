defmodule Dunda.Auth.OTP do
  @moduledoc """
  One-time password lifecycle backed by Redis.

  Only a keyed digest is stored; codes are single-use, expire after five
  minutes, and are never returned by the API. Delivery is delegated to an
  explicitly configured provider and fails closed when none is configured.
  """

  @ttl_seconds 300

  @callback deliver(String.t(), String.t()) :: :ok | {:error, term()}

  @spec send_code(String.t()) :: :ok | {:error, atom()}
  def send_code(phone) do
    with {:ok, phone} <- normalize_phone(phone),
         {:ok, "OK"} <-
           Redix.command(:redix, ["SET", cooldown_key(phone), "1", "EX", "60", "NX"]),
         code <- random_code(),
         digest <- digest(phone, code),
         {:ok, "OK"} <-
           Redix.command(:redix, ["SET", key(phone), digest, "EX", to_string(@ttl_seconds)]),
         {:ok, "OK"} <-
           Redix.command(:redix, ["SET", attempts_key(phone), "0", "EX", to_string(@ttl_seconds)]) do
      case adapter().deliver(phone, code) do
        :ok ->
          :ok

        {:error, _} ->
          Redix.command(:redix, ["DEL", key(phone), attempts_key(phone), cooldown_key(phone)])
          {:error, :otp_unavailable}
      end
    else
      _ -> {:error, :otp_unavailable}
    end
  end

  @spec verify_code(String.t(), String.t()) :: :ok | {:error, atom()}
  def verify_code(phone, code) when is_binary(code) and byte_size(code) == 6 do
    with {:ok, phone} <- normalize_phone(phone),
         digest <- digest(phone, code),
         {:ok, result} <- consume_digest(key(phone), attempts_key(phone), digest) do
      if result == 1, do: :ok, else: {:error, :invalid_otp}
    else
      _ -> {:error, :invalid_otp}
    end
  end

  def verify_code(_, _), do: {:error, :invalid_otp}

  defp consume_digest(otp_key, attempts_key, expected) do
    script = """
    local attempts = redis.call('INCR', KEYS[2])
    if attempts > 5 then
      redis.call('DEL', KEYS[1], KEYS[2])
      return 0
    end
    local value = redis.call('GET', KEYS[1])
    if value and value == ARGV[1] then
      redis.call('DEL', KEYS[1], KEYS[2])
      return 1
    end
    return 0
    """

    Redix.command(:redix, ["EVAL", script, "2", otp_key, attempts_key, expected])
  end

  defp normalize_phone(phone) when is_binary(phone) do
    digits = String.replace(phone, ~r/\D/, "")

    cond do
      String.starts_with?(digits, "254") and byte_size(digits) == 12 ->
        {:ok, digits}

      String.starts_with?(digits, "0") and byte_size(digits) == 10 ->
        {:ok, "254" <> String.slice(digits, 1..-1//1)}

      String.starts_with?(digits, "7") and byte_size(digits) == 9 ->
        {:ok, "254" <> digits}

      String.starts_with?(digits, "1") and byte_size(digits) == 9 ->
        {:ok, "254" <> digits}

      true ->
        {:error, :invalid_phone}
    end
  end

  defp normalize_phone(_), do: {:error, :invalid_phone}

  defp random_code do
    unbiased_integer(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  # Rejection sampling avoids modulo bias from mapping the 2^32 source space
  # into one million codes.
  defp unbiased_integer(modulus) do
    value = :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned()
    acceptance_limit = div(4_294_967_296, modulus) * modulus
    if value < acceptance_limit, do: rem(value, modulus), else: unbiased_integer(modulus)
  end

  defp digest(phone, code) do
    :crypto.mac(:hmac, :sha256, otp_secret(), phone <> ":" <> code)
    |> Base.encode16(case: :lower)
  end

  defp key(phone), do: "auth:otp:v1:#{phone}"
  defp attempts_key(phone), do: "auth:otp:v1:attempts:#{phone}"
  defp cooldown_key(phone), do: "auth:otp:v1:cooldown:#{phone}"

  defp otp_secret do
    Application.get_env(:dunda, :otp_secret) ||
      Application.get_env(:dunda, Dunda.Hashed.HMAC, [])
      |> Keyword.get(:secret, "")
      |> to_string()
  end

  defp adapter do
    Application.get_env(:dunda, :otp, []) |> Keyword.get(:adapter, Dunda.Auth.OTP.Disabled)
  end
end

defmodule Dunda.Auth.OTP.Disabled do
  @behaviour Dunda.Auth.OTP
  @impl true
  def deliver(_phone, _code), do: {:error, :provider_not_configured}
end
