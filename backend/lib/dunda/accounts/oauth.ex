defmodule Dunda.Accounts.OAuth do
  @moduledoc """
  Behaviour for verifying a client-supplied OAuth credential (e.g. a Google ID
  token from the mobile Google Sign-In SDK) and returning a normalised profile:

      %{provider: "google", uid: "…", email: "…", name: "…", avatar_url: "…"}

  The adapter is runtime-selected so dev/test use `OAuth.Sandbox`:

      config :dunda, :oauth, adapter: Dunda.Accounts.OAuth.Google
  """

  @type profile :: %{
          provider: String.t(),
          uid: String.t(),
          email: String.t() | nil,
          name: String.t() | nil,
          avatar_url: String.t() | nil
        }

  @callback verify(provider :: String.t(), token :: String.t()) ::
              {:ok, profile} | {:error, term()}

  @spec verify(String.t(), String.t()) :: {:ok, profile} | {:error, term()}
  def verify(provider, token), do: adapter().verify(provider, token)

  defp adapter do
    Application.get_env(:dunda, :oauth, [])
    |> Keyword.get(:adapter, Dunda.Accounts.OAuth.Google)
  end
end
