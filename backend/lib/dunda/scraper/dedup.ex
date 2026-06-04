defmodule Dunda.Scraper.Dedup do
  @moduledoc """
  In-memory scalable Bloom filter used as a *cheap pre-filter* in front of the
  authoritative DB unique index.

  Flow: `Bloom → DB`. If the bloom says "definitely new" we skip a DB round-trip
  on the hot path; anything the bloom flags as "maybe seen" still falls through
  to the idempotent `ON CONFLICT` upsert, so a bloom false-positive can never
  silently drop a genuinely new event (the upsert is the source of truth).

  The filter is process-local and resets on restart — that is acceptable because
  the DB constraint guarantees correctness; the bloom only saves work.
  """
  use GenServer

  @capacity 50_000
  @false_positive 0.001

  # ── Client ───────────────────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Returns `true` and records `key` if it has not been seen before this runtime;
  returns `false` if the bloom believes it was already seen.

  When the GenServer is not running (e.g. test envs) every key is treated as new
  so the DB upsert remains the only correctness boundary.
  """
  @spec new?(String.t()) :: boolean()
  def new?(key) do
    case Process.whereis(__MODULE__) do
      nil -> true
      _pid -> GenServer.call(__MODULE__, {:new?, key})
    end
  end

  # ── Server ─────────────────────────────────────────────────────────────────

  @impl true
  def init(:ok) do
    {:ok, Bloomex.scalable(@capacity, @false_positive, 2, 0.9)}
  end

  @impl true
  def handle_call({:new?, key}, _from, filter) do
    if Bloomex.member?(filter, key) do
      {:reply, false, filter}
    else
      {:reply, true, Bloomex.add(filter, key)}
    end
  end
end
