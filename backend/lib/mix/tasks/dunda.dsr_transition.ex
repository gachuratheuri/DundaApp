defmodule Mix.Tasks.Dunda.DsrTransition do
  use Mix.Task
  @shortdoc "Operator-driven data-subject-request status transition"

  @moduledoc """
  Moves a `Dunda.Accounts.DataSubjectRequest` through its status lifecycle
  (`received -> in_progress -> completed | rejected`). This is ops tooling,
  not end-user self-service — end users move `rectification`/`objection`
  requests via `PATCH /api/privacy/requests/:id`
  (`DundaWeb.PrivacyController.update_request/2`); every other request type
  (`access`, `erasure`, `portability`) is completed by an operator after the
  corresponding export/anonymisation has actually been delivered, which is
  what this task records.

      mix dunda.dsr_transition --id <uuid> --status completed
      mix dunda.dsr_transition --id <uuid> --status rejected --note "duplicate of <uuid>"
  """

  alias Dunda.Accounts.{DataSubjectRequest, Privacy}
  alias Dunda.Repo

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, switches: [id: :string, status: :string, note: :string])

    with id when is_binary(id) <- opts[:id] || Mix.raise("--id is required"),
         status when is_binary(status) <- opts[:status] || Mix.raise("--status is required"),
         %DataSubjectRequest{} = request <-
           Repo.get(DataSubjectRequest, id) || Mix.raise("request not found: #{id}") do
      attrs = if opts[:note], do: %{notes: opts[:note]}, else: %{}

      case Privacy.transition_status(request, status, attrs) do
        {:ok, updated} ->
          Mix.shell().info("#{updated.id}: #{request.status} -> #{updated.status}")

        {:error, :invalid_transition} ->
          Mix.raise("invalid transition: #{request.status} -> #{status}")

        {:error, changeset} ->
          Mix.raise("transition rejected: #{inspect(changeset.errors)}")
      end
    end
  end
end
