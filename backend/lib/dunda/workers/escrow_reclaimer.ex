defmodule Dunda.Workers.EscrowReclaimer do
  use Oban.Worker, queue: :escrow_cleanup, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_tier_id" => tier_id}}) when not is_nil(tier_id) do
    reclaim_for_tier(tier_id)
  end

  def perform(%Oban.Job{args: _}) do
    # Sweeper sweep: find all events and reclaim for each tier
    Dunda.Repo.all(Dunda.Events.Event)
    |> Enum.each(fn event -> reclaim_for_tier(event.id) end)

    :ok
  end

  defp reclaim_for_tier(tier_id) do
    escrow_key = "escrow:#{tier_id}"
    inv_key    = "inventory:#{tier_id}"

    # Fetch all entries in the escrow hash
    case Redix.command(:redix, ["HGETALL", escrow_key]) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> Enum.chunk_every(2)
        |> Enum.each(fn
          [user_id, qty] ->
            expiry_key = "expiry:#{escrow_key}:#{user_id}"
            case Redix.command(:redix, ["EXISTS", expiry_key]) do
              {:ok, 0} ->
                # Expiry key gone but escrow entry remains — reclaim atomically
                reclaim_script = """
                if redis.call("HEXISTS", KEYS[1], ARGV[1]) == 1 then
                  redis.call("INCRBY", KEYS[2], ARGV[2])
                  redis.call("HDEL", KEYS[1], ARGV[1])
                  return 1
                end
                return 0
                """
                Redix.command(:redix, ["EVAL", reclaim_script, 2, escrow_key, inv_key, user_id, qty])
              _ -> :noop
            end
          _ -> :noop
        end)
      _ -> :noop
    end

    :ok
  end
end
