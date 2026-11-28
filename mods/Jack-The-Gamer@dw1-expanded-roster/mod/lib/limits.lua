-- The game's checks against its own number of Digimon, raised to the moved
-- tables' CAPACITY (lib/release.lua; functions named as in dw_decomp). Checks
-- that loop over the game's own roster (medals, the evolution chart, card
-- rolls) stay as they are, and so do compares with 62-66 that aren't about
-- Digimon (battle timers, screen positions, the sound library).

local tables = require("lib.tables")
local R = require("lib.release")

local M = {}

-- address, the instruction there (slti/sltiu rt, rs, limit): R.type_limits
M.EXE = R.type_limits

-- Techniques (lib/tables.lua). A finisher is any technique from 0x3A below
-- a bound, 0x71 in the game; these are every check of it in the US build
-- (dw_decomp: battle_main, std_main/std_setup, vs_main, vs_combat, evl,
-- partner_impl; 32 in C, 32 here: slti/sltiu rt, rs, 0x71), raised to
-- tables.FINISHER_END. The other compares with 113 aren't about techniques
-- (Digimon type 0x71, a rotation, screen positions).
local FINISHER_CHECKS = R.finisher_checks
-- The generic attack, technique 0x79 (`tech = 0x79` in getAttackTech:
-- addiu v0, zero, 0x79), moves with the Bubbles past the finishers. A
-- flattened Digimon attacks with it too (BTL/STD_tickFlatState and
-- VS__tickDigimonFlat pass 0x79 to tickRangedAttack: addiu a3, zero, 0x79);
-- missed at first, which left those reaching technique 0x79, a new
-- finisher's number since there are nine of them.
local GENERIC_ATTACK = R.generic_attack
-- drawMoveName (Battle Mode slots) draws names of techniques < 0x79.
local NAME_CHECK = R.name_check

local function with_imm(w, v) return (w & 0xFFFF0000) | v end

-- Every rewrite: `patch(file, addr, expect, value)`.
function M.patch_code(patch)
  for _, p in ipairs(M.EXE) do patch(R.exe, p[1], p[2], with_imm(p[2], tables.CAPACITY)) end
  for _, p in ipairs(FINISHER_CHECKS) do patch(p[1], p[2], p[3], with_imm(p[3], tables.FINISHER_END)) end
  for _, p in ipairs(GENERIC_ATTACK) do patch(p[1], p[2], p[3], with_imm(p[3], tables.MOVED_MOVES[0x79])) end
  patch(NAME_CHECK[1], NAME_CHECK[2], NAME_CHECK[3], with_imm(NAME_CHECK[3], tables.MOVES))
end

-- hasDigimonRaised(type) is isTriggerSet(0x200 + type), and only the game's
-- first 63 types have such a flag (setDigimonRaised ignores the rest): a new
-- Digimon reads as never raised instead of reading some other flag.
local HAS_DIGIMON_RAISED = R.has_digimon_raised

-- A Digimon's size: initializeDigimonObject (0x800A0E68) gives the root
-- bone a scale of 0x1000, or 0x1800 for type 0x71; both paths meet at
-- 0x800A1094 with the type in s4 and the root PositionData in s1 (scale
-- words at +96/+100/+104). The root's scale reaches every bone (their
-- matrices are chained), so a new Digimon built on a smaller donor's
-- skeleton grows evenly, joints included. type -> scale (4096 = 1).
M.root_scale = {}
local ROOT_SCALE = R.root_scale -- {at, type = {reg} or {stack offset}, root register}

