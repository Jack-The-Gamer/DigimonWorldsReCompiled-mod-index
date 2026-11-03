-- The game's checks against its own number of Digimon, raised to the moved
-- tables' CAPACITY (SLUS-01032; functions named as in dw_decomp). Checks
-- that loop over the game's own roster (medals, the evolution chart, card
-- rolls) stay as they are, and so do compares with 62-66 that aren't about
-- Digimon (battle timers, screen positions, the sound library).

local tables = require("lib.tables")

local M = {}

-- address, the instruction there (slti/sltiu rt, rs, limit)
M.EXE = {
  { 0x800A1F98, 0x2A2100B4 }, -- loadMMD: type < 180
  { 0x800A258C, 0x288100B4 }, -- getEntityModelComponent: type < 180
  { 0x800A2840, 0x2A0100B4 }, -- loadMMDAsync: type < 180 (the evolution's next model)
  { 0x800A2A70, 0x2A2100B4 }, -- applyMMD: type < 180
  { 0x800C64F8, 0x2A010042 }, -- loadPartnerSounds: type < 66, else the default voice 15
  { 0x800E9188, 0x2A010042 }, -- loadVLALL (the evolution's voice): type <= 65, else voice 15
}

-- Adds the rewrites to `patch(addr, expect, value)`.
function M.patch_exe(patch)
  for _, p in ipairs(M.EXE) do
    patch(p[1], p[2], (p[2] & 0xFFFF0000) | tables.CAPACITY)
  end
end

-- hasDigimonRaised(type) is isTriggerSet(0x200 + type), and only the game's
-- first 63 types have such a flag (setDigimonRaised ignores the rest): a new
-- Digimon reads as never raised instead of reading some other flag.
local HAS_DIGIMON_RAISED = 0x800FF824

function M.install()
  dwrc.on_exec(HAS_DIGIMON_RAISED, function(ctx)
    if (ctx:reg("a0") & 0xFFFF) < 180 then return false end
    ctx:ret(0)
    return true
  end)
end

return M
