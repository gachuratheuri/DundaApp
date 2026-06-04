local inv_key    = KEYS[1]
local escrow_key = KEYS[2]
local user_id    = ARGV[1]
local quantity   = tonumber(ARGV[2])
local ttl_ms     = tonumber(ARGV[3])

if redis.call("HEXISTS", escrow_key, user_id) == 1 then
  return -2 -- duplicate_escrow_attempt
end

local available = tonumber(redis.call("GET", inv_key) or "0")
if available >= quantity then
  redis.call("DECRBY", inv_key, quantity)
  redis.call("HSET", escrow_key, user_id, quantity)
  
  -- Create an expiry key that we can listen to with keyspace notifications
  local expiry_key = "expiry:" .. escrow_key .. ":" .. user_id
  redis.call("SET", expiry_key, "1", "PX", ttl_ms)
  
  return 1 -- ok
else
  return -1 -- insufficient_inventory
end
