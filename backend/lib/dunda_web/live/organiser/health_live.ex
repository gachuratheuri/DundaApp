defmodule DundaWeb.Organiser.HealthLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :system_status, "All Systems Operational")}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-10 bg-[#020202] text-white min-h-screen">
      <h1 class="text-4xl font-black uppercase mb-8">System Health</h1>
      <p class="text-green-400 font-mono"><%= @system_status %></p>
    </div>
    """
  end
end
