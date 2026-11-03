-- The files in the disc's root directory (ISO 9660), read from the virtual
-- disc while the mod loads. Digimon World keeps its executable and every
-- overlay (BTL_REL.BIN, STD_REL.BIN, ...) there.

local bin = require("lib.bin")

local M = {}

local root = nil

-- name (without ";1") -> { lba, size }
function M.root()
  if root then return root end
  local pvd = dwrc.disc.read(16)
  assert(pvd:sub(2, 6) == "CD001", "no ISO 9660 volume on this disc")
  local lba, size = bin.u32(pvd, 156 + 2), bin.u32(pvd, 156 + 10)
  local dir = dwrc.disc.read(lba, (size + 2047) // 2048)
  root = {}
  local o = 0
  while o < #dir do
    local len = bin.u8(dir, o)
    if len == 0 then
      o = (o // 2048 + 1) * 2048 -- records don't cross sectors
    else
      local nlen = bin.u8(dir, o + 32)
      local name = dir:sub(o + 34, o + 33 + nlen):gsub(";1$", "")
      root[name] = { lba = bin.u32(dir, o + 2), size = bin.u32(dir, o + 10) }
      o = o + len
    end
  end
  return root
end

-- A root file's whole sectors (its data then the rest of the last sector),
-- its LBA and its size.
function M.read(name)
  local f = assert(M.root()[name], name .. " is not on the disc")
  return dwrc.disc.read(f.lba, (f.size + 2047) // 2048), f.lba, f.size
end

return M
