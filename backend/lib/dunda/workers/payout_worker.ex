defmodule Dunda.Workers.PayoutWorker do
  @moduledoc """
  Durable organiser payout submission.

  Order selection and payout-item attachment commit before the external B2C
  request. Provider acceptance only records `submitted`; `paid` is set only by
  the verified result callback. A batch is atomically claimed as `submitting`
  before the call, so concurrent workers cannot issue a second request;
  ambiguous outcomes are retained for manual reconciliation and never silently
  retried.
  """

  use Oban.Worker, queue: :payments, max_attempts: 3
  require Logger

  alias Dunda.Organisations
  alias Dunda.Organisations.Payouts
  alias Dunda.Payments.Daraja
  alias Dunda.{Accounts, Repo}

  @impl Oban.Worker
  def perform(_job) do
    if Dunda.Containment.blocked?(:payouts) do
      {:cancel, :phase_0_containment}
    else
      Organisations.list_organisations()
      |> Enum.each(&settle_organisation/1)

      Payouts.payable_user_ids()
      |> Enum.each(&settle_seller/1)

      :ok
    end
  end

  defp settle_organisation(%{id: organisation_id, mpesa_phone_encrypted: phone})
       when is_binary(phone) do
    settle_beneficiary(
      phone,
      "organisation:#{organisation_id}",
      &Payouts.create_batch(organisation_id, &1, &2)
    )
  end

  defp settle_organisation(%{id: organisation_id}),
    do:
      Logger.warning("Payout organisation #{organisation_id} has no encrypted payout destination")

  defp settle_seller(user_id) do
    case Repo.get(Accounts.User, user_id) do
      %{phone_msisdn: phone} when is_binary(phone) ->
        settle_beneficiary(
          phone,
          "seller:#{user_id}",
          &Payouts.create_seller_batch(user_id, &1, &2)
        )

      _ ->
        Logger.warning("Resale seller #{user_id} has no verified encrypted payout destination")
    end
  end

  defp settle_beneficiary(phone, beneficiary_label, create_batch) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case create_batch.(now, now) do
      {:ok, %{status: "submitted"} = batch} ->
        Logger.info(
          "Payout batch #{batch.id} already submitted; awaiting verified provider result"
        )

      {:ok, %{status: status} = batch} when status in ["pending", "submitting"] ->
        case Payouts.claim_batch_submission(batch) do
          {:ok, %{status: "submitting"} = claimed} when status == "pending" ->
            submit(phone, claimed)

          {:ok, %{status: "submitting"}} ->
            Logger.info(
              "Payout batch #{batch.id} is already being reconciled; no duplicate submission"
            )

          {:ok, %{status: "submitted"}} ->
            Logger.info(
              "Payout batch #{batch.id} already submitted; awaiting verified provider result"
            )

          {:ok, %{status: "manual_review"}} ->
            Logger.warning(
              "Payout batch #{batch.id} exceeded the submission claim timeout; operator reconciliation required"
            )

          {:error, reason} ->
            Logger.warning("Payout batch #{batch.id} could not be claimed: #{inspect(reason)}")
        end

      {:error, :nothing_payable} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Payout batch for #{beneficiary_label} retained for reconciliation: #{inspect(reason)}"
        )
    end
  end

  defp submit(phone, batch) do
    if rem(batch.amount_cents, 100) != 0 do
      _ = Payouts.mark_batch_manual_review(batch, :fractional_kes_not_supported_by_b2c)

      Logger.warning(
        "Payout batch #{batch.id} requires fractional KES and was held for manual review"
      )
    else
      submit_whole_kes(phone, batch)
    end
  end

  defp submit_whole_kes(phone, batch) do
    amount = div(batch.amount_cents, 100)

    case Daraja.b2c(phone, amount, "Dunda payout batch #{batch.id}") do
      {:ok, conversation_id} ->
        case Payouts.mark_batch_submitted(batch, conversation_id) do
          {:ok, _submitted} ->
            Logger.info("Payout batch #{batch.id} submitted; awaiting verified provider result")

          {:error, reason} ->
            Logger.warning(
              "Payout batch #{batch.id} could not persist provider reference: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        _ = Payouts.mark_batch_manual_review(batch, reason)

        Logger.warning(
          "Payout batch #{batch.id} moved to manual review after ambiguous provider response: #{inspect(reason)}"
        )
    end
  end
end
