defmodule Dunda.Workers.DsrDeadlineWorker do
  @moduledoc """
  Monitors open data-subject requests (`Dunda.Accounts.DataSubjectRequest`)
  against their statutory `due_by` deadline. This is the alerting substrate
  the Phase 11 gap audit found missing — it does not itself page anyone;
  it emits `Dunda.Observability` counters and an audit event that an external
  alerting pipeline (`infra/observability/alerts/business_invariants.yml`)
  can act on. Runs regardless of Phase 0 containment: privacy-deadline
  monitoring is not a guarded external-effect path.
  """
  use Oban.Worker, queue: :compliance, max_attempts: 3

  import Ecto.Query

  alias Dunda.Accounts.DataSubjectRequest
  alias Dunda.Repo

  @due_soon_window_days 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    soon_cutoff = DateTime.add(now, @due_soon_window_days * 86_400, :second)

    open =
      from(r in DataSubjectRequest, where: r.status not in ["completed", "rejected"])
      |> Repo.all()

    {overdue, due_soon} =
      Enum.reduce(open, {[], []}, fn request, {overdue, due_soon} ->
        cond do
          DateTime.compare(request.due_by, now) == :lt -> {[request | overdue], due_soon}
          DateTime.compare(request.due_by, soon_cutoff) != :gt -> {overdue, [request | due_soon]}
          true -> {overdue, due_soon}
        end
      end)

    # Point-in-time counts (can legitimately go back down as requests are
    # completed) — gauges, not monotonic counters. `dsr_deadline_checks_total`
    # is the true monotonic counter: one per worker run, for liveness.
    Dunda.Observability.gauge(:dsr_requests_overdue, length(overdue))
    Dunda.Observability.gauge(:dsr_requests_due_soon, length(due_soon))
    Dunda.Observability.increment(:dsr_deadline_checks_total)

    if overdue != [] do
      _ =
        Dunda.Audit.record(%{
          action: "privacy.dsr_deadline_overdue",
          resource_type: "data_subject_request",
          metadata: %{count: length(overdue), request_ids: Enum.map(overdue, & &1.id)}
        })
    end

    :ok
  end
end
