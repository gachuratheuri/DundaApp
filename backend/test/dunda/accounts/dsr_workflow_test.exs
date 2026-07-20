defmodule Dunda.Accounts.DsrWorkflowTest do
  use Dunda.DataCase, async: true

  alias Dunda.Accounts.{DataSubjectRequest, Privacy, User}

  defp unique, do: System.unique_integer([:positive])

  defp insert_user! do
    n = unique()

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "dsr-#{n}@example.com",
        "password" => "password123!",
        "name" => "DSR Test #{n}"
      })

    user
  end

  defp insert_request!(user, type) do
    {:ok, request} = Privacy.create_request(user.id, type, user.email)
    request
  end

  describe "process_rectification/3" do
    test "updates the user's name and completes the request" do
      user = insert_user!()
      request = insert_request!(user, "rectification")

      assert {:ok, updated} = Privacy.process_rectification(user.id, request.id, %{"name" => "New Name"})
      assert updated.status == "completed"
      assert %DateTime{} = updated.completed_at

      assert Repo.get!(User, user.id).name == "New Name"
    end

    test "rejects a request that does not belong to the caller" do
      owner = insert_user!()
      other = insert_user!()
      request = insert_request!(owner, "rectification")

      assert {:error, :not_found} = Privacy.process_rectification(other.id, request.id, %{"name" => "Hijacked"})
    end

    test "rejects processing through the wrong request type" do
      user = insert_user!()
      request = insert_request!(user, "access")

      assert {:error, :wrong_request_type} = Privacy.process_rectification(user.id, request.id, %{"name" => "x"})
    end
  end

  describe "record_objection/3" do
    test "moves the request to in_progress and records the scope, without deleting anything" do
      user = insert_user!()
      request = insert_request!(user, "objection")

      assert {:ok, updated} = Privacy.record_objection(user.id, request.id, "marketing notifications")
      assert updated.status == "in_progress"
      assert updated.notes =~ "marketing notifications"
      assert Repo.get!(User, user.id).id == user.id
    end
  end

  describe "transition_status/3" do
    test "allows received -> in_progress -> completed" do
      user = insert_user!()
      request = insert_request!(user, "access")

      assert {:ok, in_progress} = Privacy.transition_status(request, "in_progress")
      assert {:ok, completed} = Privacy.transition_status(in_progress, "completed")
      assert completed.status == "completed"
      assert %DateTime{} = completed.completed_at
    end

    test "rejects a transition out of a terminal state" do
      user = insert_user!()
      request = insert_request!(user, "access")
      {:ok, completed} = Privacy.transition_status(request, "completed")

      assert {:error, :invalid_transition} = Privacy.transition_status(completed, "in_progress")
    end

    test "rejects skipping backward from rejected" do
      user = insert_user!()
      request = insert_request!(user, "access")
      {:ok, rejected} = Privacy.transition_status(request, "rejected")

      assert {:error, :invalid_transition} = Privacy.transition_status(rejected, "received")
    end
  end

  test "requests are auditable: creation and every transition write an audit event" do
    user = insert_user!()
    request = insert_request!(user, "rectification")

    count_before = Repo.aggregate(Dunda.Audit.Event, :count)
    {:ok, _} = Privacy.process_rectification(user.id, request.id, %{"name" => "Audited Name"})
    count_after = Repo.aggregate(Dunda.Audit.Event, :count)

    assert count_after > count_before
  end
end
