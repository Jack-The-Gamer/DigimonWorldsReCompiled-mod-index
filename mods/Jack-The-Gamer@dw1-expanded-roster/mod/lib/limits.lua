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

-- Techniques (lib/tables.lua). A finisher is any technique from 0x3A below
-- a bound, 0x71 in the game; these are every check of it in the US build
-- (dw_decomp: battle_main, std_main/std_setup, vs_main, vs_combat, evl,
-- partner_impl; 32 in C, 32 here: slti/sltiu rt, rs, 0x71), raised to
-- tables.FINISHER_END. The other compares with 113 aren't about techniques
-- (Digimon type 0x71, a rotation, screen positions).
local FINISHER_CHECKS = {
  { "SLUS_010.32", 0x800A46C8, 0x2CA10071 }, -- initializePartner
  { "SLUS_010.32", 0x800F5E34, 0x28A10071 }, -- VS__tickDigimonSenile
  { "BTL_REL.BIN", 0x80058734, 0x28A10071 }, -- BTL_tickEnemyAI
  { "BTL_REL.BIN", 0x8005A1AC, 0x28810071 }, -- BTL_tickMeleeAttack
  { "BTL_REL.BIN", 0x8005BCA4, 0x28E10071 }, -- BTL_calculateHitChance
  { "BTL_REL.BIN", 0x8005BFC4, 0x2A010071 }, -- BTL_calculateDamage
  { "BTL_REL.BIN", 0x8005C10C, 0x2A010071 }, -- BTL_calculateDamage
  { "BTL_REL.BIN", 0x8005D3D8, 0x28410071 }, -- BTL_isMoveUsable
  { "BTL_REL.BIN", 0x8005D824, 0x2A610071 }, -- BTL_startQueuedMove
  { "BTL_REL.BIN", 0x8005DB2C, 0x2A210071 }, -- BTL_setupMoveExecution
  { "BTL_REL.BIN", 0x8005DCC4, 0x2A210071 }, -- BTL_setupMoveExecution
  { "BTL_REL.BIN", 0x8005E050, 0x28410071 }, -- BTL_addFinisherProgress
  { "STD_REL.BIN", 0x8005729C, 0x28410071 }, -- STD_initializeOpponent
  { "STD_REL.BIN", 0x800574BC, 0x2C610071 }, -- STD_initializeOpponent
  { "STD_REL.BIN", 0x800601CC, 0x28A10071 }, -- STD_tickEnemyAI
  { "STD_REL.BIN", 0x80061D74, 0x28810071 }, -- STD_tickMeleeAttack
  { "STD_REL.BIN", 0x80063D6C, 0x28E10071 }, -- STD_applyPartnerStatsToFighter
  { "STD_REL.BIN", 0x80063FAC, 0x2A010071 }, -- STD_calculateDamage
  { "STD_REL.BIN", 0x800640F4, 0x2A010071 }, -- STD_calculateDamage
  { "STD_REL.BIN", 0x8006517C, 0x28410071 }, -- STD_isMoveUsable
  { "STD_REL.BIN", 0x800655C8, 0x2A610071 }, -- STD_startQueuedMove
  { "STD_REL.BIN", 0x800659AC, 0x2A010071 }, -- STD_setupMoveExecution
  { "STD_REL.BIN", 0x80065B44, 0x2A010071 }, -- STD_setupMoveExecution
  { "STD_REL.BIN", 0x80065E84, 0x28410071 }, -- STD_addFinisherProgress
  { "VS_REL.BIN",  0x8005B9F0, 0x28E10071 }, -- VS_applyPartnerStatsToFighter
  { "VS_REL.BIN",  0x8005BC20, 0x28C10071 }, -- VS_rollAttackOutcome
  { "VS_REL.BIN",  0x8005CB84, 0x28410071 }, -- VS_isMoveUsable
  { "VS_REL.BIN",  0x8005CF80, 0x2A610071 }, -- VS_startFighterMove
  { "VS_REL.BIN",  0x8005D364, 0x2A210071 }, -- VS_playMoveEffect
  { "VS_REL.BIN",  0x8005D384, 0x2A210071 }, -- VS_playMoveEffect
  { "VS_REL.BIN",  0x8005D868, 0x28410071 }, -- VS_addFinisherProgress
  { "EVL_REL.BIN", 0x80063A0C, 0x2C810071 }, -- EVL_applyEvolution
}
-- The generic attack, technique 0x79 (`tech = 0x79` in getAttackTech:
-- addiu v0, zero, 0x79), moves with the Bubbles past the finishers.
local GENERIC_ATTACK = {
  { "BTL_REL.BIN", 0x8005B7B8, 0x24020079 },
  { "STD_REL.BIN", 0x800638AC, 0x24020079 },
  { "VS_REL.BIN",  0x8005B530, 0x24020079 },
}
-- drawMoveName (Battle Mode slots) draws names of techniques < 0x79.
local NAME_CHECK = { "SLUS_010.32", 0x8010FC0C, 0x28410079 }

