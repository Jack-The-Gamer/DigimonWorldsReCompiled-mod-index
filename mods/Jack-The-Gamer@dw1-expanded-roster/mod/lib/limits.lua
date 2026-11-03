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

-- A Digimon's size: initializeDigimonObject (0x800A0E68) gives the root
-- bone a scale of 0x1000, or 0x1800 for type 0x71; both paths meet at
-- 0x800A1094 with the type in s4 and the root PositionData in s1 (scale
-- words at +96/+100/+104). The root's scale reaches every bone (their
-- matrices are chained), so a new Digimon built on a smaller donor's
-- skeleton grows evenly, joints included. type -> scale (4096 = 1).
M.root_scale = {}
local ROOT_SCALE_SET = 0x800A1094

function M.install()
  dwrc.on_exec(HAS_DIGIMON_RAISED, function(ctx)
    if (ctx:reg("a0") & 0xFFFF) < 180 then return false end
    ctx:ret(0)
    return true
  end)
  dwrc.on_exec(ROOT_SCALE_SET, function(ctx)
    local s = M.root_scale[ctx:reg("s4")]
    if s then
      local root = ctx:reg("s1")
      ctx:write32(root + 96, s); ctx:write32(root + 100, s); ctx:write32(root + 104, s)
    end
    return false
  end)
end

return M
