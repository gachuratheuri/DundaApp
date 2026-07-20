defmodule DundaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :dunda

  # Session is used only by the LiveView organiser portal (CSRF + LiveSocket).
  @session_options [
    store: :cookie,
    key: "_dunda_portal_key",
    signing_salt: "dunda_portal_salt",
    same_site: "Lax",
    http_only: true,
    secure: Application.compile_env(:dunda, :secure_cookies, false),
    max_age: 28_800
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  # Authenticated client socket for live settlement telemetry (QA FI-01).
  socket "/socket", DundaWeb.UserSocket, websocket: true, longpoll: false

  # Serve compiled portal assets (Tailwind CSS + esbuild JS bundle).
  plug Plug.Static,
    at: "/",
    from: :dunda,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  plug Plug.RequestId
  plug DundaWeb.Plugs.RequestMetrics
  plug DundaWeb.Plugs.ContainmentHeaders
  plug DundaWeb.Plugs.SecurityHeaders
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 1_000_000

  plug Plug.MethodOverride
  plug Plug.Head

  plug Plug.Session, @session_options

  plug DundaWeb.Router
end
