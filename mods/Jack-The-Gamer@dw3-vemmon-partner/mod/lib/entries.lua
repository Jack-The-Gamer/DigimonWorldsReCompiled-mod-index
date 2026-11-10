-- A partner's Digimon ("entries", PartnerEntry): the game keeps 44 per
-- partner, one for each of its 44 forms, in the partner's record. The mod's
-- three forms (Snatchmon, Destromon, Galacticmon) go in three extra entries
-- per partner in the mod's RAM (ext.extra), always in the same order, so
-- the record keeps only the game's forms. Entry indices 44-46 are the
-- extras.
--
-- The game reaches the entries only through partner.c's functions (GAME.funcs),
-- which the mod answers for partners 0-7 and 17 with the same rules plus the
-- extras. Their callers' lists:
--   * the Lab's entry panel (where a partner's slots are picked) lists all
--     of them: its buffer (entries[47], then entryCount) gets room for 49 by
--     moving entryCount to the end of the panel (0xD8 -> 0x100);
--   * the Lab's entry list keeps 44 on its stack: it gets the game's forms,
--     and the extras are added to the panel's own list (ids[50]) before its
--     windows are made;
--   * the slot screen and the battle report only count them: the count
--     includes the extras;
--   * the Digivolve Chart's recipes name only the game's forms: as before.

local eu = require("lib.eu")
local ext = require("lib.ext")
local files = require("lib.files")
local forms = require("lib.forms")
local mips = require("lib.mips")
local tables = require("lib.tables")

local M = {}

local FIRST_ENTRY_ID = 3
local P_SLOTS = ext.P_INFO + 0x48           -- s16 slots[4] (3 used)
local SIZE = ext.ENTRY_SIZE
M.TOTAL = ext.ENTRY_COUNT + ext.EXTRA_COUNT

local function s32(v) if v >= 0x80000000 then return v - 0x100000000 end return v end
local function sreg(ctx, r) return s32(ctx:reg(r)) end

function M.entry_addr(p, i)
  if i < ext.ENTRY_COUNT then return ext.record(p) + ext.P_ENTRIES + i * SIZE end
  return ext.extra(p, i - ext.ENTRY_COUNT)
end

-- The index of Digimon `id` among partner p's entries, or -1.
function M.find(ctx, p, id)
  if id < FIRST_ENTRY_ID then return -1 end
  local s = ctx:read_bytes(ext.record(p) + ext.P_ENTRIES, ext.ENTRY_COUNT * SIZE)
  for i = 0, ext.ENTRY_COUNT - 1 do
    if string.unpack("<i2", s, i * SIZE + 1) == id then return i end
  end
  for k = 0, ext.EXTRA_COUNT - 1 do
    if ctx:read_s16(ext.extra(p, k)) == id then return ext.ENTRY_COUNT + k end
  end
  return -1
end

