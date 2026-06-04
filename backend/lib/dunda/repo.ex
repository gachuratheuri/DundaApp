defmodule Dunda.Repo do
  @moduledoc """
  Primary read/write repository. All mutating operations (ticket purchase,
  settlement, scan events) must route here, never to a replica.
  """
  use Ecto.Repo,
    otp_app: :dunda,
    adapter: Ecto.Adapters.Postgres
end
