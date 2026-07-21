defmodule Dunda.Checkout do
  @moduledoc "Unified quote, reservation, payment-intent and fulfilment aggregate."
  import Ecto.Query, only: [from: 2]

  alias Dunda.Checkout.{
    Quote,
    QuoteSigner,
    PaymentIntent,
    PaymentAttempt,
    PaymentIntentTransition,
    ProviderEvent,
    InventoryPool,
    InventoryReservation,
    PaymentLineItem,
    TicketBatch,
    OutboxEvent
  }

  alias Dunda.{Events, Repo}
  alias Dunda.Ticketing.Ticket

  @quote_ttl 600
  @reservation_ttl 900
  @max_quantity 100

  def create_quote(user_id, attrs) when is_map(attrs) do
    if Dunda.Containment.blocked?(:checkout),
      do: {:error, :phase_0_containment},
      else: create_quote_open(user_id, attrs)
  end

  defp create_quote_open(user_id, attrs) do
    event_id = parse_id(attrs[:event_id] || attrs["event_id"])
    quantity = parse_positive(attrs[:quantity] || attrs["quantity"])

    with {:ok, tier_id} <- parse_optional_id(attrs[:tier_id] || attrs["tier_id"]),
         true <- is_integer(event_id),
         true <- is_integer(quantity) and quantity > 0 and quantity <= @max_quantity,
         event when not is_nil(event) <- Repo.get(Events.Event, event_id),
         :ok <- event_on_sale(event),
         {:ok, tier} <- resolve_tier(event.id, tier_id),
         :ok <- tier_on_sale(tier, quantity) do
      unit_price = if tier, do: tier.price_cents, else: event.price_cents

      expires_at =
        DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), @quote_ttl, :second)

      attrs = %{
        user_id: user_id,
        event_id: event.id,
        ticket_tier_id: tier && tier.id,
        quantity: quantity,
        unit_price_cents: unit_price,
        fee_cents: 0,
        total_cents: unit_price * quantity,
        currency: event.currency || "KES",
        price_version: price_version(event),
        expires_at: expires_at
      }

      signature = QuoteSigner.sign(attrs)

      case %Quote{} |> Quote.changeset(Map.put(attrs, :signature, signature)) |> Repo.insert() do
        {:ok, quote} -> {:ok, quote}
        {:error, changeset} -> {:error, changeset}
      end
    else
      false -> {:error, :bad_quantity}
      nil -> {:error, :event_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_quote}
    end
  end

  def create_payment_intent(user_id, attrs) when is_map(attrs) do
    if Dunda.Containment.blocked?(:checkout) do
      {:error, :phase_0_containment}
    else
      started_at = System.monotonic_time(:microsecond)
      result = create_intent_transaction(user_id, attrs)

      Dunda.Observability.observe_operation(
        :inventory_reservation,
        System.monotonic_time(:microsecond) - started_at
      )

      result
    end
  end

  def get_payment_intent_for_user(id, user_id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get_by(PaymentIntent, id: uuid, user_id: user_id)
      :error -> nil
    end
  end

  def get_payment_intent(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(PaymentIntent, uuid)
      :error -> nil
    end
  end

  @doc "Durably creates a provider-attempt record before any external request."
  def prepare_provider_submission(intent_id) do
    Repo.transaction(fn ->
      intent =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent_id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      cond do
        intent.state in ["provider_pending", "confirmed", "confirmed_late", "fulfilled"] ->
          {:already_submitted, intent}

        intent.state != "inventory_reserved" ->
          Repo.rollback({:invalid_submission_state, intent.state})

        true ->
          attempt_key = "payment-attempt:#{intent.id}:#{intent.version}"

          attempt =
            Repo.insert!(
              %PaymentAttempt{}
              |> PaymentAttempt.changeset(%{
                payment_intent_id: intent.id,
                provider: provider(),
                attempt_key: attempt_key,
                status: "pending",
                request_payload: %{amount_cents: intent.amount_cents, currency: intent.currency}
              }),
              on_conflict: :nothing,
              conflict_target: :attempt_key
            )

          attempt =
            if attempt.id,
              do: attempt,
              else: Repo.get_by!(PaymentAttempt, attempt_key: attempt_key)

          updated =
            Repo.update!(
              PaymentIntent.changeset(intent, %{
                state: "provider_submission_pending",
                provider: provider(),
                version: intent.version + 1
              })
            )

          record_transition!(
            updated,
            intent.state,
            "provider_submission_pending",
            intent.version,
            "provider_submission_started",
            %{attempt_id: attempt.id}
          )

          {:submit, updated, attempt}
      end
    end)
    |> unwrap()
  end

  def complete_provider_submission(intent_id, attempt_id, attrs) do
    Repo.transaction(fn ->
      intent =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent_id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      attempt =
        Repo.one(
          from a in PaymentAttempt,
            where: a.id == ^attempt_id and a.payment_intent_id == ^intent_id,
            lock: "FOR UPDATE"
        ) || Repo.rollback(:payment_attempt_not_found)

      case attrs[:result] || attrs["result"] do
        :ok ->
          checkout_id = attrs[:provider_checkout_id] || attrs["provider_checkout_id"]
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          Repo.update!(
            PaymentAttempt.changeset(attempt, %{
              status: "submitted",
              provider_checkout_id: checkout_id,
              response_payload: Map.get(attrs, :response_payload, %{}),
              submitted_at: now
            })
          )

          updated =
            Repo.update!(
              PaymentIntent.changeset(intent, %{
                state: "provider_pending",
                provider_checkout_id: checkout_id,
                redirect_url: attrs[:redirect_url] || attrs["redirect_url"],
                version: intent.version + 1
              })
            )

          record_transition!(
            updated,
            intent.state,
            "provider_pending",
            intent.version,
            "provider_submitted",
            %{attempt_id: attempt.id}
          )

          enqueue_outbox!(
            "payment-intent:#{intent.id}:reconciliation",
            "payment_reconciliation_requested",
            "payment_intent",
            intent.id,
            %{payment_intent_id: intent.id}
          )

          updated

        :failed ->
          reason = attrs[:reason] || attrs["reason"] || "provider_rejected"

          Repo.update!(
            PaymentAttempt.changeset(attempt, %{
              status: "failed",
              failure_reason: to_string(reason),
              completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
          )

          release_reservation!(
            intent,
            Repo.one!(
              from r in InventoryReservation,
                where: r.payment_intent_id == ^intent.id and r.status == "active",
                lock: "FOR UPDATE"
            ),
            reason
          )

        :ambiguous ->
          reason = attrs[:reason] || attrs["reason"] || "provider_submission_ambiguous"

          Repo.update!(
            PaymentAttempt.changeset(attempt, %{
              status: "manual_review",
              failure_reason: to_string(reason)
            })
          )

          updated =
            Repo.update!(
              PaymentIntent.changeset(intent, %{
                state: "manual_review",
                manual_review_reason: to_string(reason),
                version: intent.version + 1
              })
            )

          record_transition!(
            updated,
            intent.state,
            "manual_review",
            intent.version,
            "provider_submission_ambiguous",
            %{}
          )

          updated
      end
    end)
    |> unwrap()
  end

  defp create_intent_transaction(user_id, attrs) do
    quote_id = cast_uuid(attrs[:quote_id] || attrs["quote_id"])
    key = attrs[:idempotency_key] || attrs["idempotency_key"]
    phone = normalise_phone(attrs[:phone] || attrs["phone"])

    Repo.transaction(fn ->
      existing =
        Repo.one(
          from p in PaymentIntent,
            where: p.user_id == ^user_id and p.idempotency_key == ^key,
            lock: "FOR UPDATE"
        )

      cond do
        existing && existing.quote_id == quote_id ->
          existing

        existing ->
          Repo.rollback(:idempotency_conflict)

        not is_binary(key) or byte_size(key) not in 16..200 ->
          Repo.rollback(:idempotency_key_required)

        is_nil(phone) ->
          Repo.rollback(:bad_phone)

        true ->
          reserve_from_quote!(user_id, quote_id, key, phone)
      end
    end)
    |> unwrap()
  end

  defp reserve_from_quote!(user_id, quote_id, key, phone) do
    quote =
      Repo.one(
        from q in Quote, where: q.id == ^quote_id and q.user_id == ^user_id, lock: "FOR UPDATE"
      ) || Repo.rollback(:quote_not_found)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    cond do
      quote.status != "active" ->
        Repo.rollback(:quote_not_active)

      DateTime.compare(quote.expires_at, now) != :gt ->
        Repo.rollback(:quote_expired)

      not QuoteSigner.valid?(
        Map.from_struct(quote) |> Map.merge(%{user_id: user_id}),
        quote.signature
      ) ->
        Repo.rollback(:quote_tampered)

      true ->
        pool = pool_for_quote!(quote)

        {count, _} =
          Repo.update_all(
            from(p in InventoryPool,
              where: p.id == ^pool.id and p.capacity - p.reserved - p.sold >= ^quote.quantity
            ),
            inc: [reserved: quote.quantity, version: 1]
          )

        if count != 1, do: Repo.rollback(:inventory_unavailable)
        enqueue_inventory_projection!(pool.id, pool.version + 1)

        intent =
          Repo.insert!(
            %PaymentIntent{}
            |> PaymentIntent.changeset(%{
              quote_id: quote.id,
              user_id: user_id,
              event_id: quote.event_id,
              ticket_tier_id: quote.ticket_tier_id,
              quantity: quote.quantity,
              amount_cents: quote.total_cents,
              currency: quote.currency,
              phone_encrypted: phone,
              idempotency_key: key,
              state: "inventory_reserved",
              expires_at: DateTime.add(now, @reservation_ttl, :second),
              version: 1
            })
          )

        record_transition!(intent, "created", "inventory_reserved", 1, "reservation_created", %{})

        line =
          Repo.insert!(
            %PaymentLineItem{}
            |> PaymentLineItem.changeset(%{
              payment_intent_id: intent.id,
              line_number: 1,
              ticket_tier_id: quote.ticket_tier_id,
              quantity: quote.quantity,
              unit_price_cents: quote.unit_price_cents,
              currency: quote.currency,
              price_version: quote.price_version
            })
          )

        Repo.insert!(
          %InventoryReservation{}
          |> InventoryReservation.changeset(%{
            payment_intent_id: intent.id,
            inventory_pool_id: pool.id,
            quantity: quote.quantity,
            status: "active",
            expires_at: DateTime.add(now, @reservation_ttl, :second)
          })
        )

        Repo.update!(Quote.changeset(quote, %{status: "consumed", consumed_at: now}))

        enqueue_outbox!(
          "payment-intent:#{intent.id}:submission",
          "payment_submission_requested",
          "payment_intent",
          intent.id,
          %{payment_intent_id: intent.id, provider: provider()}
        )

        _ = line
        intent
    end
  end

  def advance_state(%PaymentIntent{} = intent, state, attrs \\ %{}) do
    Repo.transaction(fn ->
      current =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent.id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      changes = Map.merge(attrs, %{state: state, version: current.version + 1})

      case Repo.update(PaymentIntent.changeset(current, changes)) do
        {:ok, updated} ->
          record_transition!(
            updated,
            current.state,
            state,
            current.version,
            Map.get(attrs, :reason, "state_advanced"),
            Map.get(attrs, :metadata, %{})
          )

          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> unwrap()
  end

  def record_provider_event(attrs) do
    safe = Map.put(attrs, :payload, sanitize_payload(Map.get(attrs, :payload, %{})))
    provider = Map.get(safe, :provider) || Map.get(safe, "provider")
    event_id = Map.get(safe, :provider_event_id) || Map.get(safe, "provider_event_id")

    case Repo.insert(%ProviderEvent{} |> ProviderEvent.changeset(safe),
           on_conflict: :nothing,
           conflict_target: [:provider, :provider_event_id]
         ) do
      {:ok, %ProviderEvent{id: nil}} ->
        # The unique conflict fired, so this provider event was already
        # durably recorded — a real duplicate delivery, not a reimplemented
        # heuristic (Phase 12 business-invariant metric).
        Dunda.Observability.increment(:webhook_duplicate_total)
        {:ok, Repo.get_by!(ProviderEvent, provider: provider, provider_event_id: event_id)}

      result ->
        result
    end
  end

  def confirm_payment(intent_id, attrs) do
    Repo.transaction(fn ->
      intent =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent_id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      if intent.state in ["fulfilled", "confirmed", "confirmed_late"],
        do: intent,
        else: confirm_locked!(intent, attrs)
    end)
    |> unwrap()
  end

  def fail_payment(intent_id, reason) do
    Repo.transaction(fn ->
      intent =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent_id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      # A reordered/stale provider failure can arrive after the intent has
      # already confirmed (or moved further). Once "failed" is no longer a
      # legal transition from the current state, this must no-op rather than
      # attempt an invalid changeset — Repo.update!/release_reservation!
      # would otherwise raise and crash the caller (Invariant 8: terminal /
      # already-progressed states are not overwritten by a stale event).
      if PaymentIntent.transition_allowed?(intent.state, "failed") do
        reservation =
          Repo.one(
            from r in InventoryReservation,
              where: r.payment_intent_id == ^intent.id and r.status == "active",
              lock: "FOR UPDATE"
          )

        case reservation do
          nil ->
            updated =
              Repo.update!(
                PaymentIntent.changeset(intent, %{
                  state: "failed",
                  failure_reason: to_string(reason),
                  version: intent.version + 1
                })
              )

            record_transition!(
              updated,
              intent.state,
              "failed",
              intent.version,
              "provider_failed",
              %{reason: to_string(reason)}
            )

            updated

          reservation ->
            release_reservation!(intent, reservation, reason)
        end
      else
        intent
      end
    end)
    |> unwrap()
  end

  def request_refund(intent_id, reason) do
    Repo.transaction(fn ->
      intent =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent_id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      if intent.state in ["refunded", "refund_pending"] do
        intent
      else
        unless PaymentIntent.transition_allowed?(intent.state, "refund_pending") do
          Repo.rollback({:invalid_refund_state, intent.state})
        end

        updated =
          Repo.update!(
            PaymentIntent.changeset(intent, %{
              state: "refund_pending",
              failure_reason: to_string(reason),
              version: intent.version + 1
            })
          )

        record_transition!(
          updated,
          intent.state,
          "refund_pending",
          intent.version,
          "refund_requested",
          %{reason: to_string(reason)}
        )

        enqueue_outbox!(
          "payment-intent:#{intent.id}:refund",
          "payment_refund_requested",
          "payment_intent",
          intent.id,
          %{payment_intent_id: intent.id, reason: to_string(reason)}
        )

        updated
      end
    end)
    |> unwrap()
  end

  @doc "Applies a provider-confirmed refund exactly once and compensates the ledger."
  def complete_refund(intent_id, attrs) do
    Repo.transaction(fn ->
      intent =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent_id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      cond do
        intent.state == "refunded" -> intent
        intent.state != "refund_pending" -> Repo.rollback({:invalid_refund_state, intent.state})
        true -> complete_refund_locked!(intent, attrs)
      end
    end)
    |> unwrap()
  end

  defp complete_refund_locked!(intent, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    tickets =
      Repo.all(
        from t in Ticket,
          join: b in TicketBatch,
          on: b.id == t.ticket_batch_id,
          join: l in PaymentLineItem,
          on: l.id == b.payment_line_item_id,
          where: l.payment_intent_id == ^intent.id,
          lock: "FOR UPDATE"
      )

    had_admission = Enum.any?(tickets, &(&1.status == "scanned"))

    Enum.each(tickets, fn ticket ->
      unless ticket.status == "refunded" do
        ticket
        |> Ticket.changeset(%{
          status: "refunded",
          revoked_at: now,
          revocation_reason: "payment_refund"
        })
        |> Repo.update!()
      end
    end)

    reconcile_refunded_inventory!(intent, had_admission, now)

    Dunda.Checkout.Journal.post!(
      "refund:#{intent.id}",
      intent.currency,
      [
        {"organiser_payable", :debit, intent.amount_cents},
        {"provider_clearing", :credit, intent.amount_cents}
      ],
      %{
        payment_intent_id: intent.id,
        provider_reference: attrs[:provider_reference] || attrs["provider_reference"]
      }
    )

    updated =
      Repo.update!(
        PaymentIntent.changeset(intent, %{
          state: "refunded",
          version: intent.version + 1
        })
      )

    record_transition!(
      updated,
      intent.state,
      "refunded",
      intent.version,
      "provider_refund_confirmed",
      %{
        provider_reference: attrs[:provider_reference] || attrs["provider_reference"],
        inventory_restocked: not had_admission and refundable_inventory?(intent.event_id)
      }
    )

    enqueue_outbox!(
      "payment-intent:#{intent.id}:refund-notification",
      "payment_refunded",
      "payment_intent",
      intent.id,
      %{payment_intent_id: intent.id}
    )

    updated
  end

  defp reconcile_refunded_inventory!(intent, had_admission, now) do
    case Repo.one(
           from r in InventoryReservation,
             where: r.payment_intent_id == ^intent.id,
             lock: "FOR UPDATE"
         ) do
      nil ->
        :ok

      %{status: status} = reservation when status in ["active", "uncertain"] ->
        pool =
          Repo.one!(
            from p in InventoryPool,
              where: p.id == ^reservation.inventory_pool_id,
              lock: "FOR UPDATE"
          )

        {1, _} =
          Repo.update_all(
            from(p in InventoryPool,
              where: p.id == ^pool.id and p.reserved >= ^reservation.quantity
            ),
            inc: [reserved: -reservation.quantity, version: 1]
          )

        enqueue_inventory_projection!(pool.id, pool.version + 1)

        Repo.update!(
          InventoryReservation.changeset(reservation, %{status: "released", released_at: now})
        )

      %{status: "consumed"} = reservation ->
        if not had_admission and refundable_inventory?(intent.event_id) do
          pool =
            Repo.one!(
              from p in InventoryPool,
                where: p.id == ^reservation.inventory_pool_id,
                lock: "FOR UPDATE"
            )

          {1, _} =
            Repo.update_all(
              from(p in InventoryPool,
                where: p.id == ^pool.id and p.sold >= ^reservation.quantity
              ),
              inc: [sold: -reservation.quantity, version: 1]
            )

          enqueue_inventory_projection!(pool.id, pool.version + 1)
        end

      _ ->
        :ok
    end
  end

  defp refundable_inventory?(event_id) do
    case Repo.get(Dunda.Events.Event, event_id) do
      %{status: "published", starts_at: starts_at} ->
        DateTime.compare(starts_at, DateTime.utc_now()) == :gt

      _ ->
        false
    end
  end

  defp confirm_locked!(intent, attrs) do
    receipt = attrs[:provider_receipt] || attrs["provider_receipt"]
    checkout_id = attrs[:provider_checkout_id] || attrs["provider_checkout_id"]
    amount = attrs[:amount_cents] || attrs["amount_cents"]
    provider_phone = attrs[:phone] || attrs["phone"]
    merchant_reference = attrs[:merchant_reference] || attrs["merchant_reference"]

    cond do
      not is_binary(receipt) or not is_binary(checkout_id) ->
        Repo.rollback(:provider_correlation_missing)

      amount != intent.amount_cents ->
        Repo.rollback(:provider_amount_mismatch)

      is_binary(provider_phone) and normalise_phone(provider_phone) != intent.phone_encrypted ->
        Repo.rollback(:provider_phone_mismatch)

      is_binary(merchant_reference) and
          merchant_reference not in ["intent_#{intent.id}", intent.idempotency_key] ->
        Repo.rollback(:provider_merchant_mismatch)

      intent.provider_checkout_id && intent.provider_checkout_id != checkout_id ->
        Repo.rollback(:provider_checkout_mismatch)

      true ->
        case Repo.one(
               from p in PaymentIntent,
                 where: p.provider_receipt == ^receipt and p.id != ^intent.id,
                 lock: "FOR UPDATE"
             ) do
          %PaymentIntent{} ->
            manual_review_locked!(intent, "provider_receipt_reused", %{provider_receipt: receipt})

          nil ->
            confirm_with_unique_checkout!(intent, attrs, receipt, checkout_id)
        end
    end
  end

  defp confirm_with_unique_checkout!(intent, attrs, receipt, checkout_id) do
    case Repo.one(
           from p in PaymentIntent,
             where: p.provider_checkout_id == ^checkout_id and p.id != ^intent.id,
             lock: "FOR UPDATE"
         ) do
      %PaymentIntent{} ->
        manual_review_locked!(intent, "provider_checkout_reused", %{
          provider_checkout_id: checkout_id
        })

      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        next_state =
          if(DateTime.compare(now, intent.expires_at) == :gt,
            do: "confirmed_late",
            else: "confirmed"
          )

        updated =
          Repo.update!(
            PaymentIntent.changeset(intent, %{
              state: next_state,
              provider: attrs[:provider] || attrs["provider"],
              provider_checkout_id: checkout_id,
              provider_receipt: receipt,
              confirmed_at: now,
              version: intent.version + 1
            })
          )

        record_transition!(
          updated,
          intent.state,
          next_state,
          intent.version,
          "provider_confirmed",
          %{provider: attrs[:provider] || attrs["provider"]}
        )

        enqueue_outbox!(
          "payment-intent:#{intent.id}:fulfilment",
          "payment_fulfilment_requested",
          "payment_intent",
          intent.id,
          %{payment_intent_id: intent.id}
        )

        updated
    end
  end

  defp manual_review_locked!(intent, reason, metadata) do
    updated =
      Repo.update!(
        PaymentIntent.changeset(intent, %{
          state: "manual_review",
          manual_review_reason: reason,
          version: intent.version + 1
        })
      )

    record_transition!(updated, intent.state, "manual_review", intent.version, reason, metadata)
    updated
  end

  def fulfil_payment_intent(intent_id) do
    Repo.transaction(fn ->
      intent =
        Repo.one(from p in PaymentIntent, where: p.id == ^intent_id, lock: "FOR UPDATE") ||
          Repo.rollback(:payment_intent_not_found)

      cond do
        intent.state == "fulfilled" ->
          intent

        intent.state not in ["confirmed", "confirmed_late"] ->
          Repo.rollback(:payment_not_confirmed)

        true ->
          fulfil_locked!(intent)
      end
    end)
    |> unwrap()
  end

  defp fulfil_locked!(intent) do
    reservation =
      Repo.one(
        from r in InventoryReservation,
          where: r.payment_intent_id == ^intent.id and r.status in ["active", "uncertain"],
          lock: "FOR UPDATE"
      ) || Repo.rollback(:reservation_not_found)

    pool =
      Repo.one(
        from p in InventoryPool, where: p.id == ^reservation.inventory_pool_id, lock: "FOR UPDATE"
      ) || Repo.rollback(:inventory_pool_not_found)

    if pool.reserved < reservation.quantity or pool.capacity - pool.sold < reservation.quantity,
      do: Repo.rollback(:inventory_unavailable_for_fulfilment)

    line =
      Repo.one(
        from l in PaymentLineItem,
          where: l.payment_intent_id == ^intent.id,
          order_by: [asc: l.line_number],
          lock: "FOR UPDATE"
      ) || Repo.rollback(:payment_line_missing)

    batch =
      Repo.insert!(
        %TicketBatch{}
        |> TicketBatch.changeset(%{
          payment_line_item_id: line.id,
          quantity: line.quantity,
          status: "created"
        }),
        on_conflict: :nothing,
        conflict_target: [:payment_line_item_id]
      )

    batch = if batch.id, do: batch, else: Repo.get_by!(TicketBatch, payment_line_item_id: line.id)
    event = Repo.get!(Dunda.Events.Event, intent.event_id)
    user = Repo.get!(Dunda.Accounts.User, intent.user_id)

    tier =
      if intent.ticket_tier_id, do: Repo.get!(Dunda.Ticketing.TicketTier, intent.ticket_tier_id)

    Enum.each(1..line.quantity, fn sequence ->
      ticket_id = Ecto.UUID.generate()

      attrs = %{
        id: ticket_id,
        user_id: user.id,
        event_id: event.id,
        tier_id: intent.ticket_tier_id,
        ticket_batch_id: batch.id,
        tier_label: if(tier, do: String.upcase(tier.name), else: "GENERAL"),
        price_kes: div(line.unit_price_cents, 100),
        status: "valid",
        jwt: nil,
        fulfillment_key: "payment-intent:#{intent.id}:line:#{line.id}:#{sequence}"
      }

      Repo.insert!(Ticket.changeset(%Ticket{}, attrs))
    end)

    Dunda.Checkout.Journal.post!(
      "settlement:#{intent.id}",
      intent.currency,
      [
        {"provider_clearing", :debit, intent.amount_cents},
        {"organiser_payable", :credit, intent.amount_cents}
      ],
      %{payment_intent_id: intent.id, provider_receipt: intent.provider_receipt}
    )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update_all(from(p in InventoryPool, where: p.id == ^pool.id),
      set: [
        reserved: pool.reserved - reservation.quantity,
        sold: pool.sold + reservation.quantity,
        version: pool.version + 1
      ]
    )

    enqueue_inventory_projection!(pool.id, pool.version + 1)

    Repo.update!(
      InventoryReservation.changeset(reservation, %{status: "consumed", consumed_at: now})
    )

    Repo.update!(TicketBatch.changeset(batch, %{status: "fulfilled"}))

    updated =
      Repo.update!(
        PaymentIntent.changeset(intent, %{
          state: "fulfilled",
          fulfilled_at: now,
          version: intent.version + 1
        })
      )

    record_transition!(updated, intent.state, "fulfilled", intent.version, "tickets_issued", %{
      ticket_batch_id: batch.id
    })

    enqueue_outbox!(
      "payment-intent:#{intent.id}:notification",
      "tickets_issued",
      "payment_intent",
      intent.id,
      %{payment_intent_id: intent.id, ticket_batch_id: batch.id}
    )

    updated
  end

  def expire_reservations(now \\ DateTime.utc_now()) do
    Repo.transaction(fn ->
      intents =
        Repo.all(
          from p in PaymentIntent,
            where:
              p.state in [
                "created",
                "inventory_reserved",
                "provider_submission_pending",
                "provider_pending",
                "expired_pending_reconciliation",
                "manual_review"
              ] and p.expires_at < ^now,
            lock: "FOR UPDATE SKIP LOCKED"
        )

      Enum.map(intents, fn intent ->
        case Repo.one(
               from r in InventoryReservation,
                 where:
                   r.payment_intent_id == ^intent.id and r.status in ["active", "uncertain"] and
                     r.expires_at < ^now,
                 lock: "FOR UPDATE"
             ) do
          nil -> nil
          reservation -> expire_reservation_locked(reservation)
        end
      end)
    end)
    |> unwrap()
  end

  defp expire_reservation_locked(reservation) do
    intent =
      Repo.one(
        from p in PaymentIntent, where: p.id == ^reservation.payment_intent_id, lock: "FOR UPDATE"
      )

    if intent &&
         intent.state in ["provider_pending", "expired_pending_reconciliation", "manual_review"],
       do: Repo.update!(InventoryReservation.changeset(reservation, %{status: "uncertain"}))

    if intent &&
         intent.state in [
           "created",
           "inventory_reserved",
           "provider_submission_pending",
           "failed"
         ],
       do: release_reservation!(intent, reservation)

    reservation.id
  end

  def release_reservation!(intent, reservation, reason \\ "reservation_expired") do
    pool =
      Repo.one!(
        from p in InventoryPool, where: p.id == ^reservation.inventory_pool_id, lock: "FOR UPDATE"
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.update_all(
        from(p in InventoryPool, where: p.id == ^pool.id and p.reserved >= ^reservation.quantity),
        inc: [reserved: -reservation.quantity, version: 1]
      )

    if count != 1, do: Repo.rollback(:reservation_release_conflict)
    enqueue_inventory_projection!(pool.id, pool.version + 1)

    Repo.update!(
      InventoryReservation.changeset(reservation, %{status: "released", released_at: now})
    )

    reason = to_string(reason)

    updated =
      Repo.update!(
        PaymentIntent.changeset(intent, %{
          state: "failed",
          failure_reason: reason,
          version: intent.version + 1
        })
      )

    record_transition!(updated, intent.state, "failed", intent.version, reason, %{})
    updated
  end

  def reconcile_redis_projection do
    Repo.all(InventoryPool)
    |> Enum.reduce_while(:ok, fn pool, :ok ->
      case Redix.command(:redix, [
             "SET",
             Dunda.Inventory.inventory_key(pool.pool_key),
             Integer.to_string(pool.capacity - pool.reserved - pool.sold)
           ]) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp enqueue_outbox!(key, type, aggregate_type, aggregate_id, payload) do
    Repo.insert!(
      %OutboxEvent{}
      |> OutboxEvent.changeset(%{
        event_key: key,
        event_type: type,
        aggregate_type: aggregate_type,
        aggregate_id: to_string(aggregate_id),
        payload: payload,
        status: "pending",
        attempts: 0,
        available_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }),
      on_conflict: :nothing,
      conflict_target: :event_key
    )
  end

  defp enqueue_inventory_projection!(pool_id, version) do
    enqueue_outbox!(
      "inventory-pool:#{pool_id}:v#{version}",
      "inventory_projection_changed",
      "inventory_pool",
      pool_id,
      %{inventory_pool_id: pool_id, version: version}
    )
  end

  defp record_transition!(intent, from_state, to_state, prior_version, reason, metadata) do
    Repo.insert!(%PaymentIntentTransition{
      payment_intent_id: intent.id,
      from_state: from_state,
      to_state: to_state,
      prior_version: prior_version,
      reason: reason,
      metadata: metadata
    })
  end

  defp pool_for_quote!(%Quote{ticket_tier_id: tier_id}) when not is_nil(tier_id) do
    Repo.get_by(InventoryPool, ticket_tier_id: tier_id) ||
      Repo.rollback(:inventory_pool_not_found)
  end

  defp pool_for_quote!(%Quote{event_id: event_id}) do
    Repo.get_by(InventoryPool, event_id: event_id, ticket_tier_id: nil) ||
      Repo.rollback(:inventory_pool_not_found)
  end

  defp resolve_tier(event_id, nil) do
    case Dunda.Ticketing.default_tier(event_id) do
      nil ->
        if Dunda.Ticketing.event_has_tiers?(event_id),
          do: {:error, :tier_not_on_sale},
          else: {:ok, nil}

      tier ->
        {:ok, tier}
    end
  end

  defp resolve_tier(event_id, tier_id),
    do: {:ok, Dunda.Ticketing.get_event_tier(event_id, tier_id)}

  defp event_on_sale(%Events.Event{status: "published"}), do: :ok
  defp event_on_sale(_), do: {:error, :event_not_on_sale}
  defp tier_on_sale(nil, _), do: :ok

  defp tier_on_sale(%{status: "on_sale", max_per_order: max}, quantity) when quantity <= max,
    do: :ok

  defp tier_on_sale(%{status: "on_sale"}, _), do: {:error, :max_per_order_exceeded}
  defp tier_on_sale(_, _), do: {:error, :tier_not_on_sale}
  defp price_version(event), do: "event-updated-#{DateTime.to_unix(event.updated_at)}"
  defp provider, do: Application.get_env(:dunda, :checkout_provider, :pesapal) |> to_string()

  defp normalise_phone(phone) when is_binary(phone) do
    digits = String.replace(phone, ~r/\D/, "")

    cond do
      Regex.match?(~r/^254[17]\d{8}$/, digits) -> digits
      Regex.match?(~r/^0[17]\d{8}$/, digits) -> "254" <> String.slice(digits, 1..-1//1)
      true -> nil
    end
  end

  defp normalise_phone(_), do: nil
  defp parse_positive(v) when is_integer(v) and v > 0, do: v

  defp parse_positive(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_positive(_), do: nil
  defp parse_id(v) when is_integer(v) and v > 0, do: v

  defp parse_id(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
  defp parse_optional_id(nil), do: {:ok, nil}

  defp parse_optional_id(v) do
    case parse_id(v) do
      nil -> {:error, :invalid_tier}
      id -> {:ok, id}
    end
  end

  defp cast_uuid(v) when is_binary(v) do
    case Ecto.UUID.cast(v) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp cast_uuid(v), do: v

  defp sanitize_payload(payload) when is_map(payload) do
    payload
    |> Enum.reject(fn {k, _} ->
      String.contains?(String.downcase(to_string(k)), [
        "token",
        "secret",
        "password",
        "authorization"
      ])
    end)
    |> Enum.take(100)
    |> Map.new(fn {k, v} ->
      {to_string(k), if(is_binary(v), do: String.slice(v, 0, 2_000), else: inspect(v, limit: 20))}
    end)
  end

  defp sanitize_payload(_), do: %{}
  defp unwrap({:ok, value}), do: {:ok, value}
  defp unwrap({:error, reason}), do: {:error, reason}
end