local function with_imm(w, v) return (w & 0xFFFF0000) | v end

-- Every rewrite: `patch(file, addr, expect, value)`.
function M.patch_code(patch)
  for _, p in ipairs(M.EXE) do patch("SLUS_010.32", p[1], p[2], with_imm(p[2], tables.CAPACITY)) end
  for _, p in ipairs(FINISHER_CHECKS) do patch(p[1], p[2], p[3], with_imm(p[3], tables.FINISHER_END)) end
  for _, p in ipairs(GENERIC_ATTACK) do patch(p[1], p[2], p[3], with_imm(p[3], tables.MOVED_MOVES[0x79])) end
  patch(NAME_CHECK[1], NAME_CHECK[2], NAME_CHECK[3], with_imm(NAME_CHECK[3], tables.MOVES))
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

-- New types that count as raised (type -> true); none yet outside the
-- developer option test_raised (a save has no room for them so far).
M.raised_new = {}

-- A technique's look in battle is its effect file: entry 0x100 + technique
-- of EFE DAT (getEFEDATEntry(id): sector EFEDAT_CD_LOCATION + 10 * (id -
-- 0x100)), loaded at battle start for every technique the fighters have;
-- the loaded file's header (EfeFileHeader.effectId, +48) must name the
-- technique asked for (setupLoadedEFEFile, else load error -3). A moved
-- or new technique reads another one's entry (efe_source: technique ->
-- the technique whose effect it uses), and its header is renamed when
-- setupLoadedEFEFile(EfeLoad *) first sees it (EfeLoad: moves +8, already
-- past the one loading; model +16; ModelComponent.mmdPtr +12).
M.efe_source = {}

