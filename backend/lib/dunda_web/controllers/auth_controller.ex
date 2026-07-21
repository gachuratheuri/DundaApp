defmodule DundaWeb.AuthController do
  use DundaWeb, :controller

  alias Dunda.Accounts
  alias Dunda.Auth.GoogleVerifier
  alias Dunda.Auth.OTP
  alias DundaWeb.Auth.Token

  @doc """
  Registers a new user with email and password.
  """
  def register(conn, %{"email" => email, "password" => password, "name" => name}) do
    attrs = %{
      email: email,
      password: password,
      name: name,
      auth_provider: "email"
    }

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        _ =
          Dunda.Audit.record_from_conn(conn, "auth.register", "user", user.id, %{
            provider: "email"
          })

        token = Token.sign(user)
        render(conn, :auth_success, user: user, token: token)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"422", changeset: changeset)
    end
  end

  def register(conn, _params), do: invalid_request(conn)

  @doc """
  Logs in a user with email and password.
  """
  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %Accounts.User{} = user ->
        _ =
          Dunda.Audit.record_from_conn(conn, "auth.login", "user", user.id, %{provider: "email"})

        token = Token.sign(user)
        render(conn, :auth_success, user: user, token: token)

      nil ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"401")
    end
  end

  def login(conn, _params), do: invalid_request(conn)

  @doc """
  Sends an OTP through the configured delivery provider. The code is never
  returned by this endpoint.
  """
  def send_otp(conn, %{"phone" => phone}) do
    case OTP.send_code(phone) do
      :ok ->
        json(conn, %{success: true, message: "If the number is eligible, a code was sent."})

      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: %{code: "otp_provider_unavailable"}})
    end
  end

  def send_otp(conn, _params), do: invalid_request(conn)

  @doc """
  Verifies the OTP and logs the user in (or creates a phone-based account).
  """
  def verify_otp(conn, %{"phone" => phone, "otp" => otp}) do
    case OTP.verify_code(phone, otp) do
      :ok ->
        # Upsert phone-based user
        case Accounts.upsert_oauth_user(%{
               provider: "phone",
               uid: phone,
               email: "#{phone}@dunda.app",
               name: "Guest User",
               avatar_url: nil
             }) do
          {:ok, user} ->
            _ =
              Dunda.Audit.record_from_conn(conn, "auth.otp_verified", "user", user.id, %{
                provider: "phone"
              })

            token = Token.sign(user)
            render(conn, :auth_success, user: user, token: token)

          {:error, :identity_conflict} ->
            conn |> put_status(:conflict) |> json(%{error: %{code: "identity_conflict"}})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(json: DundaWeb.ErrorJSON)
            |> render(:"422", changeset: changeset)
        end

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_credentials"}})
    end
  end

  def verify_otp(conn, _params), do: invalid_request(conn)

  @doc """
  Handles Google OAuth login only after provider-side signature and claim
  verification. No client-supplied JWT payload is decoded locally.
  Expected params: %{"token" => google_id_token}
  """
  def google(conn, %{"token" => token}) do
    case GoogleVerifier.verify(token) do
      {:ok, profile} ->
        case Accounts.upsert_oauth_user(profile) do
          {:ok, user} ->
            _ =
              Dunda.Audit.record_from_conn(conn, "auth.oauth_verified", "user", user.id, %{
                provider: "google"
              })

            token = Token.sign(user)
            render(conn, :auth_success, user: user, token: token)

          {:error, :identity_conflict} ->
            conn
            |> put_status(:conflict)
            |> json(%{error: %{code: "identity_conflict"}})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(json: DundaWeb.ErrorJSON)
            |> render(:"422", changeset: changeset)
        end

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"401")
    end
  end

  def google(conn, _params), do: invalid_request(conn)

  defp invalid_request(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "invalid_request"}})
  end
end
