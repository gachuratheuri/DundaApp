defmodule Dunda.ReleaseApproval do
  @moduledoc """Persisted multi-party approval for controlled Phase 4 feature release."""

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  # Extended from (security, finance, operations) to the full five-role G12
  # governance set (Phase 12 §12.12) — product and privacy sign-off are now
  # required before any globally guarded feature can activate, matching the
  # root plan's exit gate: "ops/security/product/finance/privacy approvals".
  @roles ~w(security finance operations product privacy)
  @type t :: %__MODULE__{}

  schema "release_approvals" do
    field :feature, :string
    field :approval_role, :string
    field :approver_ref, :string
    field :evidence_uri, :string
    field :canary_percent, :integer, default: 0
    field :approved_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [
      :feature, :approval_role, :approver_ref, :evidence_uri, :canary_percent,
      :approved_at, :expires_at, :revoked_at, :metadata
    ])
    |> update_change(:feature, &String.trim/1)
    |> update_change(:approval_role, &String.trim/1)
    |> update_change(:approver_ref, &String.trim/1)
    |> update_change(:evidence_uri, &String.trim/1)
    |> validate_required([:feature, :approval_role, :approver_ref, :evidence_uri, :approved_at, :expires_at])
    |> validate_inclusion(:approval_role, @roles)
    |> validate_length(:feature, min: 1, max: 120)
    |> validate_length(:approver_ref, min: 1, max: 200)
    |> validate_length(:evidence_uri, min: 8, max: 2_048)
    |> validate_number(:canary_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_change(:approved_at, fn :approved_at, approved_at ->
      if match?(%DateTime{}, approved_at) and DateTime.compare(approved_at, DateTime.utc_now()) in [:lt, :eq],
        do: [],
        else: [approved_at: "must not be in the future"]
    end)
    |> validate_change(:expires_at, fn :expires_at, expires_at ->
      if match?(%DateTime{}, expires_at) and DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
        do: [],
        else: [expires_at: "must be in the future"]
    end)
    |> unique_constraint([:feature, :approval_role, :approver_ref, :approved_at],
      name: :release_approvals_active_unique
    )
  end
end
