-- Builds a block of data for a known address: the game's structs, laid out
-- one after the other, with pointers to each other.

local M = {}
M.__index = M

function M.new(base)
  return setmetatable({ base = base, parts = {}, size = 0 }, M)
end

-- The address the next byte goes to.
function M:addr() return self.base + self.size end

function M:raw(s)
  self.parts[#self.parts + 1] = s
  self.size = self.size + #s
  return self
end

function M:align(n)
  local r = self.size % n
  if r ~= 0 then self:raw(string.rep("\0", n - r)) end
  return self
end

function M:u8(v) return self:raw(string.pack("<I1", v & 0xff)) end
function M:u16(v) return self:raw(string.pack("<I2", v & 0xffff)) end
function M:u32(v) return self:raw(string.pack("<I4", v & 0xffffffff)) end

-- A list of halfwords (a condition or action list); returns its address.
function M:u16s(list)
  self:align(4)
  local at = self:addr()
  for _, v in ipairs(list) do self:u16(v) end
  self:align(4)
  return at
end

function M:data() return table.concat(self.parts) end

return M
