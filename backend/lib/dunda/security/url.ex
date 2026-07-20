defmodule Dunda.Security.URL do
  @moduledoc """SSRF-resistant validation for organiser-controlled HTTP targets."""
  import Bitwise, only: [&&&: 2]

  @max_body_bytes 5_000_000

  @max_redirects 3

  @spec safe_https_url?(term()) :: boolean()
  def safe_https_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: "https", host: host, userinfo: nil, port: port}
      when is_binary(host) and (is_nil(port) or port == 443) ->
        host = String.downcase(host)
        host not in ["localhost", "metadata.google.internal"] and not private_host?(host) and
          allowed_host?(host)

      _ ->
        false
    end
  end

  def safe_https_url?(_), do: false

  @spec max_body_bytes() :: pos_integer()
  def max_body_bytes, do: @max_body_bytes

  @doc "Fetches an HTTPS resource with bounded redirects and re-validation."
  def fetch(url, opts \\ []) do
    timeout = Keyword.get(opts, :receive_timeout, 15_000)
    do_fetch(url, timeout, 0)
  end

  defp do_fetch(url, timeout, redirects) when redirects <= @max_redirects do
    if not safe_https_url?(url) do
      {:error, :unsafe_url}
    else
      case Req.get(url, max_retries: 0, receive_timeout: timeout, decode_body: false, redirect: false) do
        {:ok, %{status: status, headers: headers}} when status in 300..399 ->
          case header(headers, "location") do
            nil -> {:error, :redirect_without_location}
            location ->
              next_url = URI.merge(url, location) |> URI.to_string()
              if redirects == @max_redirects, do: {:error, :too_many_redirects}, else: do_fetch(next_url, timeout, redirects + 1)
          end

        {:ok, %{status: 200, headers: headers, body: body}} ->
          cond do
            body_size_header(headers) > @max_body_bytes -> {:error, :response_too_large}
            is_binary(body) and byte_size(body) <= @max_body_bytes -> {:ok, body}
            true -> {:error, :response_too_large}
          end

        {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) <= @max_body_bytes -> {:ok, body}
        {:ok, %{status: 200}} -> {:error, :response_too_large}
        {:ok, %{status: status}} -> {:error, {:http_status, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp do_fetch(_url, _timeout, _redirects), do: {:error, :too_many_redirects}

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) -> if String.downcase(key) == name, do: value
      _ -> nil
    end)
  end

  defp header(headers, name) when is_map(headers), do: Map.get(headers, name) || Map.get(headers, String.downcase(name))

  defp body_size_header(headers) do
    case header(headers, "content-length") do
      value when is_binary(value) -> case Integer.parse(value) do {size, ""} -> size; _ -> 0 end
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  defp private_host?(host) do
    v4 = :inet.getaddrs(String.to_charlist(host), :inet)
    v6 = :inet.getaddrs(String.to_charlist(host), :inet6)

    case {v4, v6} do
      {{:ok, addresses}, {:ok, addresses6}} -> Enum.any?(addresses ++ addresses6, &private_ip?/1)
      {{:ok, addresses}, _} -> Enum.any?(addresses, &private_ip?/1)
      {_, {:ok, addresses6}} -> Enum.any?(addresses6, &private_ip?/1)
      _ -> true
    end
  end

  defp private_ip?({a, b, c, d}) do
    a == 0 or a == 10 or a == 127 or (a == 169 and b == 254) or
      (a == 172 and b in 16..31) or (a == 192 and b == 168) or
      a >= 224 or {a, b, c, d} == {255, 255, 255, 255}
  end

  defp private_ip?({a, b, c, d, e, f, g, h}) do
    all_zero = {a, b, c, d, e, f, g, h} == {0, 0, 0, 0, 0, 0, 0, 0}
    loopback = {a, b, c, d, e, f, g, h} == {0, 0, 0, 0, 0, 0, 0, 1}
    unique_local = (a &&& 0xFE00) == 0xFC00
    link_local = (a &&& 0xFFC0) == 0xFE80
    multicast = (a &&& 0xFF00) == 0xFF00
    all_zero or loopback or unique_local or link_local or multicast
  end

  defp allowed_host?(host) do
    configured = Application.get_env(:dunda, :scraper_allowed_hosts, [])

    (configured == [] and not Application.get_env(:dunda, :scraper_require_allowlist, false)) or
      Enum.any?(configured, fn suffix ->
        suffix = suffix |> to_string() |> String.downcase() |> String.trim()
        host == suffix or String.ends_with?(host, "." <> suffix)
      end)
  end
end
