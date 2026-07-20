defmodule Dunda.Accounts.ConsentTest do
  use Dunda.DataCase, async: true

  alias Dunda.Accounts

  defp insert_user! do
    n = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "consent-#{n}@example.com",
        "password" => "password123!",
        "name" => "Consent Test"
      })

    user
  end

  test "record_consent/3 grants and active_consent?/2 reflects it" do
    user = insert_user!()
    refute Accounts.active_consent?(user.id, "marketing_notifications")

    assert {:ok, consent} = Accounts.record_consent(user.id, "marketing_notifications", "v1")
    assert consent.purpose == "marketing_notifications"
    assert consent.version == "v1"
    assert is_nil(consent.revoked_at)
    assert Accounts.active_consent?(user.id, "marketing_notifications")
  end

  test "revoke_consent/2 revokes without deleting the historical row" do
    user = insert_user!()
    {:ok, consent} = Accounts.record_consent(user.id, "marketing_notifications", "v1")

    assert {:ok, revoked} = Accounts.revoke_consent(user.id, "marketing_notifications")
    assert revoked.id == consent.id
    assert %DateTime{} = revoked.revoked_at
    refute Accounts.active_consent?(user.id, "marketing_notifications")
    assert Repo.get!(Dunda.Accounts.Consent, consent.id)
  end

  test "revoke_consent/2 is a no-op when nothing is active" do
    user = insert_user!()
    assert {:ok, nil} = Accounts.revoke_consent(user.id, "marketing_notifications")
  end

  test "re-consenting after revocation creates a new row rather than mutating the old one" do
    user = insert_user!()
    {:ok, first} = Accounts.record_consent(user.id, "marketing_notifications", "v1")
    {:ok, _} = Accounts.revoke_consent(user.id, "marketing_notifications")
    {:ok, second} = Accounts.record_consent(user.id, "marketing_notifications", "v2")

    assert second.id != first.id
    assert second.version == "v2"
    assert Accounts.active_consent?(user.id, "marketing_notifications")

    reloaded_first = Repo.get!(Dunda.Accounts.Consent, first.id)
    assert reloaded_first.version == "v1"
    assert reloaded_first.revoked_at
  end

  test "record_consent/3 revokes an existing active grant before inserting the new one (enforces the DB uniqueness constraint)" do
    user = insert_user!()
    {:ok, first} = Accounts.record_consent(user.id, "marketing_notifications", "v1")
    {:ok, second} = Accounts.record_consent(user.id, "marketing_notifications", "v2")

    assert second.id != first.id
    assert Repo.get!(Dunda.Accounts.Consent, first.id).revoked_at
    assert Accounts.active_consent?(user.id, "marketing_notifications")
  end
end
