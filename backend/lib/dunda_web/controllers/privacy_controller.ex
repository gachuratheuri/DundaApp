defmodule DundaWeb.PrivacyController do
  use DundaWeb, :controller

  alias Dunda.Accounts.Privacy

  def create_request(conn, %{"request_type" => request_type}) do
    user = conn.assigns.current_user

    case Privacy.create_request(user.id, request_type, user.email) do
      {:ok, request} ->
        conn
        |> put_status(:accepted)
        |> json(%{data: %{id: request.id, request_type: request.request_type, status: request.status, due_by: request.due_by}})

      {:error, :invalid_request_type} ->
        invalid_request(conn)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)})
    end
  end

  def create_request(conn, _params), do: invalid_request(conn)

  def export(conn, _params) do
    case Privacy.export_user(conn.assigns.current_user.id) do
      {:ok, export} -> json(conn, %{data: export})
      {:error, :user_not_found} -> conn |> put_status(:not_found) |> json(%{error: %{code: "user_not_found"}})
    end
  end

  defp invalid_request(conn) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: %{code: "invalid_request"}})
  end
end
