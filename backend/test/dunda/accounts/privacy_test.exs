defmodule Dunda.Accounts.PrivacyTest do
  use ExUnit.Case, async: true

  alias Dunda.Accounts.User

  test "privacy pseudonymisation accepts the controlled email provider" do
    changeset =
      User.privacy_changeset(%User{}, %{
        email: "deleted-123@dunda.invalid",
        auth_provider: "email"
      })

    assert changeset.valid?
  end
end
