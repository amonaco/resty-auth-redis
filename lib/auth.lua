--
-- Auth
--
-- A module that provides authentication and cache via Redis
-- 

local Auth = { _VERSION = '0.0.1' }
Auth.__index = Auth

local conf  = require "conf.service"
local http  = require "resty.http"
local cjson = require "cjson"
local redis = require "resty.redis"
local hash_ring = require "lib.hash_ring"

local hr = hash_ring:create(conf.redis.hosts)

setmetatable(Auth, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

-- authenticate using a redis cache
function Auth:check(device_id, token)

  ngx.log(ngx.STDERR, string.format("auth request for %s", device_id))

  -- get hash ring node for device_id
  local node = hr:get_node(device_id)
  local host, port = node:match("([^:]+):([^:]+)")

  -- connect to redis
  local red = redis:new()
  local ok, err = red:connect(host, port)
  if not ok then
    ngx.log(ngx.STDERR, "failed to connect to redis because: ", err)
    return
  end

  -- get key, token in the value
  local res, err = red:get(device_id .. ':' .. conf.redis.suffix)
  if not res then
    ngx.log(ngx.STDERR, "failed to get from redis because: ", err)
    return false
  end

  -- keep connection in cosocket pool
  local ok, err = red:set_keepalive(conf.redis.timeout, conf.redis.pool_size)
  if not res then
    ngx.log(ngx.STDERR, "failed to send connection to cosocket: ", err)
    return false
  end

  -- check if token matches, then return
  if res == token then
    ngx.log(ngx.STDERR, "token on redis hit, giving thumbs up")
    return true
  end

  -- not authenticated, prepare backend request 
  local data = {
    device_id = device_id,
    token = token
  }

  local httpc = http.new()
  local res, err = httpc:request_uri(conf.auth_backend, {
    method  = "POST",
    body    = cjson.encode(data),
    headers = {
      ["Content-Type"] = "application/json",
    }
  })

  -- check there's an actual response
  if not res then
    ngx.log(ngx.STDERR, string.format("error while querying %s because %s",
      conf.auth_backend, err))
    return false
  end

  -- check response code
  if res.status == 200 then

    local data = cjson.decode(res.body)
    local doorbot_id = data.doorbot_id

    self:set_key(doorbot_id, token, data) -- set key for next request
    return true, data
  else
    return false
  end
end

-- method for storing a token
function Auth:set_key(client_id, token)

  local node = hr:get_node(device_id)
  local host, port = node:match("([^:]+):([^:]+)")

  -- connect to redis
  local red = redis:new()
  local ok, err = red:connect(host, port)

  local key_token = client_id .. ':' .. 'token'
  local key_data  = client_id .. ':' .. 'data'

  -- set keys and expiry atomically
  red:multi()

  red:set(key_token, token)
  red:expire(key_token, conf.redis.key_expiry)
  red:set(key_data, ngx.encode_base64(data))
  red:expire(key_data, conf.redis.key_expiry)

  ok, err = red:exec()
  if not ok then
    ngx.log(ngx.STDERR, "couldn't set key reason: ", err)
  end
end

return Auth
