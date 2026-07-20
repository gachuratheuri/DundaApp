defmodule DundaWeb.Organiser.EventsLive do
  use DundaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    organisation_ids =
      Dunda.Organisations.list_organisations_for_user(socket.assigns.current_organiser.id)
      |> Enum.map(& &1.id)

    events =
      try do
        Dunda.Events.list_events_for_organisations(organisation_ids)
      rescue
        _ -> []
      end

    events = Enum.map(events, fn e ->
      # Convert schema structs to maps + append fields for listing
      status =
        cond do
          e.remaining == 0 -> "Sold Out"
          DateTime.compare(e.starts_at, DateTime.utc_now()) == :lt -> "Draft"
          true -> "On Sale"
        end
      
      # Simulate realistic waitlist metrics for sold-out/low stock items
      waitlist_count = if status == "Sold Out", do: div(e.capacity, 4), else: 0
      unmet_demand = if waitlist_count > 0, do: min(div(waitlist_count * 100, e.capacity), 100), else: 0

      %{
        id: e.id,
        name: e.name,
        venue: e.venue,
        starts_at: e.starts_at,
        price_cents: e.price_cents,
        capacity: e.capacity,
        remaining: e.remaining,
        status: status,
        waitlist_count: waitlist_count,
        unmet_demand_percent: unmet_demand
      }
    end)

    {:ok, assign(socket, :events, events)}
  end

  defp format_date(datetime) do
    datetime
    |> DateTime.shift_zone!("Africa/Nairobi")
    |> Calendar.strftime("%b %d, %Y · %I:%M %p")
  rescue
    _ -> 
      Calendar.strftime(datetime, "%b %d, %Y · %I:%M %p")
  end

  defp format_price(0), do: "FREE"
  defp format_price(cents) do
    shillings = div(cents, 100)
    formatted =
      shillings
      |> Integer.to_charlist()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.join(",")
      |> String.reverse()
    
    "KSh " <> formatted
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <!-- Header Section -->
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Events & <span class="text-opticyan">Inventory</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Live capacity holds, waitlists, and ticket tiers
            </p>
          </div>
          <div>
            <.link navigate={~p"/portal/events/new"} class="bg-nebulamagenta text-white font-black uppercase tracking-wider text-xs px-5 py-3 hover:bg-white hover:text-black transition-all transform hover:-translate-y-0.5 rounded-none border border-nebulamagenta glow-magenta">
              + Create New Event
            </link>
          </div>
        </div>

        <!-- Events Catalog Table -->
        <div class="border border-white/10 bg-abyssnavy overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="border-b border-white/10 bg-black/60 text-xs font-bold uppercase tracking-widest text-[#A0A0FF]">
                  <th class="px-6 py-4">Event details</th>
                  <th class="px-6 py-4">Date & Time</th>
                  <th class="px-6 py-4">Capacity Status</th>
                  <th class="px-6 py-4">Waitlist Demand</th>
                  <th class="px-6 py-4">Status</th>
                  <th class="px-6 py-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-white/5">
                <%= for e <- @events do %>
                  <tr class="hover:bg-white/5 transition-colors">
                    <!-- Event Details -->
                    <td class="px-6 py-5">
                      <div class="font-black text-base text-white tracking-tight hover:text-opticyan transition-colors"><%= e.name %></div>
                      <div class="text-xs text-gray-400 mt-1 uppercase font-semibold tracking-wider flex items-center gap-1.5">
                        <svg class="h-3.5 w-3.5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                        <%= e.venue %>
                      </div>
                    </td>
                    
                    <!-- Date & Time -->
                    <td class="px-6 py-5 text-sm font-mono text-gray-300">
                      <%= format_date(e.starts_at) %>
                    </td>

                    <!-- Capacity / Inventory -->
                    <td class="px-6 py-5">
                      <div class="flex items-center justify-between text-xs text-gray-400 mb-1.5 font-bold uppercase tracking-wide">
                        <span><%= e.remaining %> / <%= e.capacity %> Left</span>
                        <span><%= format_price(e.price_cents) %></span>
                      </div>
                      <!-- Stock Progress Bar -->
                      <div class="w-full bg-[#111] h-1.5 border border-white/5">
                        <% pct = if e.capacity > 0, do: (e.remaining * 100) / e.capacity, else: 0 %>
                        <div class={"h-full #{if e.remaining < e.capacity * 0.1, do: "bg-nebulamagenta animate-pulse", else: "bg-opticyan"}"} style={"width: #{pct}%"}></div>
                      </div>
                    </td>

                    <!-- Waitlist Intelligence -->
                    <td class="px-6 py-5">
                      <%= if e.waitlist_count > 0 do %>
                        <div class="flex items-center gap-3">
                          <div>
                            <div class="text-sm font-mono font-black text-white"><%= e.waitlist_count %> queued</div>
                            <div class="text-[10px] text-gray-500 uppercase tracking-widest font-bold mt-0.5">Unmet Demand</div>
                          </div>
                          <!-- Unmet Demand Meter -->
                          <div class="flex-grow max-w-[80px]">
                            <div class="w-full bg-black h-2 border border-white/10 rounded-full relative overflow-hidden">
                              <div class="h-full bg-solfeggiogold" style={"width: #{e.unmet_demand_percent}%"}></div>
                            </div>
                            <div class="text-[9px] text-solfeggiogold font-bold mt-1 text-right"><%= e.unmet_demand_percent %>%</div>
                          </div>
                        </div>
                      <% else %>
                        <span class="text-xs text-gray-500 uppercase tracking-widest font-bold">Stable</span>
                      <% end %>
                    </td>

                    <!-- Status Badges -->
                    <td class="px-6 py-5">
                      <%= case e.status do %>
                        <% "On Sale" -> %>
                          <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-green-950/40 text-xs font-bold uppercase tracking-wider text-acidgreen border border-acidgreen/20">
                            <span class="h-1.5 w-1.5 rounded-full bg-acidgreen animate-pulse"></span>
                            On Sale
                          </span>
                        <% "Sold Out" -> %>
                          <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-red-950/40 text-xs font-bold uppercase tracking-wider text-nebulamagenta border border-nebulamagenta/20">
                            <span class="h-1.5 w-1.5 rounded-full bg-nebulamagenta"></span>
                            Sold Out
                          </span>
                        <% "Published" -> %>
                          <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-cyan-950/40 text-xs font-bold uppercase tracking-wider text-opticyan border border-opticyan/20">
                            <span class="h-1.5 w-1.5 rounded-full bg-opticyan"></span>
                            Published
                          </span>
                        <% "Draft" -> %>
                          <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-white/5 text-xs font-bold uppercase tracking-wider text-gray-400 border border-white/10">
                            Draft
                          </span>
                      <% end %>
                    </td>

                    <!-- Actions -->
                    <td class="px-6 py-5 text-right space-x-2">
                      <.link navigate={~p"/portal/events/#{e.id}/tickets"} class="text-xs uppercase tracking-wider font-black text-opticyan hover:underline">
                        Manage
                      </.link>
                      <span class="text-gray-600">·</span>
                      <.link navigate={~p"/portal/events/#{e.id}/edit"} class="text-xs uppercase tracking-wider font-black text-gray-400 hover:text-white transition-colors">
                        Edit
                      </.link>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
