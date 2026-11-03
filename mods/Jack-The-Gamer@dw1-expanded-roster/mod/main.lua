-- DW1 Expanded Roster (work in progress): the roster core.
--
-- So far:
-- * the game's per-Digimon tables move to a bigger home (room for
--   tables.CAPACITY types instead of 180) and every piece of code that reads
--   them is pointed there (lib/tables.lua, lib/reloc.lua);
-- * the checks against 180 types are raised (lib/limits.lua);
-- * new files can be added by name, and ALLTIM.TIM (one texture per type) is
--   rebuilt with entries for the new types (lib/files.lua).
-- The executable and its 16 overlays are patched on the virtual disc while
-- the mod loads (Re:Compiled 1.6: dwrc.disc); the player's disc is never
-- changed and the mod ships nothing of the game's. No new Digimon yet: the
-- developer option test_clone adds type 180, a copy of Agumon.

local bin = require("lib.bin")
local iso = require("lib.iso")
local reloc = require("lib.reloc")
local tables = require("lib.tables")
local limits = require("lib.limits")
local files = require("lib.files")
local evolution = require("lib.evolution")
local backports = require("lib.backports")
local dw3model = require("lib.dw3model")
local convert = require("lib.convert")

if dwrc.serial ~= "SLUS-01032" then
  dwrc.log("DW1 Expanded Roster only works with Digimon World (USA) for now")
  return
end

local EXE = "SLUS_010.32"
local EXE_CODE = 0x80090800          -- the executable's first byte after its 2 KiB header
local REL_BIN_OFFSETS = 0x8012B96C   -- the overlays' load addresses (16 words)
local REL_BIN_FILES = 0x8012BA8C     -- and their names (16 pointers)
local FILE_OFFSET_TABLE = 0x8011FE1C -- every file: {sector, size, name*}, up to size 0
local TEXTURE_SIZE = 0x4800          -- ALLTIM.TIM: one 9-sector TIM per type

local t0 = os.clock()
local exe, exe_lba, exe_size = iso.read(EXE)
assert(exe:sub(1, 8) == "PS-X EXE", "SLUS_010.32 is not an executable")
local function exe_off(addr) return addr - EXE_CODE + 0x800 end

-- A file by name, as the game finds it: its first sector and size.
local function game_file(name)
  local e = FILE_OFFSET_TABLE
  while true do
    local size = bin.u32(exe, exe_off(e + 4))
    if size == 0 then error(name .. " is not in the game's file table") end
    if bin.cstr(exe, exe_off(bin.u32(exe, exe_off(e + 8)))) == name then return bin.u32(exe, exe_off(e)), size end
    e = e + 12
  end
