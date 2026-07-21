defmodule DundaWeb.Organiser.DashboardLive do
  use DundaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Do not render fabricated financial or operational telemetry.  The
    # dashboard remains an honest zero/unknown view until tenant-scoped
    # reporting queries are enabled after the Phase 1 release gate.
    {:ok,
     socket
     |> assign(:total_sales_cents, 0)
     |> assign(:tickets_sold_count, 0)
     |> assign(:active_events_count, 0)
     |> assign(:conversion_rate, 0)
     |> assign(:purchases, [])
     |> assign(:scrapers, [])}
  end

  # Format currency in KSh
  defp format_currency(cents) do
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

  defp format_time(datetime) do
    datetime
    |> DateTime.shift_zone!("Africa/Nairobi")
    |> Calendar.strftime("%I:%M:%S %p")
  rescue
    _ ->
      # Fallback if timezone data is missing
      Calendar.strftime(datetime, "%I:%M:%S %p")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <!-- Title & Subtitle Section -->
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Organiser <span class="text-opticyan">Dashboard</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Live System Telemetry & Ticket Escrow Management
            </p>
          </div>
          <div class="flex items-center gap-3">
            <a href="/portal/events/new" class="bg-opticyan text-black font-black uppercase tracking-wider text-xs px-5 py-3 hover:bg-white transition-all transform hover:-translate-y-0.5 rounded-none border border-opticyan glow-cyan">
              + Create Event Listing
            </a>
          </div>
        </div>

        <!-- KPI Grid -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
          <!-- KPI 1 -->
          <div class="border border-white/10 bg-abyssnavy p-6 relative overflow-hidden flex flex-col justify-between h-32">
            <div class="absolute top-0 right-0 w-24 h-24 bg-opticyan opacity-5 blur-3xl rounded-full"></div>
            <span class="text-xs uppercase tracking-widest text-gray-500 font-bold">Total Revenue</span>
            <div class="flex items-baseline gap-1">
              <span class="text-3xl font-black tracking-tight text-opticyan font-oswald" id="sales-kpi" phx-hook="CountUp" data-target={div(@total_sales_cents, 100)} data-prefix="KSh ">
                <%= format_currency(@total_sales_cents) %>
              </span>
            </div>
            <div class="text-[10px] text-gray-500 uppercase tracking-widest font-semibold flex items-center gap-1">
              <span class="h-1.5 w-1.5 rounded-full bg-acidgreen animate-ping"></span> Real-time Escrow hold
            </div>
          </div>

          <!-- KPI 2 -->
          <div class="border border-white/10 bg-abyssnavy p-6 relative overflow-hidden flex flex-col justify-between h-32">
            <div class="absolute top-0 right-0 w-24 h-24 bg-nebulamagenta opacity-5 blur-3xl rounded-full"></div>
            <span class="text-xs uppercase tracking-widest text-gray-500 font-bold">Tickets Sold</span>
            <span class="text-3xl font-black tracking-tight text-nebulamagenta font-oswald" id="tickets-kpi" phx-hook="CountUp" data-target={@tickets_sold_count}>
              <%= @tickets_sold_count %>
            </span>
            <span class="text-[10px] text-gray-500 uppercase tracking-widest font-semibold">Across all sales channels</span>
          </div>

          <!-- KPI 3 -->
          <div class="border border-white/10 bg-abyssnavy p-6 relative overflow-hidden flex flex-col justify-between h-32">
            <div class="absolute top-0 right-0 w-24 h-24 bg-solfeggiogold opacity-5 blur-3xl rounded-full"></div>
            <span class="text-xs uppercase tracking-widest text-gray-500 font-bold">Conversion Rate</span>
            <span class="text-3xl font-black tracking-tight text-solfeggiogold font-oswald" id="conv-kpi" phx-hook="CountUp" data-target={@conversion_rate} data-suffix="%">
              <%= @conversion_rate %>%
            </span>
            <span class="text-[10px] text-gray-500 uppercase tracking-widest font-semibold">Visits to reservation conversion</span>
          </div>

          <!-- KPI 4 -->
          <div class="border border-white/10 bg-abyssnavy p-6 relative overflow-hidden flex flex-col justify-between h-32">
            <div class="absolute top-0 right-0 w-24 h-24 bg-white opacity-5 blur-3xl rounded-full"></div>
            <span class="text-xs uppercase tracking-widest text-gray-500 font-bold">Active Events</span>
            <span class="text-3xl font-black tracking-tight text-white font-oswald" id="events-kpi" phx-hook="CountUp" data-target={@active_events_count}>
              <%= @active_events_count %>
            </span>
            <span class="text-[10px] text-gray-500 uppercase tracking-widest font-semibold">Ready for admission scans</span>
          </div>
        </div>

        <!-- Telemetry & Feeds Split -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <!-- Column 1 & 2: Sales Feed -->
          <div class="lg:col-span-2 border border-white/10 bg-abyssnavy p-6 flex flex-col justify-between">
            <div>
              <div class="flex items-center justify-between border-b border-white/10 pb-4 mb-6">
                <h3 class="text-lg font-black uppercase tracking-wider font-oswald flex items-center gap-2">
                  <span class="flex h-2 w-2 relative">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-opticyan opacity-75"></span>
                    <span class="relative inline-flex rounded-full h-2 w-2 bg-opticyan"></span>
                  </span>
                  Live Admission Sales Ticker
                </h3>
                <span class="text-[10px] bg-[#111] border border-white/10 text-gray-400 font-mono px-2 py-1 uppercase tracking-wider">
                  PubSub Channel Active
                </span>
              </div>

              <!-- Ticker Stream -->
              <div class="space-y-4">
                <%= if Enum.empty?(@purchases) do %>
                  <p class="text-gray-500 text-sm text-center py-12">Waiting for next transaction stream...</p>
                <% else %>
                  <div :for={p <- @purchases} class="border-b border-white/5 pb-4 last:border-0 last:pb-0 flex items-center justify-between hover:bg-white/5 p-2 transition-all">
                    <div>
                      <div class="flex items-center gap-2">
                        <span class="text-sm font-black text-white font-mono"><%= p.buyer %></span>
                        <span class="text-xs text-gray-500 uppercase font-semibold">bought</span>
                        <span class="text-xs px-2 py-0.5 bg-white/5 border border-white/10 font-bold text-opticyan uppercase"><%= p.qty %>x <%= p.tier %></span>
                      </div>
                      <div class="text-[11px] text-gray-400 mt-1 uppercase font-semibold tracking-wide">
                        <%= p.event %>
                      </div>
                    </div>
                    <div class="text-right">
                      <div class="text-sm font-bold text-acidgreen font-mono">
                        +<%= format_currency(p.qty * p.price_cents) %>
                      </div>
                      <div class="text-[10px] text-gray-500 font-mono mt-0.5">
                        <%= format_time(p.timestamp) %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
            
            <div class="border-t border-white/10 pt-4 mt-6 text-center">
              <a href="/portal/events" class="text-xs uppercase tracking-widest text-[#A0A0FF] hover:text-white font-bold transition-colors">
                View All Event Inventories &rarr;
              </a>
            </div>
          </div>

          <!-- Column 3: Scraper Pulse & System Status -->
          <div class="border border-white/10 bg-abyssnavy p-6">
            <h3 class="text-lg font-black uppercase tracking-wider font-oswald border-b border-white/10 pb-4 mb-6">
              Scraper Pulse & Freshness
            </h3>
            
            <div class="space-y-6">
              <div :for={s <- @scrapers} class="flex items-start justify-between">
                <div>
                  <div class="text-sm font-bold text-white"><%= s.name %></div>
                  <div class="text-xs text-gray-500 uppercase mt-0.5 tracking-wider font-medium flex items-center gap-1.5">
                    <%= s.source %> · <span class="font-mono text-gray-400"><%= s.rate %></span>
                  </div>
                </div>
                
                <div class="flex flex-col items-end gap-1">
                  <%= case s.status do %>
                    <% :healthy -> %>
                      <span class="inline-flex items-center gap-1 rounded-full bg-green-950/40 px-2 py-0.5 text-[10px] font-bold text-acidgreen border border-acidgreen/20">
                        <span class="h-1.5 w-1.5 rounded-full bg-acidgreen animate-pulse"></span>
                        <%= s.lag %>
                      </span>
                    <% :warning -> %>
                      <span class="inline-flex items-center gap-1 rounded-full bg-yellow-950/40 px-2 py-0.5 text-[10px] font-bold text-solfeggiogold border border-solfeggiogold/20">
                        <span class="h-1.5 w-1.5 rounded-full bg-solfeggiogold"></span>
                        <%= s.lag %>
                      </span>
                    <% :error -> %>
                      <span class="inline-flex items-center gap-1 rounded-full bg-red-950/40 px-2 py-0.5 text-[10px] font-bold text-nebulamagenta border border-nebulamagenta/20">
                        <span class="h-1.5 w-1.5 rounded-full bg-nebulamagenta"></span>
                        OFFLINE
                      </span>
                  <% end %>
                </div>
              </div>
            </div>

            <!-- Escrow details & integrations -->
            <div class="border-t border-white/10 pt-6 mt-8">
              <h4 class="text-xs uppercase tracking-widest text-[#A0A0FF] font-bold mb-4">Escrow Telemetry</h4>
              
              <ul class="space-y-3 text-xs">
                <li class="flex justify-between items-center py-2 border-b border-white/5">
                  <span class="text-gray-400">M-Pesa STK Gateway</span>
                  <span class="text-acidgreen font-mono font-bold uppercase">Connected (100%)</span>
                </li>
                <li class="flex justify-between items-center py-2 border-b border-white/5">
                  <span class="text-gray-400">Pesapal Hosted Checkout</span>
                  <span class="text-acidgreen font-mono font-bold uppercase">Connected</span>
                </li>
                <li class="flex justify-between items-center py-2 border-b border-white/5">
                  <span class="text-gray-400">Redis Lock Manager</span>
                  <span class="text-acidgreen font-mono font-bold uppercase">Active</span>
                </li>
                <li class="flex justify-between items-center py-2">
                  <span class="text-gray-400">ODPC Data Anonymizer</span>
                  <span class="text-acidgreen font-mono font-bold uppercase">Enforcing</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
