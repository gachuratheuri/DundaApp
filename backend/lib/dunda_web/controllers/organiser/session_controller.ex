defmodule DundaWeb.Organiser.SessionController do
  use DundaWeb, :controller

  alias Dunda.Accounts
  alias Dunda.Auth.LoginThrottle

  @doc """
  Logs in the organiser and redirects to portal dashboard.
  """
  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    with :ok <- LoginThrottle.consume(email),
         %Accounts.User{} = user <- Accounts.get_user_by_email_and_password(email, password),
         true <- DundaWeb.PortalAccess.allowed?(user) do
      :ok = LoginThrottle.clear(email)

      conn
      |> put_session(:organiser_user_id, user.id)
      |> configure_session(renew: true)
      |> redirect(to: "/portal")
    else
      _ ->
        invalid_login(conn)
    end
  end

  defp invalid_login(conn) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> redirect(to: "/portal/login")
  end

  @doc """
  Logs out the organiser, clears the session, and redirects to login.
  """
  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/portal/login")
  end
end
