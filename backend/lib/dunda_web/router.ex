defmodule DundaWeb.Router do
  use DundaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug DundaWeb.Plugs.RateLimit, scope: "api", limit: 120, window_seconds: 60, fail_closed: false
  end

  pipeline :api_auth do
    plug DundaWeb.Plugs.RateLimit, scope: "api-auth", limit: 90, window_seconds: 60, fail_closed: true
    plug DundaWeb.Plugs.AuthPlug
  end

  pipeline :auth_rate_limit do
    plug DundaWeb.Plugs.RateLimit, scope: "auth", limit: 20, window_seconds: 60, fail_closed: true
  end

  pipeline :webhook_rate_limit do
    plug DundaWeb.Plugs.RateLimit, scope: "webhook", limit: 300, window_seconds: 60, fail_closed: true
  end

  pipeline :metrics_rate_limit do
    plug DundaWeb.Plugs.RateLimit, scope: "metrics", limit: 30, window_seconds: 60, fail_closed: true
  end

  pipeline :resale_gate do
    plug DundaWeb.Plugs.ResaleGate
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
    get "/livez", HealthController, :live
    get "/readyz", HealthController, :ready
    get "/healthz", HealthController, :show
  end

  scope "/internal", DundaWeb do
    pipe_through :metrics_rate_limit

    get "/metrics", MetricsController, :show
    get "/release-health", ReleaseHealthController, :show
  end

  pipeline :organiser_auth do
    plug DundaWeb.Plugs.OrganiserAuthPlug
  end

  # Organiser Sessions
  scope "/portal", DundaWeb.Organiser do
    pipe_through :browser

    live "/login", LoginLive, :index
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # Protected Organiser Portal
  scope "/portal", DundaWeb.Organiser do
    pipe_through [:browser, :organiser_auth]

    live_session :organiser_portal, on_mount: [{DundaWeb.OrganiserAuth, :ensure_authenticated}] do
      live "/", DashboardLive, :index
      live "/onboarding", OnboardingLive, :index
      live "/analytics", AnalyticsLive, :index
      live "/payouts", PayoutsLive, :index
      live "/scraper", ScraperLive, :index
      live "/events", EventsLive, :index
      live "/events/new", EventEditorLive, :new
      live "/events/:id/edit", EventEditorLive, :edit
      live "/events/:id/extras", ExtrasLive, :index
      live "/events/:id/tickets", TicketsLive, :index
      live "/team", TeamLive, :index
      live "/health", HealthLive, :index
      live "/support", SupportLive, :index
    end
  end

  scope "/api", DundaWeb do
    pipe_through [:api, :auth_rate_limit]

    # Auth
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    post "/auth/google", ContainmentController, :disabled
    post "/auth/otp/send", ContainmentController, :disabled
    post "/auth/otp/verify", ContainmentController, :disabled

  end

  scope "/api", DundaWeb do
    pipe_through :api

    get "/events", EventController, :index
    get "/events/:id", EventController, :show
  end

  # Provider callbacks are isolated from ordinary public API traffic and have
  # a fail-closed limiter before signature verification.
  scope "/api", DundaWeb do
    pipe_through [:api, :webhook_rate_limit]

    post "/mpesa/callback", ContainmentController, :disabled
    post "/mpesa/b2c/result", PayoutController, :result
    get "/pesapal/ipn", ContainmentController, :disabled
    post "/pesapal/ipn", ContainmentController, :disabled
  end

  scope "/api", DundaWeb do
    pipe_through [:api, :api_auth]

    get "/tickets", TicketController, :index
    post "/tickets/:id/device-challenge", TicketCredentialController, :challenge
    post "/tickets/:id/bind-device", TicketCredentialController, :bind
    post "/privacy/requests", PrivacyController, :create_request
    get "/privacy/export", PrivacyController, :export
    # Consumer checkout is identity-bound and price-authoritative. The
    # controller preserves the Phase 0 containment response until G3–G5 pass.
    post "/quotes", CheckoutController, :quote
    post "/checkout", CheckoutController, :create
    get "/checkout/:id/status", CheckoutController, :status
    post "/billing/orders", ContainmentController, :disabled

  end

  scope "/api/providers", DundaWeb do
    pipe_through [:api, :webhook_rate_limit]
    post "/:provider/events", ProviderEventsController, :create
  end

  # Venue-local coordinator protocol. A scanner operator must be an active
  # organisation member; the coordinator serialises admission on the primary DB.
  scope "/api/scanner", DundaWeb do
    pipe_through [:api, :api_auth, :webhook_rate_limit]
    post "/devices", ScannerController, :register_device
    post "/devices/:id/revoke", ScannerController, :revoke_device
    get "/manifests/:event_id", ScannerController, :manifest
    post "/manifests/:event_id/publish", ScannerController, :publish_manifest
    post "/admissions", ScannerController, :admit
  end

  scope "/api", DundaWeb do
    pipe_through [:api, :resale_gate, :api_auth]

    get "/resale/listings", ResaleController, :index
    post "/resale/listings", ResaleController, :create
    post "/resale/listings/:id/intent", ResaleController, :intent
  end
end
