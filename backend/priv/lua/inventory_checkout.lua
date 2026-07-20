local inv_key         = KEYS[1]
local escrow_key      = KEYS[2]
local user_escrow_key = KEYS[3]
local transaction_id  = ARGV[1]
local quantity        = tonumber(ARGV[2])
local ttl_ms          = tonumber(ARGV[3])
local user_id         = ARGV[4]

-- If this user has an active escrow in progress (locked), deny checkout
if redis.call("EXISTS", user_escrow_key) == 1 then
  return -2 -- duplicate_escrow_attempt
end

local available = tonumber(redis.call("GET", inv_key) or "0")
if available >= quantity then
  redis.call("DECRBY", inv_key, quantity)
  redis.call("HSET", escrow_key, transaction_id, quantity)

  -- Create an expiry key that we can listen to with keyspace notifications
  local expiry_key = "expiry:" .. escrow_key .. ":" .. transaction_id
  redis.call("SET", expiry_key, "1", "PX", ttl_ms)

  -- Acquire the concurrent user escrow lock
  redis.call("SET", user_escrow_key, transaction_id, "PX", ttl_ms)

  -- Map the transaction_id to the user_id so release/commit can clear the user lock
  local tx_user_key = "tx_user:" .. transaction_id
  redis.call("SET", tx_user_key, user_id, "PX", ttl_ms)

  return 1 -- ok
else
  return -1 -- insufficient_inventory
end