end
local function read_game_file(name)
  local lba, size = game_file(name)
  return dwrc.disc.read(lba, (size + 2047) // 2048):sub(1, size)
end

-- Changes to the executable besides the moved references (word index -> value).
local exe_extra = {}
local function patch_exe(addr, expect, value)
  local v = bin.u32(exe, exe_off(addr))
  if v ~= expect then error(string.format("unexpected code at %08X: %08X, not %08X", addr, v, expect)) end
  exe_extra[(addr - EXE_CODE) // 4 + 1] = value
end
limits.patch_exe(patch_exe)

-- Every file of code with its load address: the executable, then the overlays
-- as the executable lists them.
local code_files = { { name = EXE, base = EXE_CODE, skip = 0x800 } }
for i = 0, 15 do
  local name = bin.cstr(exe, exe_off(bin.u32(exe, exe_off(REL_BIN_FILES + 4 * i))))
  code_files[#code_files + 1] = { name = name, base = bin.u32(exe, exe_off(REL_BIN_OFFSETS + 4 * i)), skip = 0 }
end

local total = 0
for _, f in ipairs(code_files) do
  local data, lba, size = iso.read(f.name)
  if f.name == EXE then data = exe end
  local code = data:sub(f.skip + 1, size)
  local patches, refs = reloc.scan(bin.words(code), f.base, tables.move, f.name)
  if f.name == EXE then
    for i, w in pairs(exe_extra) do
      if patches[i] then error(string.format("%s: %08X is both moved and patched", f.name, f.base + 4 * (i - 1))) end
      patches[i] = w
    end
  end
  if next(patches) then
    -- word indices are relative to the code; shift them past the header
    local shifted = {}
    for i, w in pairs(patches) do shifted[i + f.skip // 4] = w end
    local out, n = bin.apply_words(data, shifted)
    dwrc.disc.write(lba, out)
    dwrc.log(string.format("%s: %d references moved (%d words changed)", f.name, refs, n))
    total = total + refs
  end
end

-- One texture per type, read at type * 9 sectors: the new types' entries go
-- after the game's 180. `textures[type]` = a TIM for a new type.
local textures = {}

-- --- the Digimon from Digimon World 2003 ----------------------------------------
local DIGIMON_DATA = 0x8012CEB4      -- the game's own copy (USA: boneCount at +20)
local DIGIMON_SKELETONS = 0x8011CE60 -- pointers to {s8 object, s8 parent}[boneCount]
local built = {}                     -- the backports that were built (type -> entry)

local function fnv(s) -- a checksum to compare with research/tools/dw1convert.py
  local h = 0x811C9DC5
  for i = 1, #s do h = ((h ~ s:byte(i)) * 0x01000193) & 0xFFFFFFFF end
  return h
end

local dw3 = dwrc.discs.info("dw3")
local dw3_table = dw3 and backports.DW3[dw3.serial]
if not dw3 then
  dwrc.log("no Digimon World 2003 disc in the library: the Digimon from it are left out")
elseif not dw3_table then
  dwrc.log("Digimon World 2003 " .. dw3.serial .. " isn't supported yet (only the European disc, SLES-03936): the Digimon from it are left out")
else
  local disc3 = iso.disc(function(lba, count) return dwrc.discs.read("dw3", lba, count) end)
  local exe3 = disc3:read(dw3_table.exe)
  local function file3(n)
    local o = n * 4 + dw3_table.sectors - dw3_table.load + 0x800
    local lba = string.unpack("<i4", exe3, o + 1)
    local count = string.unpack("<I2", exe3, n * 2 + dw3_table.counts - dw3_table.load + 0x800 + 1)
    return dwrc.discs.read("dw3", lba, count)
  end
  local alltim
  for _, b in ipairs(backports.list) do
    local src = b.source[dw3.serial]
    local ok, err = pcall(function()
      local t1 = os.clock()
      local m3 = dw3model.read(file3(src.file), src.bones, src.motions)
      local mats = dw3model.pose(m3, m3.idle_frame)
      local skel, n = {}, bin.s32(exe, exe_off(DIGIMON_DATA + b.donor * 0x34 + 20))
      local sk = bin.u32(exe, exe_off(DIGIMON_SKELETONS + 4 * b.donor))
      for i = 0, n - 1 do skel[i] = { string.unpack("<i1i1", exe, exe_off(sk + 2 * i) + 1) }; skel[i][3] = nil end
      alltim = alltim or read_game_file("ALLTIM.TIM")
      local entry = alltim:sub(b.donor * TEXTURE_SIZE + 1, (b.donor + 1) * TEXTURE_SIZE)
      local mmd, tim, info = convert.convert(b.mapping, m3, mats, skel, read_game_file(b.donor_file), entry, b.height)
      if #mmd > 0x18800 then error(string.format("its model is %d bytes, more than the partner's 100,352", #mmd)) end
      files.add(b.file .. ".MMD", mmd)
      textures[b.type] = tim
      built[b.type] = b
      dwrc.log(string.format("%s built from %s: %d vertices, %d polygons, %d bytes (%.2f s; checksums %08X %08X)",
        b.name, dw3.title, info.verts, info.prims, #mmd, os.clock() - t1, fnv(mmd), fnv(tim)))
    end)
    if not ok then dwrc.log(b.name .. " couldn't be built: " .. tostring(err)) end
  end
end

-- Developer option: type 199, a copy of Agumon, for testing new type numbers.
local test_clone = dwrc.options.test_clone
local CLONE, CLONE_OF, CLONE_FILE = 199, 3, "XAGU"
if test_clone then
  local alltim = read_game_file("ALLTIM.TIM")
  textures[CLONE] = alltim:sub(CLONE_OF * TEXTURE_SIZE + 1, (CLONE_OF + 1) * TEXTURE_SIZE)
  files.add(CLONE_FILE .. ".MMD", read_game_file("AGUM.MMD"))
end

if next(textures) then
  local alltim = read_game_file("ALLTIM.TIM")
  assert(#alltim == 180 * TEXTURE_SIZE, "ALLTIM.TIM isn't 180 textures")
  local extra = {}
  for t = 180, tables.CAPACITY - 1 do extra[#extra + 1] = textures[t] or string.rep("\0", TEXTURE_SIZE) end
  files.add("ALLTIM.TIM", alltim .. table.concat(extra))
end

dwrc.log(string.format("roster core ready: %d references moved, %d bytes at %08X..%08X (%.2f s)", total, tables.BYTES, tables.HEAP_START, tables.END, os.clock() - t0))

-- A new type's 4-letter file name, in the moved tables' string room.
local function set_file_name(ctx, t, name)
  local at = tables.STRINGS + 16 * (t - 180)
  ctx:write_bytes(at, name .. "\0")
  ctx:write32(tables.entry("PTR_DIGIMON_FILE_NAMES", t), at)
end

local function setup(ctx)
  for t, b in pairs(built) do
    -- For now every table entry starts as the donor's (stats, care, voice,
    -- techniques); the Digimon's own values come next.
    tables.copy_entries(ctx, b.donor, t)
    local data = tables.entry("DIGIMON_DATA", t) -- USA: name[20], ..., height +26, level +29
    ctx:write_bytes(data, b.name .. string.rep("\0", 20 - #b.name))
    ctx:write16(data + 26, b.height)
    ctx:write8(data + 29, b.level)
    set_file_name(ctx, t, b.file)
    ctx:write16(tables.entry("EVOLUTION_STATS_GAINS", t) + 12, t) -- the evolution target names it
  end
  if not test_clone then return end
  tables.copy_entries(ctx, CLONE_OF, CLONE)
  -- DigimonPara (USA): name[20] first; level at +29 (a Champion, so the
  -- clone is what Agumon evolves into)
  local data = tables.entry("DIGIMON_DATA", CLONE)
  ctx:write_bytes(data, "Test Agumon" .. string.rep("\0", 9))
  ctx:write8(data + 29, 4)
  -- Agumon's only evolution is the clone, with requirements it meets:
  -- care mistakes >= -1, every stat (HP/10 >= 0, the one it averages) and
  -- the "from Agumon" bonus make 3 points; the weight point (-1 +- 5) is
  -- missed on purpose.
  local paths = tables.entry("EVOLUTION_PATHS", CLONE_OF) + 5
  ctx:write_bytes(paths, string.char(CLONE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))
  local reqs = tables.entry("EVOLUTION_REQS", CLONE)
  local r = { CLONE_OF, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1 }
  for i, v in ipairs(r) do ctx:write16(reqs + 2 * (i - 1), v & 0xFFFF) end
  ctx:write8(reqs + 26, 0)
  set_file_name(ctx, CLONE, CLONE_FILE)
  -- EvoStatsGains {hp, mp, off, def, speed, brains, targetDigimon}: an
  -- evolution target is an index here, and this names the Digimon
  ctx:write16(tables.entry("EVOLUTION_STATS_GAINS", CLONE) + 12, CLONE)
end

tables.install(dwrc.options.check_relocation, setup)
limits.install()
files.install()
if dwrc.options.check_evolution then
  evolution.compare(0x800DD7AC, 200) -- from partnerTick, every frame in the field
else
  evolution.install()
end
