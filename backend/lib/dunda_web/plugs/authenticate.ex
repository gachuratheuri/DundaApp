defmodule DundaWeb.Plugs.Authenticate do
  @moduledoc """
  Verifies the `Authorization: Bearer <token>` header, loads the user, and
  assigns `:current_user`. On any failure it halts with `401`.

  Use in a router pipeline:

      pipeline :authenticated do
        plug DundaWeb.Plugs.Authenticate
      end
  """
  import Plug.Conn

  alias Dunda.Accounts
  alias Dunda.Accounts.Token

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, user_id} <- Token.verify(token),
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ -> unauthorized(conn)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when byte_size(token) > 0 -> {:ok, token}
      _ -> :error
    end
  end

  defp unauthorized(conn) do
    body = Phoenix.json_library().encode!(%{error: "unauthorized"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