-- The ids of partner p's entries: the record's in order, then the extras'.
function M.ids(ctx, p)
  local list = {}
  local s = ctx:read_bytes(ext.record(p) + ext.P_ENTRIES, ext.ENTRY_COUNT * SIZE)
  for i = 0, ext.ENTRY_COUNT - 1 do
    local id = string.unpack("<i2", s, i * SIZE + 1)
    if id >= FIRST_ENTRY_ID then list[#list + 1] = id end
  end
  local originals = #list
  for k = 0, ext.EXTRA_COUNT - 1 do
    local id = ctx:read_s16(ext.extra(p, k))
    if id >= FIRST_ENTRY_ID then list[#list + 1] = id end
  end
  return list, originals
end

-- listPartnerEntries' callers, by return address: what each gets.
--   all: every entry, room for `room`;  count_all: the game's forms, the
--   count of all;  (others) the game's forms and their count.
local CALLERS = {
  { ra = 0x80085E7C, file = eu.FILE_STGDGLAB, mode = "all", room = 49 },        -- STGDGLAB_updateEntryPanel
  { ra = 0x800876A0, file = eu.FILE_STGDGLAB, mode = "count_all" },             -- STGDGLAB_runSlotScreen
  { ra = 0x8008479C, file = eu.FILE_STFGTREP, mode = "count_all" },             -- STFGTREP_runPartner
  { ra = 0x800843BC, file = eu.FILE_STGDGLAB, mode = "game" },                  -- STGDGLAB_updateRecipeScreen
  { ra = 0x8008E9A8, file = eu.FILE_STGDGLAB, mode = "game" },                  -- STGDGLAB_updateEntryList (extras: below)
}
local by_ra = {}

local function caller(ctx)
  local c = by_ra[ctx:reg("ra")]
  if c and ctx:read32(c.ra - 8) == c.sig1 and ctx:read32(c.ra - 4) == c.sig2 then return c end
  return nil
end

local function list_entries(ctx, p, out)
  local list, originals = M.ids(ctx, p)
  local c = caller(ctx)
  local mode = c and c.mode or "game"
  local n, room = originals, ext.ENTRY_COUNT
  if mode == "all" then n, room = #list, c.room end
  local parts = {}
  for i = 1, room do parts[i] = string.pack("<i2", i <= n and list[i] or 0) end
  ctx:write_bytes(out, table.concat(parts))
  if mode == "game" then return originals end
  return #list
end

-- The Lab's panel for picking slots (STGDGLAB_updateEntryPanel and
-- STGDGLAB_createEntryPanel): its entryCount moves from 0xD8 to 0x100.
local ENTRY_COUNT_SITES = {
  { 0x80085E88, 0xAE4200D8 },   -- sw v0, 216(s2): listPartnerEntries' count
  { 0x80085F1C, 0x8E4200D8 }, { 0x80086124, 0x8E4300D8 }, { 0x800862C8, 0x8E4200D8 },
  { 0x800862FC, 0x8E4300D8 }, { 0x80086338, 0x8E4300D8 }, { 0x80086D14, 0x8E4300D8 },
}
local CREATE_ENTRY_PANEL_SIZE = 0x80087034          -- addiu a1, zero, 0x100 (createTask's size)
local ENTRY_LIST_WINDOWS_CALL = 0x8008EA28          -- jal STGDGLAB_createEntryListWindows
local createEntryListWindows = 0x8008D7CC

function M.build()
  for _, c in ipairs(CALLERS) do
    c.sig1 = files.read32(c.file, c.ra - 8)
    c.sig2 = files.read32(c.file, c.ra - 4)
    by_ra[c.ra] = c
  end
  local lab = eu.FILE_STGDGLAB
  for _, s in ipairs(ENTRY_COUNT_SITES) do
    files.patch32(lab, s[1], s[2], (s[2] & 0xFFFF0000) | 0x100)
  end
  files.patch32(lab, CREATE_ENTRY_PANEL_SIZE, 0x24050100, 0x24050104)
  M.list_stub = tables.stub("entry_list_extras")
  files.patch32(lab, ENTRY_LIST_WINDOWS_CALL, mips.jal(createEntryListWindows), mips.jal(M.list_stub))
end

local function partner_hook(addr, fn)
  dwrc.on_exec(addr, function(ctx)
    local p = sreg(ctx, "a0")
    if not ext.is_partner(p) then return false end
    return ctx:ret(fn(ctx, p) & 0xFFFFFFFF)
  end)
end

function M.install()
  partner_hook(eu.findPartnerEntry, function(ctx, p)
    return M.find(ctx, p, sreg(ctx, "a1"))
  end)

  -- getPartnerSlots(partner, s16 *out): the ids of the slots' entries
  partner_hook(eu.getPartnerSlots, function(ctx, p)
    local out = ctx:reg("a1")
    local slots = ext.record(p) + P_SLOTS
    local n = 0
    for i = 0, 2 do
      local s = ctx:read_s16(slots + 2 * i)
      if s >= FIRST_ENTRY_ID then
        local idx = M.find(ctx, p, s)
        if idx >= 0 then
          local id = ctx:read_s16(M.entry_addr(p, idx))
          if id >= FIRST_ENTRY_ID then
            ctx:write16(out + 2 * n, id)
            n = n + 1
          end
        end
      end
    end
    for i = n, 2 do ctx:write16(out + 2 * i, 0xFFFF) end
    return n
  end)

  -- setPartnerSlots(partner, s16 *ids)
  partner_hook(eu.setPartnerSlots, function(ctx, p)
    local ids = ctx:reg("a1")
    local slots = ext.record(p) + P_SLOTS
    for i = 0, 2 do
      local idx = M.find(ctx, p, ctx:read_s16(ids + 2 * i))
      ctx:write16(slots + 2 * i, idx >= 0 and ctx:read16(M.entry_addr(p, idx)) or 0xFFFF)
    end
    return 0
  end)

  -- listPartnerEntries(partner, u16 *out): the count
  partner_hook(eu.listPartnerEntries, function(ctx, p)
    return list_entries(ctx, p, ctx:reg("a1"))
  end)

  -- addPartnerEntry(partner, id): Digimon `id` at level 1; 0 if it has it
  -- or has no room. The mod's forms go in their extra entry.
  partner_hook(eu.addPartnerEntry, function(ctx, p)
    local id = sreg(ctx, "a1")
    if M.find(ctx, p, id) ~= -1 then return 0 end
    local at
    local k = forms.extra_slot(id)
    if k then
      if ctx:read16(ext.extra(p, k)) == 0 then at = ext.extra(p, k) end
    else
      for i = 0, ext.ENTRY_COUNT - 1 do
        local e = M.entry_addr(p, i)
        if ctx:read16(e) == 0 then at = e break end
      end
    end
    if not at then return 0 end
    ctx:write16(at, id)
    ctx:write8(at + 2, 1)
    return 1
  end)

  -- getPartnerEntry(partner, id, PartnerEntry *out): the index, or -1
  partner_hook(eu.getPartnerEntry, function(ctx, p)
    local i = M.find(ctx, p, sreg(ctx, "a1"))
    if i ~= -1 then ctx:write_bytes(ctx:reg("a2"), ctx:read_bytes(M.entry_addr(p, i), SIZE)) end
    return i
  end)

  -- setPartnerEntry(partner, id, PartnerEntry *in)
  partner_hook(eu.setPartnerEntry, function(ctx, p)
    local i = M.find(ctx, p, sreg(ctx, "a1"))
    if i ~= -1 then ctx:write_bytes(M.entry_addr(p, i), ctx:read_bytes(ctx:reg("a2"), SIZE)) end
    return i
  end)

  -- The Lab's entry list (STGDGLAB_updateEntryList, a0 = the list): with
  -- allEntries, the extras not in the slots go after the game's forms.
  dwrc.on_exec(M.list_stub, function(ctx)
    local panel = ctx:reg("a0")
    if ctx:read32(panel + 0x50) ~= 0 then
      local p = s32(ctx:read32(panel + 0x54))
      if ext.is_partner(p) then
        local count = ctx:read32(panel + 0x15C)
        local s0, s1_, s2 = s32(ctx:read32(panel + 0x90)), s32(ctx:read32(panel + 0x94)), s32(ctx:read32(panel + 0x98))
        for k = 0, ext.EXTRA_COUNT - 1 do
          local id = ctx:read_s16(ext.extra(p, k))
          if id >= FIRST_ENTRY_ID and id ~= s0 and id ~= s1_ and id ~= s2 and count < 50 then
            ctx:write32(panel + 0x90 + 4 * count, id)
            count = count + 1
          end
        end
        ctx:write32(panel + 0x15C, count)
      end
    end
    ctx:set_pc(createEntryListWindows)
    return true
  end)
end

return M
