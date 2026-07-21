defmodule Dunda.Security.StepUp do
  @moduledoc "Short-lived, signed capability for sensitive administrative changes."

  @spec issue(integer(), String.t(), pos_integer()) :: String.t()
  def issue(user_id, purpose, ttl_seconds \\ 300) do
    issued_at = System.system_time(:second)

    payload =
      Jason.encode!(%{
        "user_id" => user_id,
        "purpose" => purpose,
        "iat" => issued_at,
        "exp" => issued_at + ttl_seconds
      })

    encoded = Base.url_encode64(payload, padding: false)
    encoded <> "." <> sign(encoded)
  end

  @spec verify(String.t(), String.t()) :: {:ok, integer()} | {:error, atom()}
  def verify(token, purpose) when is_binary(token) and is_binary(purpose) do
    with [encoded, signature] <- String.split(token, ".", parts: 2),
         true <- secure_equal(signature, sign(encoded)),
         {:ok, payload} <- Base.url_decode64(encoded, padding: false),
         {:ok, claims} <- Jason.decode(payload),
         true <- claims["purpose"] == purpose,
         true <- is_integer(claims["user_id"]),
         true <- is_integer(claims["exp"]) and claims["exp"] >= System.system_time(:second) do
      {:ok, claims["user_id"]}
    else
      _ -> {:error, :invalid_step_up}
    end
  rescue
    _ -> {:error, :invalid_step_up}
  end

  defp sign(encoded) do
    :crypto.mac(:hmac, :sha256, secret(), encoded) |> Base.url_encode64(padding: false)
  end

  defp secure_equal(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_equal(_, _), do: false

  defp secret do
    Application.get_env(:dunda, :step_up_secret, "")
    |> to_string()
    |> then(fn value -> :crypto.hash(:sha256, value) end)
  end
end
