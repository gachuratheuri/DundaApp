defmodule Dunda.Audit do
  @moduledoc """
  Append-only security and financial audit events.

  Audit metadata is deliberately redacted before persistence.  The database
  migration installs an immutability trigger, so corrections are represented
  by a new event rather than an update or deletion.
  """

  alias Dunda.Audit.Event
  alias Dunda.Repo

  require Logger

  @sensitive_keys ~w(password token authorization cookie otp secret passkey consumer_secret)

  @spec record(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def record(attrs) when is_map(attrs) do
    metadata = Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))

    attrs
    |> Map.put(:metadata, bounded_metadata(metadata))
    |> Map.put_new(:occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> then(&(%Event{} |> Event.changeset(&1) |> Repo.insert()))
    |> case do
      {:ok, _event} = result -> result
      {:error, _changeset} = result ->
        Dunda.Observability.increment(:audit_write_errors)
        Logger.error("audit event write failed")
        result
    end
  end

  @spec record_from_conn(Plug.Conn.t(), String.t(), String.t() | nil, term(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def record_from_conn(conn, action, resource_type, resource_id, metadata \\ %{}) do
    user_id = get_in(conn.assigns, [:current_user, :id]) || get_in(conn.assigns, [:current_organiser, :id])

    record(%{
      actor_user_id: user_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id && to_string(resource_id),
      request_id: List.first(Plug.Conn.get_req_header(conn, "x-request-id")),
      metadata: metadata
    })
  end

  defp redact_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.reject(fn {key, _value} ->
      key |> to_string() |> String.downcase() |> String.contains?(@sensitive_keys)
    end)
    |> Map.new(fn {key, value} -> {to_string(key), redact_value(value)} end)
  end

  defp redact_metadata(_), do: %{}

  defp bounded_metadata(metadata) do
    redacted = redact_metadata(metadata)

    if byte_size(Jason.encode!(redacted)) <= 32_000 do
      redacted
    else
      %{"truncated" => true, "reason" => "metadata_limit_exceeded"}
    end
  rescue
    _ -> %{"truncated" => true, "reason" => "metadata_not_serializable"}
  end

  defp redact_value(value) when is_map(value), do: redact_metadata(value)
  defp redact_value(value) when is_list(value), do: Enum.map(value, &redact_value/1)
  defp redact_value(value) when is_binary(value) and byte_size(value) <= 2_000, do: value
  defp redact_value(value) when is_binary(value), do: String.slice(value, 0, 2_000)
  defp redact_value(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp redact_value(value), do: inspect(value, limit: 20, printable_limit: 500)
end
