defmodule DundaWeb.FallbackController do
  @moduledoc """
  Translates `{:error, _}` tuples returned from controller actions into JSON
  error responses with the appropriate HTTP status.
  """
  use DundaWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(error("not_found"))
  end

  def call(conn, {:error, :unprocessable_entity}) do
    conn |> put_status(:unprocessable_entity) |> json(error("invalid_request"))
  end

  def call(conn, {:error, :insufficient_inventory}) do
    conn |> put_status(:conflict) |> json(error("sold_out"))
  end

  def call(conn, {:error, :duplicate_escrow_attempt}) do
    conn |> put_status(:conflict) |> json(error("already_reserved"))
  end

  def call(conn, {:error, :phase_0_containment}) do
    conn
    |> put_status(:service_unavailable)
    |> put_resp_header("retry-after", "86400")
    |> put_resp_header("x-dunda-containment", "phase-0")
    |> json(error("phase_0_containment"))
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    conn |> put_status(:bad_request) |> json(error(Atom.to_string(reason)))
  end

  defp error(code), do: %{error: %{code: code}}
end
