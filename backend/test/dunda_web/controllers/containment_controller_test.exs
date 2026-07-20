defmodule DundaWeb.ContainmentControllerTest do
  use DundaWeb.ConnCase, async: true

  test "payment initiation is explicitly unavailable during Phase 0", %{conn: conn} do
    conn = post(conn, "/api/checkout", %{})

    assert conn.status == 503
    assert get_resp_header(conn, "x-dunda-containment") == ["phase-0"]
    assert get_resp_header(conn, "retry-after") == ["86400"]
    assert %{"error" => %{"code" => "phase_0_containment"}} = json_response(conn, 503)
  end

  test "all resale reads are blocked rather than exposing mutable listings", %{conn: conn} do
    conn = get(conn, "/api/resale/listings")

    assert conn.status == 503
    assert %{"error" => %{"code" => "phase_0_containment"}} = json_response(conn, 503)
  end
end
