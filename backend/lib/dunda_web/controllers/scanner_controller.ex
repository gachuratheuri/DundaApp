defmodule DundaWeb.ScannerController do
  use DundaWeb, :controller
  alias Dunda.Ticketing.{Admission, Manifests, ScannerDevices}

  def register_device(conn, params) do
    if Dunda.Containment.blocked?(:scanner_admission),
      do: DundaWeb.ContainmentController.disabled(conn, params),
      else: register_device_open(conn, params)
  end

  defp register_device_open(conn, params) do
    case ScannerDevices.register(conn.assigns.current_user.id, params) do
      {:ok, device} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{id: device.id, key_fingerprint: device.key_fingerprint, status: device.status}
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def revoke_device(conn, %{"id" => id, "reason" => reason}) do
    if Dunda.Containment.blocked?(:scanner_admission),
      do: DundaWeb.ContainmentController.disabled(conn, %{}),
      else: result(conn, ScannerDevices.revoke(id, conn.assigns.current_user.id, reason))
  end

  def manifest(conn, %{"event_id" => event_id}) do
    if Dunda.Containment.blocked?(:scanner_admission),
      do: DundaWeb.ContainmentController.disabled(conn, %{}),
      else: manifest_open(conn, event_id)
  end

  defp manifest_open(conn, event_id) do
    case Manifests.latest_for_operator(event_id, conn.assigns.current_user.id) do
      nil ->
        error(conn, :manifest_not_found)

      manifest ->
        json(conn, %{
          data: %{
            event_id: manifest.event_id,
            version: manifest.version,
            key_id: manifest.key_id,
            payload: manifest.payload,
            payload_hash: manifest.payload_hash,
            signature: Base.url_encode64(manifest.signature, padding: false),
            valid_from: manifest.valid_from,
            valid_until: manifest.valid_until,
            manifest_public_key:
              Base.url_encode64(Dunda.Ticketing.ManifestProtocol.public_key(), padding: false)
          }
        })
    end
  end

  def publish_manifest(conn, %{"event_id" => event_id}) do
    if Dunda.Containment.blocked?(:scanner_admission),
      do: DundaWeb.ContainmentController.disabled(conn, %{}),
      else: publish_manifest_open(conn, event_id)
  end

  defp publish_manifest_open(conn, event_id) do
    case Manifests.publish(event_id, conn.assigns.current_user.id) do
      {:ok, manifest} ->
        json(conn, %{
          data: %{
            event_id: manifest.event_id,
            version: manifest.version,
            key_id: manifest.key_id,
            payload_hash: manifest.payload_hash,
            valid_from: manifest.valid_from,
            valid_until: manifest.valid_until
          }
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def admit(conn, params) do
    if Dunda.Containment.blocked?(:scanner_admission),
      do: DundaWeb.ContainmentController.disabled(conn, params),
      else: admit_open(conn, params)
  end

  defp admit_open(conn, params) do
    case Admission.admit(conn.assigns.current_user.id, params) do
      {:ok, admission} ->
        json(conn, %{
          data: %{
            admission_id: admission.admission_id,
            result: admission.result,
            reason: admission.reason,
            coordinator_received_at: admission.coordinator_received_at
          }
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  defp result(conn, {:ok, value}) when is_map(value), do: json(conn, %{data: value})
  defp result(conn, {:ok, _}), do: json(conn, %{data: %{status: "ok"}})
  defp result(conn, {:error, reason}), do: error(conn, reason)

  defp error(conn, reason),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: %{code: to_string(reason)}})
end
