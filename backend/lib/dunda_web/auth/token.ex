defmodule DundaWeb.Auth.Token do
  @moduledoc """
  Generates and verifies stateless JWT-like tokens using Phoenix.Token.
  Tokens encode the user and account-wide authentication version and expire
  after fifteen minutes.
  """

  alias DundaWeb.Endpoint

  @salt "dunda_auth_token_salt"
  @max_age 15 * 60

  @doc """
  Signs a token for the given user.
  """
  def sign(%Dunda.Accounts.User{} = user) do
    Phoenix.Token.sign(Endpoint, @salt, %{
      "user_id" => user.id,
      "auth_version" => user.auth_version || 1
    })
  end

  @doc """
  Verifies a token and extracts its versioned subject.
  """
  def verify(token) do
    Phoenix.Token.verify(Endpoint, @salt, token, max_age: @max_age)
  end
end
