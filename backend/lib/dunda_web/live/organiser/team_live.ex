defmodule DundaWeb.Organiser.TeamLive do
  use DundaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :team, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Team & <span class="text-opticyan">Roles</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Manage permissions and staff access
            </p>
          </div>
          <div>
            <button class="bg-opticyan text-black font-black uppercase tracking-wider text-xs px-5 py-3 hover:bg-white transition-all transform hover:-translate-y-0.5 rounded-none border border-opticyan glow-cyan">
              + Invite Member
            </button>
          </div>
        </div>

        <div class="border border-white/10 bg-abyssnavy overflow-hidden">
          <table class="w-full text-left border-collapse">
            <thead class="text-xs uppercase bg-[#111] text-gray-500 font-bold tracking-widest border-b border-white/10">
              <tr>
                <th class="px-6 py-4">Name</th>
                <th class="px-6 py-4">Role</th>
                <th class="px-6 py-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5 text-sm">
              <tr>
                <td class="px-6 py-4 text-gray-500" colspan="3">Tenant membership data is unavailable until the RBAC query is enabled.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
