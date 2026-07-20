defmodule Dunda.Ticketing.InventoryPoolServer do
  @moduledoc """
  Per-pool serialisation point for inventory acquisition.

  One process per pool id (`"tier:<id>"` or `"event:<id>"`, see
  `Dunda.Inventory`), registered cluster-wide via `Horde.Registry`. The process
  seeds the Redis counter from Postgres on first use — always as
  `capacity - already_sold`, never raw capacity, so a lost Redis key can never
  resurrect sold inventory — and then serialises the atomic
  check+decrement+escrow Lua script.
  """
  use GenServer, restart: :transient
  require Logger

  alias Dunda.Inventory

  @lua_script File.read!("priv/lua/inventory_checkout.lua")
  @escrow_ttl_ms 300_000

  # ── Client API ──────────────────────────────────────────────────────────────

  def start_link(pool_id) do
    GenServer.start_link(__MODULE__, pool_id, name: via_tuple(pool_id))
  end

  def acquire_tickets(pool_id, owner_id, quantity, user_id) do
    ensure_started(pool_id)
    GenServer.call(via_tuple(pool_id), {:acquire, owner_id, quantity, user_id}, 5_000)
  catch
    :exit, {:timeout, _} -> {:error, :lock_timeout}
    :exit, {:noproc, _} -> {:error, :server_unavailable}
  end

  # ── Private Helpers ─────────────────────────────────────────────────────────

  defp ensure_started(pool_id) do
    case Horde.DynamicSupervisor.start_child(
           Dunda.InventorySupervisor,
           {__MODULE__, pool_id}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> raise "Failed to start InventoryPoolServer: #{inspect(error)}"
    end
  end

  defp via_tuple(pool_id) do
    {:via, Horde.Registry, {Dunda.InventoryRegistry, "pool:#{pool_id}"}}
  end

  # ── GenServer Callbacks ──────────────────────────────────────────────────────

  @impl true
  def init(pool_id) do
    state = %{
      pool_id: pool_id,
      inv_key: Inventory.inventory_key(pool_id),
      escrow_key: Inventory.escrow_key(pool_id),
      script_sha1: nil
    }

    # Defer Redis I/O out of init/1 so a slow or unavailable Redis cannot block
    # the (distributed) supervisor that is starting us.
    {:ok, state, {:continue, :load_script}}
  end

  @impl true
  def handle_continue(:load_script, state) do
    seed_inventory_if_missing(state)

    case Redix.command(:redix, ["SCRIPT", "LOAD", @lua_script]) do
      {:ok, sha1} ->
        {:noreply, %{state | script_sha1: sha1}}

      error ->
        Logger.warning(
          "[InventoryPool] SCRIPT LOAD failed, will EVAL on demand: #{inspect(error)}"
        )

        {:noreply, state}
    end
  end

  # Seed the live counter from Postgres truth: capacity minus tickets already
  # issued. Seeding raw capacity would resell sold inventory whenever Redis
  # loses the key (eviction, restart without persistence, failover).
  defp seed_inventory_if_missing(state) do
    case Redix.command(:redix, ["EXISTS", state.inv_key]) do
      {:ok, 0} ->
        case initial_count(state.pool_id) do
          {:ok, count} ->
            case Redix.command(:redix, ["SET", state.inv_key, to_string(count), "NX"]) do
              {:ok, _} -> :ok
              {:error, reason} ->
                Logger.error("[InventoryPool] failed to SET counter for #{state.inv_key}: #{inspect(reason)}")
                raise "failed to seed inventory counter: #{inspect(reason)}"
            end

          {:error, reason} ->
            Logger.error(
              "[InventoryPool] cannot seed #{state.inv_key}: #{inspect(reason)}"
            )
            raise "failed to compute initial count for seeding: #{inspect(reason)}"
        end

      {:ok, 1} ->
        :ok

      {:error, reason} ->
        Logger.error("[InventoryPool] failed to check EXISTS for #{state.inv_key}: #{inspect(reason)}")
        raise "failed to check existing inventory: #{inspect(reason)}"
    end
  end

  defp initial_count("tier:" <> tier_id) do
    case Dunda.Repo.get(Dunda.Ticketing.TicketTier, tier_id) do
      %Dunda.Ticketing.TicketTier{id: id, capacity: capacity} ->
        {:ok, max(capacity - Dunda.Ticketing.sold_count_for_tier(id), 0)}

      nil ->
        {:error, :unknown_tier}
    end
  rescue
    e -> {:error, e}
  end

  defp initial_count("event:" <> event_id), do: initial_count_for_event(event_id)
  # Legacy pool ids were raw event ids; keep them resolvable.
  defp initial_count(event_id), do: initial_count_for_event(event_id)

  defp initial_count_for_event(event_id) do
    case Dunda.Repo.get(Dunda.Events.Event, event_id) do
      %Dunda.Events.Event{id: id, capacity: capacity} ->
        {:ok, max(capacity - Dunda.Ticketing.sold_count_for_event(id), 0)}

      nil ->
        {:error, :unknown_event}
    end
  rescue
    e -> {:error, e}
  end

  @impl true
  def handle_call({:acquire, owner_id, quantity, user_id}, _from, state) do
    keys = [state.inv_key, state.escrow_key, "user_escrow:#{user_id}"]
    argv = [to_string(owner_id), to_string(quantity), to_string(@escrow_ttl_ms), to_string(user_id)]
    result = run_lua(state.script_sha1, keys, argv)
    {:reply, result, state}
  end

  # No cached SHA (Redis was unavailable at boot) — load it on demand via EVAL.
  defp run_lua(nil, keys, argv) do
    Redix.command(:redix, ["EVAL", @lua_script, length(keys)] ++ keys ++ argv)
    |> handle_lua_result()
  end

  defp run_lua(sha1, keys, argv) do
    case Redix.command(:redix, ["EVALSHA", sha1, length(keys)] ++ keys ++ argv) do
      {:error, %Redix.Error{message: "NOSCRIPT" <> _}} ->
        Redix.command(:redix, ["EVAL", @lua_script, length(keys)] ++ keys ++ argv)
        |> handle_lua_result()

      result ->
        handle_lua_result(result)
    end
  end

  defp handle_lua_result({:ok, 1}), do: :ok
  defp handle_lua_result({:ok, -1}), do: {:error, :insufficient_inventory}
  defp handle_lua_result({:ok, -2}), do: {:error, :duplicate_escrow_attempt}

  defp handle_lua_result(error) do
    Logger.error("[InventoryPool] Redis failure: #{inspect(error)}")
    {:error, :redis_failed}
  end
end
