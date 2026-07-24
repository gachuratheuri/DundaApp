defmodule DundaWeb.AuthController do
  use DundaWeb, :controller

  alias Dunda.Accounts
  alias Dunda.Auth.GoogleVerifier
  alias Dunda.Auth.OTP
  alias Dunda.Auth.Sessions

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

        issue_session(conn, user)

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

        issue_session(conn, user)

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
               email: nil,
               name: "Guest User",
               avatar_url: nil
             }) do
          {:ok, user} ->
            _ =
              Dunda.Audit.record_from_conn(conn, "auth.otp_verified", "user", user.id, %{
                provider: "phone"
              })

            issue_session(conn, user)

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

            issue_session(conn, user)

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

  def refresh(conn, %{"refresh_token" => refresh_token} = params) do
    case Sessions.rotate(refresh_token, params["device_id"]) do
      {:ok, session} ->
        render(conn, :auth_success,
          user: session.user,
          token: session.access_token,
          refresh_token: session.refresh_token
        )

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_session"}})
    end
  end

  def refresh(conn, _params), do: invalid_request(conn)

  def logout(conn, params) do
    user = conn.assigns.current_user

    result =
      if params["all_devices"] == true do
        Sessions.revoke_all(user)
      else
        Sessions.revoke(params["refresh_token"])
      end

    case result do
      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: %{code: "logout_failed"}})

      _ ->
        _ = Dunda.Audit.record_from_conn(conn, "auth.logout", "user", user.id, %{})
        send_resp(conn, :no_content, "")
    end
  end

  defp issue_session(conn, user) do
    device_id = conn.body_params["device_id"]

    case Sessions.issue(user, device_id) do
      {:ok, session} ->
        render(conn, :auth_success,
          user: user,
          token: session.access_token,
          refresh_token: session.refresh_token
        )

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: %{code: "session_creation_failed"}})
    end
  end

  defp invalid_request(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "invalid_request"}})
  end
end
