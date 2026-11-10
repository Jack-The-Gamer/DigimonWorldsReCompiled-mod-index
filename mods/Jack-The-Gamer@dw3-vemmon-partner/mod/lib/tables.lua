-- A ninth partner and four new Digimon in the game's code.
--
-- Partners: the game finds partner p's record (Partner, 0x3DC bytes) as
-- GAME.partners + p * 0x3DC, which the compiler multiplies with a chain of
-- five shifts and subtractions. Every such chain (sites_partner.lua, 34 of
-- them in the executable and 8 overlays) becomes a lookup in T988, a table
-- of p * 0x3DC whose entry 17 instead points at Vemmon's record in the mod's
-- RAM:   sll B,X,2 / lui at,hi(T988) / addu B,B,at / lw B,lo(T988)(B) / nop
-- Partner 17 puts Vemmon's burst gauge (BATTLE_SETUP.gauges[17]) on two
-- unused bytes after BATTLE_RESULT.
--
-- Digimon: DIGIMON_DATA moves to the mod's RAM with room for 59 entries
-- (the 26 lui/addiu pairs that address it, sites_digimon_data.lua), and
-- findDigimon's miss path searches the new ones (55-58). A partner's own
-- Digimon is DIGIMON_DATA[p]: those 19 x * 0x58 chains (also in
-- sites_partner.lua) look up DT, p * 0x58 with entry 17 at Vemmon's (55).
-- The two battle checks for "the partner is still a Rookie" (they compare
-- the fighter with DIGIMON_DATA[0-7]) also test Vemmon.
--
-- Where they live: the new DIGIMON_DATA, the routines, T988 and DT in the
-- game's old TECHS (0x80042BDC, 7974 bytes, unused once TECHS moves),
-- written into the executable; the new TECHS (techs.lua, 8244 bytes) in
-- the mod's RAM at the heap's end (ext.lua), written when the game starts
-- (newGame) and again whenever the stamp in the mod's RAM differs (a save
-- state of another build of the mod).

local bin = require("lib.bin")
local blob = require("lib.blob")
local disc = require("lib.disc")
local eu = require("lib.eu")
local ext = require("lib.ext")
local files = require("lib.files")
local forms = require("lib.forms")
local mips = require("lib.mips")

local R = mips.R
local M = {}

local techs = require("lib.techs")

