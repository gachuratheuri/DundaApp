defmodule Dunda.Billing.Setup do
  @moduledoc """
  One-time / idempotent Pesapal IPN bootstrap and the durable resolution of the
  registered `ipn_id`.

  ## Four-level resolution (`ipn_id/0`)

      Priority 1: PESAPAL_IPN_ID env var        ← always set this in production
      Priority 2: Application env (ETS cache)   ← set by setup_ipn/0, lost on restart
      Priority 3: billing_config DB table       ← set by setup_ipn/0, survives restart
      Priority 4: nil → orders fail immediately ← never reached if Priority 1 is set

  Deploy-time command:

      Dunda.Billing.Setup.setup_ipn()

  registers the IPN URL, writes the returned id to BOTH the DB and the ETS cache,
  and prints platform-specific commands to pin it as `PESAPAL_IPN_ID`. Run
  `verify_ipn/0` afterwards to confirm via `GetIpnList`.
  """
  require Logger

  import Ecto.Query, only: [from: 2]

  alias Dunda.Billing.{Config, Pesapal}
  alias Dunda.Repo

  @db_key "pesapal_ipn_id"

  @doc "Resolve the active Pesapal IPN id across the four fallback levels."
  @spec ipn_id() :: String.t() | nil
  def ipn_id do
    env_ipn_id() || app_env_ipn_id() || db_ipn_id()
  end

  @doc """
  Register the configured IPN URL with Pesapal, persist the returned id to the
  DB + ETS cache, and print pinning instructions. Idempotent: re-running simply
  registers again and refreshes the stored id.
  """
  @spec setup_ipn() :: {:ok, String.t()} | {:error, term()}
  def setup_ipn do
    url = config(:ipn_url) || raise "PESAPAL_IPN_URL is not configured"

    case Pesapal.register_ipn(url) do
      {:ok, ipn_id} ->
        Application.put_env(:dunda, :pesapal_ipn_id, ipn_id)
        put_db_config(@db_key, ipn_id)
        print_instructions(ipn_id)
        {:ok, ipn_id}

      {:error, reason} = err ->
        Logger.error("setup_ipn failed: #{inspect(reason)}")
        err
    end
  end

  @doc "Confirm our `ipn_id` is present in Pesapal's `GetIpnList`."
  @spec verify_ipn() :: {:ok, map()} | {:error, term()}
  def verify_ipn do
    case Pesapal.list_ipns() do
      {:ok, list} ->
        id = ipn_id()
        registered? = Enum.any?(list, &(&1["ipn_id"] == id))
        {:ok, %{ipn_id: id, registered: registered?, total_registered: length(list)}}

      {:error, reason} = err ->
        Logger.error("verify_ipn failed: #{inspect(reason)}")
        err
    end
  end

  # ── Resolution levels ────────────────────────────────────────────────────────

  defp env_ipn_id do
    blank_to_nil(System.get_env("PESAPAL_IPN_ID")) || blank_to_nil(config(:ipn_id))
  end

  defp app_env_ipn_id, do: Application.get_env(:dunda, :pesapal_ipn_id)

  defp db_ipn_id do
    case Repo.one(from c in Config, where: c.key == ^@db_key, select: c.value) do
      nil -> nil
      value -> value
    end
  rescue
    _ -> nil
  end

  # ── DB upsert ────────────────────────────────────────────────────────────────

  defp put_db_config(key, value) do
    %Config{}
    |> Config.changeset(%{key: key, value: value})
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp config(key) do
    Application.get_env(:dunda, :pesapal, []) |> Keyword.get(key)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp print_instructions(ipn_id) do
    IO.puts("""

    ────────────────────────────────────────────────────────────────────────
     Pesapal IPN registered. ipn_id = #{ipn_id}

     Pin it as PESAPAL_IPN_ID so it survives restarts WITHOUT a DB read:

       fly:    fly secrets set PESAPAL_IPN_ID=#{ipn_id}
       render: set PESAPAL_IPN_ID=#{ipn_id} in the dashboard env
       vps:    echo 'PESAPAL_IPN_ID=#{ipn_id}' >> .env

     It has also been written to the billing_config table (survives restart)
     and the Application env (ETS cache, lost on restart).
    ────────────────────────────────────────────────────────────────────────
    """)
  end
end
