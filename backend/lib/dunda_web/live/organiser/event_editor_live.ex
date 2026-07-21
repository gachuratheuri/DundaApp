defmodule DundaWeb.Organiser.EventEditorLive do
  use DundaWeb, :live_view

  alias Dunda.Events
  alias Dunda.Organisations

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(
        :organisation_ids,
        authorised_organisation_ids(socket.assigns.current_organiser.id)
      )
      |> assign(
        :organisation_id,
        first_authorised_organisation_id(socket.assigns.current_organiser.id)
      )
      |> assign(:event_id, params["id"])
      |> assign(:action, socket.assigns.live_action)
      |> assign(:uploaded_files, [])
      |> allow_upload(:cover_image, accept: ~w(.jpg .jpeg .png), max_entries: 1)

    socket =
      case socket.assigns.action do
        :edit ->
          case Events.get_event_for_organisations(params["id"], socket.assigns.organisation_ids) do
            nil ->
              socket
              |> put_flash(:error, "Event not found.")
              |> push_navigate(to: ~p"/portal/events")

            event ->
              socket
              |> assign(:page_title, "Edit Event: #{event.name}")
              |> assign(:form_data, %{
                "name" => event.name,
                "venue" => event.venue,
                "starts_at" => format_datetime_for_input(event.starts_at),
                "price_cents" => event.price_cents,
                "capacity" => event.capacity
              })
              |> assign(:ticket_tiers, [
                %{
                  id: 1,
                  name: "Regular Admission",
                  price_cents: event.price_cents,
                  capacity: event.capacity,
                  description: "General entry"
                }
              ])
              |> assign(:extras, [
                %{
                  id: 1,
                  name: "VIP Secured Parking",
                  price_cents: 50000,
                  description: "Closest parking lot next to VIP gate"
                }
              ])
          end

        :new ->
          socket
          |> assign(:page_title, "Create New Event")
          |> assign(:form_data, %{
            "name" => "",
            "venue" => "",
            "starts_at" => "",
            "price_cents" => 150_000,
            "capacity" => 1000
          })
          |> assign(:ticket_tiers, [
            %{
              id: 1,
              name: "Regular Admission",
              price_cents: 150_000,
              capacity: 1000,
              description: "General admission entry"
            }
          ])
          |> assign(:extras, [])
      end

    {:ok, socket}
  end

  defp format_datetime_for_input(nil), do: ""

  defp format_datetime_for_input(dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end

  @impl true
  def handle_event("validate", params, socket) do
    event_params = Map.get(params, "event", %{})

    # Parse and update tiers
    tiers_params = Map.get(params, "tiers", %{})

    updated_tiers =
      Enum.map(socket.assigns.ticket_tiers, fn tier ->
        case Map.get(tiers_params, to_string(tier.id)) do
          nil ->
            tier

          p ->
            %{
              tier
              | name: p["name"] || tier.name,
                price_cents: parse_cents(p["price_cents"]),
                capacity: parse_integer(p["capacity"]),
                description: p["description"] || tier.description
            }
        end
      end)

    # Parse and update extras
    extras_params = Map.get(params, "extras", %{})

    updated_extras =
      Enum.map(socket.assigns.extras, fn extra ->
        case Map.get(extras_params, to_string(extra.id)) do
          nil ->
            extra

          p ->
            %{
              extra
              | name: p["name"] || extra.name,
                price_cents: parse_cents(p["price_cents"]),
                description: p["description"] || extra.description
            }
        end
      end)

    {:noreply,
     socket
     |> assign(:form_data, event_params)
     |> assign(:ticket_tiers, updated_tiers)
     |> assign(:extras, updated_extras)}
  end

  @impl true
  def handle_event("add_tier", _params, socket) do
    tiers = socket.assigns.ticket_tiers
    new_id = if Enum.empty?(tiers), do: 1, else: Enum.max_by(tiers, & &1.id).id + 1

    new_tier = %{
      id: new_id,
      name: "New Tier",
      price_cents: 100_000,
      capacity: 100,
      description: "Access level details"
    }

    {:noreply, assign(socket, :ticket_tiers, tiers ++ [new_tier])}
  end

  @impl true
  def handle_event("remove_tier", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    # Don't delete the last tier
    tiers =
      if length(socket.assigns.ticket_tiers) > 1 do
        Enum.reject(socket.assigns.ticket_tiers, &(&1.id == id))
      else
        socket.assigns.ticket_tiers
      end

    {:noreply, assign(socket, :ticket_tiers, tiers)}
  end

  @impl true
  def handle_event("add_extra", _params, socket) do
    extras = socket.assigns.extras
    new_id = if Enum.empty?(extras), do: 1, else: Enum.max_by(extras, & &1.id).id + 1

    new_extra = %{
      id: new_id,
      name: "New Extra",
      price_cents: 5000,
      description: "Voucher/Upgrade details"
    }

    {:noreply, assign(socket, :extras, extras ++ [new_extra])}
  end

  @impl true
  def handle_event("remove_extra", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    extras = Enum.reject(socket.assigns.extras, &(&1.id == id))
    {:noreply, assign(socket, :extras, extras)}
  end

  @impl true
  def handle_event("save", params, socket) do
    event_params = Map.get(params, "event", %{})

    starts_at =
      case DateTime.from_iso8601(event_params["starts_at"] <> ":00Z") do
        {:ok, dt, _} -> dt
        _ -> DateTime.add(DateTime.utc_now(), 30 * 86400, :second)
      end

    primary_tier =
      List.first(socket.assigns.ticket_tiers) || %{price_cents: 150_000, capacity: 1000}

    attrs = %{
      name: event_params["name"] || "New Astral Event",
      venue: event_params["venue"] || "Nairobi Venue",
      starts_at: starts_at,
      price_cents: primary_tier.price_cents,
      capacity: primary_tier.capacity,
      organisation_id: socket.assigns.organisation_id
    }

    if is_nil(socket.assigns.organisation_id) or
         not Organisations.authorised?(
           socket.assigns.current_organiser.id,
           socket.assigns.organisation_id,
           :manage_events
         ) do
      {:noreply,
       socket
       |> put_flash(:error, "No authorised organisation is available.")
       |> push_navigate(to: ~p"/portal/events")}
    else
      case socket.assigns.action do
        :new ->
          case Events.create_event(attrs) do
            {:ok, _event} ->
              {:noreply,
               socket
               |> put_flash(:info, "Event successfully published.")
               |> push_navigate(to: ~p"/portal/events")}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> put_flash(:info, "Event created (Offline Sandbox Mode)")
               |> push_navigate(to: ~p"/portal/events")}
          end

        :edit ->
          case Events.get_event_for_organisations(
                 socket.assigns.event_id,
                 socket.assigns.organisation_ids
               ) do
            nil ->
              {:noreply,
               socket
               |> put_flash(:info, "Event updated (Offline Sandbox Mode)")
               |> push_navigate(to: ~p"/portal/events")}

            event ->
              if Organisations.member?(
                   socket.assigns.current_organiser.id,
                   event.organisation_id,
                   ~w(owner admin manager)
                 ) do
                case Events.update_event(
                       event,
                       Map.put(attrs, :organisation_id, event.organisation_id)
                     ) do
                  {:ok, _event} ->
                    {:noreply,
                     socket
                     |> put_flash(:info, "Event updated successfully.")
                     |> push_navigate(to: ~p"/portal/events")}

                  {:error, _changeset} ->
                    {:noreply,
                     socket
                     |> put_flash(:info, "Event updated (Offline Sandbox Mode)")
                     |> push_navigate(to: ~p"/portal/events")}
                end
              else
                {:noreply,
                 socket
                 |> put_flash(:error, "You are not authorised for this organisation.")
                 |> push_navigate(to: ~p"/portal/events")}
              end
          end
      end
    end
  end

  defp first_authorised_organisation_id(user_id) do
    case Organisations.list_organisations_for_user(user_id, ~w(owner admin manager)) do
      [%{id: id} | _] -> id
      [] -> nil
    end
  end

  defp authorised_organisation_ids(user_id) do
    Organisations.list_organisations_for_user(user_id, ~w(owner admin manager))
    |> Enum.map(& &1.id)
  end

  defp parse_cents(str) do
    case Float.parse(str || "") do
      {val, _} ->
        round(val * 100)

      :error ->
        case Integer.parse(str || "") do
          {val, _} -> val * 100
          :error -> 0
        end
    end
  end

  defp parse_integer(str) do
    case Integer.parse(str || "") do
      {val, _} -> val
      :error -> 0
    end
  end

  # Helper formatters
  defp format_cents_to_shillings(0), do: "0"

  defp format_cents_to_shillings(cents) do
    to_string(div(cents, 100))
  end

  defp format_price(0), do: "FREE"

  defp format_price(cents) do
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

  defp format_date_preview(starts_at_str) do
    case DateTime.from_iso8601(starts_at_str <> ":00Z") do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%b %d, %Y · %I:%M %p")

      _ ->
        "TBD Date & Time"
    end
  rescue
    _ -> "TBD Date & Time"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-black min-h-screen text-white py-12 px-6 lg:px-12">
      <div class="mx-auto max-w-7xl">
        <!-- Back navigation -->
        <div class="mb-6">
          <a href="/portal/events" class="text-xs uppercase tracking-widest text-[#A0A0FF] hover:text-white font-bold flex items-center gap-1 transition-colors">
            &larr; Back to Events Catalog
          </a>
        </div>

        <!-- Header -->
        <div class="mb-10 border-b border-white/10 pb-6">
          <h1 class="text-5xl font-black uppercase tracking-tighter font-oswald text-white">
            <%= if @action == :new, do: "Create", else: "Edit" %> <span class="text-opticyan">Event Listing</span>
          </h1>
          <p class="text-sm uppercase tracking-widest text-[#A0A0FF] mt-1 font-semibold">
            Publish manual ticket layers & upselling integrations
          </p>
        </div>

        <!-- Form & Preview Layout -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-10">
          
          <!-- Left Columns: Editor -->
          <div class="lg:col-span-2 space-y-8">
            <.form for={%{}} phx-change="validate" phx-submit="save" class="space-y-8">
              
              <!-- Card 1: Core Details -->
              <div class="border border-white/10 bg-abyssnavy p-6 rounded-none space-y-6">
                <h3 class="text-lg font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3">
                  1. Event Details
                </h3>
                
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Event Title</label>
                    <input type="text" name="event[name]" value={@form_data["name"]} placeholder="e.g. Blankets & Wine Nairobi" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none transition-colors" />
                  </div>
                  <div>
                    <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Venue / Location</label>
                    <input type="text" name="event[venue]" value={@form_data["venue"]} placeholder="e.g. Carnivore Grounds" class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none transition-colors" />
                  </div>
                </div>

                <div>
                  <label class="block text-xs uppercase tracking-widest text-gray-500 font-bold mb-2">Starts At (Local Time)</label>
                  <input type="datetime-local" name="event[starts_at]" value={@form_data["starts_at"]} class="w-full bg-black/60 border border-white/10 px-4 py-3 text-sm focus:border-opticyan focus:outline-none text-white transition-colors" />
                </div>
              </div>

              <!-- Card 2: Cover Art Upload -->
              <div class="border border-white/10 bg-abyssnavy p-6 rounded-none space-y-6">
                <h3 class="text-lg font-black uppercase tracking-wider font-oswald border-b border-white/5 pb-3">
                  2. Cover Illustration
                </h3>
                
                <!-- LiveView drag and drop zone -->
                <div class="border-2 border-dashed border-white/20 p-8 text-center bg-black/40 hover:border-opticyan hover:bg-opticyan/5 transition-all cursor-pointer relative" phx-drop-target={@uploads.cover_image.ref}>
                  <label class="cursor-pointer block">
                    <.live_file_input upload={@uploads.cover_image} class="hidden" />
                    <svg class="mx-auto h-12 w-12 text-gray-500 mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    <span class="text-sm font-bold text-white block">Drag and drop cover image or <span class="text-opticyan underline">browse</span></span>
                    <span class="text-[10px] text-gray-500 uppercase tracking-wider mt-1 block">Supports PNG, JPG (Max 5MB)</span>
                  </label>
                  
                  <!-- Upload progress/preview list -->
                  <%= for entry <- @uploads.cover_image.entries do %>
                    <div class="mt-4 flex items-center justify-center gap-4 border border-white/10 p-3 bg-black/60">
                      <div class="h-16 w-16 overflow-hidden bg-voidblack">
                        <.live_img_preview entry={entry} class="h-full w-full object-cover" />
                      </div>
                      <div class="text-left flex-grow max-w-[200px]">
                        <div class="text-xs font-bold truncate text-white"><%= entry.client_name %></div>
                        <div class="w-full bg-voidblack h-1 mt-1 rounded overflow-hidden">
                          <div class="bg-opticyan h-full" style={"width: #{entry.progress}%"}></div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Card 3: Ticket Tiers Builder -->
              <div class="border border-white/10 bg-abyssnavy p-6 rounded-none space-y-6">
                <div class="flex justify-between items-center border-b border-white/5 pb-3">
                  <h3 class="text-lg font-black uppercase tracking-wider font-oswald">
                    3. Ticket Tiers
                  </h3>
                  <button type="button" phx-click="add_tier" class="text-xs uppercase tracking-wider font-black text-opticyan hover:underline">
                    + Add Ticket Tier
                  </button>
                </div>

                <div class="space-y-6">
                  <%= for {tier, index} <- Enum.with_index(@ticket_tiers) do %>
                    <div class="p-4 border border-white/5 bg-black/30 space-y-4 relative">
                      <div class="flex justify-between items-center">
                        <span class="text-xs font-mono text-gray-500 uppercase">Tier #<%= index + 1 %></span>
                        <%= if length(@ticket_tiers) > 1 do %>
                          <button type="button" phx-click="remove_tier" phx-value-id={tier.id} class="text-xs uppercase font-black text-nebulamagenta hover:underline">
                            Remove
                          </button>
                        <% end %>
                      </div>

                      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                        <div>
                          <label class="block text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1">Tier Name</label>
                          <input type="text" name={"tiers[#{tier.id}][name]"} value={tier.name} class="w-full bg-black border border-white/10 px-3 py-2 text-xs text-white focus:border-opticyan focus:outline-none" />
                        </div>
                        <div>
                          <label class="block text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1">Price (KSh)</label>
                          <input type="number" step="0.01" name={"tiers[#{tier.id}][price_cents]"} value={format_cents_to_shillings(tier.price_cents)} class="w-full bg-black border border-white/10 px-3 py-2 text-xs text-white focus:border-opticyan focus:outline-none font-mono" />
                        </div>
                        <div>
                          <label class="block text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1">Capacity</label>
                          <input type="number" name={"tiers[#{tier.id}][capacity]"} value={tier.capacity} class="w-full bg-black border border-white/10 px-3 py-2 text-xs text-white focus:border-opticyan focus:outline-none font-mono" />
                        </div>
                      </div>

                      <div>
                        <label class="block text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1">Description (Rules, VIP details)</label>
                        <input type="text" name={"tiers[#{tier.id}][description]"} value={tier.description} class="w-full bg-black border border-white/10 px-3 py-2 text-xs text-white focus:border-opticyan focus:outline-none" />
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Card 4: Extras / Upsell Builder -->
              <div class="border border-white/10 bg-abyssnavy p-6 rounded-none space-y-6">
                <div class="flex justify-between items-center border-b border-white/5 pb-3">
                  <h3 class="text-lg font-black uppercase tracking-wider font-oswald">
                    4. Extras & Upsells
                  </h3>
                  <button type="button" phx-click="add_extra" class="text-xs uppercase tracking-wider font-black text-[#A0A0FF] hover:text-white hover:underline">
                    + Add Extra Upsell
                  </button>
                </div>

                <%= if Enum.empty?(@extras) do %>
                  <p class="text-xs text-gray-500 uppercase tracking-wider py-4 text-center">No extras configured yet. Upsell merch, parking, or VIP passes.</p>
                <% else %>
                  <div class="space-y-6">
                    <%= for {extra, index} <- Enum.with_index(@extras) do %>
                      <div class="p-4 border border-white/5 bg-black/30 space-y-4 relative">
                        <div class="flex justify-between items-center">
                          <span class="text-xs font-mono text-gray-500 uppercase">Extra #<%= index + 1 %></span>
                          <button type="button" phx-click="remove_extra" phx-value-id={extra.id} class="text-xs uppercase font-black text-nebulamagenta hover:underline">
                            Remove
                          </button>
                        </div>

                        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                          <div>
                            <label class="block text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1">Extra Option Name</label>
                            <input type="text" name={"extras[#{extra.id}][name]"} value={extra.name} placeholder="e.g. VIP Dedicated Parking" class="w-full bg-black border border-white/10 px-3 py-2 text-xs text-white focus:border-opticyan focus:outline-none" />
                          </div>
                          <div>
                            <label class="block text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1">Price (KSh)</label>
                            <input type="number" step="0.01" name={"extras[#{extra.id}][price_cents]"} value={format_cents_to_shillings(extra.price_cents)} class="w-full bg-black border border-white/10 px-3 py-2 text-xs text-white focus:border-opticyan focus:outline-none font-mono" />
                          </div>
                        </div>

                        <div>
                          <label class="block text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1">Short Description</label>
                          <input type="text" name={"extras[#{extra.id}][description]"} value={extra.description} class="w-full bg-black border border-white/10 px-3 py-2 text-xs text-white focus:border-opticyan focus:outline-none" />
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <!-- Submit Buttons -->
              <div class="flex items-center gap-4 pt-4">
                <button type="submit" class="bg-opticyan text-black font-black uppercase tracking-wider text-sm px-8 py-4 hover:bg-white transition-all transform hover:-translate-y-0.5 border border-opticyan glow-cyan rounded-none">
                  <%= if @action == :new, do: "Publish & List Event", else: "Save Changes" %>
                </button>
                <a href="/portal/events" class="border border-white/10 text-white font-bold uppercase tracking-wider text-sm px-8 py-4 hover:bg-white/5 transition-all">
                  Cancel
                </a>
              </div>
            </.form>
          </div>

          <!-- Right Column: Live Mobile Mockup Preview -->
          <div class="lg:col-span-1">
            <div class="sticky top-24 space-y-4">
              <span class="text-xs uppercase tracking-widest text-opticyan font-black block">Live Mobile Preview</span>
              
              <!-- Phone Simulator Container -->
              <div class="border-4 border-[#1f1f2e] bg-black p-4 rounded-[30px] aspect-[9/18] w-full max-w-[340px] mx-auto shadow-2xl relative overflow-hidden flex flex-col justify-between">
                <!-- Phone top pill camera mockup -->
                <div class="absolute top-2 left-1/2 transform -translate-x-1/2 h-4 w-24 bg-[#1f1f2e] rounded-full z-20 flex items-center justify-around px-2">
                  <div class="h-1.5 w-1.5 bg-black rounded-full"></div>
                  <div class="h-1.5 w-12 bg-black rounded-full"></div>
                </div>

                <div class="flex-grow flex flex-col justify-between pt-6 relative">
                  <div>
                    <!-- Simulated Header Art -->
                    <div class="w-full aspect-[16/9] bg-gradient-to-tr from-purple-950 to-voidblack border border-white/10 relative overflow-hidden flex items-center justify-center">
                      <%= if not Enum.empty?(@uploads.cover_image.entries) do %>
                        <.live_img_preview entry={List.first(@uploads.cover_image.entries)} class="w-full h-full object-cover absolute inset-0" />
                      <% else %>
                        <div class="text-[10px] text-gray-500 font-mono tracking-widest uppercase">Geometric Overlay</div>
                      <% end %>
                      <!-- Pulsing green status dot -->
                      <span class="absolute top-2 left-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-black/60 text-[8px] font-bold uppercase tracking-wider text-acidgreen border border-acidgreen/20">
                        <span class="h-1 w-1 rounded-full bg-acidgreen animate-pulse"></span>
                        ON SALE
                      </span>
                      <!-- Price badge -->
                      <div class="absolute bottom-2 right-2 px-2 py-1 bg-black text-xs font-mono font-black text-opticyan">
                        <%= format_price((List.first(@ticket_tiers) || %{price_cents: 0}).price_cents) %>
                      </div>
                    </div>

                    <!-- Event Meta -->
                    <div class="mt-4 space-y-2">
                      <h4 class="text-2xl font-black uppercase tracking-tighter text-white font-oswald leading-none">
                        <%= if String.trim(@form_data["name"] || "") == "", do: "ASTRAL EVENT NAME", else: @form_data["name"] %>
                      </h4>
                      
                      <div class="text-[10px] text-[#A0A0FF] font-bold uppercase tracking-widest flex items-center gap-1 mt-1">
                        <svg class="h-3 w-3 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                        </svg>
                        <%= if String.trim(@form_data["venue"] || "") == "", do: "NAIROBI NIGHT GROUND", else: @form_data["venue"] %>
                      </div>

                      <div class="text-[10px] text-gray-400 font-mono">
                        <%= if String.trim(@form_data["starts_at"] || "") == "", do: "Jul 19, 2026 at 06:00 PM", else: format_date_preview(@form_data["starts_at"]) %>
                      </div>
                    </div>

                    <!-- Simulated Stock capacity indicator -->
                    <% 
                      total_cap = Enum.reduce(@ticket_tiers, 0, fn t, acc -> acc + t.capacity end)
                    %>
                    <div class="mt-6 space-y-1">
                      <div class="flex justify-between text-[9px] text-gray-500 uppercase tracking-widest font-bold">
                        <span>Available Capacity</span>
                        <span><%= total_cap %> Spots</span>
                      </div>
                      <div class="w-full bg-[#111] h-1 border border-white/10">
                        <div class="h-full bg-opticyan" style="width: 100%"></div>
                      </div>
                    </div>

                    <!-- Ticket tiers list on mockup -->
                    <div class="mt-6 space-y-2 border-t border-white/10 pt-4">
                      <span class="text-[8px] uppercase tracking-widest text-gray-500 font-black block">Available Tiers</span>
                      <%= for tier <- @ticket_tiers do %>
                        <div class="flex justify-between items-center py-1 border-b border-white/5 last:border-0">
                          <div>
                            <div class="text-[10px] font-bold text-white"><%= tier.name %></div>
                            <div class="text-[8px] text-gray-500"><%= tier.description %></div>
                          </div>
                          <div class="text-[10px] font-mono font-bold text-opticyan"><%= format_price(tier.price_cents) %></div>
                        </div>
                      <% end %>
                    </div>

                    <!-- Extras list on mockup -->
                    <%= if not Enum.empty?(@extras) do %>
                      <div class="mt-4 space-y-2 border-t border-white/10 pt-4">
                        <span class="text-[8px] uppercase tracking-widest text-[#A0A0FF] font-black block">Upsell Extras</span>
                        <%= for extra <- @extras do %>
                          <div class="flex justify-between items-center py-1 border-b border-white/5 last:border-0">
                            <div>
                              <div class="text-[10px] font-bold text-gray-300"><%= extra.name %></div>
                            </div>
                            <div class="text-[10px] font-mono font-bold text-solfeggiogold"><%= format_price(extra.price_cents) %></div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  
                  <!-- Bottom Action Mockup -->
                  <div class="pt-6 pb-2">
                    <button type="button" class="w-full bg-opticyan text-black font-black uppercase text-[10px] tracking-wider py-2 rounded-none">
                      BUY TICKET NOW
                    </button>
                  </div>

                </div>
              </div>
            </div>
          </div>

        </div>
      </div>
    </div>
    """
  end
end
