defmodule DundaWeb.PrivacyController do
  use DundaWeb, :controller

  alias Dunda.Accounts.{DataSubjectRequest, Privacy}
  alias Dunda.Repo

  def create_request(conn, %{"request_type" => request_type}) do
    user = conn.assigns.current_user

    case Privacy.create_request(user.id, request_type, user.email) do
      {:ok, request} ->
        conn
        |> put_status(:accepted)
        |> json(%{
          data: %{
            id: request.id,
            request_type: request.request_type,
            status: request.status,
            due_by: request.due_by
          }
        })

      {:error, :invalid_request_type} ->
        invalid_request(conn)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          errors: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
        })
    end
  end

  def create_request(conn, _params), do: invalid_request(conn)

  def export(conn, _params) do
    case Privacy.export_user(conn.assigns.current_user.id) do
      {:ok, export} ->
        json(conn, %{data: export})

      {:error, :user_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: %{code: "user_not_found"}})
    end
  end

  @doc """
  Processes a data-subject's own request. Dispatch is by the request's own
  recorded `request_type` (never client-supplied), so a client cannot
  reclassify their request to reach a different code path:

    * `rectification` — updates permitted fields (`params["name"]`).
    * `objection` — records an objection; `params["scope"]` is free text.

  Access/erasure/portability requests are not mutated through this endpoint
  (access/portability are read-only exports; erasure is a distinct,
  irreversible operation intentionally not exposed as unauthenticated
  self-service destructive action here).
  """
  def update_request(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    case Repo.get_by(DataSubjectRequest, id: id, user_id: user.id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: %{code: "request_not_found"}})

      %{request_type: "rectification"} ->
        respond_dsr_update(
          conn,
          Privacy.process_rectification(user.id, id, Map.take(params, ["name"]))
        )

      %{request_type: "objection"} ->
        respond_dsr_update(conn, Privacy.record_objection(user.id, id, params["scope"]))

      _other ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "request_type_not_updatable"}})
    end
  end

  defp respond_dsr_update(conn, {:ok, request}) do
    json(conn, %{
      data: %{id: request.id, request_type: request.request_type, status: request.status}
    })
  end

  defp respond_dsr_update(conn, {:error, :not_found}),
    do: conn |> put_status(:not_found) |> json(%{error: %{code: "request_not_found"}})

  defp respond_dsr_update(conn, {:error, :wrong_request_type}),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: %{code: "request_type_not_updatable"}})

  defp respond_dsr_update(conn, {:error, :invalid_transition}),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: %{code: "invalid_transition"}})

  defp respond_dsr_update(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      errors: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    })
  end

  defp invalid_request(conn) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: %{code: "invalid_request"}})
  end
end
