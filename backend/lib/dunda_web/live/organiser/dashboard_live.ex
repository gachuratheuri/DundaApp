defmodule DundaWeb.Organiser.DashboardLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    # Fetch metrics, payout queue status, etc.
    {:ok, assign(socket, :metrics, %{
      total_sales: "KSh 4,500,000",
      tickets_sold: 1250,
      payout_status: "Pending (Next: Tuesday)",
      active_events: 2,
      health: %{
        scraper_lag: "12ms",
        mpesa_callbacks: "100% Success",
        inventory: "Stable"
      }
    })}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-10 bg-[#020202] text-white min-h-screen">
      <h1 class="text-4xl font-black uppercase tracking-tighter mb-8" style="font-family: 'Oswald', sans-serif;">Organiser Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <div class="p-6 border border-white/10 bg-[#0A0A0A] rounded-xl relative overflow-hidden">
          <div class="absolute top-0 right-0 w-32 h-32 bg-[#00F0FF] opacity-10 blur-3xl"></div>
          <h3 class="text-sm text-[#A0A0FF] font-medium tracking-wide uppercase mb-2">Total Sales</h3>
          <p class="text-3xl font-black text-[#00F0FF]"><%= @metrics.total_sales %></p>
        </div>
        <div class="p-6 border border-white/10 bg-[#0A0A0A] rounded-xl relative overflow-hidden">
          <div class="absolute top-0 right-0 w-32 h-32 bg-[#FF1C5E] opacity-10 blur-3xl"></div>
          <h3 class="text-sm text-[#A0A0FF] font-medium tracking-wide uppercase mb-2">Tickets Sold</h3>
          <p class="text-3xl font-black text-[#FF1C5E]"><%= @metrics.tickets_sold %></p>
        </div>
        <div class="p-6 border border-white/10 bg-[#0A0A0A] rounded-xl relative overflow-hidden">
          <div class="absolute top-0 right-0 w-32 h-32 bg-[#F4F800] opacity-10 blur-3xl"></div>
          <h3 class="text-sm text-[#A0A0FF] font-medium tracking-wide uppercase mb-2">Payout Queue</h3>
          <p class="text-lg font-bold text-[#F4F800] mt-2"><%= @metrics.payout_status %></p>
        </div>
      </div>

      <div class="mt-8 border-t border-white/10 pt-8">
        <h2 class="text-2xl font-bold mb-6">System Health & Scraper Pulse</h2>
        <ul class="space-y-4">
          <li class="flex justify-between items-center p-4 bg-[#0A0A0A] rounded-lg border border-white/10">
            <span class="text-[#A0A0FF]">Scraper Latency</span>
            <span class="text-green-400 font-mono"><%= @metrics.health.scraper_lag %></span>
          </li>
          <li class="flex justify-between items-center p-4 bg-[#0A0A0A] rounded-lg border border-white/10">
            <span class="text-[#A0A0FF]">M-Pesa Callback Delivery</span>
            <span class="text-green-400 font-mono"><%= @metrics.health.mpesa_callbacks %></span>
          </li>
          <li class="flex justify-between items-center p-4 bg-[#0A0A0A] rounded-lg border border-white/10">
            <span class="text-[#A0A0FF]">Escrow Redis Inventory</span>
            <span class="text-green-400 font-mono"><%= @metrics.health.inventory %></span>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
