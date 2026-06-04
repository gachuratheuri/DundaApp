defmodule DundaWeb.Organiser.TicketsLive do
  use DundaWeb, :live_view

  def mount(%{"id" => event_id}, _session, socket) do
    {:ok, assign(socket, :event_id, event_id)}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-10 bg-[#020202] text-white min-h-screen">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-4xl font-black uppercase tracking-tighter" style="font-family: 'Oswald', sans-serif;">Ticket Builder</h1>
        <button class="bg-[#00F0FF] text-[#020202] px-6 py-3 rounded-full font-bold uppercase tracking-wide hover:scale-105 transition-transform" phx-click="new_tier">
          + Add Tier
        </button>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="p-6 bg-[#0A0A0A] border border-white/10 rounded-xl relative">
          <div class="absolute top-4 right-4 bg-white/10 text-white text-xs px-2 py-1 rounded">250 Cap</div>
          <h2 class="text-xl font-bold mb-2">General Admission</h2>
          <p class="text-3xl font-black text-[#FF1C5E] mb-4">KSh 1,500</p>
          <div class="w-full bg-white/10 h-2 rounded-full mb-2">
            <div class="bg-[#00F0FF] h-2 rounded-full" style="width: 40%"></div>
          </div>
          <p class="text-sm text-gray-400">100 / 250 Sold</p>
        </div>
      </div>
    </div>
    """
  end
end
