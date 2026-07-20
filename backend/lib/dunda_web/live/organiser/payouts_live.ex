defmodule DundaWeb.Organiser.PayoutsLive do
  use DundaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Financial figures are intentionally blank until tenant-scoped reporting
    # is wired to the authoritative order/payout ledger.
    {:ok, assign(socket, :balance, 0)}
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
              Escrow & <span class="text-acidgreen">Payouts</span>
            </h1>
            <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
              M-Pesa B2B Disbursements & Retention
            </p>
          </div>
          <div>
            <button class="bg-white/10 border border-white/20 px-6 py-3 text-xs font-bold uppercase tracking-wider text-white hover:bg-white/20 transition-colors">
              Download Statement (.CSV)
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 mb-12">
          <!-- Main Balance Card -->
          <div class="lg:col-span-2 border border-white/10 bg-abyssnavy p-8 relative overflow-hidden">
            <div class="absolute top-0 right-0 w-64 h-64 bg-acidgreen opacity-5 blur-3xl rounded-full pointer-events-none"></div>
            
            <span class="text-sm font-black uppercase tracking-widest text-gray-500 block mb-2">Available Escrow Balance</span>
            <div class="text-6xl font-black font-oswald text-acidgreen tracking-tight glow-green mb-8">
              <%= format_currency(@balance) %>
            </div>
            
            <div class="flex flex-col sm:flex-row gap-4 border-t border-white/10 pt-6">
              <div class="flex-1">
                <span class="text-[10px] uppercase tracking-widest text-gray-500 font-bold block mb-1">Pending Clearance</span>
                <span class="text-lg font-mono font-bold text-white">KSh 0</span>
              </div>
              <div class="flex-1">
                <span class="text-[10px] uppercase tracking-widest text-gray-500 font-bold block mb-1">Next Automated Payout</span>
                <span class="text-lg font-mono font-bold text-white">Not scheduled</span>
              </div>
            </div>
          </div>

          <!-- Payout Settings -->
          <div class="border border-white/10 bg-abyssnavy p-8">
            <h3 class="text-sm font-black uppercase tracking-wider font-oswald mb-6 border-b border-white/10 pb-2">Disbursement Details</h3>
            
            <div class="space-y-6">
              <div>
                <span class="text-[10px] uppercase tracking-widest text-gray-500 font-bold block mb-1">Destination M-Pesa Till</span>
                <div class="flex items-center gap-2">
                  <span class="h-2 w-2 rounded-full bg-acidgreen animate-pulse"></span>
                  <span class="text-xl font-mono text-white font-bold">Not configured</span>
                </div>
                <span class="text-[10px] text-gray-500 mt-1 block font-bold">Verification status unavailable</span>
              </div>

              <div>
                <span class="text-[10px] uppercase tracking-widest text-gray-500 font-bold block mb-1">Payout Schedule</span>
                <span class="text-sm text-white font-bold">Event Conclusion + 24 Hrs</span>
              </div>

              <div class="pt-4 border-t border-white/10">
                <button class="text-xs uppercase font-black text-[#A0A0FF] hover:text-white hover:underline">
                  Change Settlement Account &rarr;
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Ledger History -->
        <h3 class="text-xl font-black uppercase tracking-wider font-oswald mb-6">Recent Settlement Ledger</h3>
        <div class="border border-white/10 bg-abyssnavy overflow-hidden">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="border-b border-white/10 bg-black/60 text-xs font-bold uppercase tracking-widest text-gray-500">
                <th class="px-6 py-4">Date</th>
                <th class="px-6 py-4">Description</th>
                <th class="px-6 py-4">Amount</th>
                <th class="px-6 py-4 text-right">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5 text-sm font-mono text-gray-300">
              <tr class="hover:bg-white/5">
                <td class="px-6 py-4">No reconciled payouts</td>
                <td class="px-6 py-4">
                  <span class="font-sans font-bold text-white uppercase text-xs">Authoritative ledger data pending</span>
                </td>
                <td class="px-6 py-4 text-white font-bold">KSh 0</td>
                <td class="px-6 py-4 text-right">
                  <span class="text-xs text-acidgreen border border-acidgreen/30 bg-acidgreen/10 px-2 py-1 rounded font-sans font-bold uppercase tracking-wide">Settled</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

      </div>
    </div>
    """
  end
end
