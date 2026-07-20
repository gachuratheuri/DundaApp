defmodule Dunda.Vault.RotationTest do
  use Dunda.DataCase, async: true

  alias Dunda.Accounts.User
  alias Dunda.Billing.Order
  alias Dunda.Events.Event
  alias Dunda.Vault.Rotation

  defp unique, do: System.unique_integer([:positive])

  defp insert_phone_user! do
    n = unique()

    {:ok, user} =
      %User{}
      |> User.changeset(%{phone_msisdn: "25471234#{n}", device_fingerprint: "device-#{n}"})
      |> Repo.insert()

    user
  end

  defp insert_event! do
    n = unique()

    {:ok, event} =
      Event.changeset(%Event{}, %{
        name: "Rotation Test #{n}",
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

  test "reencrypt_all/0 re-saves every encrypted field without changing the decrypted value" do
    user = insert_phone_user!()
    event = insert_event!()

    {:ok, order} =
      Order.create_changeset(%Order{}, %{
        merchant_reference: "rotation-test-#{unique()}",
        amount_cents: 1_000,
        event_id: event.id,
        phone_encrypted: "254799999999",
        idempotency_key: String.duplicate("r", 16)
      })
      |> Repo.insert()

    results = Rotation.reencrypt_all()

    assert %{migrated: user_migrated, failed: 0} = results[User]
    assert user_migrated >= 1
    assert %{migrated: order_migrated, failed: 0} = results[Order]
    assert order_migrated >= 1

    reloaded_user = Repo.get!(User, user.id)
    assert reloaded_user.phone_msisdn == user.phone_msisdn
    assert reloaded_user.device_fingerprint == user.device_fingerprint

    reloaded_order = Repo.get!(Order, order.id)
    assert reloaded_order.phone_encrypted == "254799999999"
  end

  test "reencrypt_all/0 skips rows with no non-nil encrypted fields without error" do
    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "rotation-nophone-#{unique()}@example.com",
        "password" => "password123!",
        "name" => "No Phone"
      })

    results = Rotation.reencrypt_all()
    assert results[User].failed == 0
    refute is_nil(Repo.get!(User, user.id))
  end

  test "rehash_blind_index/0 recomputes the hash from the independently-stored plaintext" do
    user = insert_phone_user!()
    original_hash = user.phone_msisdn_hash

    assert %{migrated: migrated, failed: 0} = Rotation.rehash_blind_index()
    assert migrated >= 1

    reloaded = Repo.get!(User, user.id)
    # Same secret configured in test.exs => rehash under the same key
    # reproduces the same hash bytes (idempotent), and the plaintext this
    # hash is derived from is unchanged.
    assert reloaded.phone_msisdn_hash == original_hash
    assert reloaded.phone_msisdn == user.phone_msisdn
  end
end
