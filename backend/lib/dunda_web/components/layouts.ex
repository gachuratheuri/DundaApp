defmodule DundaWeb.Layouts do
  @moduledoc """
  Root + app layouts for the organiser portal.

  Styling and JS are compiled by the Tailwind + esbuild asset pipeline (see
  `assets/`, `config/config.exs`, and the `assets.*` mix aliases) and served as
  `/assets/app.css` + `/assets/app.js`. The cyber-brutalist ChromaNoir theme
  tokens live in `assets/tailwind.config.js`.
  """
  use DundaWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full bg-black">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Tiketa · Organiser Portal</title>
        
        <!-- Google Fonts -->
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&family=Oswald:wght@900&display=swap" rel="stylesheet" />
        
        <!-- Compiled portal assets (Tailwind + esbuild), replacing the CDN -->
        <link phx-track-static rel="stylesheet" href="/assets/app.css" />
        <script defer phx-track-static type="text/javascript" src="/assets/app.js"></script>
      </head>
      <body class="h-full text-white antialiased">
        <div class="min-h-full flex flex-col justify-between">
          <header class="border-b border-white/10 bg-black/80 backdrop-blur-md sticky top-0 z-50">
            <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
              <div class="flex h-16 items-center justify-between">
                <div class="flex items-center gap-8">
                  <a href="/portal" class="flex items-center gap-2">
                    <span class="text-2xl font-black tracking-tighter text-white font-oswald">DUNDA <span class="text-opticyan">PORTAL</span></span>
                  </a>
                  <%= if assigns[:current_organiser] do %>
                    <nav class="hidden md:flex space-x-6 text-sm font-semibold uppercase tracking-wider text-gray-400">
                      <a href="/portal" class="hover:text-white transition-colors">Dashboard</a>
                      <a href="/portal/events" class="hover:text-white transition-colors">Events</a>
                      <a href="/portal/analytics" class="hover:text-white transition-colors">Analytics</a>
                      <a href="/portal/payouts" class="hover:text-white transition-colors">Payouts</a>
                      <a href="/portal/scraper" class="hover:text-white transition-colors">Scraper</a>
                      <a href="/portal/team" class="hover:text-white transition-colors">Team</a>
                      <a href="/portal/support" class="hover:text-white transition-colors">Support</a>
                      <a href="/portal/health" class="hover:text-white transition-colors">System Health</a>
                    </nav>
                  <% end %>
                </div>
                <div class="flex items-center gap-4">
                  <%= if assigns[:current_organiser] do %>
                    <span class="text-xs text-gray-400 font-bold uppercase"><%= @current_organiser.name %></span>
                    <.link href={~p"/portal/logout"} method="delete" class="text-xs text-opticyan hover:underline font-bold uppercase">Sign Out</.link>
                  <% else %>
                    <span class="inline-flex items-center gap-1.5 rounded-full bg-[#111] px-3 py-1 text-xs font-semibold text-acidgreen border border-acidgreen/20">
                      <span class="h-2 w-2 rounded-full bg-acidgreen animate-pulse"></span>
                      Live Context
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          </header>

          <main class="flex-grow">
            <%= @inner_content %>
          </main>

          <footer class="border-t border-white/5 bg-voidblack py-6 mt-12">
            <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 flex flex-col md:flex-row justify-between items-center gap-4 text-xs text-gray-500 uppercase tracking-widest">
              <div>© 2026 TIKETA. ALL RIGHTS RESERVED.</div>
              <div class="flex gap-6">
                <a href="/portal/health" class="hover:text-white transition-colors">System status</a>
                <span>·</span>
                <a href="/portal/support" class="hover:text-white transition-colors">Support hub</a>
              </div>
            </div>
          </footer>
        </div>

      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <div class="w-full">
      <%= @inner_content %>
    </div>
    """
  end
end
