defmodule Dunda.Accounts do
  @moduledoc """
  Account context for independent users: email/password registration + login and
  OAuth (Google/Apple/…) find-or-create. The original phone/M-Pesa user creation
  remains available via `Dunda.Accounts.User.changeset/2`.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Accounts.User
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

  Matches first on `(auth_provider, provider_uid)`, then links by email if an
  account with that email already exists, otherwise creates a new account.
  """
  @spec upsert_oauth_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
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
          %User{} = existing -> link_oauth(existing, attrs)
          _ -> create_oauth(attrs)
        end
    end
  end

  defp create_oauth(attrs) do
    %User{} |> User.oauth_changeset(attrs) |> Repo.insert()
  end

  defp link_oauth(user, attrs) do
    user |> User.oauth_changeset(attrs) |> Repo.update()
  end
end
