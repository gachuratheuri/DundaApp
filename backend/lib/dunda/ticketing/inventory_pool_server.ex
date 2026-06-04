defmodule Dunda.Ticketing.InventoryPoolServer do
  use GenServer, restart: :transient
  require Logger

  @lua_script File.read!("priv/lua/inventory_checkout.lua")
  @escrow_ttl_ms 300_000

  # ── Client API ──────────────────────────────────────────────────────────────

  def start_link(ticket_tier_id) do
    GenServer.start_link(__MODULE__, ticket_tier_id, name: via_tuple(ticket_tier_id))
  end

  def acquire_tickets(ticket_tier_id, user_id, quantity) do
    ensure_started(ticket_tier_id)
    GenServer.call(via_tuple(ticket_tier_id), {:acquire, user_id, quantity}, 5_000)
  catch
    :exit, {:timeout, _} -> {:error, :lock_timeout}
    :exit, {:noproc, _}  -> {:error, :server_unavailable}
  end

  def release_escrow(ticket_tier_id, user_id) do
    GenServer.cast(via_tuple(ticket_tier_id), {:release, user_id})
  end

  # ── Private Helpers ─────────────────────────────────────────────────────────

  defp ensure_started(ticket_tier_id) do
    case Horde.DynamicSupervisor.start_child(
      Dunda.InventorySupervisor,
      {__MODULE__, ticket_tier_id}
    ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> raise "Failed to start InventoryPoolServer: #{inspect(error)}"
    end
  end

  defp via_tuple(ticket_tier_id) do
    {:via, Horde.Registry, {Dunda.InventoryRegistry, "pool:#{ticket_tier_id}"}}
  end

  # ── GenServer Callbacks ──────────────────────────────────────────────────────

  @impl true
  def init(ticket_tier_id) do
    state = %{
      ticket_tier_id: ticket_tier_id,
      inv_key: "inventory:#{ticket_tier_id}",
      escrow_key: "escrow:#{ticket_tier_id}",
      script_sha1: nil
    }

    # Defer Redis I/O out of init/1 so a slow or unavailable Redis cannot block
    # the (distributed) supervisor that is starting us.
    {:ok, state, {:continue, :load_script}}
  end

  @impl true
  def handle_continue(:load_script, state) do
    case Redix.command(:redix, ["SCRIPT", "LOAD", @lua_script]) do
      {:ok, sha1} ->
        {:noreply, %{state | script_sha1: sha1}}

      error ->
        Logger.warning("[InventoryPool] SCRIPT LOAD failed, will EVAL on demand: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:acquire, user_id, quantity}, _from, state) do
    keys = [state.inv_key, state.escrow_key]
    argv = [user_id, to_string(quantity), to_string(@escrow_ttl_ms)]
    result = run_lua(state.script_sha1, keys, argv, state)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:release, user_id}, state) do
    release_keys = [state.inv_key, state.escrow_key]
    release_argv = [user_id]
    Redix.command(:redix, ["EVAL", release_lua_script(), length(release_keys)] ++ release_keys ++ release_argv)
    {:noreply, state}
  end

  # No cached SHA (Redis was unavailable at boot) — load it on demand via EVAL.
  defp run_lua(nil, keys, argv, _state) do
    Redix.command(:redix, ["EVAL", @lua_script, length(keys)] ++ keys ++ argv)
    |> handle_lua_result()
  end

  defp run_lua(sha1, keys, argv, state) do
    case Redix.command(:redix, ["EVALSHA", sha1, length(keys)] ++ keys ++ argv) do
      {:ok, 1}  -> :ok
      {:ok, -1} -> {:error, :insufficient_inventory}
      {:ok, -2} -> {:error, :duplicate_escrow_attempt}
      {:error, %Redix.Error{message: "NOSCRIPT" <> _}} ->
        Redix.command(:redix, ["EVAL", @lua_script, length(keys)] ++ keys ++ argv)
        |> handle_lua_result()
      error ->
        Logger.error("[InventoryPool] Redis failure: #{inspect(error)}")
        {:error, :system_locking_timeout}
    end
  end

  defp handle_lua_result({:ok, 1}),  do: :ok
  defp handle_lua_result({:ok, -1}), do: {:error, :insufficient_inventory}
  defp handle_lua_result({:ok, -2}), do: {:error, :duplicate_escrow_attempt}
  defp handle_lua_result(_),         do: {:error, :redis_failed}

  defp release_lua_script do
    """
    local inv_key    = KEYS[1]
    local escrow_key = KEYS[2]
    local user_id    = ARGV[1]
    local qty = redis.call("HGET", escrow_key, user_id)
    if qty then
      redis.call("INCRBY", inv_key, tonumber(qty))
      redis.call("HDEL", escrow_key, user_id)
      redis.call("DEL", "expiry:" .. escrow_key .. ":" .. user_id)
    end
    return 1
    """
  end
end
