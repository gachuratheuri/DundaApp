defmodule Dunda.Organisations.Payouts do
  @moduledoc "Idempotent payout-attempt persistence; provider acceptance is not settlement."

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Dunda.Organisations.Payout
  alias Dunda.Organisations.{PayoutBatch, PayoutItem}
  alias Dunda.Checkout.PayableEntry
  alias Dunda.Repo

  @submission_timeout_seconds 900

  @spec pending_for(integer(), integer()) :: Payout.t() | nil
  def pending_for(organisation_id, amount_cents) do
    Repo.one(
      from p in Payout,
        where:
          p.organisation_id == ^organisation_id and p.amount_cents == ^amount_cents and
            p.status in ["pending", "processing"],
        order_by: [desc: p.inserted_at],
        limit: 1
    )
  end

  @spec get_by_idempotency_key(String.t()) :: Payout.t() | nil
  def get_by_idempotency_key(key), do: Repo.get_by(Payout, idempotency_key: key)

  @spec create_pending(map()) :: {:ok, Payout.t()} | {:error, Ecto.Changeset.t()}
  def create_pending(attrs) do
    %Payout{}
    |> Payout.changeset(put_encrypted_phone(attrs) |> Map.put(:status, "pending"))
    |> Repo.insert()
  end

  @spec mark_processing(Payout.t(), String.t()) :: {:ok, Payout.t()} | {:error, term()}
  def mark_processing(%Payout{} = payout, conversation_id) do
    payout
    |> Payout.changeset(%{status: "processing", b2c_conversation_id: conversation_id})
    |> Repo.update()
  end

  @doc "Reconciles a provider result and only then closes the queued order batch."
  @spec reconcile_provider_result(String.t(), term(), String.t() | nil) ::
          {:ok, Payout.t()} | {:error, atom() | Ecto.Changeset.t()}
  def reconcile_provider_result(conversation_id, result_code, receipt) do
    Repo.transaction(fn ->
      payout =
        Repo.get_by(Payout, b2c_conversation_id: conversation_id)
        |> case do
          nil -> Repo.rollback(:payout_not_found)
          payout -> payout
        end

      success? = to_string(result_code) == "0"

      attrs =
        if success? do
          %{
            status: "paid",
            b2c_receipt: receipt,
            paid_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }
        else
          %{status: "failed", failure_reason: "provider_result_#{result_code}"}
        end

      case payout |> Payout.changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          _ =
            Dunda.Audit.record(%{
              action: "payout.provider_reconciled",
              resource_type: "payout",
              resource_id: to_string(updated.id),
              metadata: %{status: updated.status, result_code: result_code}
            })

          if success? do
            case Dunda.Billing.mark_organisation_paid(payout.organisation_id) do
              {:error, reason} -> Repo.rollback(reason)
              {_count, _} -> :ok
            end
          else
            Dunda.Billing.unqueue_organisation_orders(payout.organisation_id)
          end

          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, payout} -> {:ok, payout}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @doc "Selects eligible organiser subledger entries once and attaches them to one payout batch."
  @spec create_batch(integer(), DateTime.t(), DateTime.t()) ::
          {:ok, PayoutBatch.t()} | {:error, term()}
  def create_batch(organisation_id, period_start, period_end) do
    create_beneficiary_batch(:organisation, organisation_id, period_start, period_end)
  end

  @doc "Selects eligible resale-seller subledger entries for one user."
  def create_seller_batch(user_id, period_start, period_end) do
    create_beneficiary_batch(:user, user_id, period_start, period_end)
  end

  def payable_user_ids do
    Repo.all(
      from p in PayableEntry,
        where:
          not is_nil(p.beneficiary_user_id) and p.status == "payable" and
            p.amount_cents > p.refunded_cents,
        distinct: true,
        select: p.beneficiary_user_id
    )
  end

  defp create_beneficiary_batch(type, beneficiary_id, period_start, period_end) do
    Repo.transaction(fn ->
      case Repo.one(
             from b in PayoutBatch,
               where: ^beneficiary_batch_query(type, beneficiary_id),
               where: b.status in ["pending", "submitting", "submitted"],
               order_by: [desc: b.inserted_at],
               limit: 1,
               lock: "FOR UPDATE"
           ) do
        %PayoutBatch{} = existing ->
          existing

        nil ->
          payables =
            Repo.all(
              from p in PayableEntry,
                where: ^beneficiary_payable_query(type, beneficiary_id),
                where: p.status == "payable" and p.amount_cents > p.refunded_cents,
                order_by: [asc: p.id],
                lock: "FOR UPDATE SKIP LOCKED"
            )

          if payables == [] do
            Repo.rollback(:nothing_payable)
          else
            currencies = payables |> Enum.map(& &1.currency) |> Enum.uniq()
            if length(currencies) != 1, do: Repo.rollback(:mixed_payout_currencies)
            currency = hd(currencies)
            amount = Enum.reduce(payables, 0, &(PayableEntry.available_cents(&1) + &2))

            key =
              "payout:#{type}:#{beneficiary_id}:" <>
                Base.url_encode64(
                  :crypto.hash(:sha256, Enum.map(payables, &to_string(&1.id)) |> Enum.join(",")),
                  padding: false
                )

            beneficiary_attrs =
              case type do
                :organisation -> %{organisation_id: beneficiary_id}
                :user -> %{beneficiary_user_id: beneficiary_id}
              end

            with {:ok, batch} <-
                   %PayoutBatch{}
                   |> PayoutBatch.changeset(
                     %{
                       amount_cents: amount,
                       currency: currency,
                       idempotency_key: key,
                       period_start: period_start,
                       period_end: period_end
                     }
                     |> Map.merge(beneficiary_attrs)
                   )
                   |> Repo.insert(),
                 {:ok, _} <- insert_items(batch, payables),
                 {count, _} <- mark_payables_queued(payables) do
              if count != length(payables), do: Repo.rollback(:payout_selection_race)

              _ =
                Dunda.Audit.record(%{
                  action: "payout.batch_created",
                  resource_type: "payout_batch",
                  resource_id: batch.id,
                  metadata: %{
                    beneficiary_type: type,
                    beneficiary_id: beneficiary_id,
                    amount_cents: amount,
                    item_count: length(payables)
                  }
                })

              batch
            else
              {:error, changeset} -> Repo.rollback(changeset)
              {:error, reason} -> Repo.rollback(reason)
            end
          end
      end
    end)
    |> case do
      {:ok, batch} -> {:ok, batch}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec pending_batch_for(integer()) :: PayoutBatch.t() | nil
  def pending_batch_for(organisation_id) do
    Repo.one(
      from b in PayoutBatch,
        where:
          b.organisation_id == ^organisation_id and
            b.status in ["pending", "submitting", "submitted"],
        order_by: [desc: b.inserted_at],
        limit: 1
    )
  end

  def pending_seller_batch_for(user_id) do
    Repo.one(
      from b in PayoutBatch,
        where:
          b.beneficiary_user_id == ^user_id and
            b.status in ["pending", "submitting", "submitted"],
        order_by: [desc: b.inserted_at],
        limit: 1
    )
  end

  @doc "Claims a pending batch before the external B2C request. A submitting batch is never retried automatically."
  @spec claim_batch_submission(PayoutBatch.t()) :: {:ok, PayoutBatch.t()} | {:error, term()}
  def claim_batch_submission(%PayoutBatch{id: id}) do
    Repo.transaction(fn ->
      batch = Repo.one(from b in PayoutBatch, where: b.id == ^id, lock: "FOR UPDATE")

      cond do
        is_nil(batch) ->
          Repo.rollback(:payout_batch_not_found)

        batch.status == "pending" ->
          case batch
               |> PayoutBatch.changeset(%{status: "submitting", submission_started_at: now()})
               |> Repo.update() do
            {:ok, claimed} -> claimed
            {:error, changeset} -> Repo.rollback(changeset)
          end

        batch.status == "submitting" and stale_submission?(batch) ->
          case batch
               |> PayoutBatch.changeset(%{
                 status: "manual_review",
                 failure_reason:
                   "submission claim exceeded #{@submission_timeout_seconds}s; verify provider before retry"
               })
               |> Repo.update() do
            {:ok, reviewed} -> reviewed
            {:error, changeset} -> Repo.rollback(changeset)
          end

        batch.status in ["submitting", "submitted"] ->
          batch

        true ->
          Repo.rollback({:payout_batch_not_claimable, batch.status})
      end
    end)
    |> case do
      {:ok, batch} -> {:ok, batch}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec mark_batch_submitted(PayoutBatch.t(), String.t()) ::
          {:ok, PayoutBatch.t()} | {:error, term()}
  def mark_batch_submitted(%PayoutBatch{status: status} = batch, conversation_id)
      when status in ["pending", "submitting"] and is_binary(conversation_id) do
    batch
    |> PayoutBatch.changeset(%{
      status: "submitted",
      b2c_conversation_id: conversation_id,
      submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def mark_batch_submitted(%PayoutBatch{} = batch, _),
    do: {:error, {:invalid_payout_transition, batch.status}}

  @spec mark_batch_manual_review(PayoutBatch.t(), term()) ::
          {:ok, PayoutBatch.t()} | {:error, term()}
  def mark_batch_manual_review(%PayoutBatch{} = batch, reason) do
    case batch
         |> PayoutBatch.changeset(%{status: "manual_review", failure_reason: inspect(reason)})
         |> Repo.update() do
      {:ok, _updated} = result ->
        _ =
          Dunda.Audit.record(%{
            action: "payout.batch_manual_review",
            resource_type: "payout_batch",
            resource_id: batch.id,
            metadata: %{reason: inspect(reason)}
          })

        result

      error ->
        error
    end
  end

  @doc "Reconciles a payout batch; provider acceptance is never treated as paid."
  def reconcile_batch_provider_result(conversation_id, result_code, receipt) do
    Repo.transaction(fn ->
      batch =
        Repo.one(
          from b in PayoutBatch,
            where: b.b2c_conversation_id == ^conversation_id,
            lock: "FOR UPDATE"
        )

      cond do
        is_nil(batch) ->
          Repo.rollback(:payout_batch_not_found)

        batch.status == "paid" ->
          batch

        batch.status == "failed" ->
          batch

        to_string(result_code) == "0" ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          payable_ids =
            Repo.all(
              from i in PayoutItem,
                where: i.payout_batch_id == ^batch.id and not is_nil(i.payable_entry_id),
                select: i.payable_entry_id
            )

          payables =
            Repo.all(
              from p in PayableEntry,
                where: p.id in ^payable_ids,
                order_by: [asc: p.id],
                lock: "FOR UPDATE"
            )

          payable_state_consistent? =
            length(payable_ids) == length(payables) and
              Enum.all?(payables, &(&1.status == "queued"))

          if payable_state_consistent? do
            {item_count, _} =
              from(i in PayoutItem,
                where: i.payout_batch_id == ^batch.id and i.status == "queued",
                update: [set: [status: "paid"]]
              )
              |> Repo.update_all([])

            {payable_count, _} =
              from(p in PayableEntry,
                where: p.id in ^payable_ids and p.status == "queued",
                update: [set: [status: "paid", paid_at: ^now, updated_at: ^now]]
              )
              |> Repo.update_all([])

            if item_count != length(payable_ids) or payable_count != length(payable_ids),
              do: Repo.rollback(:payout_finalisation_race)

            case batch
                 |> PayoutBatch.changeset(%{
                   status: "paid",
                   b2c_receipt: receipt,
                   paid_at: now
                 })
                 |> Repo.update() do
              {:ok, paid} ->
                _ =
                  Dunda.Audit.record(%{
                    action: "payout.batch_paid",
                    resource_type: "payout_batch",
                    resource_id: batch.id,
                    metadata: %{result_code: result_code}
                  })

                paid

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
          else
            reason = "provider_success_conflicts_with_refunded_or_nonqueued_payable"

            {_, _} =
              from(i in PayoutItem,
                where: i.payout_batch_id == ^batch.id and i.status == "queued",
                update: [set: [status: "manual_review", failure_reason: ^reason]]
              )
              |> Repo.update_all([])

            case batch
                 |> PayoutBatch.changeset(%{
                   status: "manual_review",
                   b2c_receipt: receipt,
                   failure_reason: reason
                 })
                 |> Repo.update() do
              {:ok, reviewed} ->
                _ =
                  Dunda.Audit.record(%{
                    action: "payout.batch_manual_review",
                    resource_type: "payout_batch",
                    resource_id: batch.id,
                    metadata: %{reason: reason, result_code: result_code}
                  })

                reviewed

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
          end

        true ->
          failure_reason = "provider_result_#{result_code}"
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          payable_ids =
            Repo.all(
              from i in PayoutItem,
                where: i.payout_batch_id == ^batch.id and not is_nil(i.payable_entry_id),
                select: i.payable_entry_id
            )

          {_, _} =
            from(i in PayoutItem,
              where: i.payout_batch_id == ^batch.id,
              update: [set: [status: "failed", failure_reason: ^failure_reason]]
            )
            |> Repo.update_all([])

          {_, _} =
            from(p in PayableEntry,
              where: p.id in ^payable_ids and p.status == "queued",
              update: [set: [status: "payable", updated_at: ^now]]
            )
            |> Repo.update_all([])

          case batch
               |> PayoutBatch.changeset(%{status: "failed", failure_reason: failure_reason})
               |> Repo.update() do
            {:ok, failed} ->
              _ =
                Dunda.Audit.record(%{
                  action: "payout.batch_failed",
                  resource_type: "payout_batch",
                  resource_id: batch.id,
                  metadata: %{result_code: result_code}
                })

              failed

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, batch} -> {:ok, batch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_items(batch, payables) do
    Enum.reduce_while(payables, {:ok, []}, fn payable, {:ok, acc} ->
      case %PayoutItem{}
           |> PayoutItem.changeset(%{
             payout_batch_id: batch.id,
             payable_entry_id: payable.id,
             amount_cents: PayableEntry.available_cents(payable),
             currency: payable.currency
           })
           |> Repo.insert() do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp mark_payables_queued(payables) do
    ids = Enum.map(payables, & &1.id)

    from(p in PayableEntry, where: p.id in ^ids and p.status == "payable")
    |> Repo.update_all(set: [status: "queued", updated_at: DateTime.utc_now()])
  end

  defp beneficiary_batch_query(:organisation, id),
    do: dynamic([b], b.organisation_id == ^id)

  defp beneficiary_batch_query(:user, id),
    do: dynamic([b], b.beneficiary_user_id == ^id)

  defp beneficiary_payable_query(:organisation, id),
    do: dynamic([p], p.organisation_id == ^id)

  defp beneficiary_payable_query(:user, id),
    do: dynamic([p], p.beneficiary_user_id == ^id)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp stale_submission?(%PayoutBatch{submission_started_at: %DateTime{} = started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second) > @submission_timeout_seconds
  end

  defp stale_submission?(_), do: false

  defp put_encrypted_phone(attrs) do
    phone = Map.get(attrs, :mpesa_phone) || Map.get(attrs, "mpesa_phone")
    if is_binary(phone), do: Map.put(attrs, :mpesa_phone_encrypted, phone), else: attrs
  end
end
