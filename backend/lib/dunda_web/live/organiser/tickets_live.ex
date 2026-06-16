defmodule DundaWeb.Organiser.TicketsLive do
  use DundaWeb, :live_view

  def mount(%{"id" => event_id}, _session, socket) do
    {:ok, assign(socket, :event_id, event_id)}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Ticket <span class="text-opticyan">Inventory</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Manage capacity layers and manual admissions
            </p>
          </div>
          <div>
            <a href="/portal/events" class="text-xs uppercase tracking-widest text-[#A0A0FF] hover:text-white font-bold transition-colors">
              &larr; Back to Events
            </a>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <div class="border border-white/10 bg-abyssnavy p-6 relative overflow-hidden">
            <div class="absolute top-4 right-4 bg-white/10 border border-white/20 text-white text-[10px] font-bold uppercase tracking-widest px-2 py-1">
              250 Capacity
            </div>
            <h2 class="text-xl font-bold mb-2">General Admission</h2>
            <p class="text-3xl font-black text-nebulamagenta mb-6 font-mono">KSh 1,500</p>
            
            <div class="space-y-1 mb-4">
              <div class="flex justify-between text-[10px] uppercase tracking-widest font-bold text-gray-500">
                <span>Sales Progress</span>
                <span>100 / 250 Sold</span>
              </div>
              <div class="w-full bg-[#111] h-1.5 border border-white/10">
                <div class="bg-opticyan h-full" style="width: 40%"></div>
              </div>
            </div>

            <div class="flex gap-2 pt-4 border-t border-white/10">
              <button class="flex-1 bg-white/5 border border-white/10 py-2 text-xs uppercase font-bold text-gray-300 hover:bg-white/10 transition-colors">
                Edit Tier
              </button>
              <button class="flex-1 bg-white/5 border border-white/10 py-2 text-xs uppercase font-bold text-gray-300 hover:bg-white/10 transition-colors">
                Hold Stock
              </button>
            </div>
          </div>
        </div>

        <div class="mt-8 border border-white/10 bg-abyssnavy p-8 text-center border-dashed">
          <p class="text-sm text-gray-500 uppercase tracking-widest mb-4">Need to add more ticket tiers?</p>
          <button class="bg-opticyan text-black font-black uppercase tracking-wider text-xs px-6 py-3 hover:bg-white transition-all rounded-none border border-opticyan glow-cyan">
            + Create New Tier
          </button>
        </div>
      </div>
    </div>
    """
  end
end
