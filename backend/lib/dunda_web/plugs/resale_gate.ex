defmodule DundaWeb.Plugs.ResaleGate do
  @moduledoc "Applies the Phase 0/Phase 4 resale gate uniformly to all actions."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Dunda.Containment.blocked?(:resale) do
      conn
      |> DundaWeb.ContainmentController.disabled(%{})
      |> halt()
    else
      conn
    end
  end
end
