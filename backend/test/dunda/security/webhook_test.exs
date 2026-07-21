defmodule Dunda.Security.WebhookTest do
  @moduledoc """
  Tests `Dunda.Security.Webhook.valid?/2` (fail-closed shared-secret
  verification for provider callbacks) — previously untested per the Phase
  12 gap audit despite gating two live webhook routes
  (`DundaWeb.MpesaController`, `DundaWeb.IpnController`).
  """
  # async: false — one test mutates the global :webhook_secrets Application
  # env (restored via on_exit); avoid racing other concurrently running
  # async test modules that read the same config key.
  use ExUnit.Case, async: false

  import Plug.Test

  alias Dunda.Security.Webhook

  # Matches config/test.exs.
  @daraja_secret "test-daraja-webhook-secret"
  @pesapal_secret "test-pesapal-webhook-secret"

  defp conn_with_secret(secret) do
    conn(:post, "/api/mpesa/callback", %{})
    |> then(fn conn ->
      if secret, do: Plug.Conn.put_req_header(conn, "x-dunda-webhook-secret", secret), else: conn
    end)
  end

  test "accepts the correct shared secret for daraja" do
    assert Webhook.valid?(conn_with_secret(@daraja_secret), :daraja)
  end

  test "accepts the correct shared secret for pesapal" do
    assert Webhook.valid?(conn_with_secret(@pesapal_secret), :pesapal)
  end

  test "rejects a missing secret header" do
    refute Webhook.valid?(conn_with_secret(nil), :daraja)
  end

  test "rejects an incorrect secret" do
    refute Webhook.valid?(conn_with_secret("wrong-secret"), :daraja)
  end

  test "rejects a secret for the wrong provider (daraja secret on the pesapal route)" do
    refute Webhook.valid?(conn_with_secret(@daraja_secret), :pesapal)
  end

  test "rejects a secret of different length without leaking timing information via a crash" do
    refute Webhook.valid?(conn_with_secret("short"), :daraja)
    refute Webhook.valid?(conn_with_secret(String.duplicate("x", 500)), :daraja)
  end

  test "rejects an empty string secret" do
    refute Webhook.valid?(conn_with_secret(""), :daraja)
  end

  test "rejects when no secret is configured for the provider at all" do
    prior = Application.get_env(:dunda, :webhook_secrets)
    Application.put_env(:dunda, :webhook_secrets, daraja: nil, pesapal: nil)
    on_exit(fn -> Application.put_env(:dunda, :webhook_secrets, prior) end)

    refute Webhook.valid?(conn_with_secret("anything"), :daraja)
  end
end
