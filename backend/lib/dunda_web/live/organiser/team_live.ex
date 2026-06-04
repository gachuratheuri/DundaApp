defmodule DundaWeb.Organiser.TeamLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :team, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-10 bg-[#020202] text-white min-h-screen">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-4xl font-black uppercase tracking-tighter" style="font-family: 'Oswald', sans-serif;">Team & Roles</h1>
        <button class="bg-white/10 border border-white/20 text-white px-6 py-3 rounded-full font-bold uppercase tracking-wide hover:bg-white/20 transition-colors">
          Invite Member
        </button>
      </div>

      <div class="border border-white/10 rounded-xl overflow-hidden bg-[#0A0A0A]">
        <table class="w-full text-left text-sm text-gray-400">
          <thead class="text-xs uppercase bg-[#111] text-[#00F0FF] border-b border-white/10">
            <tr>
              <th class="px-6 py-4">Name</th>
              <th class="px-6 py-4">Role</th>
              <th class="px-6 py-4 text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr class="border-b border-white/10 hover:bg-white/5">
              <td class="px-6 py-4 font-bold text-white flex items-center gap-3">
                <div class="w-8 h-8 rounded-full bg-[#FF1C5E] flex items-center justify-center text-white font-bold">D</div>
                David M.
              </td>
              <td class="px-6 py-4"><span class="bg-[#00F0FF]/10 text-[#00F0FF] border border-[#00F0FF]/30 px-3 py-1 rounded-full text-xs">Admin</span></td>
              <td class="px-6 py-4 text-right">
                <a href="#" class="text-gray-500 hover:text-white">Manage</a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
