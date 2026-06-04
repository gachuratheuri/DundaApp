defmodule DundaWeb.Organiser.EventsLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :events, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-10 bg-[#020202] text-white min-h-screen">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-4xl font-black uppercase tracking-tighter" style="font-family: 'Oswald', sans-serif;">Events & Inventory</h1>
        <button class="bg-[#FF1C5E] text-white px-6 py-3 rounded-full font-bold uppercase tracking-wide hover:scale-105 transition-transform" phx-click="new_event">
          + Create Event
        </button>
      </div>

      <div class="border border-white/10 rounded-xl overflow-hidden bg-[#0A0A0A]">
        <table class="w-full text-left text-sm text-gray-400">
          <thead class="text-xs uppercase bg-[#111] text-[#00F0FF] border-b border-white/10">
            <tr>
              <th class="px-6 py-4">Event Name</th>
              <th class="px-6 py-4">Date</th>
              <th class="px-6 py-4">Status</th>
              <th class="px-6 py-4 text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr class="border-b border-white/10 hover:bg-white/5">
              <td class="px-6 py-4 font-bold text-white">Blankets & Wine Nairobi</td>
              <td class="px-6 py-4">Jul 19, 2026</td>
              <td class="px-6 py-4"><span class="bg-green-900/30 text-green-400 border border-green-500/30 px-3 py-1 rounded-full text-xs">Live</span></td>
              <td class="px-6 py-4 text-right">
                <a href="#" class="text-[#00F0FF] hover:underline">Manage Tickets</a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
