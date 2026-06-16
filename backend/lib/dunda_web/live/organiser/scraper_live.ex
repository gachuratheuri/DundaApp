defmodule DundaWeb.Organiser.ScraperLive do
  @moduledoc """
  The Organiser Portal scraper-configuration surface.

  Editing an organisation's source IDs here writes the `organisations` row that
  `DispatchWorker.dynamic_targets_from_orgs/0` reads on every cron tick. On a
  successful save we ALSO enqueue a `DispatchWorker` job immediately, so newly
  connected sources appear in the catalogue within minutes rather than waiting
  for the next 30-minute tick.
  """
  use DundaWeb, :live_view

  alias Dunda.Organisations
  alias Dunda.Organisations.Organisation
  alias Dunda.Workers.DispatchWorker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:notice, nil)
     |> load_organisations()
     |> select_record(%Organisation{})}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, socket |> assign(:notice, nil) |> select_record(%Organisation{})}
  end

  def handle_event("select", %{"id" => id}, socket) do
    case Organisations.get_organisation(id) do
      nil -> {:noreply, socket}
      org -> {:noreply, socket |> assign(:notice, nil) |> select_record(org)}
    end
  end

  def handle_event("validate", %{"organisation" => params}, socket) do
    form =
      socket.assigns.selected
      |> Organisations.change_organisation(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"organisation" => params}, socket) do
    selected = socket.assigns.selected
    result = save_record(selected, params)

    case result do
      {:ok, org} ->
        # Fire an immediate dispatch so new IDs are picked up without waiting
        # for the next cron tick.
        if org.scraper_enabled, do: Oban.insert(DispatchWorker.new(%{}))

        {:noreply,
         socket
         |> assign(:notice, "Saved “#{org.name}”. Dispatch triggered — sources refresh shortly.")
         |> load_organisations()
         |> select_record(org)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_record(%Organisation{id: nil}, params), do: Organisations.create_organisation(params)
  defp save_record(%Organisation{} = org, params), do: Organisations.update_organisation(org, params)

  defp load_organisations(socket) do
    assign(socket, :organisations, Organisations.list_organisations())
  end

  defp select_record(socket, %Organisation{} = org) do
    socket
    |> assign(:selected, org)
    |> assign(:form, org |> Organisations.change_organisation() |> to_form())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Scraper <span class="text-opticyan">Configuration</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Connect your sources. Saved IDs reconfigure the live scraper instantly.
            </p>
          </div>
          <div>
            <button phx-click="new" class="bg-white/10 border border-white/20 text-white font-bold uppercase tracking-wider text-xs px-5 py-3 hover:bg-white/20 transition-all rounded-none">
              + New Organisation
            </button>
          </div>
        </div>

        <div :if={@notice} class="mb-6 px-4 py-3 border border-opticyan bg-opticyan/10 text-opticyan text-xs font-bold uppercase tracking-widest">
          <%= @notice %>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-10">
          <!-- Left Col: Organisations List -->
          <div class="lg:col-span-1 border border-white/10 bg-abyssnavy p-6">
            <h3 class="text-lg font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3 mb-4">
              Configured Sources
            </h3>
            <div class="space-y-2">
              <button
                :for={org <- @organisations}
                phx-click="select"
                phx-value-id={org.id}
                class={[
                  "w-full text-left px-4 py-3 text-sm font-bold border transition-colors",
                  @selected.id == org.id && "bg-opticyan/10 border-opticyan text-opticyan",
                  @selected.id != org.id && "bg-black/40 border-white/5 text-gray-400 hover:bg-white/5 hover:text-white"
                ]}
              >
                <%= org.name %>
                <span :if={!org.scraper_enabled} class="text-[10px] text-nebulamagenta uppercase tracking-widest ml-2 border border-nebulamagenta/30 px-1 py-0.5">Paused</span>
              </button>
            </div>
          </div>

          <!-- Right Col: Editor Form -->
          <div class="lg:col-span-2 border border-white/10 bg-abyssnavy p-8">
            <h3 class="text-lg font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3 mb-6">
              Source Details
            </h3>
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Organisation Name</label>
                  <input type="text" name={@form[:name].name} value={@form[:name].value} placeholder="e.g. Carnivore Grounds" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none text-white transition-colors" />
                  <.error field={@form[:name]} />
                </div>
                <div>
                  <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Slug</label>
                  <input type="text" name={@form[:slug].name} value={@form[:slug].value} placeholder="carnivore-grounds" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none text-white transition-colors font-mono" />
                  <.error field={@form[:slug]} />
                </div>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label class="block text-xs uppercase tracking-widest text-[#3b5998] font-bold mb-2">Facebook Page ID</label>
                  <input type="text" name={@form[:facebook_page_id].name} value={@form[:facebook_page_id].value} class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-[#3b5998] focus:outline-none text-white transition-colors font-mono" />
                </div>
                <div>
                  <label class="block text-xs uppercase tracking-widest text-[#E1306C] font-bold mb-2">Instagram Account ID</label>
                  <input type="text" name={@form[:instagram_account_id].name} value={@form[:instagram_account_id].value} class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-[#E1306C] focus:outline-none text-white transition-colors font-mono" />
                </div>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label class="block text-xs uppercase tracking-widest text-[#F05537] font-bold mb-2">Eventbrite Org ID</label>
                  <input type="text" name={@form[:eventbrite_org_id].name} value={@form[:eventbrite_org_id].value} class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-[#F05537] focus:outline-none text-white transition-colors font-mono" />
                </div>
                <div>
                  <label class="block text-xs uppercase tracking-widest text-solfeggiogold font-bold mb-2">HTML Scrape URL</label>
                  <input type="text" name={@form[:html_scrape_url].name} value={@form[:html_scrape_url].value} class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-solfeggiogold focus:outline-none text-white transition-colors font-mono" />
                </div>
              </div>

              <div class="border-t border-white/10 pt-6">
                <label class="block text-xs uppercase tracking-widest text-acidgreen font-bold mb-2">M-Pesa Payout Phone (2547XXXXXXXX)</label>
                <input type="tel" name={@form[:mpesa_phone].name} value={@form[:mpesa_phone].value} class="w-full md:w-1/2 bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-acidgreen focus:outline-none text-white transition-colors font-mono" />
                <.error field={@form[:mpesa_phone]} />
              </div>

              <div class="flex items-center gap-3 py-4">
                <input type="hidden" name={@form[:scraper_enabled].name} value="false" />
                <input
                  type="checkbox"
                  id="scraper_enabled"
                  name={@form[:scraper_enabled].name}
                  value="true"
                  checked={@form[:scraper_enabled].value in [true, "true"]}
                  class="w-5 h-5 bg-black border-white/20 text-opticyan focus:ring-opticyan focus:ring-offset-black"
                />
                <label for="scraper_enabled" class="text-sm font-bold text-white uppercase tracking-wider">
                  Enable background scraping for this source
                </label>
              </div>

              <div class="flex items-center gap-4 pt-4 border-t border-white/10">
                <button type="submit" class="bg-opticyan text-black font-black uppercase tracking-wider text-sm px-8 py-4 hover:bg-white transition-all border border-opticyan glow-cyan rounded-none">
                  Save & Dispatch Job
                </button>
                <button type="button" class="border border-white/10 text-gray-400 font-bold uppercase tracking-wider text-sm px-8 py-4 hover:bg-white/5 hover:text-white transition-all rounded-none" phx-click="new">
                  Reset
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Small inline error helper (avoids a full CoreComponents module).
  defp error(assigns) do
    ~H"""
    <span :for={msg <- translate_errors(@field.errors)} class="err"><%= msg %></span>
    """
  end

  defp translate_errors(errors) do
    Enum.map(errors, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
