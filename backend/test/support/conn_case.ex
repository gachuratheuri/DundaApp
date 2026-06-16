defmodule DundaWeb.ConnCase do
  @moduledoc """
  Test case for tests that require setting up a connection (controllers / JSON
  endpoints). Each test gets an isolated, rolled-back DB transaction.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint DundaWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import DundaWeb.ConnCase

      use DundaWeb, :verified_routes
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Dunda.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
