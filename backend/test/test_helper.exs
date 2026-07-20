ExUnit.start()

# Tests tagged `:redis` exercise the real inventory/escrow engine and need a
# reachable Redis (CI provides one as a service container). Exclude them
# gracefully when Redis is down instead of failing the whole suite.
case Redix.command(:redix, ["PING"]) do
  {:ok, "PONG"} ->
    :ok

  _ ->
    IO.puts("Redis unreachable — excluding :redis-tagged integration tests")
    ExUnit.configure(exclude: [:redis])
end

# Repos run in manual SQL sandbox mode so each test gets an isolated, rolled-back
# transaction. Tests that don't touch the DB simply never check a connection out.
Ecto.Adapters.SQL.Sandbox.mode(Dunda.Repo, :manual)
