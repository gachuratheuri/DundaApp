defmodule Dunda.Billing do
  @moduledoc """
  Consumer billing context built on Pesapal hosted checkout.

  Flow: `create_order/1` persists a pending `Order`, submits it to Pesapal and
  stores the returned `order_tracking_id`, returning the hosted `redirect_url`.
  Pesapal later calls our IPN; `Dunda.Workers.IpnVerificationWorker` then calls
  `confirm_order/1`, which authoritatively re-checks the status via Pesapal's
  `GetTransactionStatus` (never trusting the IPN payload alone).
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Billing.{Order, Pesapal}
  alias Dunda.Repo
  alias Dunda.Ticketing
  alias Dunda.Events
  alias Dunda.Accounts

  @doc """
  Create a pending order and submit it to Pesapal.

  Returns `{:ok, %{order: order, redirect_url: url}}` on success.
  """
  @spec create_order(map()) ::
          {:ok, %{order: Order.t(), redirect_url: String.t()}} | {:error, term()}
  def create_order(attrs) do
    if Dunda.Containment.blocked?(:billing) do
      {:error, :phase_0_containment}
    else
      with {:ok, attrs} <- authoritative_order_attrs(attrs),
           result <- create_or_reuse_order(attrs) do
        result
      end
    end
  end

  @spec get_order_by_tracking_id(String.t()) :: Order.t() | nil
  def get_order_by_tracking_id(otid), do: Repo.get_by(Order, order_tracking_id: otid)

  @doc """
  Authoritatively reconcile an order against Pesapal's transaction status.
  Idempotent — safe to call repeatedly from IPN retries.
  """
  @spec confirm_order(String.t()) :: {:ok, Order.t()} | {:error, term()}
  def confirm_order(order_tracking_id) do
    if Dunda.Containment.blocked?(:billing) do
      {:error, :phase_0_containment}
    else
      case get_order_by_tracking_id(order_tracking_id) do
      nil ->
        {:error, :order_not_found}

      order ->
        case Pesapal.transaction_status(order_tracking_id) do
          {:ok, status} ->
            new_status = classify(status)

            # Fulfilment is part of the completion invariant.  Do not mark a
            # payment complete when the authoritative ticket transaction has
            # failed; a retry can then safely re-run the same fulfillment key.
            with :ok <- ensure_order_fulfilled(order, new_status) do
              case update_status(order, %{
                     status: new_status,
                     pesapal_status: status["payment_status_description"]
                   }) do
                {:ok, updated} = result ->
                  _ = Dunda.Audit.record(%{
                    action: "billing.order_reconciled",
                    resource_type: "order",
                    resource_id: to_string(updated.id),
                    metadata: %{status: new_status}
                  })

                  result

                error -> error
              end
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc "Submits an already-committed payment intent exactly once."
  @spec submit_order_intent(Order.t()) :: {:ok, Order.t()} | {:error, term()}
  def submit_order_intent(%Order{} = order) do
    if Dunda.Containment.blocked?(:billing) do
      {:error, :phase_0_containment}
    else
      case order do
        %Order{status: "pending", order_tracking_id: nil} ->
          with {:ok, %{order_tracking_id: tracking_id, redirect_url: url}} <-
                 Pesapal.submit_order(order_payload(order, %{})),
               {:ok, updated} <- update_status(order, %{order_tracking_id: tracking_id, redirect_url: url}) do
            {:ok, updated}
          end

        %Order{order_tracking_id: tracking_id} when is_binary(tracking_id) ->
          {:ok, order}

        _ ->
          {:error, :payment_intent_not_submittable}
      end
    end
  end

  @doc "Completed-but-unpaid totals (in cents) grouped by organisation."
  @spec payable_totals() :: [{pos_integer(), non_neg_integer()}]
  def payable_totals do
    from(o in Order,
      where:
        o.kind == "primary" and o.status == "completed" and o.payout_status == "unpaid" and not is_nil(o.organisation_id),
      group_by: o.organisation_id,
      select: {o.organisation_id, sum(o.amount_cents)}
    )
    |> Repo.all()
  end

  @doc "Moves the current unpaid settlement batch to queued atomically."
  @spec queue_organisation_orders(pos_integer()) :: {non_neg_integer(), nil}
  def queue_organisation_orders(organisation_id) do
    from(o in Order,
      where:
        o.organisation_id == ^organisation_id and o.kind == "primary" and o.status == "completed" and
          o.payout_status == "unpaid"
    )
    |> Repo.update_all(set: [payout_status: "queued", updated_at: DateTime.utc_now()])
  end

  @doc "Returns the immutable order ids in the currently queued payout batch."
  @spec queued_order_ids(pos_integer()) :: [integer()]
  def queued_order_ids(organisation_id) do
    from(o in Order,
      where: o.organisation_id == ^organisation_id and o.kind == "primary" and o.status == "completed" and o.payout_status == "queued",
      order_by: [asc: o.id],
      select: o.id
    )
    |> Repo.all()
  end

  @doc "Returns a failed/unsubmitted payout batch to the unpaid state."
  @spec unqueue_organisation_orders(pos_integer()) :: {non_neg_integer(), nil}
  def unqueue_organisation_orders(organisation_id) do
    from(o in Order,
      where: o.organisation_id == ^organisation_id and o.kind == "primary" and o.status == "completed" and o.payout_status == "queued"
    )
    |> Repo.update_all(set: [payout_status: "unpaid", updated_at: DateTime.utc_now()])
  end

  @doc "Mark an organisation's completed+unpaid orders as `paid` after a B2C payout."
  @spec mark_organisation_paid(pos_integer()) :: {non_neg_integer(), nil} | {:error, atom()}
  def mark_organisation_paid(organisation_id) do
    if Dunda.Containment.blocked?(:payouts) do
      {:error, :phase_0_containment}
    else
      from(o in Order,
        where:
          o.organisation_id == ^organisation_id and o.kind == "primary" and o.status == "completed" and
            o.payout_status in ["queued", "unpaid"]
      )
      |> Repo.update_all(set: [payout_status: "paid", updated_at: DateTime.utc_now()])
    end
  end

  # ── Internals ────────────────────────────────────────────────────────────────

  defp insert_order(attrs) do
    %Order{}
    |> Order.create_changeset(attrs)
    |> Repo.insert()
  end

  defp create_or_reuse_order(attrs) do
    case Repo.get_by(Order, user_id: attrs.user_id, idempotency_key: attrs.idempotency_key) do
      %Order{order_tracking_id: tracking_id, redirect_url: url} = order
      when is_binary(tracking_id) and is_binary(url) ->
        {:ok, %{order: order, redirect_url: url}}

      %Order{} ->
        {:error, :idempotency_incomplete}

      nil ->
        with {:ok, order} <- insert_order(attrs),
             {:ok, %{order_tracking_id: otid, redirect_url: url}} <-
               Pesapal.submit_order(order_payload(order, attrs)),
             {:ok, order} <- update_status(order, %{order_tracking_id: otid, redirect_url: url}) do
          _ = Dunda.Audit.record(%{
            actor_user_id: attrs.user_id,
            action: "billing.order_created",
            resource_type: "order",
            resource_id: to_string(order.id),
            metadata: %{amount_cents: order.amount_cents, quantity: order.quantity}
          })

          {:ok, %{order: order, redirect_url: url}}
        else
          {:error, %Ecto.Changeset{} = changeset} ->
            if idempotency_conflict?(changeset) do
              case Repo.get_by(Order, user_id: attrs.user_id, idempotency_key: attrs.idempotency_key) do
                %Order{order_tracking_id: tracking_id, redirect_url: url} = existing
                when is_binary(tracking_id) and is_binary(url) ->
                  {:ok, %{order: existing, redirect_url: url}}

                _ -> {:error, :idempotency_incomplete}
              end
            else
              {:error, changeset}
            end

          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp authoritative_order_attrs(attrs) do
    event_id = Map.get(attrs, :event_id) || Map.get(attrs, "event_id")
    tier_id = Map.get(attrs, :ticket_tier_id) || Map.get(attrs, :tier_id)
    user_id = Map.get(attrs, :user_id) || Map.get(attrs, "user_id")
    quantity = parse_positive_integer(Map.get(attrs, :quantity) || Map.get(attrs, "quantity"))
    idempotency_key = Map.get(attrs, :idempotency_key) || Map.get(attrs, "idempotency_key")

    with {:ok, event_id} <- parse_id(event_id),
         {:ok, user_id} <- parse_id(user_id),
         {:ok, quantity} <- quantity,
         {:ok, tier_id} <- parse_optional_id(tier_id),
         true <- is_binary(idempotency_key) and byte_size(idempotency_key) in 16..200,
         %Events.Event{} = event <- Repo.get(Events.Event, event_id),
         :ok <- validate_event(event),
         {:ok, tier} <- resolve_tier(event.id, tier_id),
         :ok <- validate_tier(tier, quantity) do
      {amount_cents, tier_id} =
        case tier do
          %Dunda.Ticketing.TicketTier{} = t -> {t.price_cents * quantity, t.id}
          nil -> {event.price_cents * quantity, nil}
        end

      {:ok,
       %{
         merchant_reference: "dunda_" <> Base.url_encode64(:crypto.hash(:sha256, idempotency_key), padding: false),
         idempotency_key: idempotency_key,
         amount_cents: amount_cents,
         currency: event.currency || "KES",
         quantity: quantity,
         phone: Map.get(attrs, :phone) || Map.get(attrs, "phone"),
         email: Map.get(attrs, :email) || Map.get(attrs, "email"),
         event_id: event.id,
         ticket_tier_id: tier_id,
         organisation_id: event.organisation_id,
         user_id: user_id
       }}
    else
      false -> {:error, :idempotency_key_required}
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_order}
    end
  end

  defp validate_event(%Events.Event{status: "published"}), do: :ok
  defp validate_event(_), do: {:error, :event_not_on_sale}

  defp resolve_tier(_event_id, nil), do: {:ok, nil}
  defp resolve_tier(event_id, tier_id) do
    case Ticketing.get_event_tier(event_id, tier_id) do
      nil -> {:error, :not_found}
      tier -> {:ok, tier}
    end
  end

  defp validate_tier(nil, _quantity), do: :ok
  defp validate_tier(%{status: "on_sale", max_per_order: max}, quantity) when quantity <= max, do: :ok
  defp validate_tier(%{status: "on_sale"}, _), do: {:error, :max_per_order_exceeded}
  defp validate_tier(_, _), do: {:error, :tier_not_on_sale}

  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_id}
    end
  end
  defp parse_id(_), do: {:error, :invalid_id}

  defp parse_optional_id(nil), do: {:ok, nil}
  defp parse_optional_id(value), do: parse_id(value)

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_quantity}
    end
  end
  defp parse_positive_integer(_), do: {:error, :invalid_quantity}

  defp update_status(order, attrs) do
    order
    |> Order.status_changeset(attrs)
    |> Repo.update()
  end

  defp idempotency_conflict?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:idempotency_key, {_message, _opts}} -> true
      {field, {_message, _opts}} when field in [:merchant_reference, :user_id] -> true
      _ -> false
    end)
  end

  # A resale order is not fulfilled merely because its payment row says
  # completed: the entitlement transfer must also be observed. Re-run the
  # idempotent transfer check on duplicate provider callbacks.
  defp ensure_order_fulfilled(%Order{status: "completed", kind: "resale"} = order, _new_status) do
    case Dunda.Market.complete_resale_purchase(order.id) do
      {:ok, _listing} -> :ok
      {:error, reason} ->
        _ = Dunda.Billing.Refunds.request_for_transfer_failure(order.id, reason)
        {:error, {:resale_transfer_refund_pending, reason}}
    end
  end

  defp ensure_order_fulfilled(%Order{status: "completed"}, _new_status), do: :ok

  defp ensure_order_fulfilled(%Order{kind: "resale"} = order, new_status)
       when new_status in ["failed", "invalid"] do
    case Dunda.Market.cancel_resale_payment_intent(order.id) do
      {:ok, _cancelled} -> :ok
      {:error, :order_not_cancellable} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_order_fulfilled(_order, new_status) when new_status != "completed", do: :ok

  defp ensure_order_fulfilled(%Order{kind: "resale"} = order, "completed") do
    case Dunda.Market.complete_resale_purchase(order.id, confirmed?: true) do
      {:ok, _listing} -> :ok
      {:error, reason} ->
        _ = Dunda.Billing.Refunds.request_for_transfer_failure(order.id, reason)
        {:error, {:resale_transfer_refund_pending, reason}}
    end
  end

  defp ensure_order_fulfilled(%Order{} = order, "completed") do
    with %Accounts.User{} = user <- Accounts.get_user(order.user_id),
         # Fulfilment must read the write-primary; a lagging replica could
         # otherwise make a settled payment appear unfulfillable.
         %Events.Event{} = event <- Repo.get(Events.Event, order.event_id),
         tier <- if(order.ticket_tier_id, do: Ticketing.get_tier(order.ticket_tier_id)),
         result <- Ticketing.issue_tickets(order, event, user, order.quantity, tier: tier) do
      case result do
        {:ok, _tickets} -> :ok
        {:error, reason} ->
          if Ticketing.fulfilled_order?(order.id, order.quantity), do: :ok, else: {:error, reason}
      end
    else
      nil -> {:error, :order_identity_or_event_missing}
      _ -> {:error, :order_identity_or_event_missing}
    end
  end

  defp order_payload(order, attrs) do
    %{
      merchant_reference: order.merchant_reference,
      amount_cents: order.amount_cents,
      currency: order.currency,
      phone: order.phone,
      email: Map.get(attrs, :email),
      description: Map.get(attrs, :description, "Dunda ticket purchase")
    }
  end

  # Pesapal status_code 1 == COMPLETED; 2 == FAILED; 0 == INVALID; 3 == REVERSED.
  defp classify(%{"status_code" => code}) when code in [1, "1"], do: "completed"
  defp classify(%{"status_code" => code}) when code in [2, "2"], do: "failed"
  defp classify(%{"payment_status_description" => "Completed"}), do: "completed"
  defp classify(%{"payment_status_description" => "Failed"}), do: "failed"
  defp classify(_), do: "pending"

  defp generate_reference do
    "dunda_" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false))
  end
end
