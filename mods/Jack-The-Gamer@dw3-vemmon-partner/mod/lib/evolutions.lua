-- The digivolutions a partner learns after battles (STFGTREP_learnDigimon):
-- each partner has a list of Evolution entries, one per form ({digimon
-- (DIGIMON_DATA index + 1), needs[2] {digimon, level}, stat (1-6 battle
-- stats, 7 the level, 8-14 resistances), value}, 16 bytes), the first
-- learnable one is learned. The game has 8 lists of 44 (STFGTREP_evolutions,
-- a table of 8 pointers, read once at 0x80086370; the loop ends at the list
-- + 44 * 16, `addiu v0, s7, 704` at 0x8008657C).
--
-- The mod's lists have 47 entries: the game's 44, then Snatchmon, Destromon
-- and Galacticmon. Every partner but Vemmon: Snatchmon with Beelzemon and
-- Diaboromon at level 20, Destromon with Snatchmon at 50, Galacticmon with
-- Destromon at 99. Vemmon: its own line at Rookie levels 5, 20 and 40, as
-- the partners' own lines are; the game's 44 forms as Guilmon's list (both
-- virus-type), its own line (Growlmon at Rookie level 5, WarGrowlmon at 20,
-- Gallantmon at 40) instead reached as other partners reach it: Growlmon
-- with Snatchmon at 20 (Vemmon's Champion, as Greymon is for Agumon),
-- WarGrowlmon and Gallantmon as in Agumon's list.

local eu = require("lib.eu")
local files = require("lib.files")
local forms = require("lib.forms")
local mips = require("lib.mips")

local M = {}

local TABLE = 0x8008903C            -- STFGTREP_evolutions[8]
local TABLE_PAIR = { 0x80086370, 0x3C038009, 0x80086374, 0x2463903C }
local LOOP_END = 0x8008657C         -- addiu v0, s7, 704 (44 entries)
local COUNT, NEW_COUNT = 44, 47
local SIZE = 16

-- DIGIMON_DATA indices of the forms the lists name
local BEELZEMON, DIABOROMON = 50, 51
local GROWLMON, WARGROWLMON, GALLANTMON = 13, 25, 37
local GUILMON, AGUMON = 5, 3

local function ev(digimon, n1, l1, n2, l2, stat, value)
  return string.pack("<ihhhhhh", digimon + 1, n1 and n1 + 1 or 0, l1 or 0, n2 and n2 + 1 or 0, l2 or 0, stat or 0, value or 0)
end

-- The entry of a list for DIGIMON_DATA index `d`.
local function find(list, d)
  for n = 0, COUNT - 1 do
    if string.unpack("<i4", list, n * SIZE + 1) == d + 1 then return n end
  end
  error("no entry for Digimon " .. d)
end

local function replace(list, n, entry)
  return list:sub(1, n * SIZE) .. entry .. list:sub((n + 1) * SIZE + 1)
end

function M.build()
  local ovl = files.overlay(eu.FILE_STFGTREP)
  local lists = {}
  for p = 0, 7 do lists[p] = ovl:read(ovl:read32(TABLE + 4 * p), COUNT * SIZE) end

  local S, D, G = forms.SNATCHMON, forms.DESTROMON, forms.GALACTICMON
  local new_forms = ev(S, BEELZEMON, 20, DIABOROMON, 20) .. ev(D, S, 50) .. ev(G, D, 99)

  -- Vemmon's
  local v = lists[GUILMON]
  local a = lists[AGUMON]
  v = replace(v, find(v, GROWLMON), ev(GROWLMON, S, 20))
  v = replace(v, find(v, WARGROWLMON), a:sub(find(a, WARGROWLMON) * SIZE + 1, (find(a, WARGROWLMON) + 1) * SIZE))
  v = replace(v, find(v, GALLANTMON), a:sub(find(a, GALLANTMON) * SIZE + 1, (find(a, GALLANTMON) + 1) * SIZE))
  local vemmon = v .. ev(S, nil, 0, nil, 0, 7, 5) .. ev(D, nil, 0, nil, 0, 7, 20) .. ev(G, nil, 0, nil, 0, 7, 40)

  -- the lists, then the table (18 pointers; 8-16 never read)
  ovl.ext:align(4)
  local at = {}
  for p = 0, 7 do
    at[p] = ovl.ext:addr()
    ovl.ext:raw(lists[p] .. new_forms)
  end
  local vat = ovl.ext:addr()
  ovl.ext:raw(vemmon)
  local table_at = ovl.ext:addr()
  for p = 0, 17 do
    ovl.ext:u32(p < 8 and at[p] or (p == 17 and vat or at[0]))
  end

  local p = TABLE_PAIR
  files.patch32(eu.FILE_STFGTREP, p[1], p[2], (p[2] & 0xFFFF0000) | mips.hi(table_at))
  files.patch32(eu.FILE_STFGTREP, p[3], p[4], (p[4] & 0xFFFF0000) | mips.lo(table_at))
  files.patch32(eu.FILE_STFGTREP, LOOP_END, 0x26E202C0, 0x26E20000 | (NEW_COUNT * SIZE))
end

return M
