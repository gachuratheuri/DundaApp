defmodule Dunda.Market do
  @moduledoc """
  Transactional secondary-market context.

  A listing is only a proposal.  Payment creates a normal order intent; the
  ticket transfer is performed only after that order has reached the
  authoritative `completed` state.  Listing, ticket, order, replacement
  entitlement, and seller ledger credit commit in one database transaction.
  """

  import Ecto.Query, only: [from: 2]

  alias Dunda.Billing.Order
  alias Dunda.Market.Listing
  alias Dunda.Repo
  alias Dunda.Ticketing.{Ticket, TicketCredentialEvent}
  alias Ecto.Multi

  @doc "Creates one active listing with an immutable face-value snapshot."
  def list_ticket(%Ticket{} = ticket, seller_id, asking_price) do
    if Dunda.Containment.blocked?(:resale) do
      {:error, :phase_0_containment}
    else
      Repo.transaction(fn ->
        locked = Repo.one(from t in Ticket, where: t.id == ^ticket.id, lock: "FOR UPDATE")

        if locked && locked.user_id == seller_id && locked.status == "valid" do
          attrs = %{
            ticket_id: locked.id,
            seller_id: seller_id,
            asking_price_kes: asking_price,
            face_value_kes: locked.price_kes,
            status: "active"
          }

          case %Listing{} |> Listing.changeset(attrs) |> Repo.insert() do
            {:ok, listing} -> listing
            {:error, changeset} -> Repo.rollback(changeset)
          end
        else
          Repo.rollback(:unauthorized_or_invalid_ticket)
        end
      end)
      |> unwrap_transaction()
    end
  end

  @doc "Gets an active listing with its ticket and event loaded."
  def get_active_listing!(id) do
    Repo.get_by!(Listing, id: id, status: "active")
    |> Repo.preload(ticket: :event)
  end

  @doc "Lists all active listings."
  def list_active_listings do
    if Dunda.Containment.blocked?(:resale),
      do: [],
      else: Repo.all(from l in Listing, where: l.status == "active", preload: [ticket: :event])
  end

  @doc "Creates the normal payment order intent bound to a resale listing."
  @spec create_resale_payment_intent(binary(), integer(), String.t()) ::
          {:ok, Order.t()} | {:error, term()}
  def create_resale_payment_intent(listing_id, buyer_id, idempotency_key),
    do: create_resale_payment_intent(listing_id, buyer_id, idempotency_key, nil)

  @spec create_resale_payment_intent(binary(), integer(), String.t(), String.t() | nil) ::
          {:ok, Order.t()} | {:error, term()}
  def create_resale_payment_intent(listing_id, buyer_id, idempotency_key, phone) do
    if Dunda.Containment.blocked?(:resale) do
      {:error, :phase_0_containment}
    else
      Repo.transaction(fn ->
        with %Order{} = existing <- existing_resale_order(buyer_id, idempotency_key) do
          existing
        else
          nil -> create_resale_intent_locked(listing_id, buyer_id, idempotency_key, phone)
        end
      end)
      |> unwrap_transaction()
    end
  end

  @doc "Completes a resale transfer only for an authoritatively completed order."
  @spec complete_resale_purchase(integer(), keyword()) :: {:ok, Listing.t()} | {:error, term()}
  def complete_resale_purchase(order_id, opts \\ []) do
    if Dunda.Containment.blocked?(:resale) do
      {:error, :phase_0_containment}
    else
      Repo.transaction(fn ->
        order = Repo.one(from o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")

        cond do
          is_nil(order) -> Repo.rollback(:order_not_found)
          order.kind != "resale" -> Repo.rollback(:not_resale_order)
          order.status == "completed" -> transfer_locked(order, false)
          order.status == "pending" and Keyword.get(opts, :confirmed?, false) -> transfer_locked(order, true)
          true -> Repo.rollback(:payment_not_confirmed)
        end
      end)
      |> unwrap_transaction()
    end
  end

  @doc "Cancels an unconfirmed resale intent and releases its listing."
  @spec cancel_resale_payment_intent(integer()) :: {:ok, Order.t()} | {:error, term()}
  def cancel_resale_payment_intent(order_id) do
    Repo.transaction(fn ->
      order = Repo.one(from o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")

      cond do
        is_nil(order) -> Repo.rollback(:order_not_found)
        order.kind != "resale" -> Repo.rollback(:not_resale_order)
        order.status not in ["pending", "failed", "invalid"] -> Repo.rollback(:order_not_cancellable)
        true ->
          if listing = Repo.one(from l in Listing, where: l.payment_order_id == ^order.id, lock: "FOR UPDATE") do
            listing
            |> Listing.changeset(%{status: "active", payment_order_id: nil})
            |> Repo.update()
            |> case do
              {:ok, _} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end

          case order |> Order.status_changeset(%{status: "failed"}) |> Repo.update() do
            {:ok, cancelled} -> cancelled
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> unwrap_transaction()
  end

  @doc "Legacy entry point deliberately refuses a buyer-only transfer."
  def execute_purchase(%Listing{}, _buyer_id), do: {:error, :resale_payment_required}
  def execute_purchase(%Listing{}, _buyer_id, _payment_proof), do: {:error, :resale_payment_required}

  defp create_resale_intent_locked(listing_id, buyer_id, idempotency_key, phone) do
    listing =
      Repo.one(
        from l in Listing,
          where: l.id == ^listing_id,
          preload: [ticket: :event],
          lock: "FOR UPDATE"
      )

    cond do
      is_nil(listing) -> Repo.rollback(:listing_not_found)
      listing.status != "active" -> Repo.rollback(:listing_not_active)
      is_nil(listing.face_value_kes) -> Repo.rollback(:face_value_missing)
      listing.ticket.user_id == buyer_id -> Repo.rollback(:seller_cannot_buy_own_listing)
      listing.ticket.status != "valid" -> Repo.rollback(:ticket_not_transferable)
      not is_binary(phone) or String.trim(phone) == "" -> Repo.rollback(:phone_required)
      not is_binary(idempotency_key) or byte_size(idempotency_key) not in 16..200 ->
        Repo.rollback(:idempotency_key_required)

      true ->
        event = listing.ticket.event

        attrs = %{
          merchant_reference: resale_reference(idempotency_key),
          amount_cents: listing.asking_price_kes * 100,
          currency: event.currency || "KES",
          quantity: 1,
          phone_encrypted: phone,
          event_id: event.id,
          organisation_id: event.organisation_id,
          user_id: buyer_id,
          idempotency_key: idempotency_key,
          kind: "resale",
          resale_listing_id: listing.id
        }

        with {:ok, order} <- %Order{} |> Order.create_changeset(attrs) |> Repo.insert(),
             {:ok, _listing} <-
               listing |> Listing.changeset(%{status: "pending", payment_order_id: order.id}) |> Repo.update() do
          _ = Dunda.Audit.record(%{action: "resale.payment_intent_created", resource_type: "order", resource_id: to_string(order.id), metadata: %{listing_id: listing.id, amount_cents: order.amount_cents}})
          order
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp transfer_locked(order, confirmed_pending?) do
    listing = Repo.one(from l in Listing, where: l.payment_order_id == ^order.id, lock: "FOR UPDATE")

    cond do
      is_nil(listing) -> Repo.rollback(:listing_not_found)
      listing.status == "sold" and listing.buyer_id == order.user_id -> listing
      listing.status not in ["active", "pending"] -> Repo.rollback(:listing_not_transferable)
      true ->
        ticket = Repo.one(from t in Ticket, where: t.id == ^listing.ticket_id, lock: "FOR UPDATE")

        if is_nil(ticket) or ticket.status != "valid" or ticket.user_id == order.user_id do
          Repo.rollback(:ticket_not_transferable)
        else
          new_id = Ecto.UUID.generate()
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          multi =
            Multi.new()
            |> Multi.insert(:new_ticket, Ticket.changeset(%Ticket{}, %{id: new_id, user_id: order.user_id, event_id: ticket.event_id, order_id: order.id, tier_id: ticket.tier_id, tier_label: ticket.tier_label, price_kes: ticket.price_kes, status: "valid", jwt: nil, transferred_from_user_id: ticket.user_id, supersedes_ticket_id: ticket.id, fulfillment_key: "resale:#{listing.id}"}))
            |> Multi.update(:old_ticket, Ticket.changeset(ticket, %{status: "transferred", jwt: nil, revoked_at: now, revocation_reason: "resale_transfer", replaced_by_ticket_id: new_id, credential_epoch: ticket.credential_epoch + 1}))
            |> Multi.run(:credential_event, fn repo, %{old_ticket: old_ticket} ->
              if old_ticket.credential_version == 2 do
                repo.insert(TicketCredentialEvent.changeset(%TicketCredentialEvent{}, %{ticket_id: old_ticket.id, event_type: "revoked", credential_epoch: old_ticket.credential_epoch, public_key_fingerprint: old_ticket.credential_public_key && Base.url_encode64(:crypto.hash(:sha256, old_ticket.credential_public_key), padding: false), actor_user_id: ticket.user_id, metadata: %{reason: "resale_transfer"}, occurred_at: now}))
              else
                {:ok, nil}
              end
            end)
            |> Multi.update(:listing, Listing.changeset(listing, %{status: "sold", buyer_id: order.user_id, sold_at: now}))

          case Repo.transaction(multi) do
            {:ok, %{listing: sold_listing}} ->
              case Dunda.Ledger.record_transfer(%{from_account: "resale:#{listing.id}:buyer", to_account: "user:#{ticket.user_id}:payable", amount_cents: order.amount_cents, reference: "resale:#{listing.id}:seller-credit"}) do
                {:ok, _transfer} ->
                  if confirmed_pending? do
                    case order |> Order.status_changeset(%{status: "completed"}) |> Repo.update() do
                      {:ok, _} -> :ok
                      {:error, changeset} -> Repo.rollback(changeset)
                    end
                  end
                  _ = Dunda.Audit.record(%{action: "resale.transfer_completed", resource_type: "resale_listing", resource_id: listing.id, metadata: %{order_id: order.id, buyer_id: order.user_id, seller_id: ticket.user_id}})
                  sold_listing

                {:error, reason} -> Repo.rollback(reason)
              end

            {:error, _operation, reason, _changes} -> Repo.rollback(reason)
          end
        end
    end
  end

  defp existing_resale_order(buyer_id, idempotency_key) do
    Repo.one(from o in Order, where: o.user_id == ^buyer_id and o.idempotency_key == ^idempotency_key and o.kind == "resale", lock: "FOR UPDATE")
  end

  defp resale_reference(key), do: "resale_" <> Base.url_encode64(:crypto.hash(:sha256, key), padding: false)

  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
