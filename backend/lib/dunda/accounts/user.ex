defmodule Dunda.Accounts.User do
  @moduledoc """
  A Dunda account. Supports three onboarding paths:

    * **phone** — the original M-Pesa flow; `phone_msisdn` is encrypted at rest
      and `phone_msisdn_hash` is a deterministic HMAC blind index.
    * **email** — independent users with an email + bcrypt-hashed password.
    * **oauth** — Google/Apple/etc; identified by `(auth_provider, provider_uid)`.

  Independent (email/OAuth) users may have no phone, so `phone_msisdn` is now
  nullable.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @kyc_statuses ~w(unverified pending verified rejected)
  @oauth_providers ~w(google apple facebook)

  schema "users" do
    field :phone_msisdn, Dunda.Encrypted.Binary
    field :phone_msisdn_hash, Dunda.Hashed.HMAC
    field :kyc_status, :string, default: "unverified"
    field :device_fingerprint, Dunda.Encrypted.Binary

    # Independent-user identity.
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :auth_provider, :string, default: "phone"
    field :provider_uid, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime

    timestamps()
  end

  @doc """
  Phone-based changeset (original M-Pesa flow). The blind-index hash is derived
  automatically from the normalised MSISDN.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:phone_msisdn, :kyc_status, :device_fingerprint])
    |> validate_required([:phone_msisdn])
    |> validate_inclusion(:kyc_status, @kyc_statuses)
    |> put_phone_hash()
    |> unique_constraint(:phone_msisdn_hash)
  end

  @doc "Email + password registration changeset (bcrypt-hashed)."
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :name])
    |> put_change(:auth_provider, "email")
    |> validate_email()
    |> validate_password()
    |> hash_password()
  end

  @doc "Find-or-create changeset for an OAuth profile."
  @spec oauth_changeset(t(), map()) :: Ecto.Changeset.t()
  def oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url, :auth_provider, :provider_uid])
    |> validate_required([:auth_provider, :provider_uid])
    |> validate_inclusion(:auth_provider, @oauth_providers)
    |> validate_email(required: false)
    |> put_change(:confirmed_at, now())
    |> unique_constraint([:auth_provider, :provider_uid])
  end

  @doc "Verify a plaintext password against the stored bcrypt hash (timing-safe)."
  @spec valid_password?(t(), String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end

  # ── Internals ────────────────────────────────────────────────────────────────

  defp put_phone_hash(changeset) do
    case fetch_change(changeset, :phone_msisdn) do
      {:ok, msisdn} -> put_change(changeset, :phone_msisdn_hash, msisdn)
      :error -> changeset
    end
  end

  defp validate_email(changeset, opts \\ []) do
    changeset =
      changeset
      |> update_change(:email, &normalise_email/1)
      |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/, message: "must be a valid email")
      |> unique_constraint(:email)

    if Keyword.get(opts, :required, true),
      do: validate_required(changeset, [:email]),
      else: changeset
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
  end

  defp hash_password(changeset) do
    case changeset do
      %{valid?: true, changes: %{password: password}} ->
        changeset
        |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)

      _ ->
        changeset
    end
  end

  defp normalise_email(nil), do: nil
  defp normalise_email(email), do: email |> String.trim() |> String.downcase()

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
