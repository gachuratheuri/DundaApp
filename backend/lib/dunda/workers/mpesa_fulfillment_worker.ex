defmodule Dunda.Workers.MpesaFulfillmentWorker do
  @moduledoc """
  Generates tickets asynchronously after an M-Pesa STK Push has been successfully settled.
  """
  use Oban.Worker, queue: :payments, max_attempts: 5

  alias Dunda.Events
  alias Dunda.Accounts
  alias Dunda.Ticketing
  alias Dunda.Ledger

  @spec enqueue(String.t(), String.t(), String.t(), integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(transaction_id, ticket_tier_id, user_id, quantity) do
    %{
      "transaction_id" => transaction_id,
      "ticket_tier_id" => ticket_tier_id,
      "user_id" => user_id,
      "quantity" => quantity
    }
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    transaction_id = args["transaction_id"]
    event_id = args["ticket_tier_id"] # CheckoutController currently passes event_id as tier_id
    user_id = args["user_id"]
    quantity = args["quantity"]

    # Verify the ledger is actually settled
    if Ledger.settled?(transaction_id) do
      event = Events.get_event(event_id)
      user = Accounts.get_user(user_id)

      if event && user do
        # Issue tickets directly to the user's wallet without an Order reference
        # We will hardcode tier_label to GENERAL for Daraja pushes unless tier logic is expanded
        Ticketing.issue_tickets(nil, event, user, quantity, "GENERAL")
        :ok
      else
        {:error, :invalid_event_or_user}
      end
    else
      # If the ledger isn't settled yet, the worker will fail and retry later
      {:error, :ledger_not_settled}
    end
  end
end
