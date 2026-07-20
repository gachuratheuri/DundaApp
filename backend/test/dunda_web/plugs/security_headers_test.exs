defmodule DundaWeb.Plugs.SecurityHeadersTest do
  use ExUnit.Case, async: true

  import Plug.Test

  test "sets explicit browser security headers" do
    conn =
      :get
      |> conn("/healthz")
      |> DundaWeb.Plugs.SecurityHeaders.call([])

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    assert get_resp_header(conn, "content-security-policy") != []
  end
end
