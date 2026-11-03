-- The files in a disc's root directory (ISO 9660), read while the mod loads:
-- Digimon World's own disc (the virtual disc: its executable and every
-- overlay are there) or another game's (`M.disc(read)` with a sector reader
-- such as dwrc.discs.read for Digimon World 2003, whose executable is the
-- only real file).

local bin = require("lib.bin")

local M = {}

local Disc = {}
Disc.__index = Disc

-- read(lba, count) -> the sectors' 2048-byte data
function M.disc(read) return setmetatable({ read_sectors = read }, Disc) end

-- name (without ";1") -> { lba, size }
function Disc:root()
  if self.files then return self.files end
  local pvd = self.read_sectors(16, 1)
  assert(pvd:sub(2, 6) == "CD001", "no ISO 9660 volume on this disc")
  local lba, size = bin.u32(pvd, 156 + 2), bin.u32(pvd, 156 + 10)
  local dir = self.read_sectors(lba, (size + 2047) // 2048)
  local files = {}
  local o = 0
  while o < #dir do
    local len = bin.u8(dir, o)
    if len == 0 then
      o = (o // 2048 + 1) * 2048 -- records don't cross sectors
    else
      local nlen = bin.u8(dir, o + 32)
      local name = dir:sub(o + 34, o + 33 + nlen):gsub(";1$", "")
      files[name] = { lba = bin.u32(dir, o + 2), size = bin.u32(dir, o + 10) }
      o = o + len
    end
  end
  self.files = files
  return files
end

-- A root file's whole sectors (its data then the rest of the last sector),
-- its LBA and its size.
function Disc:read(name)
  local f = assert(self:root()[name], name .. " is not on the disc")
  return self.read_sectors(f.lba, (f.size + 2047) // 2048), f.lba, f.size
end

-- Digimon World's own (virtual) disc.
local own = M.disc(function(lba, count) return dwrc.disc.read(lba, count) end)
function M.root() return own:root() end
function M.read(name) return own:read(name) end

return M
