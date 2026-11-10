-- An overlay file (AAA/PRO/*.PRO) changed while the mod loads: words of its
-- code or data patched, and a block of the mod's own data or code appended.
-- The game copies an overlay to its address in whole sectors
-- (loadModeOverlay: the file table's sector count x 2048), so what is
-- appended after the original sectors lands right behind the overlay in
-- RAM, every time the overlay loads, as long as it stays below `limit` (the
-- next area: the stages' at 0x800A5DE0 for the mode overlays).

local bin = require("lib.bin")
local blob = require("lib.blob")
local disc = require("lib.disc")

local M = {}
M.__index = M

function M.open(file, base, limit)
  local data = disc.read_file(file)
  local o = setmetatable({ file = file, base = base, limit = limit, data = data }, M)
  o.ext = blob.new(base + #data)   -- the appended block, right after the original sectors
  return o
end

function M:off(addr)
  local o = addr - self.base
  assert(o >= 0 and o + 4 <= #self.data, string.format("%08x is outside overlay file %d", addr, self.file))
  return o
end

function M:read32(addr) return bin.u32(self.data, self:off(addr)) end

function M:read(addr, n)
  local o = self:off(addr)
  return self.data:sub(o + 1, o + n)
end

function M:patch32(addr, expect, value)
  local v = self:read32(addr)
  if expect ~= nil and v ~= expect then
    error(string.format("file %d: unexpected code at %08x: %08x, not %08x (is this Digimon World 2003, Europe?)", self.file, addr, v, expect))
  end
  self.data = bin.put32(self.data, self:off(addr), value)
end

function M:commit()
  if self.ext.size > 0 then
    local endaddr = self.ext:addr()
    assert(endaddr <= self.limit, string.format("file %d: the mod's block ends at %08x, past %08x", self.file, endaddr, self.limit))
  end
  disc.replace_file(self.file, self.data .. self.ext:data())
end

return M
