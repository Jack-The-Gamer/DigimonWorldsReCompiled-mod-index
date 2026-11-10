-- The overlays the mod changes, opened once and shared by the parts of the
-- mod that patch them (an overlay is written back once, by commit()), and
-- word patches by file ("exe" or an overlay's number).

local disc = require("lib.disc")
local eu = require("lib.eu")
local overlay = require("lib.overlay")

local M = {}

local open, order = {}, {}

-- Overlay `n`: a mode overlay (at OVERLAY_VRAM, up to the stages' area) or,
-- for eu.STAGE_FILES, a stage overlay (at STAGE_VRAM, up to the heap).
function M.overlay(n)
  local o = open[n]
  if not o then
    if eu.STAGE_FILES[n] then
      o = overlay.open(n, eu.STAGE_VRAM, eu.HEAP_START)
    else
      o = overlay.open(n, eu.OVERLAY_VRAM, eu.STAGE_VRAM)
    end
    open[n] = o
    order[#order + 1] = n
  end
  return o
end

function M.read32(file, addr)
  if file == "exe" then return disc.exe_read32(addr) end
  return M.overlay(file):read32(addr)
end

-- Writes a word after checking that it holds `expect`.
function M.patch32(file, addr, expect, value)
  if file == "exe" then
    disc.exe_patch32(addr, expect, value)
  else
    M.overlay(file):patch32(addr, expect, value)
  end
end

-- Writes the changed overlays to the virtual disc.
function M.commit()
  for _, n in ipairs(order) do open[n]:commit() end
end

return M
