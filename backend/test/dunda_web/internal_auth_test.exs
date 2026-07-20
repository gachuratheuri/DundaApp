defmodule DundaWeb.InternalAuthTest do
  use ExUnit.Case, async: false

  import Plug.Test

  setup do
    previous = Application.get_env(:dunda, :metrics_token)
    Application.put_env(:dunda, :metrics_token, "phase5-test-token")

    on_exit(fn -> Application.put_env(:dunda, :metrics_token, previous) end)
    :ok
  end

  test "requires an exact token" do
    valid =
      conn(:get, "/internal/release-health")
      |> Plug.Conn.put_req_header("x-metrics-token", "phase5-test-token")

    invalid =
      conn(:get, "/internal/release-health")
      |> Plug.Conn.put_req_header("x-metrics-token", "wrong")

    assert DundaWeb.InternalAuth.authorized?(valid)
    refute DundaWeb.InternalAuth.authorized?(invalid)
  end
end
