defmodule DundaWeb.CoreEndpointsContractTest do
  @moduledoc """
  API-contract tests against `priv/openapi/dunda.json`
  (`Dunda.ContractCase`) for the two lowest-risk, dependency-light public
  endpoints. Deliberately does not touch `checkout_controller_test.exs` —
  that suite's success-path assertion (`transaction_id`/`status`) does not
  match `DundaWeb.CheckoutController.create/2`'s actual response shape
  (`payment_intent_id`/`state`); that discrepancy is recorded as a finding
  in `docs/phase_12_verification_observability_rollout.md` rather than
  silently patched over here.
  """
  use DundaWeb.ConnCase, async: true

  import Dunda.ContractCase

  test "GET /healthz matches its contract", %{conn: conn} do
    conn = get(conn, "/healthz")
    body = json_response(conn, 200)
    assert_matches_contract("healthz", 200, body)
  end

  test "GET /api/events matches its contract", %{conn: conn} do
    conn = get(conn, "/api/events")
    body = json_response(conn, 200)
    assert_matches_contract("listEvents", 200, body)
  end
end
