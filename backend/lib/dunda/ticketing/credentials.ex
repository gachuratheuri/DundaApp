defmodule Dunda.Ticketing.Credentials do
  @moduledoc "Device binding and protocol-v2 credential lifecycle."
  import Ecto.Query, only: [from: 2]
  alias Dunda.Repo
  alias Dunda.Ticketing.{CredentialProtocol, Ticket, TicketCredentialEvent, Entitlement}

  @challenge_max_age 300
  @pre_gate_seconds 7_200
  @post_event_seconds 21_600

  def device_challenge(ticket_id, user_id) do
    if Dunda.Containment.blocked?(:ticket_credentials), do: {:error, :phase_0_containment}, else: device_challenge_open(ticket_id, user_id)
  end

  defp device_challenge_open(ticket_id, user_id) do
    with %Ticket{} = ticket <- Repo.get_by(Ticket, id: ticket_id, user_id: user_id),
         true <- ticket.status == "valid" do
      challenge = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      token = Phoenix.Token.sign(DundaWeb.Endpoint, "ticket-device-binding", %{ticket_id: ticket.id, user_id: user_id, challenge: challenge}, max_age: @challenge_max_age)
      {:ok, %{challenge: challenge, token: token, expires_in: @challenge_max_age}}
    else
      nil -> {:error, :ticket_not_found}
      false -> {:error, :ticket_not_bindable}
    end
  end

  def bind_device(ticket_id, user_id, token, public_key, signature, step_up_token \\ nil) do
    if Dunda.Containment.blocked?(:ticket_credentials), do: {:error, :phase_0_containment}, else: bind_device_open(ticket_id, user_id, token, public_key, signature, step_up_token)
  end

  defp bind_device_open(ticket_id, user_id, token, public_key, signature, step_up_token) do
    with {:ok, claims} <- Phoenix.Token.verify(DundaWeb.Endpoint, "ticket-device-binding", token, max_age: @challenge_max_age),
         true <- to_string(Map.get(claims, :ticket_id) || Map.get(claims, "ticket_id")) == to_string(ticket_id) and to_string(Map.get(claims, :user_id) || Map.get(claims, "user_id")) == to_string(user_id),
         true <- CredentialProtocol.valid_public_key?(public_key),
         challenge <- Map.get(claims, :challenge) || Map.get(claims, "challenge"),
         true <- is_binary(challenge),
         true <- CredentialProtocol.verify_device_signature(public_key, CredentialProtocol.canonical_binding(ticket_id, user_id, challenge), signature) do
      bind_locked(ticket_id, user_id, public_key, step_up_token)
    else
      {:error, _} -> {:error, :invalid_device_challenge}
      false -> {:error, :invalid_device_proof}
    end
  end

  defp bind_locked(ticket_id, user_id, public_key, step_up_token) do
    Repo.transaction(fn ->
      ticket = Repo.one(from t in Ticket, where: t.id == ^ticket_id and t.user_id == ^user_id, lock: "FOR UPDATE") || Repo.rollback(:ticket_not_found)
      if ticket.status != "valid", do: Repo.rollback(:ticket_not_bindable)
      if ticket.credential_version == 2 do
        case Dunda.Security.StepUp.verify(step_up_token || "", "ticket_credential_rebind") do
          {:ok, ^user_id} -> :ok
          _ -> Repo.rollback(:step_up_required_for_rebind)
        end
      end
      event = Repo.get!(Dunda.Events.Event, ticket.event_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      valid_from = DateTime.add(event.starts_at, -@pre_gate_seconds, :second)
      valid_until = DateTime.add(event.ends_at || DateTime.add(event.starts_at, 86_400, :second), @post_event_seconds, :second)
      epoch = ticket.credential_epoch + 1
      jwt = Entitlement.mint_device_bound(ticket.id, public_key, valid_from: valid_from, valid_until: valid_until, event_id: event.id, claims: [{"credential_epoch", epoch}])
      event_type = if ticket.credential_version == 1, do: "bound", else: "rebound"
      updated = Repo.update!(Ticket.changeset(ticket, %{credential_version: 2, credential_public_key: public_key, credential_valid_from: valid_from, credential_valid_until: valid_until, credential_bound_at: now, credential_epoch: epoch, jwt: jwt}))
      Repo.insert!(TicketCredentialEvent.changeset(%TicketCredentialEvent{}, %{ticket_id: ticket.id, event_type: event_type, credential_epoch: epoch, public_key_fingerprint: fingerprint(public_key), actor_user_id: user_id, metadata: %{protocol_version: 2}, occurred_at: now}))
      _ = Dunda.Audit.record(%{action: "ticket.credential_#{event_type}", resource_type: "ticket", resource_id: ticket.id, actor_id: user_id, metadata: %{credential_epoch: epoch, protocol_version: 2}})
      updated
    end)
  end

  def revoke_device(ticket_id, actor_id, reason) do
    Repo.transaction(fn ->
      ticket = Repo.one(from t in Ticket, where: t.id == ^ticket_id, lock: "FOR UPDATE") || Repo.rollback(:ticket_not_found)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.update!(Ticket.changeset(ticket, %{revoked_at: now, revocation_reason: reason, status: "revoked", jwt: nil, credential_epoch: ticket.credential_epoch + 1}))
      Repo.insert!(TicketCredentialEvent.changeset(%TicketCredentialEvent{}, %{ticket_id: ticket.id, event_type: "revoked", credential_epoch: ticket.credential_epoch + 1, actor_user_id: actor_id, metadata: %{reason: String.slice(to_string(reason), 0, 240)}, occurred_at: now}))
      :ok
    end)
  end

  defp fingerprint(public_key), do: Base.url_encode64(:crypto.hash(:sha256, public_key), padding: false)
end
