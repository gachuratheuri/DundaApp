ExUnit.start()

# Tests tagged `:redis` exercise the real inventory/escrow engine and need a
# reachable Redis (CI provides one as a service container). Exclude them
# gracefully when Redis is down instead of failing the whole suite.
redis_status =
  if Process.whereis(:redix) do
    try do
      Redix.command(:redix, ["PING"])
    catch
      :exit, _reason -> {:error, :redis_unavailable}
    end
  else
    {:error, :redis_not_started}
  end

case redis_status do
  {:ok, "PONG"} ->
    :ok

  _ ->
    if System.get_env("REQUIRE_REDIS_TESTS") == "true" do
      raise "Redis is required for the integration test suite but is unreachable"
    else
      IO.puts("Redis unreachable — excluding :redis-tagged integration tests outside CI")
      ExUnit.configure(exclude: [:redis])
    end
end

# Repos run in manual SQL sandbox mode so each test gets an isolated, rolled-back
# transaction. Tests that don't touch the DB simply never check a connection out.
if Process.whereis(Dunda.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(Dunda.Repo, :manual)
end
