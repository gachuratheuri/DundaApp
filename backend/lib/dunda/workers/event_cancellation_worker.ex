defmodule Dunda.Workers.EventCancellationWorker do
  @moduledoc "Resumable bounded refund-intent sweep for cancelled events."

  use Oban.Worker, queue: :payments, max_attempts: 5
  import Ecto.Query, only: [from: 2]
  require Logger

  alias Dunda.Billing.{Order, Refunds}
  alias Dunda.Repo

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id, "cursor" => cursor, "actor_id" => actor_id, "reason" => reason}}) do
    batch_size = @batch_size

    orders =
      Repo.all(
        from o in Order,
          where:
            o.event_id == ^event_id and o.id > ^cursor and o.status in ["completed", "partially_refunded"] and
              o.refund_status not in ["succeeded", "manual_review"],
          order_by: [asc: o.id],
          limit: ^batch_size
      )

    Enum.each(orders, fn order ->
      case Refunds.request_remaining(order.id, actor_id, reason, "event-cancel:#{event_id}:#{order.id}") do
        {:ok, _refund} -> :ok
        {:error, error} -> Logger.error("event cancellation refund intent failed for order #{order.id}: #{inspect(error)}")
      end
    end)

    case List.last(orders) do
      nil -> :ok
      last ->
        __MODULE__.new(%{"event_id" => event_id, "cursor" => last.id, "actor_id" => actor_id, "reason" => reason})
        |> Oban.insert()
        :ok
    end
  end
end
