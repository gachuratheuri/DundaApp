defmodule Dunda.Containment do
  @moduledoc """
  Emergency containment controls for the pre-production system.

  This is deliberately fail-closed. The flag is enabled in the base
  configuration and must be removed only after the security and financial
  invariants in the implementation plan have been independently verified.
  """

  @blocked_features [
    :oauth_authentication,
    :otp_authentication,
    :checkout,
    :billing,
    :resale,
    :mpesa_callbacks,
    :pesapal_ipn,
    :payouts,
    :dynamic_scraping,
    :ticket_credentials,
    :scanner_admission,
    :portal_access,
    :portal_mutations
  ]

  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:dunda, :containment_mode, true) == true

  @spec blocked?(atom()) :: boolean()
  def blocked?(feature) when is_atom(feature) do
    (enabled?() or feature_blocked_by_release_gate?(feature)) and feature in @blocked_features
  end

  @doc """
  Subject-aware Phase 4 decision for canary-capable callers.  The legacy
  feature guards intentionally call `blocked?/1` without a subject and thus
  require 100% approval before any global activation.
  """
  @spec permitted?(atom(), term()) :: boolean()
  def permitted?(feature, subject) when is_atom(feature) do
    feature in @blocked_features and not enabled?() and
      Dunda.ReleaseApprovals.approved?(feature, subject)
  end

  @spec blocked_features() :: [atom()]
  def blocked_features, do: @blocked_features

  @doc "Returns the deployment label exposed by operational diagnostics."
  @spec environment() :: String.t()
  def environment do
    :dunda
    |> Application.get_env(:environment, "non-production")
    |> to_string()
  end

  @doc "Whether organiser portal access is permitted for this user."
  @spec portal_allowed?(term()) :: boolean()
  def portal_allowed?(%{id: id, email: email}) do
    configured_ids = Application.get_env(:dunda, :portal_admin_user_ids, [])
    configured_emails = Application.get_env(:dunda, :portal_admin_emails, [])
    env_emails = System.get_env("PORTAL_ADMIN_EMAILS", "") |> String.split(",", trim: true)
    env_ids = System.get_env("PORTAL_ADMIN_USER_IDS", "") |> String.split(",", trim: true)

    id_values = (List.wrap(configured_ids) ++ env_ids) |> Enum.map(&to_string/1) |> MapSet.new()

    email_values =
      (List.wrap(configured_emails) ++ env_emails)
      |> Enum.map(&(to_string(&1) |> String.trim() |> String.downcase()))
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    (not is_nil(id) and MapSet.member?(id_values, to_string(id))) or
      (is_binary(email) and MapSet.member?(email_values, String.downcase(String.trim(email))))
  end

  def portal_allowed?(_), do: false

  @doc "All organiser LiveView events are read-only during emergency containment."
  @spec portal_mutations_blocked?() :: boolean()
  def portal_mutations_blocked?, do: blocked?(:portal_mutations)

  defp feature_blocked_by_release_gate?(feature) do
    feature in @blocked_features and
      Application.get_env(:dunda, :phase4_gate_enforced, true) and
      not Dunda.ReleaseApprovals.approved?(feature)
  rescue
    _ -> true
  end
end
