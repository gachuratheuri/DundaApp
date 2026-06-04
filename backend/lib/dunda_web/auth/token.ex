defmodule DundaWeb.Auth.Token do
  @moduledoc """
  Generates and verifies stateless JWT-like tokens using Phoenix.Token.
  Tokens encode the `user_id` and have a default expiry (e.g., 30 days).
  """

  alias DundaWeb.Endpoint

  @salt "dunda_auth_token_salt"
  @max_age 30 * 86_400 # 30 days

  @doc """
  Signs a token for the given user.
  """
  def sign(%Dunda.Accounts.User{} = user) do
    Phoenix.Token.sign(Endpoint, @salt, user.id)
  end

  @doc """
  Verifies a token and extracts the user_id.
  """
  def verify(token) do
    Phoenix.Token.verify(Endpoint, @salt, token, max_age: @max_age)
  end
end
