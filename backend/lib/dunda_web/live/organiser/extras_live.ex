defmodule DundaWeb.Organiser.ExtrasLive do
  use DundaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, :extras, [
       %{id: 1, name: "VIP Parking", price: 100_000, quantity: 50, active: true},
       %{id: 2, name: "Bottle Service", price: 2_500_000, quantity: 10, active: true}
     ])}
  end

  defp format_currency(cents) do
    shillings = div(cents, 100)

    formatted =
      shillings
      |> Integer.to_charlist()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.join(",")
      |> String.reverse()

    "KSh " <> formatted
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <!-- Header -->
        <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between border-b border-white/10 pb-6 gap-4">
          <div>
            <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
              Manage <span class="text-opticyan">Extras</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              Add-ons & Merch
            </p>
          </div>
          <div>
            <button class="bg-opticyan text-black font-black uppercase tracking-wider text-sm px-6 py-3 hover:bg-white transition-colors">
              + New Extra
            </button>
          </div>
        </div>

        <!-- Extras Table -->
        <div class="border border-white/10 bg-abyssnavy overflow-hidden">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="border-b border-white/10 bg-black/60 text-xs font-bold uppercase tracking-widest text-gray-500">
                <th class="px-6 py-4">Add-on Name</th>
                <th class="px-6 py-4">Price</th>
                <th class="px-6 py-4">Inventory</th>
                <th class="px-6 py-4 text-right">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5 text-sm font-mono text-gray-300">
              <%= for extra <- @extras do %>
                <tr class="hover:bg-white/5 cursor-pointer">
                  <td class="px-6 py-4">
                    <span class="font-sans font-bold text-white uppercase text-sm"><%= extra.name %></span>
                  </td>
                  <td class="px-6 py-4 text-white font-bold"><%= format_currency(extra.price) %></td>
                  <td class="px-6 py-4">
                    <%= extra.quantity %> units
                  </td>
                  <td class="px-6 py-4 text-right">
                    <%= if extra.active do %>
                      <span class="text-xs text-acidgreen border border-acidgreen/30 bg-acidgreen/10 px-2 py-1 rounded font-sans font-bold uppercase tracking-wide">Active</span>
                    <% else %>
                      <span class="text-xs text-red-500 border border-red-500/30 bg-red-500/10 px-2 py-1 rounded font-sans font-bold uppercase tracking-wide">Disabled</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

      </div>
    </div>
    """
  end
end
