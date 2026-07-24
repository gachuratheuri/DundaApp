defmodule Dunda.Auth.LoginThrottle do
  @moduledoc "Fail-closed, privacy-preserving per-account login throttling."

  @limit 10
  @window_seconds 900
  @script """
  local count = redis.call('INCR', KEYS[1])
  if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
  return count
  """

  def consume(identifier) when is_binary(identifier) do
    key = key(identifier)

    case Redix.command(:redix, [
           "EVAL",
           @script,
           "1",
           key,
           Integer.to_string(@window_seconds)
         ]) do
      {:ok, count} when is_integer(count) and count <= @limit -> :ok
      {:ok, _count} -> {:error, :locked}
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def consume(_), do: {:error, :locked}

  def clear(identifier) when is_binary(identifier) do
    _ = Redix.command(:redix, ["DEL", key(identifier)])
    :ok
  end

  defp key(identifier) do
    digest =
      identifier
      |> String.trim()
      |> String.downcase()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "login-throttle:v1:#{digest}"
  end
end
