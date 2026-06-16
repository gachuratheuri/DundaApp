defmodule DundaWeb.ChannelCase do
  @moduledoc """
  Test case for channel + socket tests. Provides `Phoenix.ChannelTest`
  helpers (`connect/2`, `subscribe_and_join/3`, `assert_broadcast/2`, …) bound
  to `DundaWeb.Endpoint`, with an isolated DB sandbox per test.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import DundaWeb.ChannelCase

      @endpoint DundaWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Dunda.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
