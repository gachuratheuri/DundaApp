defmodule Dunda.Workers.PayoutWorker do
  @moduledoc """
  Daily organiser settlement (queue `payments`, cron 06:00 EAT).

  Sums each organisation's completed-but-unpaid orders and sends the net amount
  to the organisation's `mpesa_phone` via Daraja B2C. Only on a successful B2C
  acknowledgement are those orders flagged `paid`, so a failed payout is simply
  retried on the next run (no double payouts, no lost settlements).
  """
  use Oban.Worker, queue: :payments, max_attempts: 3

  require Logger

  alias Dunda.Billing
  alias Dunda.Organisations
  alias Dunda.Payments.Daraja

  @impl Oban.Worker
  def perform(_job) do
    Billing.payable_totals()
    |> Enum.each(&settle/1)

    :ok
  end

  defp settle({org_id, total_cents}) when is_integer(total_cents) and total_cents > 0 do
    case Organisations.get_organisation(org_id) do
      %{mpesa_phone: phone} when is_binary(phone) ->
        amount = div(total_cents, 100)

        case Daraja.b2c(phone, amount, "Dunda payout org #{org_id}") do
          {:ok, conversation_id} ->
            {count, _} = Billing.mark_organisation_paid(org_id)
            Logger.info("PayoutWorker paid org #{org_id} KES #{amount} (#{count} orders, #{conversation_id})")

          {:error, reason} ->
            Logger.error("PayoutWorker B2C failed for org #{org_id}: #{inspect(reason)}")
        end

      _ ->
        Logger.warning("PayoutWorker: org #{org_id} has KES #{div(total_cents, 100)} due but no mpesa_phone set")
    end
  end

  defp settle(_), do: :ok
end
