defmodule Dunda.RetentionTest do
  use Dunda.DataCase, async: false

  alias Dunda.Accounts.Notification
  alias Dunda.Billing.Order
  alias Dunda.Events.Event
  alias Dunda.Ledger.Entry, as: LedgerEntry
  alias Dunda.Ticketing.Ticket

  defp unique, do: System.unique_integer([:positive])

  defp insert_user! do
    n = unique()

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "retention-#{n}@example.com",
        "password" => "password123!",
        "name" => "Retention Test"
      })

    user
  end

  defp insert_event! do
    n = unique()

    {:ok, event} =
      Event.changeset(%Event{}, %{
        name: "Retention Test #{n}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: 10,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })
      |> Repo.insert()

    event
  end

  defp insert_old_read_notification!(user) do
    old =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(-400, :day) |> NaiveDateTime.truncate(:second)

    {:ok, notification} =
      %Notification{}
      |> Notification.changeset(%{
        user_id: user.id,
        type: "test",
        title: "old",
        body: "old",
        read_at: DateTime.utc_now()
      })
      |> Repo.insert()

    # Backdate inserted_at directly — the changeset always stamps "now".
    {1, _} =
      Repo.update_all(from(n in Notification, where: n.id == ^notification.id),
        set: [inserted_at: old]
      )

    notification
  end

  setup do
    on_exit(fn -> Application.put_env(:dunda, :containment_mode, false) end)
    :ok
  end

  test "preview/1 counts deletable notifications without deleting anything" do
    user = insert_user!()
    insert_old_read_notification!(user)

    report = Dunda.Retention.preview()
    assert report.deletable_read_notifications >= 1
    assert Repo.aggregate(Notification, :count) >= 1
  end

  test "execute/1 deletes only old read notifications, never ledger/order/ticket/audit rows" do
    Application.put_env(:dunda, :containment_mode, false)

    user = insert_user!()
    event = insert_event!()
    insert_old_read_notification!(user)

    {:ok, order} =
      Order.create_changeset(%Order{}, %{
        merchant_reference: "retention-order-#{unique()}",
        amount_cents: 1_000,
        event_id: event.id,
        idempotency_key: String.duplicate("q", 16)
      })
      |> Repo.insert()

    {:ok, ticket} =
      Ticket.changeset(%Ticket{}, %{
        tier_label: "GA",
        price_kes: 1_000,
        status: "valid",
        user_id: user.id,
        event_id: event.id,
        order_id: order.id
      })
      |> Repo.insert()

    ledger_count_before = Repo.aggregate(LedgerEntry, :count)
    order_count_before = Repo.aggregate(Order, :count)
    ticket_count_before = Repo.aggregate(Ticket, :count)
    audit_count_before = Repo.aggregate(Dunda.Audit.Event, :count)

    assert {:ok, deleted_count} = Dunda.Retention.execute()
    assert deleted_count >= 1

    assert Repo.aggregate(LedgerEntry, :count) == ledger_count_before
    assert Repo.aggregate(Order, :count) == order_count_before
    assert Repo.aggregate(Ticket, :count) == ticket_count_before
    # The retention run itself is audited, so this is expected to grow, not
    # stay equal — the invariant under test is that it never *shrinks*
    # (retention never deletes audit evidence).
    assert Repo.aggregate(Dunda.Audit.Event, :count) >= audit_count_before

    assert Repo.get(Order, order.id)
    assert Repo.get(Ticket, ticket.id)
  end

  test "execute/1 is blocked during Phase 0 containment" do
    Application.put_env(:dunda, :containment_mode, true)
    assert {:error, :phase_0_containment} = Dunda.Retention.execute()
  end
end
