defmodule Dunda.Security.URL do
  @moduledoc "SSRF-resistant validation for organiser-controlled HTTP targets."
  import Bitwise, only: [&&&: 2]

  @max_body_bytes 5_000_000

  @max_redirects 3

  @spec safe_https_url?(term()) :: boolean()
  def safe_https_url?(url) when is_binary(url) do
    match?({:ok, _uri, _addresses}, validate_and_resolve(url))
  end

  def safe_https_url?(_), do: false

  @spec max_body_bytes() :: pos_integer()
  def max_body_bytes, do: @max_body_bytes

  @doc "Returns a query- and credential-free URL suitable for diagnostics."
  def log_safe(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        URI.to_string(%{uri | userinfo: nil, query: nil, fragment: nil})

      _ ->
        "[invalid-url]"
    end
  rescue
    _ -> "[invalid-url]"
  end

  def log_safe(_), do: "[invalid-url]"

  @doc "Fetches an HTTPS resource with bounded redirects and re-validation."
  def fetch(url, opts \\ []) do
    timeout = Keyword.get(opts, :receive_timeout, 15_000)
    do_fetch(url, timeout, 0)
  end

  defp do_fetch(url, timeout, redirects) when redirects <= @max_redirects do
    case validate_and_resolve(url) do
      {:ok, uri, [address | _]} ->
        original_host = String.downcase(uri.host)
        pinned_url = %{uri | host: address |> :inet.ntoa() |> to_string()} |> URI.to_string()

        case Req.get(pinned_url,
               max_retries: 0,
               receive_timeout: timeout,
               decode_body: false,
               redirect: false,
               headers: [{"host", original_host}, {"accept-encoding", "identity"}],
               connect_options: [hostname: original_host]
             ) do
          {:ok, %{status: status, headers: headers}} when status in 300..399 ->
            case header(headers, "location") do
              nil ->
                {:error, :redirect_without_location}

              location ->
                next_url = URI.merge(uri, location) |> URI.to_string()

                if redirects == @max_redirects,
                  do: {:error, :too_many_redirects},
                  else: do_fetch(next_url, timeout, redirects + 1)
            end

          {:ok, %{status: 200, headers: headers, body: body}} ->
            cond do
              body_size_header(headers) > @max_body_bytes -> {:error, :response_too_large}
              is_binary(body) and byte_size(body) <= @max_body_bytes -> {:ok, body}
              true -> {:error, :response_too_large}
            end

          {:ok, %{status: 200, body: body}}
          when is_binary(body) and byte_size(body) <= @max_body_bytes ->
            {:ok, body}

          {:ok, %{status: 200}} ->
            {:error, :response_too_large}

          {:ok, %{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :unsafe_url}
    end
  end

  defp do_fetch(_url, _timeout, _redirects), do: {:error, :too_many_redirects}

  defp header(headers, name) when is_map(headers),
    do: normalise_header(Map.get(headers, name) || Map.get(headers, String.downcase(name)))

  defp normalise_header([value | _]) when is_binary(value), do: value
  defp normalise_header(value), do: value

  defp body_size_header(headers) do
    case header(headers, "content-length") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {size, ""} -> size
          _ -> 0
        end

      value when is_integer(value) ->
        value

      _ ->
        0
    end
  end

  defp validate_and_resolve(url) do
    with %URI{scheme: "https", host: host, userinfo: nil, port: port} = uri <-
           URI.parse(String.trim(url)),
         true <- is_binary(host) and (is_nil(port) or port == 443),
         host = String.downcase(host),
         true <- host not in ["localhost", "metadata.google.internal"],
         true <- allowed_host?(host),
         {:ok, addresses} <- resolve_addresses(host),
         true <- addresses != [] and Enum.all?(addresses, &(not private_ip?(&1))) do
      {:ok, %{uri | host: host}, addresses}
    else
      _ -> {:error, :unsafe_url}
    end
  rescue
    _ -> {:error, :unsafe_url}
  end

  defp resolve_addresses(host) do
    v4 = :inet.getaddrs(String.to_charlist(host), :inet)
    v6 = :inet.getaddrs(String.to_charlist(host), :inet6)

    case {v4, v6} do
      {{:ok, addresses}, {:ok, addresses6}} -> {:ok, addresses ++ addresses6}
      {{:ok, addresses}, _} -> {:ok, addresses}
      {_, {:ok, addresses6}} -> {:ok, addresses6}
      _ -> {:error, :dns_resolution_failed}
    end
  end

  defp private_ip?({a, b, c, d}) do
    cgnat = a == 100 and b >= 64 and b <= 127
    benchmark = a == 198 and (b == 18 or b == 19)

    a == 0 or a == 10 or a == 127 or (a == 169 and b == 254) or
      (a == 172 and b in 16..31) or (a == 192 and b == 168) or
      a >= 224 or {a, b, c, d} == {255, 255, 255, 255} or
      cgnat or benchmark
  end

  defp private_ip?({0, 0, 0, 0, 0, 0xFFFF, g, h}) do
    # IPv4-mapped IPv6 address (::ffff:w.x.y.z)
    a = Bitwise.bsr(g, 8)
    b = Bitwise.band(g, 0xFF)
    c = Bitwise.bsr(h, 8)
    d = Bitwise.band(h, 0xFF)
    private_ip?({a, b, c, d})
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
