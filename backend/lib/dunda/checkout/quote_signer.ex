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
    Jason.encode!(%{
      "currency" => attrs.currency,
      "event_id" => attrs.event_id,
      "expires_at" => DateTime.to_iso8601(attrs.expires_at),
      "fee_cents" => attrs.fee_cents,
      "price_version" => attrs.price_version,
      "quantity" => attrs.quantity,
      "ticket_tier_id" => attrs.ticket_tier_id,
      "total_cents" => attrs.total_cents,
      "unit_price_cents" => attrs.unit_price_cents,
      "user_id" => attrs.user_id
    })
  end

  defp secret do
    case Application.get_env(:dunda, :quote_signing_secret) do
      value when is_binary(value) and byte_size(value) >= 16 ->
        :crypto.hash(:sha256, value)

      _ ->
        raise "quote_signing_secret must contain at least 16 bytes"
    end
  end
end
