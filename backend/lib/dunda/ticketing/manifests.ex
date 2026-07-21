defmodule Dunda.Ticketing.Manifests do
  @moduledoc "Creates and serves signed, bounded event manifests to edge coordinators."
  import Ecto.Query, only: [from: 2]
  alias Dunda.Repo
  alias Dunda.Ticketing.{EventManifest, ManifestProtocol, Ticket}

  def publish(event_id, actor_id) do
    if Dunda.Containment.blocked?(:scanner_admission),
      do: {:error, :phase_0_containment},
      else: publish_open(event_id, actor_id)
  end

  defp publish_open(event_id, actor_id) do
    with %Dunda.Events.Event{} = event <- Repo.get(Dunda.Events.Event, event_id),
         :ok <- authorised?(event.organisation_id, actor_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      version =
        (Repo.one(from m in EventManifest, where: m.event_id == ^event.id, select: max(m.version)) ||
           0) + 1

      payload = payload(event)
      signature = ManifestProtocol.sign(payload)

      attrs = %{
        event_id: event.id,
        version: version,
        key_id: ManifestProtocol.key_id(),
        payload: payload,
        payload_hash:
          Base.encode16(:crypto.hash(:sha256, ManifestProtocol.canonical_payload(payload)),
            case: :lower
          ),
        signature: signature,
        valid_from: DateTime.add(event.starts_at, -7_200, :second),
        valid_until:
          DateTime.add(
            event.ends_at || DateTime.add(event.starts_at, 86_400, :second),
            21_600,
            :second
          ),
        published_at: now
      }

      case Repo.insert(EventManifest.changeset(%EventManifest{}, attrs)) do
        {:ok, manifest} -> {:ok, manifest}
        {:error, changeset} -> {:error, changeset}
      end
    else
      nil -> {:error, :event_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def latest(event_id, now \\ DateTime.utc_now()) do
    Repo.one(
      from m in EventManifest,
        where:
          m.event_id == ^event_id and is_nil(m.revoked_at) and m.valid_from <= ^now and
            m.valid_until > ^now,
        order_by: [desc: m.version],
        limit: 1
    )
  end

  def latest_for_operator(event_id, operator_id, now \\ DateTime.utc_now()) do
    event = Repo.get(Dunda.Events.Event, event_id)

    with %Dunda.Events.Event{organisation_id: organisation_id} <- event,
         :ok <- authorised_scanner?(organisation_id, operator_id) do
      case latest(event_id, now) do
        %EventManifest{} = manifest -> if valid?(manifest, now), do: manifest, else: nil
        nil -> nil
      end
    else
      _ -> nil
    end
  end

  def valid?(%EventManifest{} = manifest, now \\ DateTime.utc_now()) do
    is_nil(manifest.revoked_at) and DateTime.compare(manifest.valid_from, now) != :gt and
      DateTime.compare(manifest.valid_until, now) == :gt and
      ManifestProtocol.verify(manifest.payload, manifest.signature)
  end

  defp payload(event) do
    tickets =
      Repo.all(
        from t in Ticket,
          where:
            t.event_id == ^event.id and t.credential_version == 2 and
              t.status in ["valid", "scanned"],
          select: %{
            ticket_id: t.id,
            credential_public_key: t.credential_public_key,
            credential_epoch: t.credential_epoch
          }
      )
      |> Enum.map(fn ticket ->
        Map.update!(ticket, :credential_public_key, fn key ->
          Base.url_encode64(key, padding: false)
        end)
      end)

    revocations =
      Repo.all(
        from t in Ticket,
          where: t.event_id == ^event.id and t.status in ["transferred", "revoked", "refunded"],
          select: %{
            ticket_id: t.id,
            credential_epoch: t.credential_epoch,
            revoked_at: t.revoked_at
          }
      )

    %{
      protocol_version: 2,
      event_id: event.id,
      event_name: event.name,
      starts_at: DateTime.to_iso8601(event.starts_at),
      ends_at: event.ends_at && DateTime.to_iso8601(event.ends_at),
      tickets: tickets,
      revocations: revocations
    }
  end

  defp authorised?(nil, _), do: {:error, :event_organisation_missing}

  defp authorised?(organisation_id, actor_id) do
    if Repo.exists?(
         from m in Dunda.Organisations.OrganisationMember,
           where:
             m.organisation_id == ^organisation_id and m.user_id == ^actor_id and
               m.role in ["owner", "admin", "manager"] and not is_nil(m.accepted_at)
       ),
       do: :ok,
       else: {:error, :not_authorised}
  end

  defp authorised_scanner?(organisation_id, actor_id) do
    if Repo.exists?(
         from m in Dunda.Organisations.OrganisationMember,
           where:
             m.organisation_id == ^organisation_id and m.user_id == ^actor_id and
               m.role in ["owner", "admin", "manager", "scanner"] and not is_nil(m.accepted_at)
       ),
       do: :ok,
       else: {:error, :not_authorised}
  end
end
