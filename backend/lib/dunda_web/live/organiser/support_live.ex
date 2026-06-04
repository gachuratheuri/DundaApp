defmodule DundaWeb.Organiser.SupportLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tickets, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-10 bg-[#020202] text-white min-h-screen">
      <h1 class="text-4xl font-black uppercase mb-8">Support Inbox</h1>
      <p class="text-gray-400">No active support disputes.</p>
    </div>
    """
  end
end