-- A new type is raised once setDigimonRaised (0x800FF7F8: every evolution in
-- EVL, and the new game's partner) has been called for it: a byte per new
-- type at tables.RAISED, kept with each save (dwrc.save_ram, program 1.10)
-- and cleared for a new game (newGameScene, 0x800EF1E0) or a save made
-- without the mod. Being RAM, save states keep it too.
local SET_DIGIMON_RAISED = R.set_digimon_raised
local NEW_GAME_SCENE = R.new_game_scene
-- Also called at setDigimonRaised, with (ctx, type): one hook per address.
M.on_raised = {}
-- New types that count as raised whatever the save says (type -> true):
-- the developer option test_raised.
M.raised_new = {}

function M.is_raised(ctx, t)
  if t < 180 or t >= tables.CAPACITY then return false end
  return M.raised_new[t] or ctx:read8(tables.RAISED + t - 180) ~= 0
end

local function clear_raised(ctx)
  ctx:write_bytes(tables.RAISED, string.rep("\0", tables.CAPACITY - 180))
end

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
local GET_ORIGINAL_TYPE = R.get_original_type

-- A new finisher can use another Digimon's effect from points of its own
-- (technique -> {type, points = {{bone, x, y, z}, ...}}): in its private copy
-- of the effect file, each {type, bone, x, y, z} list (s16 each, a type of -1
-- ends it; an effect with several start points has one list each) gets that
-- type's entry (or its first one) set to start at the matching point (the
-- last point for any further lists); bone is a skeleton index, x y z are in
-- that bone's space.
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
local GET_EFEDAT_ENTRY = R.get_efedat_entry
-- The three battle overlays load at the same address (0x80052AE0): each
-- hook acts only when its own overlay's code is there.
local SETUP_LOADED_EFE = R.setup_loaded_efe
local code_words = {} -- file -> { addr -> its first 4 words (from the disc) }

-- The evolution scene (EVL_REL.BIN at 0x80060000) breaks the old model into
-- shards: EVL_buildShardSet writes 6 bytes per vertex and per polygon of
-- each object, one after another from the scratch top EVL_initEvoSequence
-- sets with EVL_setScratchTop(EVL_D_80066274), a 0x153C-byte buffer (906
-- of them; MetalGreymon has 815). Past it lie the scene's flash data and
-- its random bone order: a bigger model (Guilmon has 1141) reads garbage
-- bones and the scene hangs. The scratch moves to tables.EVL_SCRATCH.
local EVL_SET_SCRATCH_TOP = R.evl_set_scratch_top

