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
      when request_type in @request_types do
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
        _ = Dunda.Audit.record(%{actor_user_id: user_id, action: "privacy.request_created", resource_type: "data_subject_request", resource_id: request.id, metadata: %{request_type: request_type}})
        result

      error -> error
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
           user: %{id: user.id, email: user.email, name: user.name, auth_provider: user.auth_provider},
           tickets:
             Repo.all(from t in Dunda.Ticketing.Ticket,
               where: t.user_id == ^user_id,
               select: %{id: t.id, event_id: t.event_id, status: t.status, inserted_at: t.inserted_at}),
           requests:
             Repo.all(from r in DataSubjectRequest,
               where: r.user_id == ^user_id,
               select: %{id: r.id, request_type: r.request_type, status: r.status, due_by: r.due_by})
         }}
    end
  end

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
          _ = Dunda.Audit.record(%{actor_user_id: user_id, action: "privacy.user_anonymised", resource_type: "user", resource_id: to_string(user_id), metadata: %{preserved_financial_evidence: true}})
          anonymised
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} when reason in [:user_not_found] -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