M.DIGIMON = 0x80042BDC              -- DigimonData[59], in the old TECHS
M.CODE = M.DIGIMON + forms.COUNT * eu.DIGIMON_SIZE   -- the routines (0x280 bytes)
M.CODE_END = M.CODE + 0x280
M.T988_FIRST, M.T988_LAST = -16, 63
M.T988 = M.CODE_END - M.T988_FIRST * 4               -- s32[-16..63]: p * sizeof(Partner); [17] reaches Vemmon's record
M.DT_FIRST, M.DT_LAST = -16, 31
M.DT = M.T988 + (M.T988_LAST + 1) * 4 - M.DT_FIRST * 4   -- s32[-16..31]: p's own Digimon * sizeof(DigimonData); [17] = 55
M.EXE_END = M.DT + (M.DT_LAST + 1) * 4
assert(M.EXE_END <= techs.TECHS + techs.COUNT * techs.SIZE, "the tables overflow the old TECHS")
M.TECHS = ext.TECHS                 -- TechData[458]: the game's 443 and the mod's
assert(M.TECHS + (techs.COUNT + #techs.LIST) * techs.SIZE <= ext.END)

-- Routines other parts of the mod reach: name -> address
M.code = {}

local code = blob.new(M.CODE)
local function routine(name, list)
  local data, labels = mips.assemble(code:addr(), list)
  M.code[name] = code:addr()
  code:raw(data)
  return labels
end

-- A routine for other parts of the mod: its address.
function M.routine(name, list)
  routine(name, list)
  return M.code[name]
end

-- An address the mod's Lua code takes over (a hook): two nops.
function M.stub(name)
  routine(name, { mips.NOP, mips.NOP })
  return M.code[name]
end

local function lookup(T0, B, X)
  return { mips.sll(B, X, 2), mips.lui(R.at, mips.hi(T0)), mips.addu(B, B, R.at), mips.lw(B, mips.lo(T0), B), mips.NOP }
end

-- Moves what lui/addiu pairs address from `old` to `new` (offsets kept):
-- `refs` as gen_refs.py writes them; a lui several pairs share changes once.
function M.repoint(refs, old, new)
  local luis = {}
  for _, r in ipairs(refs) do
    local file, lui_at, lui_word, use_at, use_word, target = r[1], r[2], r[3], r[4], r[5], r[6]
    assert(use_word >> 26 == 0x09, string.format("%08x: not an addiu", use_at))
    local t = new + (target - old)
    local key = tostring(file) .. ":" .. lui_at
    local hi = (lui_word & 0xFFFF0000) | mips.hi(t)
    if luis[key] then
      assert(luis[key] == hi, string.format("%08x: a lui shared by targets in different 64K", lui_at))
    else
      luis[key] = hi
      files.patch32(file, lui_at, lui_word, hi)
    end
    files.patch32(file, use_at, use_word, (use_word & 0xFFFF0000) | mips.lo(t))
  end
end

local function patch_sites(list, T0)
  for _, s in ipairs(list) do
    local file, addrs, B, X, words = s[1], s[2], s[3], s[4], s[5]
    local new = lookup(T0, B, X)
    for i = 1, 5 do files.patch32(file, addrs[i], words[i], new[i]) end
  end
end

function M.build()
  local sites = require("lib.sites_partner")
  local refs = require("lib.sites_digimon_data")
  local vemmon_rookie = forms.ID[forms.VEMMON]

  -- the tables
  local t988 = blob.new(M.T988 + M.T988_FIRST * 4)
  for i = M.T988_FIRST, M.T988_LAST do
    t988:u32(i == ext.VEMMON_ID and (ext.VEMMON - ext.GAME_PARTNERS) or i * ext.PARTNER_SIZE)
  end
  local dt = blob.new(M.DT + M.DT_FIRST * 4)
  for i = M.DT_FIRST, M.DT_LAST do
    dt:u32((i == ext.VEMMON_ID and forms.VEMMON or i) * eu.DIGIMON_SIZE)
  end
  local game = disc.exe_read(eu.DIGIMON_DATA, eu.DIGIMON_COUNT * eu.DIGIMON_SIZE)
  local digimon = game .. forms.entries(game)

  -- findDigimon: after the game's 52, the mod's
  local first = M.DIGIMON + forms.VEMMON * eu.DIGIMON_SIZE
  routine("find_digimon_tail", {
    mips.lui(R.a1, mips.hi(first)),
    mips.addiu(R.a1, R.a1, mips.lo(first)),
    mips.addiu(R.v1, R.zero, forms.VEMMON),
    "loop",
    mips.lhu(R.v0, 0, R.a1),
    mips.NOP,
    mips.beq_to(R.v0, R.a0, "found"),
    mips.addu(R.v0, R.v1, R.zero),
    mips.addiu(R.v1, R.v1, 1),
    mips.slti(R.v0, R.v1, forms.COUNT),
    mips.bne_to(R.v0, R.zero, "loop"),
    mips.addiu(R.a1, R.a1, eu.DIGIMON_SIZE),
    mips.jr(R.ra),
    mips.addiu(R.v0, R.zero, -1),
    "found",
    mips.jr(R.ra),
    mips.NOP,
  })
  files.patch32("exe", eu.FIND_DIGIMON_MISS, 0x03E00008, mips.j(M.code.find_digimon_tail))
  files.patch32("exe", eu.FIND_DIGIMON_MISS + 4, 0x2402FFFF, mips.NOP)

  -- FIGHTSTG_testEnemyCondition, condition 8 ("the partner is a Rookie"):
  -- its loop over DIGIMON_DATA[0-7] ends with `j 80089134` (result 0); the
  -- fighter's id is in v1.
  routine("enemy_condition_rookie", {
    mips.addiu(R.at, R.zero, vemmon_rookie),
    mips.bne_to(R.v1, R.at, "no"),
    mips.NOP,
    mips.j(0x8008912C),             -- addiu s1, zero, 1 (result 1)
    mips.NOP,
    "no",
    mips.j(0x80089134),
    mips.NOP,
  })
  files.patch32(eu.FILE_FIGHTSTG, 0x80088F64, mips.j(0x80089134), mips.j(M.code.enemy_condition_rookie))

  -- FIGHTSTG_rollDedigivolve: no dedigivolving a Rookie; after its loop
  -- (fighter id in v1), `sll v1, a1, 3; addu v1, v1, a1` start the roll.
  routine("dedigivolve_rookie", {
    mips.addiu(R.at, R.zero, vemmon_rookie),
    mips.bne_to(R.v1, R.at, "no"),
    mips.NOP,
    mips.j(0x800A1448),             -- return 0
    mips.addu(R.v0, R.zero, R.zero),
    "no",
    mips.sll(R.v1, R.a1, 3),
    mips.j(0x800A141C),
    mips.addu(R.v1, R.v1, R.a1),
  })
  files.patch32(eu.FILE_FIGHTSTG, 0x800A1414, 0x000518C0, mips.j(M.code.dedigivolve_rookie))
  files.patch32(eu.FILE_FIGHTSTG, 0x800A1418, 0x00651821, mips.NOP)

  -- the multiplications
  patch_sites(sites.partner, M.T988)
  patch_sites(sites.digimon, M.DT)

  -- DIGIMON_DATA's and TECHS's new places
  M.repoint(refs, eu.DIGIMON_DATA, M.DIGIMON)
  techs.build()
  M.repoint(require("lib.sites_techs"), techs.TECHS, M.TECHS)

  M.parts = { t988 = t988, dt = dt, digimon = digimon, techs = techs.data }
end

-- The tables, once every part of the mod has added its routines (call
-- after build() and the others' setup): those in the executable go there,
-- TECHS waits for the game to start.
local stamp

function M.finish()
  assert(code:addr() <= M.CODE_END, "the mod's routines overflow their area")
  local s = blob.new(M.DIGIMON)
  s:raw(M.parts.digimon)
  s:raw(code:data())
  s:raw(string.rep("\0", M.T988 + M.T988_FIRST * 4 - s:addr()))
  s:raw(M.parts.t988:data())
  s:raw(string.rep("\0", M.DT + M.DT_FIRST * 4 - s:addr()))
  s:raw(M.parts.dt:data())
  assert(s:addr() == M.EXE_END)
  -- the rest of the old TECHS, unused
  s:raw(string.rep("\0", techs.TECHS + techs.COUNT * techs.SIZE - s:addr()))
  disc.exe_write(M.DIGIMON, s:data())
  -- FNV-1a of TECHS and the executable's tables
  local h = 0x811C9DC5
  local all = M.parts.techs .. s:data()
  for i = 1, #all do h = ((h ~ all:byte(i)) * 0x01000193) & 0xFFFFFFFF end
  stamp = h
end

function M.write_static(ctx)
  ctx:write_bytes(M.TECHS, M.parts.techs)
  ctx:write32(ext.STAMP, stamp)
end

function M.install()
  dwrc.on_exec(eu.newGame, function(ctx)
    M.write_static(ctx)
    return false
  end)
  dwrc.on_frame(function(ctx)
    if ctx:read32(ext.STAMP) ~= stamp then M.write_static(ctx) end
  end)
end

return M