-- A Digimon using another one's techniques on its donor's skeleton (type ->
-- {type = the other's original type, bones = {its bone -> {bone, x, y, z}}}).
-- checkTechCompatibility pops an effect's start-point list ({type, bone, x,
-- y, z} s16, 10 bytes each, a negative type ends it) and looks the user's
-- original type up in it, else stops the effect. When the list has no entry
-- for the user's own original type but one for the other Digimon, the word
-- it pops (the top of EFE_DATA_STACK) is pointed at a private one-entry
-- list: that entry with the bone translated (bone 0, the entity, stays as it
-- is; a bone without a translation keeps its number and offset). A list
-- naming neither (a mixed technique list: `fallback` = {bone, x, y, z}, or
-- `near`: lists built from specialties) takes the entry of the Digimon
-- closest to the user's height (DigimonPara.height), starting at the user's
-- point for the technique's kind (`points[kind]`, else `fallback`, else in
-- front of it at 3/5 of its height and its radius away) unless that entry
-- starts at bone 0 (the entity: its offset is a place before the user, kept).
-- Lists can be long (Megaton Punch's has 29 entries).
M.borrow = {}
local loaded = {} -- effect file address -> {stop, technique} (the battle's loaded effects)
local CHECK_TECH = R.check_tech
local EFE_DATA_STACK = R.efe_data_stack         -- int32 * (pop: *--ptr)
local EFE_SCRIPT_CONTEXT = R.efe_script_context -- EfeSubEffect * (sourceEntity at +16)

-- Called with every code file's words while the mod loads (main.lua).
function M.note_code(file, base, words)
  for _, h in ipairs(CHECK_TECH) do
    if h[1] == file then
      local i = (h[2] - base) // 4 + 1
      code_words[h[2]] = { words[i], words[i + 1], words[i + 2], words[i + 3] }
    end
  end
  if file == "EVL_REL.BIN" then
    local i = (EVL_SET_SCRATCH_TOP - base) // 4 + 1
    code_words[EVL_SET_SCRATCH_TOP] = { words[i], words[i + 1], words[i + 2], words[i + 3] }
  end
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
    ctx:ret(M.is_raised(ctx, t) and 1 or 0)
    return true
  end)
  dwrc.save_ram(tables.RAISED, tables.CAPACITY - 180)
  dwrc.on_exec(SET_DIGIMON_RAISED, function(ctx)
    local t = ctx:reg("a0") & 0xFFFF
    if t >= 180 and t < tables.CAPACITY then ctx:write8(tables.RAISED + t - 180, 1) end
    for _, f in ipairs(M.on_raised) do f(ctx, t) end
    return false
  end)
  dwrc.on_exec(NEW_GAME_SCENE, function(ctx) clear_raised(ctx); return false end)
  dwrc.on_save(function(ctx, info)
    if info.event == "loaded" and not info.found then clear_raised(ctx) end
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
      do -- which technique each effect file is, for borrow's kind
        local f = ctx:read32(ctx:read32(load + 16) + 12)
        if want >= 0x100 and want < 0x200 then loaded[f] = { f + 0x34 + ctx:read32(f + 36), want - 0x100 } end
      end
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
        for i, l in ipairs(lists) do
          local at, n = l[1], l[2]
          local pick = at
          for k = 0, n - 1 do
            if string.unpack("<i2", data, at + 10 * k + 1) == o.type then pick = at + 10 * k end
          end
          local pt = o.points[math.min(i, #o.points)] -- {bone, x, y, z}; the last one for any further lists
          ctx:write_bytes(mmd + 0x34 + pick, string.pack("<i2i2i2i2i2", o.type, pt[1], pt[2], pt[3], pt[4]))
        end
      end
      return false
    end)
  end
  for _, h in ipairs(CHECK_TECH) do
    local addr = h[2]
    dwrc.on_exec(addr, function(ctx)
      if not next(M.borrow) or not is_here(ctx, addr) then return false end
      local user = ctx:read32(ctx:read32(EFE_SCRIPT_CONTEXT) + 16)
      local t = user ~= 0 and ctx:read32(user)
      local b = t and M.borrow[t]
      if not b then return false end
      local top = ctx:read32(EFE_DATA_STACK) - 4
      local list = ctx:read32(top)
      local own = M.original_type[t] or t
      local found, near, gap
      local function height(ty) return ctx:read_s16(tables.entry("DIGIMON_DATA", ty) + R.para.height) end
      local mine = height(t)
      for k = 0, 47 do
        local ty = ctx:read_s16(list + 10 * k)
        if ty < 0 then break end
        if ty == own then return false end
        if b.type and ty == b.type and not found then found = list + 10 * k end
        if ty < 180 then
          local g = math.abs(height(ty) - mine)
          if not gap or g < gap then near, gap = list + 10 * k, g end
        end
      end
      local any = false
      if not found and (b.fallback or b.near) and near then found, any = near, true end
      if not found then return false end
      local bone, x, y, z = ctx:read_s16(found + 2), ctx:read_s16(found + 4), ctx:read_s16(found + 6), ctx:read_s16(found + 8)
      local to = bone ~= 0 and not any and b.bones[bone]
      if bone ~= 0 and any then
        local kind
        for f, r in pairs(loaded) do
          if list >= f and list < r[1] then kind = ctx:read8(tables.entry("MOVE_DATA", r[2]) + 9) end
        end
        local data = tables.entry("DIGIMON_DATA", t)
        to = (b.points and kind and b.points[kind]) or b.fallback
          or { 0, 0, -(ctx:read_s16(data + R.para.height) * 3 // 5), -ctx:read16(data + R.para.radius) }
      end
      if to then bone, x, y, z = to[1], to[2], to[3], to[4] end
      local slot = tables.BORROW + 12 * ((list >> 1) % tables.BORROW_SLOTS)
      ctx:write_bytes(slot, string.pack("<i2i2i2i2i2i2", own, bone, x, y, z, -1))
      ctx:write32(top, slot)
      return false
    end)
  end
  dwrc.on_exec(EVL_SET_SCRATCH_TOP, function(ctx)
    if is_here(ctx, EVL_SET_SCRATCH_TOP) then ctx:set_reg("a0", tables.EVL_SCRATCH) end
    return false
  end)
  dwrc.on_exec(ROOT_SCALE.at, function(ctx)
    local ty = ROOT_SCALE.type.reg and ctx:reg(ROOT_SCALE.type.reg) or ctx:read32(ctx:reg("sp") + ROOT_SCALE.type.stack)
    local s = M.root_scale[ty]
    if s then
      local root = ctx:reg(ROOT_SCALE.root)
      ctx:write32(root + 96, s); ctx:write32(root + 100, s); ctx:write32(root + 104, s)
    end
    return false
  end)
end

return M
