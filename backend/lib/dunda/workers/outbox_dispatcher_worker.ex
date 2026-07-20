defmodule Dunda.Workers.OutboxDispatcherWorker do
  @moduledoc "Claims committed outbox events and hands them to durable Oban work."
  use Oban.Worker, queue: :payments, max_attempts: 10
  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.OutboxEvent
  alias Dunda.Repo

  require OpenTelemetry.Tracer

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.transaction(fn ->
        events = Repo.all(from e in OutboxEvent, where: e.status == "pending" and e.available_at <= ^now, order_by: [asc: e.inserted_at], limit: 100, lock: "FOR UPDATE SKIP LOCKED")
        Enum.each(events, fn event -> dispatch_traced(event, now) end)
      end)
      :ok
    end
  end

  # Manual span (Phase 12 observability): no maintained OpenTelemetry
  # auto-instrumentation exists for Oban, so the durable-intent-to-dispatch
  # boundary (Invariant 9) is traced explicitly here rather than left dark.
  defp dispatch_traced(%OutboxEvent{} = event, now) do
    OpenTelemetry.Tracer.with_span "outbox.dispatch", %{
      attributes: %{"outbox.event_type" => event.event_type, "outbox.aggregate_id" => to_string(event.aggregate_id)}
    } do
      dispatch(event, now)
    end
  end

  defp dispatch(%OutboxEvent{event_type: "payment_submission_requested"} = event, now) do
    case Dunda.Workers.PaymentSubmissionWorker.new(%{"payment_intent_id" => event.aggregate_id, "outbox_event_id" => event.id}) |> Oban.insert() do
      {:ok, _job} -> Repo.update!(OutboxEvent.changeset(event, %{status: "published", published_at: now, attempts: event.attempts + 1}))
      {:error, reason} -> Repo.rollback({:outbox_dispatch_failed, reason})
    end
  end
  defp dispatch(%OutboxEvent{event_type: "payment_fulfilment_requested"} = event, now) do
    case Dunda.Workers.PaymentFulfilmentWorker.new(%{"payment_intent_id" => event.aggregate_id, "outbox_event_id" => event.id}) |> Oban.insert() do
      {:ok, _job} -> Repo.update!(OutboxEvent.changeset(event, %{status: "published", published_at: now, attempts: event.attempts + 1}))
      {:error, reason} -> Repo.rollback({:outbox_dispatch_failed, reason})
    end
  end
  defp dispatch(%OutboxEvent{event_type: "payment_refund_requested"} = event, now) do
    case Dunda.Workers.PaymentRefundWorker.new(%{"payment_intent_id" => event.aggregate_id, "outbox_event_id" => event.id}) |> Oban.insert() do
      {:ok, _job} -> Repo.update!(OutboxEvent.changeset(event, %{status: "published", published_at: now, attempts: event.attempts + 1}))
      {:error, reason} -> Repo.rollback({:outbox_dispatch_failed, reason})
    end
  end
  defp dispatch(%OutboxEvent{} = event, now), do: Repo.update!(OutboxEvent.changeset(event, %{status: "published", published_at: now, attempts: event.attempts + 1}))
end
