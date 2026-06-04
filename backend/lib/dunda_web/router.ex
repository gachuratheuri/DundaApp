defmodule DundaWeb.Router do
  use DundaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug DundaWeb.Plugs.AuthPlug
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DundaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Liveness/readiness probe — no auth, no DB requirement beyond a fast check.
  scope "/", DundaWeb do
    get "/healthz", HealthController, :show
  end

  # Organiser Portal (LiveView).
  scope "/portal", DundaWeb.Organiser do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/scraper", ScraperLive, :index
    live "/events", EventsLive, :index
    live "/events/new", EventsLive, :new
    live "/events/:id/tickets", TicketsLive, :index
    live "/team", TeamLive, :index
    live "/health", HealthLive, :index
    live "/support", SupportLive, :index
  end

  scope "/api", DundaWeb do
    pipe_through :api

    # Auth
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    post "/auth/google", AuthController, :google
    post "/auth/otp/send", AuthController, :send_otp
    post "/auth/otp/verify", AuthController, :verify_otp

    get "/events", EventController, :index
    get "/events/:id", EventController, :show

    # Consumer billing via Pesapal hosted checkout.
    post "/billing/orders", BillingController, :create

    # Safaricom Daraja STK callback (server-to-server).
    post "/mpesa/callback", MpesaController, :callback

    # Pesapal IPN (registered via Dunda.Billing.Setup.setup_ipn/0).
    get "/pesapal/ipn", IpnController, :ipn
    post "/pesapal/ipn", IpnController, :ipn
  end

  scope "/api", DundaWeb do
    pipe_through [:api, :api_auth]

    get "/tickets", TicketController, :index
    post "/checkout", CheckoutController, :create

    get "/resale/listings", ResaleController, :index
    post "/resale/listings", ResaleController, :create
    post "/resale/listings/:id/buy", ResaleController, :buy
  end
end
