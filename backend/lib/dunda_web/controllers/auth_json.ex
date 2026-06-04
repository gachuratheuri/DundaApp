defmodule DundaWeb.AuthJSON do
  @doc """
  Renders an authentication success response containing the user and token.
  """
  def auth_success(%{user: user, token: token}) do
    %{
      token: token,
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
