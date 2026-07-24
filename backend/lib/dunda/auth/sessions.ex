defmodule Dunda.Auth.Sessions do
  @moduledoc """
  Device-scoped rotating sessions.

  Refresh credentials are opaque random values; only SHA-256 digests are
  persisted. Rotation is serialized by a row lock. Reuse of a replaced token
  revokes its whole family and increments the user's authentication version,
  invalidating every outstanding access token.
  """
  import Ecto.Query

  alias Dunda.Accounts.User
  alias Dunda.Auth.RefreshToken
  alias Dunda.Repo
  alias DundaWeb.Auth.Token

  @refresh_ttl_seconds 30 * 86_400

  @spec issue(User.t(), String.t() | nil) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t()}}
          | {:error, term()}
  def issue(%User{} = user, device_id \\ nil) do
    raw = generate_token()
    now = now()

    attrs = %{
      user_id: user.id,
      family_id: Ecto.UUID.generate(),
      token_hash: digest(raw),
      device_id: normalise_device_id(device_id),
      expires_at: DateTime.add(now, @refresh_ttl_seconds, :second)
    }

    case %RefreshToken{} |> RefreshToken.changeset(attrs) |> Repo.insert() do
      {:ok, _record} -> {:ok, %{access_token: Token.sign(user), refresh_token: raw}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec rotate(String.t(), String.t() | nil) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t(), user: User.t()}}
          | {:error, atom()}
  def rotate(raw, device_id \\ nil)

  def rotate(raw, device_id) when is_binary(raw) do
    Repo.transaction(fn ->
      case Repo.one(
             from t in RefreshToken,
               where: t.token_hash == ^digest(raw),
               lock: "FOR UPDATE"
           ) do
        nil ->
          {:error, :invalid_refresh_token}

        %RefreshToken{revoked_at: revoked_at} = old when not is_nil(revoked_at) ->
          detect_reuse!(old)
          {:error, :refresh_token_reuse}

        %RefreshToken{expires_at: expires_at} = old ->
          if DateTime.compare(expires_at, now()) != :gt do
            revoke!(old)
            {:error, :expired_refresh_token}
          else
            rotate_locked!(old, device_id)
          end
      end
    end)
    |> normalise_transaction()
  end

  def rotate(_, _), do: {:error, :invalid_refresh_token}

  @spec revoke(String.t()) :: :ok
  def revoke(raw) when is_binary(raw) do
    Repo.transaction(fn ->
      case Repo.one(
             from t in RefreshToken,
               where: t.token_hash == ^digest(raw),
               lock: "FOR UPDATE"
           ) do
        nil -> :ok
        token -> revoke!(token)
      end
    end)

    :ok
  end

  def revoke(_), do: :ok

  @spec revoke_all(User.t()) :: {:ok, User.t()} | {:error, term()}
  def revoke_all(%User{} = user) do
    Repo.transaction(fn ->
      current = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")
      timestamp = now()

      Repo.update_all(
        from(t in RefreshToken, where: t.user_id == ^current.id and is_nil(t.revoked_at)),
        set: [revoked_at: timestamp, updated_at: timestamp]
      )

      Repo.update!(User.auth_version_changeset(current, current.auth_version + 1))
    end)
  end

  defp rotate_locked!(old, device_id) do
    raw = generate_token()
    timestamp = now()
    user = Repo.get!(User, old.user_id)

    replacement =
      Repo.insert!(
        RefreshToken.changeset(%RefreshToken{}, %{
          user_id: old.user_id,
          family_id: old.family_id,
          token_hash: digest(raw),
          device_id: normalise_device_id(device_id || old.device_id),
          expires_at: DateTime.add(timestamp, @refresh_ttl_seconds, :second)
        })
      )

    Repo.update!(
      RefreshToken.changeset(old, %{
        revoked_at: timestamp,
        last_used_at: timestamp,
        replaced_by_id: replacement.id
      })
    )

    {:ok, %{access_token: Token.sign(user), refresh_token: raw, user: user}}
  end

  defp detect_reuse!(old) do
    timestamp = now()

    Repo.update_all(
      from(t in RefreshToken, where: t.family_id == ^old.family_id),
      set: [revoked_at: timestamp, reuse_detected_at: timestamp, updated_at: timestamp]
    )

    user = Repo.one!(from u in User, where: u.id == ^old.user_id, lock: "FOR UPDATE")
    Repo.update!(User.auth_version_changeset(user, user.auth_version + 1))

    Dunda.Audit.record(%{
      actor_user_id: user.id,
      action: "auth.refresh_reuse_detected",
      resource_type: "refresh_token_family",
      resource_id: old.family_id,
      metadata: %{device_id: old.device_id}
    })
  end

  defp revoke!(token) do
    if is_nil(token.revoked_at) do
      Repo.update!(RefreshToken.changeset(token, %{revoked_at: now()}))
    end

    :ok
  end

  defp normalise_transaction({:ok, result}), do: result
  defp normalise_transaction({:error, reason}), do: {:error, reason}

  defp generate_token,
    do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp digest(raw), do: :crypto.hash(:sha256, raw)

  defp normalise_device_id(value) when is_binary(value) do
    value |> String.trim() |> String.slice(0, 200) |> empty_to_default()
  end

  defp normalise_device_id(_), do: "unspecified"
  defp empty_to_default(""), do: "unspecified"
  defp empty_to_default(value), do: value
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
