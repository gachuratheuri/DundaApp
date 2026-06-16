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
    attrs = Map.put(attrs, :merchant_reference, generate_reference())

    with {:ok, order} <- insert_order(attrs),
         {:ok, %{order_tracking_id: otid, redirect_url: url}} <-
           Pesapal.submit_order(order_payload(order, attrs)),
         {:ok, order} <- update_status(order, %{order_tracking_id: otid}) do
      {:ok, %{order: order, redirect_url: url}}
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
    case get_order_by_tracking_id(order_tracking_id) do
      nil ->
        {:error, :order_not_found}

      order ->
        case Pesapal.transaction_status(order_tracking_id) do
          {:ok, status} ->
            new_status = classify(status)

            # Issue tickets if transitioning to completed
            if new_status == "completed" and order.status != "completed" and order.user_id and order.event_id do
              user = Accounts.get_user(order.user_id)
              event = Events.get_event(order.event_id)

              if user && event do
                Ticketing.issue_tickets(order, event, user, order.quantity)
              end
            end

            update_status(order, %{
              status: new_status,
              pesapal_status: status["payment_status_description"]
            })

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc "Completed-but-unpaid totals (in cents) grouped by organisation."
  @spec payable_totals() :: [{pos_integer(), non_neg_integer()}]
  def payable_totals do
    from(o in Order,
      where:
        o.status == "completed" and o.payout_status == "unpaid" and not is_nil(o.organisation_id),
      group_by: o.organisation_id,
      select: {o.organisation_id, sum(o.amount_cents)}
    )
    |> Repo.all()
  end

  @doc "Mark an organisation's completed+unpaid orders as `paid` after a B2C payout."
  @spec mark_organisation_paid(pos_integer()) :: {non_neg_integer(), nil}
  def mark_organisation_paid(organisation_id) do
    from(o in Order,
      where:
        o.organisation_id == ^organisation_id and o.status == "completed" and
          o.payout_status == "unpaid"
    )
    |> Repo.update_all(set: [payout_status: "paid", updated_at: DateTime.utc_now()])
  end

  # ── Internals ────────────────────────────────────────────────────────────────

  defp insert_order(attrs) do
    %Order{}
    |> Order.create_changeset(attrs)
    |> Repo.insert()
  end

  defp update_status(order, attrs) do
    order
    |> Order.status_changeset(attrs)
    |> Repo.update()
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
