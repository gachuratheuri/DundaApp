defmodule DundaWeb.Plugs.AuthPlug do
  @moduledoc """
  Extracts the Bearer token from the Authorization header and verifies it.
  If valid, assigns `:current_user` to the conn.
  If invalid or missing, halts with a 401 Unauthorized response.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_view: 2, render: 2]

  alias Dunda.Accounts
  alias DundaWeb.Auth.Token

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{"user_id" => user_id, "auth_version" => version}} <- Token.verify(token),
         %Accounts.User{auth_version: ^version} = user <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"401")
        |> halt()
    end
  end
end
