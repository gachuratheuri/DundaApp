defmodule Dunda.Ticketing.ScannerDevices do
  @moduledoc "Operator-authorised scanner device registration and revocation."
  import Ecto.Query, only: [from: 2]
  alias Dunda.Repo
  alias Dunda.Ticketing.{ScannerDevice, CredentialProtocol}

  def register(operator_id, attrs) do
    if Dunda.Containment.blocked?(:scanner_admission), do: {:error, :phase_0_containment}, else: register_open(operator_id, attrs)
  end

  defp register_open(operator_id, attrs) do
    with {:ok, public_key} <- CredentialProtocol.decode(attrs[:device_public_key] || attrs["device_public_key"]),
         true <- CredentialProtocol.valid_public_key?(public_key),
         {:ok, event_id} <- event_id(attrs[:event_id] || attrs["event_id"]),
         %Dunda.Events.Event{organisation_id: organisation_id} <- Repo.get(Dunda.Events.Event, event_id),
         :ok <- require_membership(organisation_id, operator_id, ["owner", "admin", "manager", "scanner"]) do
      attrs = %{organisation_id: organisation_id, event_id: event_id, operator_user_id: operator_id, device_name: attrs[:device_name] || attrs["device_name"], device_public_key: public_key, key_fingerprint: fingerprint(public_key), status: "active"}
      Repo.insert(ScannerDevice.changeset(%ScannerDevice{}, attrs))
    else
      false -> {:error, :invalid_device_public_key}
      nil -> {:error, :event_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def revoke(device_id, actor_id, reason) do
    if Dunda.Containment.blocked?(:scanner_admission), do: {:error, :phase_0_containment}, else: revoke_open(device_id, actor_id, reason)
  end

  defp revoke_open(device_id, actor_id, reason) do
    device = Repo.get(ScannerDevice, device_id)
    with %ScannerDevice{} = device <- device,
         :ok <- require_membership(device.organisation_id, actor_id, ["owner", "admin", "manager"]) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.update(ScannerDevice.changeset(device, %{status: "revoked", revoked_at: now, revocation_reason: String.slice(to_string(reason), 0, 240)}))
    else
      nil -> {:error, :scanner_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_membership(organisation_id, user_id, roles) do
    if Repo.exists?(from m in Dunda.Organisations.OrganisationMember, where: m.organisation_id == ^organisation_id and m.user_id == ^user_id and m.role in ^roles and not is_nil(m.accepted_at)), do: :ok, else: {:error, :not_authorised}
  end

  defp event_id(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp event_id(value) when is_binary(value), do: case Integer.parse(value) do {id, ""} when id > 0 -> {:ok, id}; _ -> {:error, :invalid_event_id} end
  defp event_id(_), do: {:error, :invalid_event_id}
  defp fingerprint(public_key), do: Base.url_encode64(:crypto.hash(:sha256, public_key), padding: false)
end
