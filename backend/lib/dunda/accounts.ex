defmodule Dunda.Accounts do
  @moduledoc """
  Account context for independent users: email/password registration + login and
  OAuth (Google/Apple/…) find-or-create. The original phone/M-Pesa user creation
  remains available via `Dunda.Accounts.User.changeset/2`.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Accounts.{Consent, User}
  alias Dunda.Repo

  @spec get_user(integer() | String.t()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.one(from u in User, where: u.email == ^String.downcase(String.trim(email)))
  end

  @doc "Register an independent email/password user."
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Authenticate by email + password (timing-safe even for unknown emails)."
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    if User.valid_password?(user || %User{}, password), do: user, else: nil
  end

  @doc """
  Find or create a user from a verified OAuth `profile`:

      %{provider: "google", uid: "…", email: "…", name: "…", avatar_url: "…"}

  Matches only on `(auth_provider, provider_uid)`. An OAuth identity is never
  silently linked to an existing password account by email; that would allow a
  provider-side account compromise to take over a local account.
  """
  @spec upsert_oauth_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | atom()}
  def upsert_oauth_user(%{provider: provider, uid: uid} = profile) do
    attrs = %{
      auth_provider: to_string(provider),
      provider_uid: to_string(uid),
      email: profile[:email],
      name: profile[:name],
      avatar_url: profile[:avatar_url]
    }

    case Repo.get_by(User, auth_provider: attrs.auth_provider, provider_uid: attrs.provider_uid) do
      %User{} = user ->
        {:ok, user}

      nil ->
        case attrs.email && get_user_by_email(attrs.email) do
          %User{} -> {:error, :identity_conflict}
          _ -> create_oauth(attrs)
        end
    end
  end

  defp create_oauth(attrs) do
    %User{} |> User.oauth_changeset(attrs) |> Repo.insert()
  end

  @doc """
  Records a versioned consent grant for `purpose` (e.g.
  `"marketing_notifications"`). Revokes any prior active grant for the same
  `(user_id, purpose)` first — `consents_one_active_grant_per_purpose`
  enforces at most one active grant, but re-consent after a policy-version
  change is a new row, not a mutation of the old one, so the history is
  preserved.
  """
  @spec record_consent(integer(), String.t(), String.t()) ::
          {:ok, Consent.t()} | {:error, Ecto.Changeset.t()}
  def record_consent(user_id, purpose, version) do
    Repo.transaction(fn ->
      _ = revoke_active_consent(user_id, purpose)

      case %Consent{}
           |> Consent.changeset(%{
             user_id: user_id,
             purpose: purpose,
             version: version,
             granted_at: DateTime.utc_now() |> DateTime.truncate(:second)
           })
           |> Repo.insert() do
        {:ok, consent} ->
          _ =
            Dunda.Audit.record(%{
              actor_user_id: user_id,
              action: "privacy.consent_granted",
              resource_type: "consent",
              resource_id: consent.id,
              metadata: %{purpose: purpose, version: version}
            })

          consent

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Revokes the active consent grant for `(user_id, purpose)`, if any."
  @spec revoke_consent(integer(), String.t()) ::
          {:ok, Consent.t() | nil} | {:error, Ecto.Changeset.t()}
  def revoke_consent(user_id, purpose) do
    case revoke_active_consent(user_id, purpose) do
      {:ok, nil} = result ->
        result

      {:ok, consent} = result ->
        _ =
          Dunda.Audit.record(%{
            actor_user_id: user_id,
            action: "privacy.consent_revoked",
            resource_type: "consent",
            resource_id: consent.id,
            metadata: %{purpose: purpose}
          })

        result

      {:error, _changeset} = error ->
        error
    end
  end

  @doc "Whether `user_id` currently has an active (granted, not revoked) consent for `purpose`."
  @spec active_consent?(integer(), String.t()) :: boolean()
  def active_consent?(user_id, purpose) do
    Repo.exists?(
      from c in Consent,
        where: c.user_id == ^user_id and c.purpose == ^purpose and is_nil(c.revoked_at)
    )
  end

  defp revoke_active_consent(user_id, purpose) do
    case Repo.one(
           from c in Consent,
             where: c.user_id == ^user_id and c.purpose == ^purpose and is_nil(c.revoked_at)
         ) do
      nil ->
        {:ok, nil}

      consent ->
        consent
        |> Consent.changeset(%{revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()
    end
  end
end
