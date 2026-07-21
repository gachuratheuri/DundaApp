defmodule Dunda.Organisations.Payouts do
  @moduledoc "Idempotent payout-attempt persistence; provider acceptance is not settlement."

  import Ecto.Query, only: [from: 2]

  alias Dunda.Organisations.Payout
  alias Dunda.Organisations.{PayoutBatch, PayoutItem}
  alias Dunda.Billing.Order
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

  @doc "Selects eligible orders once and attaches them to one payout batch."
  @spec create_batch(integer(), DateTime.t(), DateTime.t()) ::
          {:ok, PayoutBatch.t()} | {:error, term()}
  def create_batch(organisation_id, period_start, period_end) do
    Repo.transaction(fn ->
      case Repo.one(
             from b in PayoutBatch,
               where:
                 b.organisation_id == ^organisation_id and
                   b.status in ["pending", "submitting", "submitted"],
               order_by: [desc: b.inserted_at],
               limit: 1,
               lock: "FOR UPDATE"
           ) do
        %PayoutBatch{} = existing ->
          existing

        nil ->
          orders =
            Repo.all(
              from o in Order,
                where:
                  o.organisation_id == ^organisation_id and o.kind == "primary" and
                    o.status in ["completed", "partially_refunded"] and
                    o.payout_status == "unpaid",
                order_by: [asc: o.id],
                lock: "FOR UPDATE SKIP LOCKED"
            )
            |> Enum.filter(&(net_amount(&1) > 0))

          if orders == [] do
            Repo.rollback(:nothing_payable)
          else
            amount = Enum.reduce(orders, 0, &(net_amount(&1) + &2))

            key =
              "payout:#{organisation_id}:" <>
                Base.url_encode64(
                  :crypto.hash(:sha256, Enum.map(orders, &to_string(&1.id)) |> Enum.join(",")),
                  padding: false
                )

            with {:ok, batch} <-
                   %PayoutBatch{}
                   |> PayoutBatch.changeset(%{
                     organisation_id: organisation_id,
                     amount_cents: amount,
                     currency: "KES",
                     idempotency_key: key,
                     period_start: period_start,
                     period_end: period_end
                   })
                   |> Repo.insert(),
                 {:ok, _} <- insert_items(batch, orders),
                 {count, _} <- mark_orders_queued(orders) do
              if count != length(orders), do: Repo.rollback(:payout_selection_race)

              _ =
                Dunda.Audit.record(%{
                  action: "payout.batch_created",
                  resource_type: "payout_batch",
                  resource_id: batch.id,
                  metadata: %{
                    organisation_id: organisation_id,
                    amount_cents: amount,
                    item_count: length(orders)
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

          item_order_ids =
            Repo.all(
              from i in PayoutItem, where: i.payout_batch_id == ^batch.id, select: i.order_id
            )

          {_, _} =
            from(i in PayoutItem,
              where: i.payout_batch_id == ^batch.id,
              update: [set: [status: "paid"]]
            )
            |> Repo.update_all([])

          {_, _} =
            from(o in Order,
              where: o.id in ^item_order_ids,
              update: [set: [payout_status: "paid", updated_at: ^now]]
            )
            |> Repo.update_all([])

          case batch
               |> PayoutBatch.changeset(%{status: "paid", b2c_receipt: receipt, paid_at: now})
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

        true ->
          failure_reason = "provider_result_#{result_code}"
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          item_order_ids =
            Repo.all(
              from i in PayoutItem, where: i.payout_batch_id == ^batch.id, select: i.order_id
            )

          {_, _} =
            from(i in PayoutItem,
              where: i.payout_batch_id == ^batch.id,
              update: [set: [status: "failed", failure_reason: ^failure_reason]]
            )
            |> Repo.update_all([])

          {_, _} =
            from(o in Order,
              where: o.id in ^item_order_ids,
              update: [set: [payout_status: "unpaid", updated_at: ^now]]
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

  defp insert_items(batch, orders) do
    Enum.reduce_while(orders, {:ok, []}, fn order, {:ok, acc} ->
      case %PayoutItem{}
           |> PayoutItem.changeset(%{
             payout_batch_id: batch.id,
             order_id: order.id,
             amount_cents: net_amount(order),
             currency: order.currency
           })
           |> Repo.insert() do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp mark_orders_queued(orders) do
    ids = Enum.map(orders, & &1.id)

    from(o in Order, where: o.id in ^ids and o.payout_status == "unpaid")
    |> Repo.update_all(set: [payout_status: "queued", updated_at: DateTime.utc_now()])
  end

  defp net_amount(%Order{amount_cents: amount, refunded_amount_cents: refunded}) do
    max(amount - (refunded || 0), 0)
  end

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
