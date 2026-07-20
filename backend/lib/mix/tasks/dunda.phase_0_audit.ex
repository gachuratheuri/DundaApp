defmodule Mix.Tasks.Dunda.Phase0Audit do
  @shortdoc "Prints a read-only Phase 0 financial and entitlement audit"

  @moduledoc """
  Produces a deterministic, read-only snapshot of the database invariants that
  must be reconciled before containment is lifted. It never writes application
  data, contacts payment providers, or enumerates Redis keys.
  """

  use Mix.Task
  import Ecto.Query

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    counts = %{
      orders: Dunda.Repo.aggregate(Dunda.Billing.Order, :count),
      tickets: Dunda.Repo.aggregate(Dunda.Ticketing.Ticket, :count),
      ledger_entries: Dunda.Repo.aggregate(Dunda.Ledger.Entry, :count),
      resale_listings: Dunda.Repo.aggregate(Dunda.Market.Listing, :count)
    }

    duplicate_fulfilments =
      from(t in Dunda.Ticketing.Ticket,
        where: not is_nil(t.fulfillment_key),
        group_by: t.fulfillment_key,
        having: count(t.id) > 1,
        select: {t.fulfillment_key, count(t.id)}
      )
      |> Dunda.Repo.all()

    Mix.shell().info("Phase 0 audit (read-only)")
    Mix.shell().info("environment=#{Dunda.Containment.environment()}")
    Enum.each(counts, fn {name, count} -> Mix.shell().info("#{name}=#{count}") end)
    Mix.shell().info("duplicate_ticket_fulfillment_keys=#{length(duplicate_fulfilments)}")

    Enum.each(duplicate_fulfilments, fn {fulfillment_key, count} ->
      Mix.shell().info("duplicate_fulfillment_key=#{fulfillment_key} tickets=#{count}")
    end)

    :ok
  end
end
