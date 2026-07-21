defmodule Dunda.Security.Password do
  @moduledoc """
  Versioned PBKDF2-HMAC-SHA-256 password hashing using OTP's `:crypto`.

  The encoded form carries its algorithm and work factor so parameters can be
  increased through authenticated rehash-on-login without mutating historical
  assumptions. Verification bounds attacker-controlled parameters before any
  expensive derivation and compares equal-length digests in constant time.
  """

  @algorithm "pbkdf2_sha256"
  @iterations 210_000
  @minimum_iterations 100_000
  @maximum_iterations 1_000_000
  @salt_bytes 16
  @digest_bytes 32
  @dummy_salt :crypto.hash(:sha256, "dunda-password-dummy-salt") |> binary_part(0, @salt_bytes)

  @spec hash(String.t()) :: String.t()
  def hash(password) when is_binary(password) and byte_size(password) > 0 do
    salt = :crypto.strong_rand_bytes(@salt_bytes)
    digest = derive(password, salt, @iterations)

    Enum.join(
      [@algorithm, Integer.to_string(@iterations), Base.encode64(salt), Base.encode64(digest)],
      "$"
    )
  end

  @spec verify(String.t(), String.t()) :: boolean()
  def verify(password, encoded) when is_binary(password) and is_binary(encoded) do
    with [@algorithm, iterations_text, salt_text, digest_text] <- String.split(encoded, "$"),
         {iterations, ""} <- Integer.parse(iterations_text),
         true <- iterations in @minimum_iterations..@maximum_iterations,
         {:ok, salt} <- Base.decode64(salt_text),
         true <- byte_size(salt) >= @salt_bytes,
         {:ok, expected} <- Base.decode64(digest_text),
         true <- byte_size(expected) == @digest_bytes do
      actual = derive(password, salt, iterations)
      Plug.Crypto.secure_compare(actual, expected)
    else
      _ ->
        no_user_verify(password)
        false
    end
  end

  def verify(password, _encoded) when is_binary(password) do
    no_user_verify(password)
    false
  end

  def verify(_, _), do: false

  @doc "Performs equivalent work when an account/hash is absent or malformed."
  @spec no_user_verify(String.t()) :: :ok
  def no_user_verify(password) when is_binary(password) do
    _ = derive(password, @dummy_salt, @iterations)
    :ok
  end

  def no_user_verify(_), do: :ok

  defp derive(password, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @digest_bytes)
  end
end
