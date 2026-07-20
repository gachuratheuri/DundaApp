defmodule DundaWeb.Plugs.OrganiserAuthPlug do
  @moduledoc """
  Plug to authenticate requests to the organiser portal.
  Checks the session for `:organiser_user_id`, validates the explicit
  emergency allow-list, and assigns the loaded user to `:current_organiser`.
  Otherwise, redirects the request to `/portal/login` and halts the pipeline.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Dunda.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if user_id = get_session(conn, :organiser_user_id) do
      case Accounts.get_user(user_id) do
        %Accounts.User{} = user ->
          if DundaWeb.PortalAccess.allowed?(user) do
            assign(conn, :current_organiser, user)
          else
            redirect_to_login(conn)
          end

        _ ->
          redirect_to_login(conn)
      end
    else
      redirect_to_login(conn)
    end
  end

  defp redirect_to_login(conn) do
    conn
    |> redirect(to: "/portal/login")
    |> halt()
  end
end
