defmodule Dunda.Checkout.QuoteSigner do
  @moduledoc "Binds a quote to its immutable server-derived attributes."

  def sign(attrs) when is_map(attrs) do
    payload = canonical(attrs)
    :crypto.mac(:hmac, :sha256, secret(), payload) |> Base.url_encode64(padding: false)
  end

  def valid?(attrs, signature) when is_binary(signature) do
    expected = sign(attrs)

    byte_size(expected) == byte_size(signature) and
      Plug.Crypto.secure_compare(expected, signature)
  end

  def valid?(_, _), do: false

  def canonical(attrs) do
    [
      attrs.user_id,
      attrs.event_id,
      attrs.ticket_tier_id || "event",
      attrs.quantity,
      attrs.unit_price_cents,
      attrs.fee_cents,
      attrs.total_cents,
      attrs.currency,
      attrs.price_version,
      DateTime.to_iso8601(attrs.expires_at)
    ]
    |> Enum.map(&to_string/1)
    |> Enum.join("|")
  end

  defp secret do
    Application.get_env(:dunda, :quote_signing_secret, "")
    |> to_string()
    |> then(fn value -> :crypto.hash(:sha256, value) end)
  end
end
