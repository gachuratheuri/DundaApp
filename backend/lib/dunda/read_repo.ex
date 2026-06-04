defmodule Dunda.ReadRepo do
  @moduledoc """
  Read-only replica repository. All read paths (event discovery, dashboards,
  analytics, search) route here to keep the primary write node free for
  onsale-moment write throughput.

  The connection is forced read-only via `after_connect` in `config/runtime.exs`
  so a stray write fails loudly instead of silently hitting a replica.
  """
  use Ecto.Repo,
    otp_app: :dunda,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
