defmodule Dunda.DataCase do
  @moduledoc """
  Test case for tests that interact with the database through `Dunda.Repo`.
  Each test runs inside a transaction that is rolled back on completion.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Dunda.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Dunda.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Dunda.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
