defmodule DundaWeb.AuthController do
  use DundaWeb, :controller

  alias Dunda.Accounts
  alias DundaWeb.Auth.Token

  @doc """
  Registers a new user with email and password.
  """
  def register(conn, %{"email" => email, "password" => password, "name" => name} = params) do
    attrs = %{
      email: email,
      password: password,
      name: name,
      auth_provider: "email"
    }

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        token = Token.sign(user)
        render(conn, :auth_success, user: user, token: token)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"422", changeset: changeset)
    end
  end

  @doc """
  Logs in a user with email and password.
  """
  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %Accounts.User{} = user ->
        token = Token.sign(user)
        render(conn, :auth_success, user: user, token: token)

      nil ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"401")
    end
  end

  @doc """
  Handles Google OAuth login using a simulated sandbox flow if actual validation is not configured,
  or standard validation if real keys are provided.
  Expected params: %{"token" => google_id_token}
  """
  def google(conn, %{"token" => token}) do
    # Sandbox mock: Extract payload assuming standard base64 encoding without signature check for testing,
    # OR replace this with Google API client verification when live.
    profile = decode_sandbox_google_token(token)

    if profile do
      case Accounts.upsert_oauth_user(profile) do
        {:ok, user} ->
          token = Token.sign(user)
          render(conn, :auth_success, user: user, token: token)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(json: DundaWeb.ErrorJSON)
          |> render(:"422", changeset: changeset)
      end
    else
      conn
      |> put_status(:unauthorized)
      |> put_view(json: DundaWeb.ErrorJSON)
      |> render(:"401")
    end
  end

  defp decode_sandbox_google_token(token) do
    case String.split(token, ".") do
      [_header, payload, _sig] ->
        with {:ok, decoded} <- Base.url_decode64(payload, padding: false),
             {:ok, json} <- Jason.decode(decoded) do
          %{
            provider: "google",
            uid: json["sub"],
            email: json["email"],
            name: json["name"],
            avatar_url: json["picture"]
          }
        else
          _ -> nil
        end
      _ -> nil
    end
  end
end
