defmodule Dunda.Workers.DsrDeadlineWorkerTest do
  # async: false — Dunda.Observability's gauge/counter table is
  # process-global (ETS, not per-test-transaction), so a concurrently
  # running async test's own perform/1 could race these assertions.
  use Dunda.DataCase, async: false

  alias Dunda.Accounts.DataSubjectRequest
  alias Dunda.Workers.DsrDeadlineWorker

  defp insert_user! do
    n = System.unique_integer([:positive])

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "dsr-deadline-#{n}@example.com",
        "password" => "password123!",
        "name" => "DSR Deadline Test"
      })

    user
  end

  defp insert_request_with_due_by!(user, due_by) do
    {:ok, request} =
      %DataSubjectRequest{}
      |> DataSubjectRequest.changeset(%{
        user_id: user.id,
        request_type: "access",
        status: "received",
        due_by: due_by
      })
      |> Repo.insert()

    request
  end

  test "gauges the overdue and due-soon counts and audits when a request is overdue" do
    user = insert_user!()
    overdue_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
    insert_request_with_due_by!(user, overdue_at)

    audit_count_before = Repo.aggregate(Dunda.Audit.Event, :count)

    assert :ok = DsrDeadlineWorker.perform(%Oban.Job{})

    counters = Dunda.Observability.counters()
    assert Map.get(counters, {:gauge, :dsr_requests_overdue}, 0) == 1
    assert Repo.aggregate(Dunda.Audit.Event, :count) > audit_count_before
  end

  test "does not count a completed request as overdue even past its due_by" do
    user = insert_user!()
    overdue_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
    request = insert_request_with_due_by!(user, overdue_at)
    {:ok, _} = Dunda.Accounts.Privacy.transition_status(request, "completed")

    assert :ok = DsrDeadlineWorker.perform(%Oban.Job{})

    counters = Dunda.Observability.counters()
    assert Map.get(counters, {:gauge, :dsr_requests_overdue}, 0) == 0
  end
end
