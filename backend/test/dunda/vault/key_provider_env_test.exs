defmodule Dunda.Vault.KeyProviderEnvTest do
  use ExUnit.Case, async: false

  alias Dunda.Vault.KeyProvider
  alias Dunda.Vault.KeyProvider.Env

  @valid_key Base.encode64(:crypto.strong_rand_bytes(32))

  setup do
    on_exit(fn ->
      System.delete_env("TEST_ONLY_KEY_VAR")
    end)
  end

  test "fetch_key/1 decodes a configured base64 key" do
    System.put_env("ENCRYPTION_KEY", @valid_key)
    on_exit(fn -> System.delete_env("ENCRYPTION_KEY") end)

    assert {:ok, decoded} = Env.fetch_key(:encryption_key)
    assert decoded == Base.decode64!(@valid_key)
  end

  test "fetch_key/1 returns :not_configured when the env var is unset" do
    System.delete_env("ENCRYPTION_KEY_PREVIOUS")
    assert {:error, :not_configured} = Env.fetch_key(:encryption_key_previous)
  end

  test "fetch_key/1 returns :not_configured for a blank string" do
    System.put_env("BLIND_INDEX_KEY", "")
    on_exit(fn -> System.delete_env("BLIND_INDEX_KEY") end)
    assert {:error, :not_configured} = Env.fetch_key(:blind_index_key)
  end

  test "fetch_key/1 returns :invalid_key_encoding for non-base64 values" do
    System.put_env("ENCRYPTION_KEY", "not base64 !!! ###")
    on_exit(fn -> System.delete_env("ENCRYPTION_KEY") end)
    assert {:error, :invalid_key_encoding} = Env.fetch_key(:encryption_key)
  end

  test "fetch_key/1 rejects an unknown key name" do
    assert {:error, :unknown_key} = Env.fetch_key(:not_a_real_key)
  end

  test "KeyProvider.fetch_key!/2 raises when the required key is absent" do
    System.delete_env("ENCRYPTION_KEY")

    assert_raise RuntimeError, ~r/could not resolve required key/, fn ->
      KeyProvider.fetch_key!(Env, :encryption_key)
    end
  end

  test "KeyProvider.fetch_key_optional/2 returns nil instead of raising when absent" do
    System.delete_env("ENCRYPTION_KEY_PREVIOUS")
    assert KeyProvider.fetch_key_optional(Env, :encryption_key_previous) == nil
  end

  test "KeyProvider.fetch_key_optional/2 returns the decoded key when present" do
    System.put_env("ENCRYPTION_KEY_PREVIOUS", @valid_key)
    on_exit(fn -> System.delete_env("ENCRYPTION_KEY_PREVIOUS") end)

    assert KeyProvider.fetch_key_optional(Env, :encryption_key_previous) ==
             Base.decode64!(@valid_key)
  end
end
