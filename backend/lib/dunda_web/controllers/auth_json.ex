defmodule DundaWeb.AuthJSON do
  @doc """
  Renders an authentication success response containing the user and token.
  """
  def auth_success(%{user: user, token: token, refresh_token: refresh_token}) do
    %{
      token: token,
      access_token: token,
      refresh_token: refresh_token,
      token_type: "Bearer",
      expires_in: 900,
      user: %{
        id: user.id,
        email: user.email,
        name: user.name,
        avatar_url: user.avatar_url,
        auth_provider: user.auth_provider
      }
    }
  end
end
