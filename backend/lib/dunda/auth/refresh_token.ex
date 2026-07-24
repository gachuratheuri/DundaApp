defmodule Dunda.Auth.RefreshToken do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "refresh_tokens" do
    field :family_id, Ecto.UUID
    field :token_hash, :binary, redact: true
    field :device_id, :string
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :reuse_detected_at, :utc_datetime
    belongs_to :user, Dunda.Accounts.User
    belongs_to :replaced_by, __MODULE__, type: :binary_id
    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :user_id,
      :family_id,
      :token_hash,
      :device_id,
      :expires_at,
      :last_used_at,
      :revoked_at,
      :reuse_detected_at,
      :replaced_by_id
    ])
    |> validate_required([:user_id, :family_id, :token_hash, :device_id, :expires_at])
    |> validate_length(:device_id, min: 1, max: 200)
    |> assoc_constraint(:user)
    |> unique_constraint(:token_hash)
  end
end
