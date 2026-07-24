defmodule Dunda.Accounts.Privacy do
  @moduledoc """
  Data-subject request primitives preserving financial and entitlement evidence.

  Erasure is implemented as irreversible pseudonymisation: ledger entries,
  orders, tickets, scans, and audit events retain their referential history,
  while direct account identifiers and encrypted contact data are removed.
  """

  import Ecto.Query, only: [from: 2]

  alias Dunda.Accounts.{DataSubjectRequest, User}
  alias Dunda.Repo

  @request_types ~w(access rectification erasure portability objection)

  @spec create_request(integer(), String.t(), String.t() | nil) ::
          {:ok, DataSubjectRequest.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create_request(user_id, request_type, subject_email \\ nil)

  def create_request(user_id, request_type, subject_email) when request_type in @request_types do
    due_by = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

    %DataSubjectRequest{}
    |> DataSubjectRequest.changeset(%{
      user_id: user_id,
      subject_email: subject_email,
      request_type: request_type,
      status: "received",
      due_by: due_by
    })
    |> Repo.insert()
    |> case do
      {:ok, request} = result ->
        _ =
          Dunda.Audit.record(%{
            actor_user_id: user_id,
            action: "privacy.request_created",
            resource_type: "data_subject_request",
            resource_id: request.id,
            metadata: %{request_type: request_type}
          })

        result

      error ->
        error
    end
  end

  def create_request(_user_id, _request_type, _subject_email), do: {:error, :invalid_request_type}

  @doc "Returns a minimised export; secrets, password hashes, and tokens are excluded."
  @spec export_user(integer()) :: {:ok, map()} | {:error, :user_not_found}
  def export_user(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        {:ok,
         %{
           user: %{
             id: user.id,
             email: user.email,
             name: user.name,
             auth_provider: user.auth_provider
           },
           tickets:
             Repo.all(
               from t in Dunda.Ticketing.Ticket,
                 where: t.user_id == ^user_id,
                 select: %{
                   id: t.id,
                   event_id: t.event_id,
                   status: t.status,
                   inserted_at: t.inserted_at
                 }
             ),
           orders:
             Repo.all(
               from o in Dunda.Billing.Order,
                 where: o.user_id == ^user_id,
                 select: %{
                   id: o.id,
                   event_id: o.event_id,
                   amount_cents: o.amount_cents,
                   currency: o.currency,
                   quantity: o.quantity,
                   kind: o.kind,
                   status: o.status,
                   refunded_amount_cents: o.refunded_amount_cents,
                   inserted_at: o.inserted_at
                 }
             ),
           payment_intents:
             Repo.all(
               from p in Dunda.Checkout.PaymentIntent,
                 where: p.user_id == ^user_id,
                 select: %{
                   id: p.id,
                   event_id: p.event_id,
                   amount_cents: p.amount_cents,
                   currency: p.currency,
                   quantity: p.quantity,
                   state: p.state,
                   provider: p.provider,
                   inserted_at: p.inserted_at
                 }
             ),
           resale_listings:
             Repo.all(
               from l in Dunda.Market.Listing,
                 where: l.seller_id == ^user_id or l.buyer_id == ^user_id,
                 select: %{
                   id: l.id,
                   ticket_id: l.ticket_id,
                   seller_id: l.seller_id,
                   buyer_id: l.buyer_id,
                   asking_price_cents: l.asking_price_cents,
                   face_value_cents: l.face_value_cents,
                   status: l.status,
                   inserted_at: l.inserted_at
                 }
             ),
           scans:
             Repo.all(
               from s in Dunda.Ticketing.TicketScan,
                 join: t in Dunda.Ticketing.Ticket,
                 on: t.id == s.ticket_id,
                 where: t.user_id == ^user_id,
                 select: %{
                   id: s.id,
                   ticket_id: s.ticket_id,
                   event_id: s.event_id,
                   result: s.result,
                   gate: s.gate,
                   scanned_at: s.scanned_at
                 }
             ),
           memberships:
             Repo.all(
               from m in Dunda.Organisations.OrganisationMember,
                 where: m.user_id == ^user_id,
                 select: %{
                   organisation_id: m.organisation_id,
                   role: m.role,
                   accepted_at: m.accepted_at
                 }
             ),
           consents:
             Repo.all(
               from c in Dunda.Accounts.Consent,
                 where: c.user_id == ^user_id,
                 select: %{
                   purpose: c.purpose,
                   version: c.version,
                   granted_at: c.granted_at,
                   revoked_at: c.revoked_at
                 }
             ),
           requests:
             Repo.all(
               from r in DataSubjectRequest,
                 where: r.user_id == ^user_id,
                 select: %{
                   id: r.id,
                   request_type: r.request_type,
                   status: r.status,
                   due_by: r.due_by
                 }
             )
         }}
    end
  end

  @statuses ~w(received in_progress completed rejected)

  @doc """
  Applies a bounded, safe rectification (display name only — email/phone
  changes go through the existing account-settings/OAuth reverification
  flows, not a generic DSR PATCH, since those fields are also authentication
  identity). Requires the request to belong to `user_id` and be of type
  `"rectification"`; completes the request on success.
  """
  @spec process_rectification(integer(), Ecto.UUID.t(), map()) ::
          {:ok, DataSubjectRequest.t()}
          | {:error, :not_found | :wrong_request_type | :invalid_transition | Ecto.Changeset.t()}
  def process_rectification(user_id, request_id, attrs) do
    with {:ok, request} <- fetch_own_request(user_id, request_id, "rectification"),
         %User{} = user <- Repo.get(User, user_id) || {:error, :not_found},
         {:ok, _user} <- user |> User.rectification_changeset(attrs) |> Repo.update() do
      complete_request(request, %{rectified_fields: attrs |> Map.keys() |> Enum.map(&to_string/1)})
    else
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Records an objection to processing. Objection does not delete or export
  anything automatically — it is a status change plus a durable, auditable
  note of what the subject objected to, for a human to act on (e.g. suppress
  a specific processing purpose). Requires the request to belong to
  `user_id` and be of type `"objection"`.
  """
  @spec record_objection(integer(), Ecto.UUID.t(), String.t() | nil) ::
          {:ok, DataSubjectRequest.t()}
          | {:error, :not_found | :wrong_request_type | :invalid_transition | Ecto.Changeset.t()}
  def record_objection(user_id, request_id, scope \\ nil) do
    with {:ok, request} <- fetch_own_request(user_id, request_id, "objection") do
      transition_status(request, "in_progress", %{notes: objection_note(scope)})
    end
  end

  @doc """
  Operator-driven status transition (`received -> in_progress -> completed
  | rejected`; `completed`/`rejected` are terminal). Intended for ops
  tooling (`mix dunda.dsr_transition`), not end-user self-service.
  """
  @spec transition_status(DataSubjectRequest.t(), String.t(), map()) ::
          {:ok, DataSubjectRequest.t()} | {:error, :invalid_transition | Ecto.Changeset.t()}
  def transition_status(%DataSubjectRequest{} = request, new_status, attrs \\ %{})
      when new_status in @statuses do
    allowed = %{
      "received" => ~w(received in_progress completed rejected),
      "in_progress" => ~w(in_progress completed rejected),
      "completed" => ~w(completed),
      "rejected" => ~w(rejected)
    }

    if new_status in Map.get(allowed, request.status, []) do
      changes =
        attrs
        |> Map.put(:status, new_status)
        |> maybe_put_completed_at(new_status)

      case request |> DataSubjectRequest.changeset(changes) |> Repo.update() do
        {:ok, updated} ->
          _ =
            Dunda.Audit.record(%{
              actor_user_id: request.user_id,
              action: "privacy.request_status_changed",
              resource_type: "data_subject_request",
              resource_id: request.id,
              metadata: %{from: request.status, to: new_status}
            })

          {:ok, updated}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :invalid_transition}
    end
  end

  defp complete_request(request, metadata) do
    case transition_status(request, "completed", %{}) do
      {:ok, updated} ->
        _ =
          Dunda.Audit.record(%{
            actor_user_id: request.user_id,
            action: "privacy.rectification_applied",
            resource_type: "data_subject_request",
            resource_id: request.id,
            metadata: metadata
          })

        {:ok, updated}

      error ->
        error
    end
  end

  defp fetch_own_request(user_id, request_id, expected_type) do
    case Repo.get_by(DataSubjectRequest, id: request_id, user_id: user_id) do
      nil -> {:error, :not_found}
      %{request_type: ^expected_type} = request -> {:ok, request}
      _other -> {:error, :wrong_request_type}
    end
  end

  defp maybe_put_completed_at(changes, status) when status in ["completed", "rejected"],
    do: Map.put(changes, :completed_at, DateTime.utc_now() |> DateTime.truncate(:second))

  defp maybe_put_completed_at(changes, _status), do: changes

  defp objection_note(nil),
    do: "Objection to processing recorded; scope not specified by subject."

  defp objection_note(scope),
    do: "Objection to processing recorded. Scope: #{String.slice(to_string(scope), 0, 500)}"

  @doc "Pseudonymises direct account data while retaining statutory evidence."
  @spec anonymise_user(integer()) :: {:ok, User.t()} | {:error, :user_not_found | term()}
  def anonymise_user(user_id) do
    Repo.transaction(fn ->
      user =
        case Repo.get(User, user_id) do
          nil -> Repo.rollback(:user_not_found)
          user -> user
        end

      pseudonym = "deleted-" <> Ecto.UUID.generate() <> "@dunda.invalid"
      timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.update_all(
        from(o in Dunda.Billing.Order, where: o.user_id == ^user_id),
        set: [phone_encrypted: nil, updated_at: timestamp]
      )

      Repo.update_all(
        from(p in Dunda.Checkout.PaymentIntent, where: p.user_id == ^user_id),
        set: [phone_encrypted: nil, updated_at: timestamp]
      )

      Repo.update_all(
        from(t in Dunda.Ticketing.Ticket, where: t.user_id == ^user_id),
        set: [holder_name: nil, updated_at: timestamp]
      )

      Repo.update_all(
        from(t in Dunda.Auth.RefreshToken, where: t.user_id == ^user_id and is_nil(t.revoked_at)),
        set: [revoked_at: timestamp, updated_at: timestamp]
      )

      Repo.update!(User.auth_version_changeset(user, user.auth_version + 1))

      case user
           |> User.privacy_changeset(%{
             email: pseudonym,
             name: "Deleted user",
             avatar_url: nil,
             auth_provider: "email",
             provider_uid: nil,
             hashed_password: nil,
             phone_msisdn: nil,
             phone_msisdn_hash: nil,
             device_fingerprint: nil,
             confirmed_at: nil
           })
           |> Repo.update() do
        {:ok, anonymised} ->
          _ =
            Dunda.Audit.record(%{
              actor_user_id: user_id,
              action: "privacy.user_anonymised",
              resource_type: "user",
              resource_id: to_string(user_id),
              metadata: %{preserved_financial_evidence: true}
            })

          anonymised

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} when reason in [:user_not_found] -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
