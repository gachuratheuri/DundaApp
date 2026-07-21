defmodule Dunda.Workers.MpesaFulfillmentWorker do
  @moduledoc """
  Runs after an M-Pesa settlement: commits the inventory escrow (so the
  reclaimer can never re-credit sold tickets) and issues the tickets.

  All settlement paths (Daraja callback, dead-letter poll, offline callback
  replay) funnel through this worker, making it the single choke point for
  post-payment side effects. Every step is idempotent, so Oban retries are safe.
  """
  use Oban.Worker, queue: :payments, max_attempts: 5

  alias Dunda.Accounts
  alias Dunda.Events
  alias Dunda.Inventory
  alias Dunda.Ledger
  alias Dunda.Ticketing

  @spec enqueue(String.t(), String.t(), String.t(), integer()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(transaction_id, pool_id, user_id, quantity) do
    %{
      "transaction_id" => transaction_id,
      "ticket_tier_id" => pool_id,
      "user_id" => user_id,
      "quantity" => quantity
    }
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      transaction_id = args["transaction_id"]
      pool_id = args["ticket_tier_id"]
      user_id = args["user_id"]
      quantity = args["quantity"]

      # Verify the ledger is actually settled
      if Ledger.settled?(transaction_id) do
        with :ok <- Inventory.commit_escrow(pool_id, transaction_id),
             {:ok, tier, event} <- resolve_pool(pool_id),
             %Accounts.User{} = user <- Accounts.get_user(user_id) do
          # Exactly-once: a retry (or a callback racing the dead-letter poll)
          # finds the tickets already recorded against this transaction.
          if Ticketing.fulfilled?(transaction_id) do
            :ok
          else
            case Ticketing.issue_tickets(nil, event, user, quantity,
                   tier: tier,
                   transaction_id: transaction_id
                 ) do
              {:ok, _tickets} -> :ok
              {:error, reason} -> {:error, reason}
            end
          end
        else
          nil -> {:error, :invalid_event_or_user}
          {:error, reason} -> {:error, reason}
        end
      else
        # If the ledger isn't settled yet, the worker will fail and retry later
        {:error, :ledger_not_settled}
      end
    end
  end

  # Lookups go to the primary repo, not the read replica: fulfillment runs
  # right after payment and must not fail (and burn Oban retries) on replica
  # lag for recently created events or tiers.
  defp resolve_pool("tier:" <> tier_id) do
    case Ticketing.get_tier(tier_id) do
      %Ticketing.TicketTier{} = tier ->
        case Dunda.Repo.get(Events.Event, tier.event_id) do
          nil -> {:error, :invalid_event_or_user}
          event -> {:ok, tier, event}
        end

      nil ->
        {:error, :invalid_event_or_user}
    end
  end

  defp resolve_pool("event:" <> event_id), do: resolve_event(event_id)
  # Legacy jobs enqueued before pool ids were namespaced carried a raw event id.
  defp resolve_pool(event_id), do: resolve_event(event_id)

  defp resolve_event(event_id) do
    case Dunda.Repo.get(Events.Event, event_id) do
      nil -> {:error, :invalid_event_or_user}
      event -> {:ok, nil, event}
    end
  end
end
