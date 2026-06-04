defmodule DundaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :dunda

  # Session is used only by the LiveView organiser portal (CSRF + LiveSocket).
  @session_options [
    store: :cookie,
    key: "_dunda_portal_key",
    signing_salt: "dunda_portal_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug Plug.Session, @session_options

  plug DundaWeb.Router
end