-- getOriginalType(type) (0x800D9A3C) names the Digimon an NPC copy stands
-- for (ORIGINAL_DIGIMON_TYPES, -1 = itself) and answers -1 above type
-- 0xB0. Effects look their user up in it: a technique's effect file lists
-- per original type where the attack comes from (EfeTechBoneOffset,
-- BTL_checkTechCompatibility), and a type it doesn't list stops the
-- effect (Growlmon's finisher charged and fired nothing). A new Digimon
-- answers its donor's original type, the skeleton and animations it uses:
-- type -> original type.
M.original_type = {}
local GET_ORIGINAL_TYPE = 0x800D9A3C

-- A new finisher can use another Digimon's effect from a point of its own
-- (technique -> {type, bone, x, y, z}): in its private copy of the effect
-- file, the {type, bone, x, y, z} list (s16 each, a type of -1 ends it)
-- gets that type's entry (or its first one) set to start there; bone is a
-- skeleton index, x y z are in that bone's space.
M.efe_origin = {}

-- The first plausible {type, bone, x, y, z} list in an effect file's data.
local function list_at(data, i) -- a plausible {type, bone, x, y, z} list at (1-based) i: its types, or nil
  local types, at = {}, i
  while true do
    local ty, bone, x, y, z = string.unpack("<i2i2i2i2i2", data, at)
    if ty == -1 then break end
    if ty < 0 or ty >= 256 or bone < 0 or bone >= 40 or math.abs(x) > 2000 or math.abs(y) > 2000 or math.abs(z) > 2000 then return nil end
    types[#types + 1] = ty
    at = at + 10
    if #types > 12 or at + 10 > #data then return nil end
  end
  if #types > 0 then return types end
end
-- The first plausible list, then every later one naming the same Digimon
-- in the same order: an effect starting from several points checks one
-- list a point (Crimson Flare: four, Phoenixmon's wings and feet). Returns
-- {{offset, count}, ...} (0-based offsets).
local function find_origin_lists(data)
  local first, out, i = nil, {}, 1
  while i <= #data - 20 do
    local types = list_at(data, i)
    local same = types and (not first or table.concat(types, ",") == first)
    if same then
      first = first or table.concat(types, ",")
      out[#out + 1] = { i - 1, #types }
      i = i + 10 * #types + 2
    else
      i = i + 2
    end
  end
  return out
end
for old, new in pairs(tables.MOVED_MOVES) do M.efe_source[new] = old end -- the Bubbles, the generic attack
local GET_EFEDAT_ENTRY = 0x800AEFF4
-- The three battle overlays load at the same address (0x80052AE0): each
-- hook acts only when its own overlay's code is there.
local SETUP_LOADED_EFE = {
  { "BTL_REL.BIN", 0x800650EC },
  { "STD_REL.BIN", 0x8006D7D4 },
  { "VS_REL.BIN",  0x800638A4 },
}
local code_words = {} -- file -> { addr -> its first 4 words (from the disc) }

-- Called with every code file's words while the mod loads (main.lua).
function M.note_code(file, base, words)
  for _, h in ipairs(SETUP_LOADED_EFE) do
    if h[1] == file then
      local i = (h[2] - base) // 4 + 1
      code_words[h[2]] = { words[i], words[i + 1], words[i + 2], words[i + 3] }
    end
  end
end

local function is_here(ctx, addr)
  local w = code_words[addr]
  if not w then return false end
  for k = 1, 4 do if ctx:read32(addr + 4 * (k - 1)) ~= w[k] then return false end end
  return true
end

function M.install()
  dwrc.on_exec(HAS_DIGIMON_RAISED, function(ctx)
    local t = ctx:reg("a0") & 0xFFFF
    if t < 180 then return false end
    ctx:ret(M.raised_new[t] and 1 or 0)
    return true
  end)
  dwrc.on_exec(GET_ORIGINAL_TYPE, function(ctx)
    local o = M.original_type[ctx:reg("a0")]
    if not o then return false end
    ctx:ret(o)
    return true
  end)
  dwrc.on_exec(GET_EFEDAT_ENTRY, function(ctx)
    local id = ctx:reg("a0")
    local src = M.efe_source[id - 0x100]
    if src then ctx:set_reg("a0", src + 0x100) end
    return false
  end)
  for _, h in ipairs(SETUP_LOADED_EFE) do
    local addr = h[2]
    dwrc.on_exec(addr, function(ctx)
      if not is_here(ctx, addr) then return false end
      local load = ctx:reg("a0")
      local want = ctx:read16(ctx:read32(load + 8) - 2)
      if want >= 0x8000 then return false end
      local src = M.efe_source[want - 0x100]
      if not src then return false end
      local mmd = ctx:read32(ctx:read32(load + 16) + 12)
      if ctx:read32(mmd + 48) ~= src + 0x100 then return false end -- renamed already
      ctx:write32(mmd + 48, want)
      local o = M.efe_origin[want - 0x100]
      if o then
        local size = ctx:read32(mmd + 36) -- dataEnd (from the data, +0x34)
        local data = ctx:read_bytes(mmd + 0x34, math.min(size, 0x10000))
        local lists = find_origin_lists(data)
        if #lists == 0 then dwrc.log(string.format("effect %X: no origin list found", src)) end
        for _, l in ipairs(lists) do
          local at, n = l[1], l[2]
          local pick = at
          for k = 0, n - 1 do
            if string.unpack("<i2", data, at + 10 * k + 1) == o.type then pick = at + 10 * k end
          end
          ctx:write_bytes(mmd + 0x34 + pick, string.pack("<i2i2i2i2i2", o.type, o.bone, o.x, o.y, o.z))
        end
      end
      return false
    end)
  end
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
