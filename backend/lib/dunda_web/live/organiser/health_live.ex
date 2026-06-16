defmodule DundaWeb.Organiser.HealthLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :system_status, "All Systems Operational")}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              System <span class="text-acidgreen">Health</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Live infrastructure status
            </p>
          </div>
        </div>
        <div class="border border-white/10 bg-abyssnavy p-8 flex items-center gap-4">
          <span class="h-4 w-4 rounded-full bg-acidgreen animate-pulse glow-green"></span>
          <p class="text-acidgreen font-mono uppercase tracking-widest font-bold text-lg"><%= @system_status %></p>
        </div>
      </div>
    </div>
    """
  end
end
