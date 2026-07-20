defmodule Dunda.ReleaseApprovals do
  @moduledoc """Read/write boundary for the Phase 4 release-approval ledger."""

  import Ecto.Query, only: [from: 2]

  alias Dunda.ReleaseApproval
  alias Dunda.Repo

  @roles ~w(security finance operations)

  @spec active_for(atom() | String.t()) :: [ReleaseApproval.t()]
  def active_for(feature) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.all(
      from a in ReleaseApproval,
        where:
          a.feature == ^to_string(feature) and is_nil(a.revoked_at) and a.approved_at <= ^now and
            a.expires_at > ^now,
        order_by: [asc: a.approval_role, desc: a.approved_at]
    )
  end

  @spec create(map()) :: {:ok, ReleaseApproval.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    case %ReleaseApproval{} |> ReleaseApproval.changeset(attrs) |> Repo.insert() do
      {:ok, approval} = result ->
        _ = Dunda.Audit.record(%{
          action: "release.approval_created",
          resource_type: "release_approval",
          resource_id: approval.id,
          metadata: %{feature: approval.feature, role: approval.approval_role, canary_percent: approval.canary_percent}
        })

        result

      error -> error
    end
  end

  @spec revoke(binary(), String.t()) :: {:ok, ReleaseApproval.t()} | {:error, term()}
  def revoke(id, reason) when is_binary(id) and is_binary(reason) do
    reason = String.trim(reason)

    if byte_size(reason) in 3..1_000 do
      case Repo.get(ReleaseApproval, id) do
        nil -> {:error, :not_found}
        %{revoked_at: revoked_at} when not is_nil(revoked_at) -> {:error, :already_revoked}
        approval ->
          approval
          |> Ecto.Changeset.cast(%{revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)}, [:revoked_at])
          |> Repo.update()
          |> case do
            {:ok, revoked} = result ->
              _ = Dunda.Audit.record(%{action: "release.approval_revoked", resource_type: "release_approval", resource_id: revoked.id, metadata: %{reason: reason}})
              result

            error -> error
          end
        end
    else
      {:error, :invalid_revocation}
    end
  end

  def revoke(_, _), do: {:error, :invalid_revocation}

  @doc "Returns the release decision; any database/configuration failure denies access."
  @spec approved?(atom() | String.t(), term()) :: boolean()
  def approved?(feature, subject \\ nil) do
    if Application.get_env(:dunda, :phase4_gate_enforced, true) != true do
      true
    else
      approvals = active_for(to_string(feature))
      roles = approvals |> Enum.map(& &1.approval_role) |> MapSet.new()

      Enum.all?(@roles, &MapSet.member?(roles, &1)) and
        distinct_approvers?(approvals) and
        canary_allowed?(approvals, subject)
    end
  rescue
    _ -> false
  end

  @spec status(atom() | String.t()) :: map()
  def status(feature) do
    approvals = active_for(to_string(feature))

    %{
      feature: to_string(feature),
      gate_enforced: Application.get_env(:dunda, :phase4_gate_enforced, true) == true,
      required_roles: @roles,
      active_roles: approvals |> Enum.map(& &1.approval_role) |> Enum.uniq() |> Enum.sort(),
      canary_percent: approvals |> Enum.map(& &1.canary_percent) |> Enum.min(fn -> 0 end),
      approved: approved?(feature)
    }
  rescue
    _ -> %{
      feature: to_string(feature),
      gate_enforced: Application.get_env(:dunda, :phase4_gate_enforced, true) == true,
      required_roles: @roles,
      active_roles: [],
      canary_percent: 0,
      approved: false
    }
  end

  defp distinct_approvers?(approvals) do
    approvals |> Enum.map(& &1.approver_ref) |> Enum.uniq() |> length() >= length(@roles)
  end

  defp canary_allowed?(approvals, nil) do
    approvals |> Enum.map(& &1.canary_percent) |> Enum.min(fn -> 0 end) == 100
  end

  defp canary_allowed?(approvals, subject) do
    percent = approvals |> Enum.map(& &1.canary_percent) |> Enum.min(fn -> 0 end)
    bucket = :erlang.phash2(to_string(subject), 100)
    bucket < percent
  end
end
