defmodule DundaWeb.Organiser.LoginLive do
  use DundaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => "", "password" => ""}, as: "user")
    {:ok, assign(socket, form: form, trigger_submit: false, error: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <h2 class="mt-6 text-center text-4xl font-black uppercase tracking-tighter font-oswald text-white">
          Organiser <span class="text-opticyan">Login</span>
        </h2>
        <p class="mt-2 text-center text-xs uppercase tracking-widest text-[#A0A0FF] font-semibold">
          Dunda Live Telemetry & Escrow Portal
        </p>
      </div>

      <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div class="bg-abyssnavy py-8 px-4 border border-white/10 sm:px-10 relative overflow-hidden">
          <div class="absolute top-0 right-0 w-24 h-24 bg-opticyan/10 blur-3xl rounded-full"></div>

          <%= if @error do %>
            <div class="mb-6 p-4 bg-magenta/15 border border-magenta/30 text-xs font-semibold uppercase tracking-wider text-magenta flex items-center gap-2">
              <span class="h-1.5 w-1.5 rounded-full bg-magenta animate-ping"></span>
              <%= @error %>
            </div>
          <% end %>

          <.form for={@form} action={~p"/portal/login"} phx-submit="login" phx-trigger-action={@trigger_submit} class="space-y-6">
            <div>
              <label for="email" class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Email Address</label>
              <input type="email" name="user[email]" value={@form.params["email"]} required class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none text-white transition-colors font-mono" />
            </div>

            <div>
              <label for="password" class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Password</label>
              <input type="password" name="user[password]" value={@form.params["password"]} required class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none text-white transition-colors font-mono" />
            </div>

            <div>
              <button type="submit" class="w-full flex justify-center py-3 px-4 border border-opticyan rounded-none text-sm font-black uppercase tracking-wider text-black bg-opticyan hover:bg-white hover:border-white transition-all transform hover:-translate-y-0.5 glow-cyan">
                Authenticate
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("login", %{"user" => %{"email" => email, "password" => password}}, socket) do
    case Dunda.Accounts.get_user_by_email_and_password(email, password) do
      %Dunda.Accounts.User{} = user ->
        if DundaWeb.PortalAccess.allowed?(user) do
          # Valid credentials, trigger the POST request to the controller to write session
          {:noreply, assign(socket, trigger_submit: true, error: nil)}
        else
          {:noreply, assign(socket, error: "Invalid email or password")}
        end

      _ ->
        {:noreply, assign(socket, error: "Invalid email or password", form: to_form(%{"email" => email, "password" => ""}, as: "user"))}
    end
  end
end
