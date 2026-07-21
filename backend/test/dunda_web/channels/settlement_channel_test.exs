defmodule DundaWeb.SettlementChannelTest do
  use DundaWeb.ChannelCase

  alias Dunda.Accounts.User
  alias Dunda.Checkout
  alias Dunda.Checkout.InventoryPool
  alias Dunda.CheckoutFixtures
  alias Dunda.Repo
  alias DundaWeb.Auth.Token
  alias DundaWeb.SettlementChannel
  alias DundaWeb.UserSocket

  defp connect_and_join(user, payment_intent_id) do
    token = Token.sign(user)
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    subscribe_and_join(socket, "settlement:#{payment_intent_id}", %{})
  end

  defp payment_intent_fixture! do
    n = System.unique_integer([:positive])

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "settlement-#{n}@example.com",
        "password" => "password123!",
        "name" => "Settlement Owner"
      })

    event = CheckoutFixtures.insert_event!()

    Repo.insert!(
      InventoryPool.changeset(%InventoryPool{}, %{
        pool_key: "event:#{event.id}",
        event_id: event.id,
        capacity: event.capacity,
        reserved: 0,
        sold: 0,
        version: 1
      })
    )

    {:ok, quote} = Checkout.create_quote(user.id, %{event_id: event.id, quantity: 1})

    {:ok, intent} =
      Checkout.create_payment_intent(user.id, %{
        quote_id: quote.id,
        idempotency_key: Base.encode16(:crypto.strong_rand_bytes(12)),
        phone: "254712345678"
      })

    {user, intent}
  end

  describe "UserSocket auth" do
    test "rejects connections without a valid token" do
      assert :error = connect(UserSocket, %{"token" => "not-a-real-token"})
      assert :error = connect(UserSocket, %{})
    end

    test "accepts connections with a valid token" do
      token = Token.sign(%User{id: 42})
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == 42
    end
  end

  describe "join settlement:<transaction_id>" do
    test "replies with the current (pending) ledger status" do
      {user, intent} = payment_intent_fixture!()
      assert {:ok, %{status: "pending"}, _socket} = connect_and_join(user, intent.id)
    end

    test "rejects a different authenticated user" do
      {_owner, intent} = payment_intent_fixture!()
      assert {:error, %{reason: "not_found"}} = connect_and_join(%User{id: -1}, intent.id)
    end
  end

  describe "broadcast_settlement/2" do
    setup do
      {user, intent} = payment_intent_fixture!()
      {:ok, _reply, socket} = connect_and_join(user, intent.id)
      %{socket: socket, intent: intent}
    end

    test "pushes a success event when ResultCode is 0", %{intent: intent} do
      SettlementChannel.broadcast_settlement(intent.id, %{
        "ResultCode" => "0",
        "MpesaReceiptNumber" => "ABC123XYZ"
      })

      assert_broadcast("settled", %{status: "success", receipt: "ABC123XYZ"})
    end

    test "pushes a failure event for any non-zero ResultCode", %{intent: intent} do
      SettlementChannel.broadcast_settlement(intent.id, %{
        "ResultCode" => "1032",
        "MpesaReceiptNumber" => nil
      })

      assert_broadcast("settled", %{status: "failure"})
    end

    test "only reaches subscribers of the matching payment intent topic" do
      # Broadcast for a different transaction should NOT reach this socket.
      SettlementChannel.broadcast_settlement(Ecto.UUID.generate(), %{
        "ResultCode" => "0",
        "MpesaReceiptNumber" => "NOPE"
      })

      refute_broadcast("settled", %{receipt: "NOPE"})
    end
  end
end
