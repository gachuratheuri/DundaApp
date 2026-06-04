defmodule Dunda.Accounts.Token do
  @moduledoc """
  Stateless bearer tokens for the mobile API, signed with the endpoint's
  `secret_key_base` via `Phoenix.Token`. Tokens carry the user id and expire
  after `@max_age` seconds.

  Stateless is appropriate for a mobile client; if per-device revocation is
  later required this can be swapped for a DB-backed `users_tokens` table behind
  the same `sign/1` + `verify/1` API.
  """
  @salt "dunda user auth"
  @max_age 60 * 60 * 24 * 60

  @spec sign(Dunda.Accounts.User.t()) :: String.t()
  def sign(%{id: id}) do
    Phoenix.Token.sign(DundaWeb.Endpoint, @salt, id)
  end

  @spec verify(String.t()) :: {:ok, integer()} | {:error, :invalid | :expired}
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(DundaWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, user_id} -> {:ok, user_id}
      {:error, :expired} -> {:error, :expired}
      {:error, _} -> {:error, :invalid}
    end
  end

  def verify(_), do: {:error, :invalid}
end
