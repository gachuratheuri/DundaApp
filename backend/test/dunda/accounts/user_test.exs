defmodule Dunda.Accounts.UserTest do
  use ExUnit.Case, async: true

  alias Dunda.Accounts.User

  describe "changeset/2" do
    test "requires a phone number" do
      changeset = User.changeset(%User{}, %{})
      refute changeset.valid?
      assert %{phone_msisdn: ["can't be blank"]} = errors(changeset)
    end

    test "derives the blind-index hash from the msisdn" do
      changeset = User.changeset(%User{}, %{phone_msisdn: "254712345678"})
      assert changeset.valid?
      assert get_change(changeset, :phone_msisdn_hash) == "254712345678"
    end

    test "rejects an unknown kyc_status" do
      changeset = User.changeset(%User{}, %{phone_msisdn: "254712345678", kyc_status: "bogus"})
      refute changeset.valid?
      assert %{kyc_status: ["is invalid"]} = errors(changeset)
    end
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp get_change(changeset, field), do: Ecto.Changeset.get_change(changeset, field)
end
