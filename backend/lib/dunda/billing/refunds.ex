defmodule Dunda.Billing.Refunds do
  @moduledoc """
  Durable refund intents and monotonic provider reconciliation.

  Ticket revocation is committed before any eventual inventory restock. The
  current release keeps restocking deferred to reconciliation because Redis is
  not the authoritative inventory ledger; this prevents a refund from
  resurrecting sold capacity.
  """

  import Ecto.Query, only: [from: 2]

  alias Dunda.Billing.{Order, Refund, RefundProviderEvent}
  alias Dunda.Events.Event
  alias Dunda.Repo
  alias Dunda.Ticketing.Ticket

  @spec request(map()) :: {:ok, Refund.t()} | {:error, term()}
  def request(attrs) when is_map(attrs) do
    order_id = Map.get(attrs, :order_id) || Map.get(attrs, "order_id")
    idempotency_key = Map.get(attrs, :idempotency_key) || Map.get(attrs, "idempotency_key")

    Repo.transaction(fn ->
      case Repo.get_by(Refund, idempotency_key: idempotency_key) do
        %Refund{} = existing -> existing
        nil -> request_locked(order_id, attrs)
      end
    end)
    |> unwrap_transaction()
  end

  @spec mark_submitted(Refund.t(), String.t()) :: {:ok, Refund.t()} | {:error, term()}
  def mark_submitted(%Refund{status: "pending"} = refund, provider_reference)
      when is_binary(provider_reference) do
    refund
    |> Refund.changeset(%{
      status: "submitted",
      provider_reference: provider_reference,
      submitted_at: now()
    })
    |> Repo.update()
  end

  def mark_submitted(%Refund{} = refund, _),
    do: {:error, {:invalid_refund_transition, refund.status}}

  @doc "Reconciles a provider result exactly once and revokes affected tickets."
  @spec reconcile_provider_result(String.t(), boolean(), String.t() | nil) ::
          {:ok, Refund.t()} | {:error, term()}
  def reconcile_provider_result(provider_reference, success?, failure_reason \\ nil) do
    Repo.transaction(fn ->
      refund =
        Repo.one(
          from r in Refund, where: r.provider_reference == ^provider_reference, lock: "FOR UPDATE"
        )

      cond do
        is_nil(refund) ->
          Repo.rollback(:refund_not_found)

        refund.status == "succeeded" ->
          refund

        refund.status == "failed" ->
          refund

        refund.status not in ["submitted", "pending", "manual_review"] ->
          Repo.rollback({:invalid_refund_transition, refund.status})

        success? ->
          complete_refund_locked(refund)

        true ->
          fail_refund_locked(refund, failure_reason || "provider_failure")
      end
    end)
    |> unwrap_transaction()
  end

  @doc "Persists one bounded provider event before applying its outcome."
  def record_provider_event(refund_id, provider_event_id, payload, outcome)
      when is_map(payload) do
    attrs = %{
      refund_id: refund_id,
      provider_event_id: provider_event_id,
      payload: sanitize_payload(payload),
      outcome: outcome,
      received_at: now()
    }

    case %RefundProviderEvent{}
         |> RefundProviderEvent.changeset(attrs)
         |> Repo.insert(on_conflict: :nothing, conflict_target: :provider_event_id) do
      {:ok, %RefundProviderEvent{id: nil}} ->
        Repo.get_by(RefundProviderEvent, provider_event_id: provider_event_id)

      result ->
        result
    end
  end

  @doc "Requests a full refund for a completed order."
  def request_full(order_id, requested_by_id, reason, idempotency_key) do
    request(%{
      order_id: order_id,
      requested_by_id: requested_by_id,
      reason: reason,
      idempotency_key: idempotency_key,
      amount_cents: order_amount(order_id)
    })
  end

  @doc "Creates the one-shot refund intent used when a confirmed resale cannot transfer."
  @spec request_for_transfer_failure(integer(), term()) :: {:ok, Refund.t()} | {:error, term()}
  def request_for_transfer_failure(order_id, reason) do
    key = "resale-transfer-failure:#{order_id}"

    Repo.transaction(fn ->
      case Repo.get_by(Refund, idempotency_key: key) do
        %Refund{} = existing ->
          existing

        nil ->
          order = Repo.one(from o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")

          if is_nil(order) do
            Repo.rollback(:order_not_found)
          else
            attrs = %{
              order_id: order.id,
              amount_cents: order.amount_cents,
              currency: order.currency,
              status: "pending",
              reason: "resale transfer failure: #{String.slice(inspect(reason), 0, 420)}",
              idempotency_key: key
            }

            with {:ok, refund} <- %Refund{} |> Refund.changeset(attrs) |> Repo.insert(),
                 {:ok, _manual} <-
                   order
                   |> Order.status_changeset(%{status: "manual_review", refund_status: "pending"})
                   |> Repo.update() do
              _ =
                Dunda.Audit.record(%{
                  action: "resale.transfer_refund_requested",
                  resource_type: "refund",
                  resource_id: refund.id,
                  metadata: %{order_id: order.id, reason: inspect(reason)}
                })

              refund
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end
      end
    end)
    |> unwrap_transaction()
  end

  @doc "Creates an intent for only the remaining refundable amount."
  def request_remaining(order_id, requested_by_id, reason, idempotency_key) do
    amount = order_amount(order_id) - refunded_or_pending_amount(order_id)

    request(%{
      order_id: order_id,
      requested_by_id: requested_by_id,
      reason: reason,
      idempotency_key: idempotency_key,
      amount_cents: amount,
      allow_remaining: true
    })
  end

  @doc "Marks an event cancelled and enqueues a resumable refund sweep."
  @spec cancel_event(integer(), integer() | nil, String.t()) :: {:ok, term()} | {:error, term()}
  def cancel_event(event_id, actor_id, reason) when is_binary(reason) do
    Repo.transaction(fn ->
      event = Repo.one(from e in Event, where: e.id == ^event_id, lock: "FOR UPDATE")

      if is_nil(event) do
        Repo.rollback(:event_not_found)
      else
        case event |> Event.changeset(%{status: "cancelled"}) |> Repo.update() do
          {:ok, cancelled} ->
            job =
              Dunda.Workers.EventCancellationWorker.new(%{
                "event_id" => event.id,
                "cursor" => 0,
                "actor_id" => actor_id,
                "reason" => reason
              })

            case Oban.insert(job) do
              {:ok, inserted} ->
                _ =
                  Dunda.Audit.record(%{
                    actor_user_id: actor_id,
                    action: "event.cancellation_started",
                    resource_type: "event",
                    resource_id: to_string(event.id),
                    metadata: %{job_id: inserted.id, reason: reason}
                  })

                cancelled

              {:error, error} ->
                Repo.rollback(error)
            end

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end
    end)
    |> unwrap_transaction()
  end

  defp request_locked(order_id, attrs) do
    order = Repo.one(from o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")
    amount = Map.get(attrs, :amount_cents) || Map.get(attrs, "amount_cents")
    ticket_id = Map.get(attrs, :ticket_id) || Map.get(attrs, "ticket_id")

    cond do
      is_nil(order) ->
        Repo.rollback(:order_not_found)

      order.status not in ["completed", "partially_refunded"] ->
        Repo.rollback(:order_not_refundable)

      not is_integer(amount) or amount <= 0 ->
        Repo.rollback(:invalid_refund_amount)

      amount + refunded_or_pending_amount(order.id) > order.amount_cents ->
        Repo.rollback(:refund_exceeds_payment)

      amount < order.amount_cents and is_nil(ticket_id) and not truthy?(attrs, :allow_remaining) ->
        Repo.rollback(:ticket_required_for_partial_refund)

      not is_nil(ticket_id) and
          not Repo.exists?(
            from t in Ticket, where: t.id == ^ticket_id and t.order_id == ^order.id
          ) ->
        Repo.rollback(:ticket_not_in_order)

      has_scanned_ticket?(order.id) ->
        Repo.rollback(:manual_review_required)

      true ->
        refund_attrs =
          attrs
          |> Map.put(:order_id, order.id)
          |> Map.put(:amount_cents, amount)
          |> Map.put_new(:currency, order.currency)
          |> Map.put_new(:status, "pending")

        case %Refund{} |> Refund.changeset(refund_attrs) |> Repo.insert() do
          {:ok, refund} ->
            update_order_refund_state(order, "pending")

            _ =
              Dunda.Audit.record(%{
                action: "refund.requested",
                resource_type: "refund",
                resource_id: refund.id,
                metadata: %{order_id: order.id, amount_cents: amount}
              })

            refund

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
    end
  end

  defp complete_refund_locked(refund) do
    order = Repo.one(from o in Order, where: o.id == ^refund.order_id, lock: "FOR UPDATE")
    now = now()

    tickets =
      if refund.ticket_id do
        Repo.all(
          from t in Ticket,
            where:
              t.id == ^refund.ticket_id and t.order_id == ^order.id and
                t.status in ["valid", "scanned"],
            lock: "FOR UPDATE"
        )
      else
        Repo.all(
          from t in Ticket,
            where: t.order_id == ^order.id and t.status in ["valid", "scanned"],
            lock: "FOR UPDATE"
        )
      end

    Enum.each(tickets, fn ticket ->
      case ticket
           |> Ticket.changeset(%{
             status: "refunded",
             revoked_at: now,
             revocation_reason: "payment_refund"
           })
           |> Repo.update() do
        {:ok, _} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)

    case Dunda.Ledger.record_transfer(%{
           from_account: "customer:#{order.user_id}:cash",
           to_account: "refund:#{order.id}:payable",
           amount_cents: refund.amount_cents,
           reference: "refund:#{refund.id}:settlement"
         }) do
      {:ok, _entry} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    {:ok, updated_refund} =
      refund |> Refund.changeset(%{status: "succeeded", completed_at: now}) |> Repo.update()

    total = refunded_or_pending_amount(order.id)
    order_status = if total >= order.amount_cents, do: "refunded", else: "partially_refunded"
    update_order_refund_state(order, order_status, total)

    _ =
      Dunda.Audit.record(%{
        action: "refund.succeeded",
        resource_type: "refund",
        resource_id: refund.id,
        metadata: %{
          order_id: order.id,
          inventory_restock: "deferred_to_authoritative_reconciliation"
        }
      })

    updated_refund
  end

  defp fail_refund_locked(refund, reason) do
    updated =
      refund
      |> Refund.changeset(%{status: "failed", failure_reason: reason, completed_at: now()})
      |> Repo.update()

    case updated do
      {:ok, value} ->
        order = Repo.get(Order, refund.order_id)
        if order, do: update_order_refund_state(order, "failed")

        _ =
          Dunda.Audit.record(%{
            action: "refund.failed",
            resource_type: "refund",
            resource_id: refund.id,
            metadata: %{reason: reason}
          })

        value

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp update_order_refund_state(order, status, total \\ nil) do
    attrs = %{
      refund_status: status,
      refunded_amount_cents: total || order.refunded_amount_cents || 0
    }

    attrs = if status == "refunded", do: Map.put(attrs, :refunded_at, now()), else: attrs

    case order |> Order.status_changeset(attrs) |> Repo.update() do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp refunded_or_pending_amount(order_id) do
    Repo.one(
      from r in Refund,
        where: r.order_id == ^order_id and r.status in ["pending", "submitted", "succeeded"],
        select: coalesce(sum(r.amount_cents), 0)
    )
  end

  defp has_scanned_ticket?(order_id),
    do: Repo.exists?(from t in Ticket, where: t.order_id == ^order_id and t.status == "scanned")

  defp order_amount(order_id) do
    case Repo.get(Order, order_id) do
      %Order{amount_cents: amount} -> amount
      _ -> 0
    end
  end

  defp sanitize_payload(payload) do
    payload
    |> Enum.reject(fn {key, _} ->
      String.contains?(String.downcase(to_string(key)), [
        "token",
        "secret",
        "password",
        "authorization"
      ])
    end)
    |> Enum.take(100)
    |> Map.new(fn {key, value} ->
      {to_string(key),
       if(is_binary(value), do: String.slice(value, 0, 2_000), else: inspect(value, limit: 20))}
    end)
  end

  defp truthy?(attrs, key),
    do: Map.get(attrs, key) == true or Map.get(attrs, to_string(key)) == true

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
