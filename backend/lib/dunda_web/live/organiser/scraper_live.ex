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
    <h1>Scraper Settings</h1>
    <p class="sub">Connect your sources. Saved IDs reconfigure the live scraper with no deploy.</p>

    <div :if={@notice} class="notice"><%= @notice %></div>

    <div class="grid">
      <div class="card orglist">
        <a href="#" phx-click="new" class={is_nil(@selected.id) && "active"}>+ New organisation</a>
        <a
          :for={org <- @organisations}
          href="#"
          phx-click="select"
          phx-value-id={org.id}
          class={@selected.id == org.id && "active"}
        >
          <%= org.name %>
          <span :if={!org.scraper_enabled} class="off"> · paused</span>
        </a>
      </div>

      <div class="card">
        <.form for={@form} phx-change="validate" phx-submit="save">
          <label>Organisation name</label>
          <input type="text" name={@form[:name].name} value={@form[:name].value} placeholder="e.g. Carnivore Grounds" />
          <.error field={@form[:name]} />

          <label>Slug</label>
          <input type="text" name={@form[:slug].name} value={@form[:slug].value} placeholder="carnivore-grounds" />
          <.error field={@form[:slug]} />

          <label>Facebook Page ID</label>
          <input type="text" name={@form[:facebook_page_id].name} value={@form[:facebook_page_id].value} />

          <label>Instagram Account ID</label>
          <input type="text" name={@form[:instagram_account_id].name} value={@form[:instagram_account_id].value} />

          <label>Eventbrite Org ID</label>
          <input type="text" name={@form[:eventbrite_org_id].name} value={@form[:eventbrite_org_id].value} />

          <label>HTML scrape URL</label>
          <input type="text" name={@form[:html_scrape_url].name} value={@form[:html_scrape_url].value} />

          <label>M-Pesa payout phone (2547XXXXXXXX)</label>
          <input type="tel" name={@form[:mpesa_phone].name} value={@form[:mpesa_phone].value} />
          <.error field={@form[:mpesa_phone]} />

          <div class="row">
            <input type="hidden" name={@form[:scraper_enabled].name} value="false" />
            <input
              type="checkbox"
              id="scraper_enabled"
              name={@form[:scraper_enabled].name}
              value="true"
              checked={@form[:scraper_enabled].value in [true, "true"]}
            />
            <label for="scraper_enabled" style="margin:0;text-transform:none;color:var(--txt)">
              Scraper enabled
            </label>
          </div>

          <div class="row">
            <button type="submit" class="btn">Save &amp; dispatch</button>
            <button type="button" class="btn ghost" phx-click="new">Clear</button>
          </div>
        </.form>
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
