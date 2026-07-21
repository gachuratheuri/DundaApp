defmodule Dunda.Ticketing.Admission do
  @moduledoc """
  Venue-local coordinator admission path.

  The coordinator is the serialisation point for a venue LAN. Independent
  scanners are not presented as globally unique while partitioned; they queue
  their signed admission records for coordinator reconciliation.
  """
  import Ecto.Query, only: [from: 2]
  alias Dunda.Repo

  alias Dunda.Ticketing.{
    CredentialProtocol,
    Entitlement,
    EventManifest,
    ScannerAdmission,
    ScannerDevice,
    Ticket,
    TicketScan
  }

  def admit(operator_id, attrs) when is_map(attrs) do
    if Dunda.Containment.blocked?(:scanner_admission),
      do: {:error, :phase_0_containment},
      else: admit_open(operator_id, attrs)
  end

  defp admit_open(operator_id, attrs) do
    with {:ok, device_id} <- uuid(attrs[:scanner_device_id] || attrs["scanner_device_id"]),
         {:ok, ticket_id} <- uuid(attrs[:ticket_id] || attrs["ticket_id"]),
         {:ok, event_id} <- integer_id(attrs[:event_id] || attrs["event_id"]),
         {:ok, manifest_version} <-
           positive_int(attrs[:manifest_version] || attrs["manifest_version"]),
         {:ok, nonce} <- CredentialProtocol.decode(attrs[:proof_nonce] || attrs["proof_nonce"]),
         {:ok, signature} <-
           CredentialProtocol.decode(attrs[:proof_signature] || attrs["proof_signature"]),
         {:ok, request_nonce} <-
           CredentialProtocol.decode(attrs[:request_nonce] || attrs["request_nonce"]),
         {:ok, request_signature} <-
           CredentialProtocol.decode(attrs[:request_signature] || attrs["request_signature"]),
         {:ok, time_step} <- positive_int(attrs[:time_step] || attrs["time_step"]),
         true <- byte_size(nonce) in 16..64,
         true <- byte_size(signature) == 64,
         true <- byte_size(request_nonce) in 16..64,
         true <- byte_size(request_signature) == 64 do
      Repo.transaction(fn ->
        admit_locked(
          operator_id,
          device_id,
          ticket_id,
          event_id,
          manifest_version,
          nonce,
          signature,
          request_nonce,
          request_signature,
          time_step,
          attrs
        )
      end)
    else
      false -> {:error, :malformed_proof}
      {:error, reason} -> {:error, reason}
    end
  end

  defp admit_locked(
         operator_id,
         device_id,
         ticket_id,
         event_id,
         manifest_version,
         nonce,
         signature,
         request_nonce,
         request_signature,
         time_step,
         attrs
       ) do
    device =
      Repo.one(
        from d in ScannerDevice,
          where:
            d.id == ^device_id and d.operator_user_id == ^operator_id and d.status == "active",
          lock: "FOR UPDATE"
      ) || Repo.rollback(:scanner_not_authorised)

    if device.event_id && device.event_id != event_id,
      do: Repo.rollback(:scanner_event_not_authorised)

    event = Repo.get!(Dunda.Events.Event, event_id)

    if event.organisation_id != device.organisation_id,
      do: Repo.rollback(:scanner_organisation_not_authorised)

    admission_id = attrs[:admission_id] || attrs["admission_id"] || Ecto.UUID.generate()

    request_payload =
      CredentialProtocol.canonical_scanner_request(
        device.id,
        event_id,
        admission_id,
        nonce,
        request_nonce
      )

    if not CredentialProtocol.verify_device_signature(
         device.device_public_key,
         request_payload,
         request_signature
       ),
       do: Repo.rollback(:invalid_scanner_request_signature)

    manifest =
      Repo.one(
        from m in EventManifest,
          where: m.event_id == ^event_id and m.version == ^manifest_version,
          lock: "FOR SHARE"
      ) || Repo.rollback(:manifest_not_found)

    if not Dunda.Ticketing.Manifests.valid?(manifest), do: Repo.rollback(:manifest_invalid)

    ticket =
      Repo.one(from t in Ticket, where: t.id == ^ticket_id, lock: "FOR UPDATE") ||
        Repo.rollback(:ticket_not_found)

    if ticket.event_id != event_id, do: Repo.rollback(:ticket_event_mismatch)
    if not manifest_contains?(manifest, ticket), do: Repo.rollback(:ticket_not_in_manifest)

    proof = %{
      ticket_id: ticket.id,
      event_id: event_id,
      time_step: time_step,
      nonce: nonce,
      credential_public_key: ticket.credential_public_key,
      signature: signature
    }

    jwt = attrs[:jwt] || attrs["jwt"]
    result = validate_ticket(ticket, proof, jwt, event_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    current_step = div(System.system_time(:second), CredentialProtocol.period_seconds())
    clock_offset_seconds = (current_step - time_step) * CredentialProtocol.period_seconds()

    base = %{
      admission_id: admission_id,
      ticket_id: ticket.id,
      event_id: event_id,
      scanner_device_id: device.id,
      manifest_version: manifest_version,
      protocol_version: 2,
      time_step: time_step,
      proof_nonce: nonce,
      proof_signature: signature,
      request_nonce: request_nonce,
      request_signature: request_signature,
      gate: attrs[:gate] || attrs["gate"],
      result: elem(result, 0),
      reason: elem(result, 1),
      clock_offset_seconds: clock_offset_seconds,
      observed_at: parse_time(attrs[:observed_at] || attrs["observed_at"]) || now,
      coordinator_received_at: now
    }

    case Repo.insert(ScannerAdmission.changeset(%ScannerAdmission{}, base),
           on_conflict: :nothing,
           conflict_target: [:ticket_id, :proof_nonce]
         ) do
      {:ok, %ScannerAdmission{id: nil}} ->
        existing = Repo.get_by!(ScannerAdmission, ticket_id: ticket.id, proof_nonce: nonce)
        %{existing | result: "duplicate", reason: "proof_replayed"}

      {:ok, admission} ->
        if elem(result, 0) == "admitted" do
          Repo.update!(
            Ticket.changeset(ticket, %{
              status: "scanned",
              checked_in_at: ticket.checked_in_at || now
            })
          )

          Repo.insert!(
            TicketScan.changeset(%TicketScan{}, %{
              ticket_id: ticket.id,
              event_id: event_id,
              scanner_id: operator_id,
              result: "admitted",
              gate: base.gate,
              reason: "coordinator_admission",
              scanned_at: now
            })
          )
        end

        Repo.update!(Ecto.Changeset.change(device, last_seen_at: now))
        admission

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp validate_ticket(%Ticket{status: status}, _proof, _jwt, _event_id) when status != "valid",
    do: {if(status == "scanned", do: "duplicate", else: "rejected"), "ticket_status_#{status}"}

  defp validate_ticket(%Ticket{credential_version: 1}, _proof, _jwt, _event_id),
    do: {"rejected", "legacy_credential_protocol"}

  defp validate_ticket(%Ticket{credential_public_key: nil}, _proof, _jwt, _event_id),
    do: {"rejected", "credential_not_bound"}

  defp validate_ticket(ticket, proof, jwt, event_id) do
    with {:ok, claims} <- Entitlement.verify_device_bound(jwt),
         true <- to_string(claims["sub"]) == to_string(ticket.id),
         true <- to_string(claims["event_id"]) == to_string(event_id),
         true <- claims["credential_epoch"] in [nil, ticket.credential_epoch],
         {:ok, jwt_key} <-
           Dunda.Ticketing.CredentialProtocol.decode(claims["credential_public_key"]),
         true <- jwt_key == ticket.credential_public_key,
         true <- DateTime.compare(DateTime.utc_now(), ticket.credential_valid_from) != :lt,
         true <- DateTime.compare(DateTime.utc_now(), ticket.credential_valid_until) == :lt,
         :ok <- CredentialProtocol.verify_proof(proof) do
      {"admitted", nil}
    else
      false -> {"rejected", "credential_outside_event_window"}
      {:error, reason} -> {"rejected", to_string(reason)}
    end
  end

  defp manifest_contains?(manifest, %Ticket{
         id: ticket_id,
         credential_public_key: credential_public_key,
         credential_epoch: credential_epoch
       })
       when is_binary(credential_public_key) do
    Enum.any?(
      Map.get(manifest.payload, "tickets", Map.get(manifest.payload, :tickets, [])),
      fn item ->
        item_id = Map.get(item, "ticket_id") || Map.get(item, :ticket_id)
        item_key = Map.get(item, "credential_public_key") || Map.get(item, :credential_public_key)
        item_epoch = Map.get(item, "credential_epoch") || Map.get(item, :credential_epoch)

        to_string(item_id) == to_string(ticket_id) and
          item_key == Base.url_encode64(credential_public_key, padding: false) and
          item_epoch == credential_epoch
      end
    )
  end

  defp manifest_contains?(_, _), do: false

  defp uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_uuid}
    end
  end

  defp uuid(_), do: {:error, :invalid_uuid}
  defp integer_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp integer_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_event_id}
    end
  end

  defp integer_id(_), do: {:error, :invalid_event_id}
  defp positive_int(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, :invalid_integer}
    end
  end

  defp positive_int(_), do: {:error, :invalid_integer}
  defp parse_time(%DateTime{} = value), do: value

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_time(_), do: nil
end
