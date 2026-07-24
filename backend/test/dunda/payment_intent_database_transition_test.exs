defmodule Dunda.PaymentIntentDatabaseTransitionTest do
  use Dunda.DataCase, async: false

  alias Dunda.Checkout.PaymentIntent

  test "the installed PostgreSQL trigger and application transition graph are identical" do
    %{rows: [[definition]]} =
      Repo.query!(
        "SELECT pg_get_functiondef('dunda_payment_intent_state_guard'::regproc)",
        []
      )

    parsed_edges =
      Regex.scan(
        ~r/OLD\.state = '([^']+)'\s+AND NEW\.state IN \(([^)]+)\)/,
        definition,
        capture: :all_but_first
      )
      |> Map.new(fn [from, targets] ->
        to =
          Regex.scan(~r/'([^']+)'/, targets, capture: :all_but_first)
          |> List.flatten()
          |> Enum.sort()

        {from, to}
      end)

    database_edges =
      Map.new(PaymentIntent.states(), fn state ->
        {state, Map.get(parsed_edges, state, [])}
      end)

    expected_edges =
      PaymentIntent.transitions()
      |> Map.new(fn {from, targets} ->
        {from, targets |> Enum.reject(&(&1 == from)) |> Enum.sort()}
      end)

    assert database_edges == expected_edges
    assert definition =~ "NEW.version <= OLD.version"
  end
end
