defmodule DundaWeb.Organiser.SessionController do
  use DundaWeb, :controller

  alias Dunda.Accounts

  @doc """
  Logs in the organiser and redirects to portal dashboard.
  """
  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %Accounts.User{} = user ->
        if DundaWeb.PortalAccess.allowed?(user) do
          conn
          |> put_session(:organiser_user_id, user.id)
          # Prevent session fixation attacks
          |> configure_session(renew: true)
          |> redirect(to: "/portal")
        else
          invalid_login(conn)
        end

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
