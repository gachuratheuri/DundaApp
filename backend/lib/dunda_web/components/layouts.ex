defmodule DundaWeb.Layouts do
  @moduledoc """
  Root + app layouts for the small organiser portal. To avoid an asset build
  step on a backend that is otherwise a JSON API, the LiveView/Phoenix JS is
  loaded from a CDN (UMD globals) and the LiveSocket is wired inline. Styling is
  inlined here in a cyber-brutalist dark theme matching the mobile app.
  """
  use DundaWeb, :html

  @phoenix_js "https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js"
  @lv_js "https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.17/priv/static/phoenix_live_view.min.js"

  def root(assigns) do
    assigns = assign(assigns, phoenix_js: @phoenix_js, lv_js: @lv_js)

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Dunda · Organiser Portal</title>
        <style>
          :root { --bg:#000; --panel:#0c0c0e; --line:rgba(252,252,253,.1);
                  --txt:#fcfcfd; --muted:#a99fb8; --acid:#b026ff; --gold:#f4f800; }
          * { box-sizing:border-box; }
          body { margin:0; background:var(--bg); color:var(--txt);
                 font-family:Inter,system-ui,sans-serif; }
          .portal { max-width:920px; margin:0 auto; padding:32px 20px 80px; }
          h1 { font-family:Oswald,Impact,sans-serif; font-weight:900;
               text-transform:uppercase; letter-spacing:-1.5px; font-size:34px; margin:0 0 4px; }
          .sub { color:var(--muted); margin:0 0 28px; }
          .grid { display:grid; grid-template-columns:280px 1fr; gap:20px; }
          .card { background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:18px; }
          .orglist a { display:block; padding:10px 12px; border-radius:8px; color:var(--txt);
                       text-decoration:none; border:1px solid transparent; }
          .orglist a:hover { border-color:var(--line); }
          .orglist a.active { background:rgba(176,38,255,.14); border-color:var(--acid); }
          .orglist .off { color:var(--muted); font-size:12px; }
          label { display:block; font-size:12px; text-transform:uppercase; letter-spacing:.5px;
                  color:var(--muted); margin:14px 0 6px; }
          input[type=text], input[type=tel] { width:100%; background:#08080a; color:var(--txt);
                  border:1px solid var(--line); border-radius:8px; padding:11px 12px; font-size:15px; }
          input:focus { outline:none; border-color:var(--acid); }
          .row { display:flex; align-items:center; gap:10px; margin-top:14px; }
          .btn { background:var(--acid); color:#000; border:none; border-radius:10px; padding:12px 20px;
                 font-weight:700; text-transform:uppercase; letter-spacing:.5px; cursor:pointer; }
          .btn.ghost { background:transparent; color:var(--txt); border:1px solid var(--line); }
          .err { color:#ff1c5e; font-size:12px; margin-top:4px; }
          .notice { background:rgba(244,248,0,.1); border:1px solid var(--gold); color:var(--gold);
                    padding:12px 14px; border-radius:10px; margin-bottom:18px; }
        </style>
      </head>
      <body>
        <%= @inner_content %>
        <script src={@phoenix_js}></script>
        <script src={@lv_js}></script>
        <script>
          (function () {
            const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
            const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
              params: { _csrf_token: csrfToken }
            });
            liveSocket.connect();
            window.liveSocket = liveSocket;
          })();
        </script>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main class="portal">
      <%= @inner_content %>
    </main>
    """
  end
end
