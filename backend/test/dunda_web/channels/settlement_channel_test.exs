defmodule DundaWeb.SettlementChannelTest do
  use DundaWeb.ChannelCase

  alias Dunda.Accounts.User
  alias DundaWeb.Auth.Token
  alias DundaWeb.SettlementChannel
  alias DundaWeb.UserSocket

  @transaction_id "tx_test_123"

  defp connect_and_join(transaction_id \\ @transaction_id) do
    token = Token.sign(%User{id: 1})
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    subscribe_and_join(socket, "settlement:#{transaction_id}", %{})
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
      assert {:ok, %{status: "pending"}, _socket} = connect_and_join()
    end
  end

  describe "broadcast_settlement/2" do
    setup do
      {:ok, _reply, socket} = connect_and_join()
      %{socket: socket}
    end

    test "pushes a success event when ResultCode is 0" do
      SettlementChannel.broadcast_settlement(@transaction_id, %{
        "ResultCode" => "0",
        "MpesaReceiptNumber" => "ABC123XYZ"
      })

      assert_broadcast "settled", %{status: "success", receipt: "ABC123XYZ"}
    end

    test "pushes a failure event for any non-zero ResultCode" do
      SettlementChannel.broadcast_settlement(@transaction_id, %{
        "ResultCode" => "1032",
        "MpesaReceiptNumber" => nil
      })

      assert_broadcast "settled", %{status: "failure"}
    end

    test "only reaches subscribers of the matching transaction topic" do
      # Broadcast for a different transaction should NOT reach this socket.
      SettlementChannel.broadcast_settlement("tx_other_999", %{
        "ResultCode" => "0",
        "MpesaReceiptNumber" => "NOPE"
      })

      refute_broadcast "settled", %{receipt: "NOPE"}
    end
  end
end
