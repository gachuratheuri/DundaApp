defmodule Dunda.Retention do
  @moduledoc "Conservative data-retention policy; statutory financial evidence is never purged."

  import Ecto.Query, only: [from: 2]

  alias Dunda.Accounts.Notification
  alias Dunda.Repo

  @notification_days 365

  @spec preview(NaiveDateTime.t()) :: map()
  def preview(now \\ NaiveDateTime.utc_now()) do
    cutoff = NaiveDateTime.add(now, -@notification_days, :day)

    %{
      deletable_read_notifications:
        Repo.aggregate(
          from(n in Notification,
            where: not is_nil(n.read_at) and n.inserted_at < ^cutoff
          ),
          :count
        ),
      protected_ledger_entries: Repo.aggregate(Dunda.Ledger.Entry, :count),
      protected_orders: Repo.aggregate(Dunda.Billing.Order, :count),
      protected_tickets: Repo.aggregate(Dunda.Ticketing.Ticket, :count),
      protected_audit_events: Repo.aggregate(Dunda.Audit.Event, :count)
    }
  end

  @doc "Executes only the explicitly approved, non-financial notification policy."
  @spec execute(NaiveDateTime.t()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def execute(now \\ NaiveDateTime.utc_now()) do
    if Dunda.Containment.enabled?() do
      {:error, :phase_0_containment}
    else
      cutoff = NaiveDateTime.add(now, -@notification_days, :day)

      {count, _} =
        Repo.delete_all(
          from(n in Notification,
            where: not is_nil(n.read_at) and n.inserted_at < ^cutoff
          )
        )

      _ =
        Dunda.Audit.record(%{action: "retention.notifications_deleted", metadata: %{count: count}})

      {:ok, count}
    end
  end
end
