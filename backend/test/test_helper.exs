ExUnit.start()

# Repos run in manual SQL sandbox mode so each test gets an isolated, rolled-back
# transaction. Tests that don't touch the DB simply never check a connection out.
Ecto.Adapters.SQL.Sandbox.mode(Dunda.Repo, :manual)
