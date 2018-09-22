--
-- Simple hash-ring routines inspired in Ruby Redis library
-- This is compatible and generates the same hashes
-- 

local crc32 = require "lib.crc32"
local _M = { _VERSION = '0.0.1' }

_M.__index = _M

setmetatable(_M, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function _M:create(nodes)

  self.ring = {
    replicas = 160,
    ring = {},
    nodes = {},
    sorted_keys = {}
  }

  for i, node in pairs(nodes) do
    self:add_node(node)
  end

  return self
end

function _M:add_node(node)

  table.insert(self.ring.nodes, node)

  for i = 1, self.ring.replicas, 1 do
    local key = crc32.hash(node .. ":" .. i - 1)
    self.ring.ring[key] = node

    table.insert(self.ring.sorted_keys, key)

  end
  table.sort(self.ring.sorted_keys)
end

function _M:binary_search(ary, value)
  local upper = #ary - 1
  local lower = 0
  local idx = 0

  while lower <= upper do
    idx = math.floor((lower + upper) / 2)

    if ary[idx] == value then
      return idx
    elseif ary[idx] > value then
      upper = idx - 1
    elseif ary[idx] < value then
      lower = idx + 1
    end
  end

  if upper < 0 then
    upper = #ary - 1
  end
  return upper
end

function _M:get_node(key)
  crc = crc32.hash(key)
  idx = self:binary_search(self.ring.sorted_keys, crc)
  return self.ring.ring[self.ring.sorted_keys[idx]]
end

return _M


