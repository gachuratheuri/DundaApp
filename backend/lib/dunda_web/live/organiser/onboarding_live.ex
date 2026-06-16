defmodule DundaWeb.Organiser.OnboardingLive do
  use DundaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:step, 1)
     |> assign(:form_data, %{
       "org_name" => "",
       "contact_email" => "",
       "phone" => "",
       "website" => "",
       "logo" => nil,
       "mpesa_till" => "",
       "agree_terms" => false
     })}
  end

  @impl true
  def handle_event("next", _params, socket) do
    {:noreply, assign(socket, :step, socket.assigns.step + 1)}
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :step, max(1, socket.assigns.step - 1))}
  end

  @impl true
  def handle_event("update", params, socket) do
    data = Map.merge(socket.assigns.form_data, params)
    {:noreply, assign(socket, :form_data, data)}
  end

  @impl true
  def handle_event("finish", _params, socket) do
    data = socket.assigns.form_data

    # Map the form_data to the expected schema attributes
    attrs = %{
      name: data["org_name"],
      slug: data["org_name"] |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-"),
      mpesa_phone: data["phone"], # using phone as mpesa_phone
      scraper_enabled: false
    }

    case Dunda.Organisations.create_organisation(attrs) do
      {:ok, _org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organisation registered successfully! Welcome to Dunda.")
         |> push_navigate(to: ~p"/portal")}
      
      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create organisation. Please check your details.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white flex flex-col justify-center items-center py-12 px-6">
      <div class="w-full max-w-2xl">
        <!-- Header -->
        <div class="mb-10 text-center">
          <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
            <span class="text-opticyan">Partner</span> Onboarding
          </h1>
          <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-2 font-semibold">
            Step <%= @step %> of 4
          </p>
          
          <!-- Progress Bar -->
          <div class="w-full bg-[#111] h-1.5 border border-white/5 mt-6">
            <div class="h-full bg-opticyan transition-all duration-300" style={"width: #{(@step / 4) * 100}%"}></div>
          </div>
        </div>

        <div class="border border-white/10 bg-abyssnavy p-8 relative overflow-hidden">
          <form phx-change="update" phx-submit={if @step == 4, do: "finish", else: "next"} class="space-y-6">
            
            <%= if @step == 1 do %>
              <div class="space-y-6">
                <h3 class="text-xl font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3 mb-6">
                  Organisation Details
                </h3>
                <div>
                  <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Legal Name / Trading Name</label>
                  <input type="text" name="org_name" value={@form_data["org_name"]} required placeholder="e.g. Blankets & Wine Ltd" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none transition-colors" />
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Contact Email</label>
                    <input type="email" name="contact_email" value={@form_data["contact_email"]} required placeholder="hello@events.co.ke" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none transition-colors" />
                  </div>
                  <div>
                    <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Phone Number</label>
                    <input type="tel" name="phone" value={@form_data["phone"]} required placeholder="+254 7XX XXX XXX" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none transition-colors" />
                  </div>
                </div>
              </div>
            <% end %>

            <%= if @step == 2 do %>
              <div class="space-y-6">
                <h3 class="text-xl font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3 mb-6">
                  Branding & Identity
                </h3>
                <div>
                  <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Website / Social Link</label>
                  <input type="url" name="website" value={@form_data["website"]} placeholder="https://instagram.com/yourbrand" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none transition-colors" />
                </div>
                <div>
                  <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Organisation Logo</label>
                  <div class="border-2 border-dashed border-white/20 p-8 text-center bg-black/40 hover:border-opticyan hover:bg-opticyan/5 transition-all cursor-pointer">
                    <span class="text-sm font-bold text-white block">Click to upload brand logo</span>
                    <span class="text-[10px] text-gray-500 uppercase tracking-wider mt-1 block">Supports PNG, JPG (Max 2MB)</span>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if @step == 3 do %>
              <div class="space-y-6">
                <h3 class="text-xl font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3 mb-6">
                  Payout Integration
                </h3>
                <p class="text-sm text-gray-400 leading-relaxed">
                  Enter your registered Safaricom M-Pesa Till Number or Paybill Number. All ticketing revenue will be automatically disbursed to this account.
                </p>
                <div>
                  <label class="block text-xs uppercase tracking-widest text-acidgreen font-bold mb-2 flex items-center gap-2">
                    <span class="h-2 w-2 rounded-full bg-acidgreen animate-pulse"></span>
                    M-Pesa Till / Paybill Number
                  </label>
                  <input type="text" name="mpesa_till" value={@form_data["mpesa_till"]} required placeholder="e.g. 523456" class="w-full bg-black/60 border border-acidgreen/30 px-4 py-3 text-xl font-mono text-white focus:border-acidgreen focus:outline-none transition-colors" />
                </div>
              </div>
            <% end %>

            <%= if @step == 4 do %>
              <div class="space-y-6">
                <h3 class="text-xl font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3 mb-6">
                  Agreement
                </h3>
                <div class="bg-black/60 border border-white/10 p-4 text-xs text-gray-400 space-y-4 h-48 overflow-y-auto">
                  <p>1. Dunda acts solely as an escrow agent between the Organiser and the Attendee.</p>
                  <p>2. The Organiser is responsible for all event fulfillment, VAT compliance, and local municipality permits.</p>
                  <p>3. Dunda's booking fee is strictly applied to the buyer checkout and does not deduce from the Organiser's face-value revenue.</p>
                  <p>4. Fraudulent events or chargeback abuse will result in immediate suspension and forfeiture of escrowed funds.</p>
                </div>
                
                <div class="flex items-start gap-3 mt-4">
                  <input type="checkbox" id="agree" name="agree_terms" value="true" required class="mt-1" />
                  <label for="agree" class="text-sm text-white font-bold">
                    I agree to the Dunda Partner Terms of Service and Odpc Data Processing Addendum.
                  </label>
                </div>
              </div>
            <% end %>

            <!-- Action Footer -->
            <div class="flex items-center justify-between pt-8 border-t border-white/10 mt-8">
              <%= if @step > 1 do %>
                <button type="button" phx-click="back" class="text-xs uppercase tracking-widest text-[#A0A0FF] hover:text-white font-bold transition-colors">
                  &larr; Back
                </button>
              <% else %>
                <div></div>
              <% end %>
              
              <button type="submit" class="bg-opticyan text-black font-black uppercase tracking-wider text-sm px-8 py-4 hover:bg-white transition-all transform hover:-translate-y-0.5 border border-opticyan glow-cyan rounded-none">
                <%= if @step == 4, do: "Complete Registration", else: "Continue &rarr;" %>
              </button>
            </div>
          </form>
        </div>
        
      </div>
    </div>
    """
  end
end
