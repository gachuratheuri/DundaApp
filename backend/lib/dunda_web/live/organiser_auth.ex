defmodule DundaWeb.OrganiserAuth do
  @moduledoc """
  Lifecycle hook for LiveViews in the organiser portal.
  Ensures that the organiser is authenticated by validating the session.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Dunda.Accounts

  def on_mount(:ensure_authenticated, _params, session, socket) do
    if user_id = session["organiser_user_id"] do
      case Accounts.get_user(user_id) do
        %Accounts.User{} = user ->
          if DundaWeb.PortalAccess.allowed?(user) do
            socket = assign_new(socket, :current_organiser, fn -> user end)

            if Dunda.Containment.portal_mutations_blocked?() do
              socket =
                Phoenix.LiveView.attach_hook(
                  socket,
                  :phase_0_read_only,
                  :handle_event,
                  fn _event, _params, socket ->
                    {:halt,
                     Phoenix.LiveView.put_flash(
                       socket,
                       :error,
                       "Portal mutations are disabled by the containment or Phase 4 release gate."
                     )}
                  end
                )

              {:cont, socket}
            else
              {:cont, socket}
            end
          else
            {:halt, redirect(socket, to: "/portal/login")}
          end

        _ ->
          {:halt, redirect(socket, to: "/portal/login")}
      end
    else
      {:halt, redirect(socket, to: "/portal/login")}
    end
  end
end
