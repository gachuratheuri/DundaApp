defmodule Dunda.Workers.EventCancellationWorker do
  @moduledoc "Resumable bounded refund-intent sweep for cancelled events."

  use Oban.Worker, queue: :payments, max_attempts: 5
  import Ecto.Query, only: [from: 2]
  require Logger

  alias Dunda.Billing.{Order, Refunds}
  alias Dunda.Repo

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "event_id" => event_id,
          "cursor" => cursor,
          "actor_id" => actor_id,
          "reason" => reason
        }
      }) do
    batch_size = @batch_size

    orders =
      Repo.all(
        from o in Order,
          where:
            o.event_id == ^event_id and o.id > ^cursor and
              o.status in ["completed", "partially_refunded"] and
              o.refund_status not in ["succeeded", "manual_review"],
          order_by: [asc: o.id],
          limit: ^batch_size
      )

    failures =
      Enum.reduce(orders, [], fn order, failures ->
        case Refunds.request_remaining(
               order.id,
               actor_id,
               reason,
               "event-cancel:#{event_id}:#{order.id}"
             ) do
          {:ok, _refund} ->
            failures

          {:error, error} ->
            Logger.error(
              "event cancellation refund intent failed for order #{order.id}: #{inspect(Dunda.Logging.Redactor.redact(error))}"
            )

            [{order.id, error} | failures]
        end
      end)

    if failures != [] do
      # Do not advance the cursor past a failed order. Idempotency keys make
      # replaying already-created intents harmless, while returning an error
      # gives Oban its normal retry/dead-letter semantics.
      {:error, {:refund_intent_batch_failed, Enum.map(failures, &elem(&1, 0))}}
    else
      case List.last(orders) do
        nil ->
          :ok

        last ->
          __MODULE__.new(%{
            "event_id" => event_id,
            "cursor" => last.id,
            "actor_id" => actor_id,
            "reason" => reason
          })
          |> Oban.insert()
          |> case do
            {:ok, _job} -> :ok
            {:error, error} -> {:error, {:continuation_enqueue_failed, error}}
          end
      end
    end
  end
end
