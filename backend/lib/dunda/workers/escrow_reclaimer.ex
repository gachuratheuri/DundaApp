defmodule Dunda.Workers.EscrowReclaimer do
  @moduledoc """
  Authoritative escrow sweep: any escrow entry whose expiry marker has lapsed
  (payment neither settled nor explicitly failed) is released back into its
  pool. Runs per-pool when targeted, or over every tier and event pool on the
  scheduled sweep. Settled purchases are safe: fulfillment commits (deletes)
  their escrow entries, so there is nothing left here to reclaim.
  """
  use Oban.Worker, queue: :escrow_cleanup, max_attempts: 3

  import Ecto.Query, only: [from: 2]

  alias Dunda.Inventory

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_tier_id" => pool_id}}) when not is_nil(pool_id) do
    if Dunda.Containment.blocked?(:checkout),
      do: {:cancel, :phase_0_containment},
      else: reclaim_for_pool(pool_id)
  end

  def perform(%Oban.Job{args: _}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      tier_pools =
        from(t in Dunda.Ticketing.TicketTier, select: t.id)
        |> Dunda.Repo.all()
        |> Enum.map(&Inventory.tier_pool/1)

      event_pools =
        from(e in Dunda.Events.Event, select: e.id)
        |> Dunda.Repo.all()
        |> Enum.map(&Inventory.event_pool/1)

      Enum.each(tier_pools ++ event_pools, &reclaim_for_pool/1)

      :ok
    end
  end

  defp reclaim_for_pool(pool_id) do
    escrow_key = Inventory.escrow_key(pool_id)

    # Fetch all entries in the escrow hash
    case Redix.command(:redix, ["HGETALL", escrow_key]) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> Enum.chunk_every(2)
        |> Enum.each(fn
          [owner_id, _qty] ->
            expiry_key = "expiry:#{escrow_key}:#{owner_id}"

            case Redix.command(:redix, ["EXISTS", expiry_key]) do
              {:ok, 0} ->
                # Expiry marker gone but escrow entry remains — the payment
                # never resolved. Release is atomic and idempotent, and also
                # clears the buyer's per-user checkout lock.
                Inventory.release_escrow(pool_id, owner_id)

              _ ->
                :noop
            end

          _ ->
            :noop
        end)

      _ ->
        :noop
    end

    :ok
  end
end
