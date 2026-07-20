defmodule Dunda.Ticketing.RevocationFilter do
  @moduledoc """
  A Counting Bloom Filter for managing the ticket revocation list.
  
  Standard Bloom Filters cannot support item deletion. Since users can receive
  refunds or transfer tickets, we need the ability to *un-revoke* or remove
  items from the offline sync payload without rebuilding the entire filter.
  
  This uses Erlang's `:atomics` for extreme high-concurrency, lock-free 
  mutations across the BEAM.
  """

  # Define structure: capacity (number of buckets) and hashes (k)
  defstruct [:ref, :capacity, :hashes]

  @type t :: %__MODULE__{}

  @doc """
  Creates a new Counting Bloom Filter.
  `capacity` is the number of integer buckets (e.g., 100,000).
  `hashes` is the number of hash functions to apply (k).
  """
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(capacity \\ 100_000, hashes \\ 4) do
    # :atomics requires 1-based indexing
    ref = :atomics.new(capacity, [{:signed, false}])
    %__MODULE__{ref: ref, capacity: capacity, hashes: hashes}
  end

  @doc "Adds an item to the counting bloom filter."
  @spec add(t(), String.t()) :: :ok
  def add(%__MODULE__{} = filter, item) do
    for index <- hash_indices(filter, item) do
      :atomics.add(filter.ref, index, 1)
    end
    :ok
  end

  @doc "Removes an item. Standard Bloom Filters can't do this!"
  @spec remove(t(), String.t()) :: :ok
  def remove(%__MODULE__{} = filter, item) do
    for index <- hash_indices(filter, item) do
      decrement_counter(filter.ref, index)
    end
    :ok
  end

  defp decrement_counter(ref, index) do
    current = :atomics.get(ref, index)
    if current > 0 do
      case :atomics.compare_exchange(ref, index, current, current - 1) do
        ^current -> :ok
        _expected_value_changed -> decrement_counter(ref, index)
      end
    else
      :ok
    end
  end

  @doc "Checks if an item is possibly in the set."
  @spec member?(t(), String.t()) :: boolean()
  def member?(%__MODULE__{} = filter, item) do
    Enum.all?(hash_indices(filter, item), fn index ->
      :atomics.get(filter.ref, index) > 0
    end)
  end

  @doc """
  Serializes the counting bloom filter down to a highly compressed standard 
  bit-array (Binary).
  
  The gate scanners (e.g., GateScannerActivity.kt) only need to perform `member?`
  checks offline; they do not remove items. Thus, we can compress the 64-bit 
  counters down to 1-bit booleans (count > 0 -> 1, count == 0 -> 0), minimizing 
  the pre-event sync payload over slow 3G networks.
  """
  @spec serialize_to_bit_array(t()) :: binary()
  def serialize_to_bit_array(%__MODULE__{} = filter) do
    # Build a bitstring by checking if each counter > 0
    for i <- 1..filter.capacity, into: <<>> do
      if :atomics.get(filter.ref, i) > 0 do
        <<1::1>>
      else
        <<0::1>>
      end
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────────────

  defp hash_indices(filter, item) do
    # We use phash2 with salting to simulate k independent hash functions
    # Returns 1-based indices for :atomics compatibility
    Enum.map(1..filter.hashes, fn seed ->
      # phash2 returns an integer between 0 and capacity-1
      val = :erlang.phash2({seed, item}, filter.capacity)
      val + 1
    end)
  end
end
