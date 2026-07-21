defmodule Dunda.Ticketing do
  @moduledoc """
  Context for issuing and managing tickets and device-bound protocol-v2
  credentials, and for the ticket tiers that act as the unit of inventory.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Repo
  alias Dunda.Ticketing.Ticket
  alias Dunda.Ticketing.TicketTier
  alias Ecto.Multi

  # ── Ticket tiers ─────────────────────────────────────────────────────────────

  @doc "Fetch a tier by id, or `nil`."
  @spec get_tier(integer() | String.t()) :: TicketTier.t() | nil
  def get_tier(id), do: Repo.get(TicketTier, id)

  @doc "Fetch a tier by id scoped to `event_id`, or `nil` (guards cross-event ids)."
  @spec get_event_tier(integer() | String.t(), integer() | String.t()) :: TicketTier.t() | nil
  def get_event_tier(event_id, tier_id) do
    Repo.get_by(TicketTier, id: tier_id, event_id: event_id)
  end

  @doc """
  The tier a checkout falls back to when the client did not pick one: the
  cheapest on-sale tier (matching the headline price the app displays), with
  `sort_order` as the tiebreak. `nil` when the event has no tiers (legacy
  events sell against the event itself).
  """
  @spec default_tier(integer() | String.t()) :: TicketTier.t() | nil
  def default_tier(event_id) do
    Repo.one(
      from t in TicketTier,
        where: t.event_id == ^event_id and t.status == "on_sale",
        order_by: [asc: t.price_cents, asc: t.sort_order],
        limit: 1
    )
  end

  @doc "Whether `event_id` has any tiers at all (regardless of status)."
  @spec event_has_tiers?(integer() | String.t()) :: boolean()
  def event_has_tiers?(event_id) do
    Repo.exists?(from t in TicketTier, where: t.event_id == ^event_id)
  end

  @doc "Number of tickets already issued against `tier_id` (any live status)."
  @spec sold_count_for_tier(integer() | String.t()) :: non_neg_integer()
  def sold_count_for_tier(tier_id) do
    Repo.aggregate(from(t in Ticket, where: t.tier_id == ^tier_id), :count)
  end

  @doc "Number of tickets already issued against `event_id` (any live status)."
  @spec sold_count_for_event(integer() | String.t()) :: non_neg_integer()
  def sold_count_for_event(event_id) do
    Repo.aggregate(from(t in Ticket, where: t.event_id == ^event_id), :count)
  end

  # ── Ticket issuance ──────────────────────────────────────────────────────────

  @doc """
  Issues `count` tickets to `user` for `event` from `order`. New tickets are
  intentionally unbound until the attendee completes the authenticated device
  binding flow; no legacy TOTP credential is returned to the client. Options:

    * `:tier` — the purchased `%TicketTier{}`; the ticket then carries the tier
      id, label, and face value. Without it the event-level price and a GENERAL
      label are used.
    * `:transaction_id` — the settling M-Pesa transaction, recorded on each
      ticket so fulfillment can be made exactly-once.
    * `:tier_label` — label override for tierless issuance (seeds, comps).

  Returns `{:ok, tickets}` or `{:error, reason}`.
  """
  def issue_tickets(order, event, user, count, opts \\ []) do
    tier = Keyword.get(opts, :tier)
    transaction_id = Keyword.get(opts, :transaction_id)
    price = face_value_kes(tier, order, event, count)

    tier_label =
      if tier,
        do: String.upcase(tier.name),
        else: Keyword.get(opts, :tier_label, "GENERAL")

    # Build a transaction that inserts each ticket atomically
    multi =
      Enum.reduce(1..count, Multi.new(), fn index, acc ->
        ticket_id = Ecto.UUID.generate()

        ticket_changeset =
          Ticket.changeset(%Ticket{}, %{
            id: ticket_id,
            user_id: user.id,
            event_id: event.id,
            order_id: if(order, do: order.id, else: nil),
            tier_id: if(tier, do: tier.id, else: nil),
            transaction_id: transaction_id,
            fulfillment_key: fulfillment_key(order, transaction_id, index, ticket_id),
            tier_label: tier_label,
            price_kes: price,
            status: "valid",
            jwt: nil
          })

        Multi.insert(acc, {:ticket, index}, ticket_changeset)
      end)

    case Repo.transaction(multi) do
      {:ok, result} ->
        # Extract the tickets from the multi result map and maintain order
        tickets = Enum.map(1..count, fn i -> Map.fetch!(result, {:ticket, i}) end)
        {:ok, tickets}

      {:error, _failed_operation, failed_value, _changes_so_far} ->
        {:error, failed_value}
    end
  end

  defp fulfillment_key(order, transaction_id, index, ticket_id) do
    cond do
      is_binary(transaction_id) -> "transaction:#{transaction_id}:#{index}"
      order && order.id -> "order:#{order.id}:#{index}"
      true -> "manual:#{ticket_id}"
    end
  end

  # Face value in whole KSh (the unit `tickets.price_kes` and the resale price
  # cap are denominated in).
  defp face_value_kes(%TicketTier{price_cents: cents}, _order, _event, _count),
    do: div(cents, 100)

  defp face_value_kes(nil, order, _event, count) when not is_nil(order),
    do: div(order.amount_cents, 100 * count)

  defp face_value_kes(nil, nil, %{price_cents: cents}, _count) when is_integer(cents),
    do: div(cents, 100)

  defp face_value_kes(nil, nil, _event, _count), do: 0

  @doc "Whether tickets were already issued for an M-Pesa `transaction_id`."
  @spec fulfilled?(String.t()) :: boolean()
  def fulfilled?(transaction_id) when is_binary(transaction_id) do
    Repo.exists?(from t in Ticket, where: t.transaction_id == ^transaction_id)
  end

  @doc "Whether an order has at least its authoritative quantity of tickets."
  @spec fulfilled_order?(integer(), pos_integer()) :: boolean()
  def fulfilled_order?(order_id, quantity)
      when is_integer(order_id) and is_integer(quantity) and quantity > 0 do
    Repo.aggregate(from(t in Ticket, where: t.order_id == ^order_id), :count) >= quantity
  end

  def fulfilled_order?(_, _), do: false

  @doc """
  Lists all tickets for a user, preloading the associated event.
  """
  def list_user_tickets(user_id) do
    Repo.all(
      from t in Ticket,
        where: t.user_id == ^user_id,
        preload: [:event]
    )
  end
end
