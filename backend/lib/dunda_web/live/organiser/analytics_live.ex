defmodule DundaWeb.Organiser.AnalyticsLive do
  use DundaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :time_range, "7d")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <!-- Header -->
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Event <span class="text-solfeggiogold">Analytics</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Deep-dive metrics and demographic breakdowns
            </p>
          </div>
          <div class="flex items-center gap-2">
            <button class="px-4 py-2 bg-white/10 border border-white/20 text-xs font-bold uppercase text-white hover:bg-white/20">7 Days</button>
            <button class="px-4 py-2 border border-white/10 text-xs font-bold uppercase text-gray-500 hover:text-white">30 Days</button>
            <button class="px-4 py-2 border border-white/10 text-xs font-bold uppercase text-gray-500 hover:text-white">All Time</button>
          </div>
        </div>

        <!-- Simulated Charts Grid -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
          
          <!-- Chart 1: Sales Velocity -->
          <div class="border border-white/10 bg-abyssnavy p-6">
            <h3 class="text-sm font-black uppercase tracking-wider font-oswald mb-6">Sales Velocity (Tickets/Day)</h3>
            
            <div class="h-48 flex items-end justify-between gap-2 border-b border-white/10 pb-2">
              <%= for i <- 1..7 do %>
                <div class="w-full flex flex-col justify-end items-center gap-2 group relative">
                  <!-- Tooltip -->
                  <div class="absolute -top-8 bg-black border border-white/20 px-2 py-1 text-[10px] opacity-0 group-hover:opacity-100 transition-opacity">
                    <%= Enum.random(20..150) %> Tix
                  </div>
                  <!-- Bar -->
                  <% height = Enum.random(20..100) %>
                  <div class={"w-full #{if i == 7, do: "bg-solfeggiogold", else: "bg-opticyan/40"} hover:bg-opticyan transition-colors"} style={"height: #{height}%"}></div>
                  <span class="text-[9px] text-gray-500 font-mono uppercase">D-<%= 8 - i %></span>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Chart 2: Demographic Breakdown -->
          <div class="border border-white/10 bg-abyssnavy p-6">
            <h3 class="text-sm font-black uppercase tracking-wider font-oswald mb-6">Ticket Holder Demographics</h3>
            
            <div class="space-y-4">
              <!-- Age Group -->
              <div>
                <div class="flex justify-between text-xs font-bold text-gray-400 mb-1">
                  <span>Age 18-24</span>
                  <span class="text-white">65%</span>
                </div>
                <div class="w-full h-2 bg-black border border-white/10">
                  <div class="h-full bg-nebulamagenta" style="width: 65%"></div>
                </div>
              </div>
              
              <div>
                <div class="flex justify-between text-xs font-bold text-gray-400 mb-1">
                  <span>Age 25-34</span>
                  <span class="text-white">28%</span>
                </div>
                <div class="w-full h-2 bg-black border border-white/10">
                  <div class="h-full bg-nebulamagenta/60" style="width: 28%"></div>
                </div>
              </div>

              <div>
                <div class="flex justify-between text-xs font-bold text-gray-400 mb-1">
                  <span>Age 35+</span>
                  <span class="text-white">7%</span>
                </div>
                <div class="w-full h-2 bg-black border border-white/10">
                  <div class="h-full bg-nebulamagenta/30" style="width: 7%"></div>
                </div>
              </div>
            </div>
            <p class="text-[10px] text-gray-500 mt-6 tracking-widest uppercase">* Anonymized via ODPC guidelines</p>
          </div>
        </div>

        <!-- Conversion Funnel -->
        <div class="border border-white/10 bg-abyssnavy p-6">
          <h3 class="text-sm font-black uppercase tracking-wider font-oswald mb-6">Discovery to Purchase Funnel</h3>
          
          <div class="space-y-6">
            <div class="relative">
              <div class="flex justify-between items-center text-sm font-bold z-10 relative px-4 text-white">
                <span>Page Views</span>
                <span class="font-mono">14,250</span>
              </div>
              <div class="absolute inset-0 bg-white/5 border border-white/10 w-full h-full"></div>
            </div>

            <div class="relative w-[75%] mx-auto">
              <div class="flex justify-between items-center text-sm font-bold z-10 relative px-4 text-white">
                <span>Checkout Initiated</span>
                <span class="font-mono">3,420 <span class="text-[10px] text-gray-500 ml-2">24%</span></span>
              </div>
              <div class="absolute inset-0 bg-opticyan/20 border border-opticyan/30 w-full h-full"></div>
            </div>

            <div class="relative w-[30%] mx-auto">
              <div class="flex justify-between items-center text-sm font-bold z-10 relative px-4 text-white">
                <span>Completed</span>
                <span class="font-mono">1,250 <span class="text-[10px] text-gray-500 ml-2">36%</span></span>
              </div>
              <div class="absolute inset-0 bg-acidgreen border border-acidgreen shadow-[0_0_15px_rgba(57,255,20,0.3)] w-full h-full text-black"></div>
            </div>
          </div>
        </div>

      </div>
    </div>
    """
  end
end
