defmodule Dunda.Logging.Redactor do
  @moduledoc """
  Application-wide `:logger` primary filter plus a `redact/1` helper for call
  sites that must `inspect/1` a payload that may carry PII, credentials, or
  provider secrets before it is safe to log.

  This is defence-in-depth, not the primary control. The primary control is
  not putting the raw value in a log call in the first place — see the fixed
  call sites listed in `docs/phase_11_privacy_governance.md` § Log redaction
  (`Dunda.Billing.Pesapal.HTTP` and `Dunda.Payments.Daraja.HTTP`). The installed
  filter redacts *structured* metadata (`Logger.metadata/1`, report-style log
  calls) reliably by key name; it cannot parse arbitrary sensitive substrings
  out of an already-interpolated string with certainty, so `redact/1` also
  applies a best-effort regex scrub (bearer/JWT tokens, Kenyan MSISDNs) to
  binary values as a second layer.

  The key list extends `Dunda.Audit.record/1`'s redaction set — both should
  be kept in sync; audit metadata and application logs are different
  surfaces but carry overlapping risk.
  """

  @sensitive_keys ~w(
    password token authorization cookie otp secret passkey consumer_secret
    receipt msisdn phone mpesa bearer jwt api_key apikey security_credential
    b2c_security_credential phone_number phonenumber
  )

  @bearer_pattern ~r/Bearer\s+[A-Za-z0-9\-_\.]+/
  @jwt_pattern ~r/eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+/
  @msisdn_pattern ~r/\b2547\d{8}\b/

  @doc "Installs the global :logger primary filter. Called once from Dunda.Application.start/2."
  @spec install() :: :ok
  def install do
    case :logger.add_primary_filter(:dunda_redactor, {&__MODULE__.filter/2, []}) do
      :ok -> :ok
      # Already installed (e.g. hot code reload in dev) — not fatal.
      {:error, {:already_exist, _}} -> :ok
    end
  end

  @doc "Erlang :logger primary filter callback: redacts structured metadata on every log event."
  @spec filter(:logger.log_event(), term()) :: :logger.log_event()
  def filter(%{meta: meta} = log_event, _extra) when is_map(meta) do
    %{log_event | meta: redact(meta)}
  end

  def filter(log_event, _extra), do: log_event

  @doc """
  Redacts sensitive keys (by name) and scrubs likely-sensitive substrings
  from maps, lists, and strings. Safe to call on any term — non-matching
  values pass through unchanged.
  """
  @spec redact(term()) :: term()
  def redact(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, val} ->
      {key, if(sensitive_key?(key), do: "[REDACTED]", else: redact(val))}
    end)
  end

  def redact(value) when is_list(value), do: Enum.map(value, &redact/1)
  def redact(value) when is_binary(value), do: scrub_string(value)
  def redact(value), do: value

  defp sensitive_key?(key) do
    key_string = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive_keys, &String.contains?(key_string, &1))
  end

  defp scrub_string(value) do
    value
    |> String.replace(@bearer_pattern, "Bearer [REDACTED]")
    |> String.replace(@jwt_pattern, "[REDACTED_JWT]")
    |> String.replace(@msisdn_pattern, "[REDACTED_MSISDN]")
  end
end
