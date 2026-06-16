defmodule DundaWeb.Organiser.SupportLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tickets, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Support <span class="text-nebulamagenta">Inbox</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Manage attendee disputes and refunds
            </p>
          </div>
        </div>
        <div class="border border-white/10 bg-abyssnavy p-12 text-center border-dashed">
          <p class="text-gray-400 font-mono uppercase tracking-widest text-sm">No active support disputes.</p>
        </div>
      </div>
    </div>
    """
  end
end
