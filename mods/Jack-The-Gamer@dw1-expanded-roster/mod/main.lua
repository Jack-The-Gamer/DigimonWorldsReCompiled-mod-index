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
-- changed and the mod ships nothing of the game's.
-- The new Digimon (lib/backports.lua) are built from the player's Digimon
-- World 2003 and Digimon World 2 discs while the mod loads (lib/dw3model.lua,
-- lib/dw2model.lua, lib/convert.lua),
-- with their chart icons (lib/icon.lua), finishers (lib/limits.lua) and
-- evolutions (lib/evolution.lua, lib/chart.lua).

local bin = require("lib.bin")
local iso = require("lib.iso")
local reloc = require("lib.reloc")
local tables = require("lib.tables")
local limits = require("lib.limits")
local files = require("lib.files")
local evolution = require("lib.evolution")
local backports = require("lib.backports")
local dw3model = require("lib.dw3model")
local dw2model = require("lib.dw2model")
local convert = require("lib.convert")
local chart = require("lib.chart")
local icon = require("lib.icon")

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

-- Every file of code with its load address: the executable, then the overlays
-- as the executable lists them.
local code_files = { { name = EXE, base = EXE_CODE, skip = 0x800 } }
for i = 0, 15 do
  local name = bin.cstr(exe, exe_off(bin.u32(exe, exe_off(REL_BIN_FILES + 4 * i))))
  code_files[#code_files + 1] = { name = name, base = bin.u32(exe, exe_off(REL_BIN_OFFSETS + 4 * i)), skip = 0 }
end

-- Changes to the code besides the moved references (lib/limits.lua):
-- file -> { addr -> {expect, value} }, checked against the code below.
local extra = {}
limits.patch_code(function(file, addr, expect, value)
  extra[file] = extra[file] or {}
  extra[file][addr] = { expect, value }
end)

local total = 0
for _, f in ipairs(code_files) do
  local data, lba, size = iso.read(f.name)
  if f.name == EXE then data = exe end
  local code = data:sub(f.skip + 1, size)
  local words = bin.words(code)
  limits.note_code(f.name, f.base, words)
  local patches, refs = reloc.scan(words, f.base, tables.move, f.name)
  for addr, p in pairs(extra[f.name] or {}) do
    local i = (addr - f.base) // 4 + 1
    if words[i] ~= p[1] then error(string.format("%s: unexpected code at %08X: %08X, not %08X", f.name, addr, words[i] or 0, p[1])) end
    if patches[i] then error(string.format("%s: %08X is both moved and patched", f.name, addr)) end
    patches[i] = p[2]
  end
  extra[f.name] = nil
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
for name in pairs(extra) do error("patches for " .. name .. ", which isn't one of the game's code files") end

-- One texture per type, read at type * 9 sectors: the new types' entries go
-- after the game's 180. `textures[type]` = a TIM for a new type.
local textures = {}

-- --- the Digimon from Digimon World 2003 and Digimon World 2 ---------------------
local DIGIMON_DATA = 0x8012CEB4      -- the game's own copy (USA: boneCount at +20)
local DIGIMON_SKELETONS = 0x8011CE60 -- pointers to {s8 object, s8 parent}[boneCount]
local built = {}                     -- the backports that were built (type -> entry)
local icons = {}                     -- their chart icons (type -> {pixels, clut})

local function fnv(s) -- a checksum to compare with research/tools/dw1convert.py
  local h = 0x811C9DC5
  for i = 1, #s do h = ((h ~ s:byte(i)) * 0x01000193) & 0xFFFFFFFF end
  return h
end

-- The other games' discs the backports come from: game -> {info, file(n)}
-- (files by number through each executable's own file table).
local sources = {}
do
  local dw3 = dwrc.discs.info("dw3")
  local t3 = dw3 and backports.DW3[dw3.serial]
  if not dw3 then
    dwrc.log("no Digimon World 2003 disc in the library: the Digimon from it are left out")
  elseif not t3 then
    dwrc.log("Digimon World 2003 " .. dw3.serial .. " isn't supported yet (only the European disc, SLES-03936): the Digimon from it are left out")
  else
    local exe3 = iso.disc(function(lba, count) return dwrc.discs.read("dw3", lba, count) end):read(t3.exe)
    sources.dw3 = { info = dw3, file = function(n)
      local lba = string.unpack("<i4", exe3, n * 4 + t3.sectors - t3.load + 0x800 + 1)
      local count = string.unpack("<I2", exe3, n * 2 + t3.counts - t3.load + 0x800 + 1)
      return dwrc.discs.read("dw3", lba, count)
    end }
  end
  local dw2 = dwrc.discs.info("dw2")
  local t2 = dw2 and backports.DW2[dw2.serial]
  if not dw2 then
    dwrc.log("no Digimon World 2 disc in the library: the Digimon from it are left out")
  elseif not t2 then
    dwrc.log("Digimon World 2 " .. dw2.serial .. " isn't supported yet (only the American disc, SLUS-01193): the Digimon from it are left out")
  else
    local exe2 = iso.disc(function(lba, count) return dwrc.discs.read("dw2", lba, count) end):read(t2.exe)
    sources.dw2 = { info = dw2, file = function(n)
      local lba = string.unpack("<i4", exe2, t2.lba + 4 * n + 1)
      local count = string.unpack("<I2", exe2, t2.sectors + 2 * n + 1)
      return dwrc.discs.read("dw2", lba, count)
    end }
  end
end

do
  local alltim
  for _, b in ipairs(backports.list) do
    local game = b.game or "dw3"
    local src = sources[game]
    local spec = src and b.source[src.info.serial]
    if src and not spec then dwrc.log(b.name .. " isn't known on " .. src.info.title .. " yet: left out") end
    if spec then
      local ok, err = pcall(function()
        local t1 = os.clock()
        local m3, mats
        if game == "dw2" then
          m3 = dw2model.read(src.file(spec.model))
          mats = dw2model.pose(m3, src.file(spec.anim), 0, 0)
        else
          m3 = dw3model.read(src.file(spec.file), spec.bones, spec.motions)
          mats = dw3model.pose(m3, m3.idle_frame)
        end
        local skel, n = {}, bin.s32(exe, exe_off(DIGIMON_DATA + b.donor * 0x34 + 20))
        local sk = bin.u32(exe, exe_off(DIGIMON_SKELETONS + 4 * b.donor))
        for i = 0, n - 1 do skel[i] = { string.unpack("<i1i1", exe, exe_off(sk + 2 * i) + 1) }; skel[i][3] = nil end
        alltim = alltim or read_game_file("ALLTIM.TIM")
        local entry = alltim:sub(b.donor * TEXTURE_SIZE + 1, (b.donor + 1) * TEXTURE_SIZE)
        -- a finisher playing another of the donor's motions (finisher.anim):
        -- technique slot k is animation 0x2E + k
        local alias
        local f = b.finisher
        if f and f.anim then
          local data, from_k, anim_k = DIGIMON_DATA + b.donor * 0x34, nil, nil
          for k = 0, 15 do
            local m = exe:byte(exe_off(data + 35 + k) + 1)
            if m == f.from then from_k = k end
            if m == f.anim then anim_k = k end
          end
          local l = f.lunge -- the dive's travel: a copy of the motion that moves it forward
          if from_k and anim_k then alias = { [0x2E + from_k] = l and { 0x2E + anim_k, l.frame, l.frames, l.distance } or 0x2E + anim_k }
          else dwrc.log(string.format("%s: its donor has no technique %d or %d; %s keeps its own motion", b.name, f.from, f.anim, f.name)) end
        end
        local mmd, tim, info = convert.convert(b.mapping, m3, mats, skel, read_game_file(b.donor_file), entry, b.height, alias)
        if #mmd > 0x18800 then error(string.format("its model is %d bytes, more than the partner's 100,352", #mmd)) end
        files.add(b.file .. ".MMD", mmd)
        textures[b.type] = tim
        built[b.type] = b
        local pixels, clut = icon.render(info.faces, info.texture, { head = b.icon_head or { 3, 4 }, head_scale = b.icon_head_scale, pivots = info.pivots, split = b.icon_split, split_factor = b.icon_split_factor, no_white = b.icon_no_white, head_from_second = b.icon_head_from_second, width = info.texture_w })
        icons[b.type] = { pixels = pixels, clut = clut }
        dwrc.log(string.format("%s built from %s: %d vertices, %d polygons, %d bytes%s (%.2f s; checksums %08X %08X)",
          b.name, src.info.title, info.verts, info.prims, #mmd, info.packed and string.format(", texture packed at %d%%", info.packed.scale * 5) or "",
          os.clock() - t1, fnv(mmd), fnv(tim)))
      end)
      if not ok then dwrc.log(b.name .. " couldn't be built: " .. tostring(err)) end
    end
  end
end

-- The new finishers' numbers (lib/tables.lua), given out in type order now
-- (not at boot) so the battle effect hooks know them in every session, a
-- loaded state's too: each looks like its donor finisher in battle.
local finisher_id = {}
local ORIGINAL_DIGIMON_TYPES = 0x8012A84C -- s16 per type, -1 = itself
for t, b in pairs(built) do
  local o = string.unpack("<i2", exe, exe_off(ORIGINAL_DIGIMON_TYPES + 2 * b.donor) + 1)
  limits.original_type[t] = o >= 0 and o or b.donor -- battle effects treat it as its donor
end
do
  local types = {}
  for t, b in pairs(built) do if b.finisher then types[#types + 1] = t end end
  table.sort(types)
  local next_id = tables.FIRST_NEW_FINISHER
  for _, t in ipairs(types) do
    local b = built[t]
    if next_id >= tables.FINISHER_END then
      dwrc.log("no room for more finishers: " .. b.name .. " keeps its donor's")
    elseif #b.finisher.name >= tables.MOVE_STRING_BYTES then
      dwrc.log(b.name .. "'s finisher name is too long: " .. b.finisher.name)
    else
      local f = b.finisher
      finisher_id[t] = next_id
      -- its look: the donor finisher's effect, or another one (f.effect),
      -- started from f.origin {bone, x, y, z} if given, or from a list of
      -- them, one for each of the effect's start points in order
      limits.efe_source[next_id] = f.effect or f.from
      if f.origin then
        local points = type(f.origin[1]) == "table" and f.origin or { f.origin }
        limits.efe_origin[next_id] = { type = limits.original_type[t], points = points }
      end
      next_id = next_id + 1
    end
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

-- --- the evolution lists -------------------------------------------------------
-- Worked out here, when the mod loads, on a copy of the game's EvolutionPath
-- table (from[5], to[6] per type, row type - 1; 0xFF none) read from the
-- executable, so the lists past the slots (evolution.extra, .extra_from)
-- are known in every session, a save state's too; the rows are written to
-- the moved table at boot (setup).
local EVOLUTION_PATHS_EXE = 0x8012B66C -- 62 rows in the executable
local rows = {}                        -- type -> its 11 bytes (1-based)

local function row(t)
  if not rows[t] then
    local r = {}
    for i = 1, 11 do r[i] = 0xFF end
    if t >= 1 and t <= 62 then
      local at = exe_off(EVOLUTION_PATHS_EXE + (t - 1) * 11)
      for i = 1, 11 do r[i] = exe:byte(at + i) end
    end
    rows[t] = r
  end
  return rows[t]
end

-- A list in its slots is centred the way the game's are (the chart's
-- detail page draws slot i at place i): an odd count in 5 places, an even
-- one in 4 (from) or 6 (to).
local function write_list(r, off, size, items)
  local n = #items
  local span = (n % 2 == 1) and 5 or (size == 5 and 4 or 6)
  local start = (span - n) // 2
  for i = 1, size do r[off + i] = 0xFF end
  for i, v in ipairs(items) do r[off + start + i] = v end
end

-- The lists past their slots: evolution.extra (targets the mod's pickers
-- try after the six) and evolution.extra_from; the chart's detail page
-- shows both.
local function extras(is_to) return is_to and evolution.extra or evolution.extra_from end

-- Type t's list (offset 0 from[5], 5 to[6]): the first `size` in its
-- slots, the rest as extras.
local function set_list(t, off, size, items, is_to)
  local first, rest = {}, {}
  for i, v in ipairs(items) do if i <= size then first[#first + 1] = v else rest[#rest + 1] = v end end
  write_list(row(t), off, size, first)
  extras(is_to)[t] = #rest > 0 and rest or nil
end

-- Adds `t` after the entries of type f's list, or to its extras when the
-- slots are full.
local function add_to_list(f, off, size, t, is_to)
  local r = row(f)
  local items = {}
  for i = 1, size do
    local v = r[off + i]
    if v == t then return end -- already there
    if v ~= 0xFF then items[#items + 1] = v end
  end
  local more = extras(is_to)
  for _, v in ipairs(more[f] or {}) do if v == t then return end end
  if #items < size then
    items[#items + 1] = t
    write_list(r, off, size, items)
  else
    more[f] = more[f] or {}
    table.insert(more[f], t)
  end
end

-- In type order (a backport may evolve from another one: Growlmon from
-- Guilmon). Each new type starts as a copy of its donor's row (as its other
-- entries do); its own lists replace the donor's, and each Digimon on them
-- gets it after its own (the pickers keep the earlier target on a tie, so
-- the game's own ones win ties).
do
  local types = {}
  for t in pairs(built) do types[#types + 1] = t end
  table.sort(types)
  for _, t in ipairs(types) do
    local b = built[t]
    local copy = {}
    for i, v in ipairs(row(b.donor)) do copy[i] = v end
    rows[t] = copy
    if b.evolves_from then
      set_list(t, 0, 5, b.evolves_from, false)
      for _, f in ipairs(b.evolves_from) do add_to_list(f, 5, 6, t, true) end
    end
    if b.evolutions then
      set_list(t, 5, 6, b.evolutions, true)
      for _, e in ipairs(b.evolutions) do add_to_list(e, 0, 5, t, false) end
    end
  end
end

-- The chart icons: in the mod's RAM (tables.ICONS), uploaded to the chart's
-- text area in VRAM (x 704, y 256: page 0x1B; the chart clears rows 12..211
-- when it opens and writes text only above row 72): icon i at texel (i % 8
-- * 32, 100 + i // 8 * 16), its CLUT in rows 200..211, 4 a row. Placed now
-- (chart.icons and chart.uploads are needed in every session); the bytes
-- are written at boot (setup_icons).
local ICON_TPAGE = 0x1B
local icon_writes = {}                 -- {address, bytes}
do
  local types = {}
  for t in pairs(icons) do types[#types + 1] = t end
  table.sort(types)
  for i, t in ipairs(types) do
    local n = i - 1
    if n >= 48 then dwrc.log("no room for more chart icons"); break end
    local at = tables.ICONS + n * tables.ICON_BYTES
    local u, v = (n % 8) * 32, 100 + (n // 8) * 16
    local cx, cy = 704 + (n % 4) * 16, 256 + 200 + n // 4
    icon_writes[#icon_writes + 1] = { at, icons[t].pixels }
    icon_writes[#icon_writes + 1] = { at + 256, icons[t].clut }
    icon_writes[#icon_writes + 1] = { at + 288, string.pack("<i2i2i2i2", 704 + u // 4, 256 + v, 8, 16) }
    icon_writes[#icon_writes + 1] = { at + 296, string.pack("<i2i2i2i2", cx, cy, 16, 1) }
    chart.icons[t] = { u = u, v = v, clut = (cy << 6) | (cx >> 4), tpage = ICON_TPAGE }
    chart.uploads[#chart.uploads + 1] = { at + 288, at }
    chart.uploads[#chart.uploads + 1] = { at + 296, at + 256 }
  end
end
local function setup_icons(ctx)
  for _, w in ipairs(icon_writes) do ctx:write_bytes(w[1], w[2]) end
end

local function setup(ctx)
  setup_icons(ctx)
  -- In type order: a backport may evolve from another one (Growlmon from
  -- Guilmon), and each one's entries start as a copy of its donor's.
  local types = {}
  for t in pairs(built) do types[#types + 1] = t end
  table.sort(types)
  for _, t in ipairs(types) do
    local b = built[t]
    -- For now every table entry starts as the donor's (stats, care, voice,
    -- techniques); the Digimon's own values come next.
    tables.copy_entries(ctx, b.donor, t)
    local data = tables.entry("DIGIMON_DATA", t) -- USA: name[20], ..., height +26, level +29
    ctx:write_bytes(data, b.name .. string.rep("\0", 20 - #b.name))
    ctx:write16(data + 26, b.height)
    ctx:write8(data + 29, b.level)
    set_file_name(ctx, t, b.file)
    -- DigimonPara: radius +24, attribute +28, specialties +30..32
    if b.radius then ctx:write16(data + 24, b.radius) end
    if b.attribute then ctx:write8(data + 28, b.attribute) end
    if b.specialties then ctx:write_bytes(data + 30, string.char(table.unpack(b.specialties))) end
    -- Its own finisher (finisher_id): the donor finisher's stats (power,
    -- MP, range...) under its own name, in place of that one in its
    -- moves[] (DigimonPara +35, technique by animation slot: the
    -- animation stays the donor's, and so does the effect, see above)
    if finisher_id[t] then
      local f, id = b.finisher, finisher_id[t]
      local str = tables.MOVE_STRINGS + tables.MOVE_STRING_BYTES * (id - tables.FIRST_NEW_FINISHER)
      ctx:write_bytes(str, f.name .. string.rep("\0", tables.MOVE_STRING_BYTES - #f.name))
      ctx:write32(tables.entry("MOVE_NAMES", id), str)
      ctx:write_bytes(tables.entry("MOVE_DATA", id), ctx:read_bytes(tables.entry("MOVE_DATA", f.from), 16))
      local found = false
      for i = 0, 15 do
        if ctx:read8(data + 35 + i) == f.from then
          ctx:write8(data + 35 + i, id)
          found = true
        end
      end
      if not found then dwrc.log(string.format("%s has no technique %d to replace with %s", b.name, f.from, f.name)) end
    end
    -- EvoStatsGains {hp, mp, off, def, speed, brains, targetDigimon}: the
    -- evolution target is an index here, and this names the Digimon
    local gains = tables.entry("EVOLUTION_STATS_GAINS", t)
    if b.gains then for i, v in ipairs(b.gains) do ctx:write16(gains + 2 * (i - 1), v) end end
    ctx:write16(gains + 12, t)
    -- EvoRequirements: 13 int16 then flags
    if b.requirements then
      local r, reqs = b.requirements, tables.entry("EVOLUTION_REQS", t)
      for i, k in ipairs({ "digimon", "hp", "mp", "offense", "defense", "speed", "brain", "care", "weight", "discipline", "happiness", "battles", "techs" }) do
        ctx:write16(reqs + 2 * (i - 1), r[k] & 0xFFFF)
      end
      ctx:write8(reqs + 26, r.flags)
    end
    -- RAISE_DATA: viewX/Y/Z at +22 (the Digimon page's camera)
    if b.view then
      local raise = tables.entry("RAISE_DATA", t)
      for i, v in ipairs(b.view) do ctx:write16(raise + 22 + 2 * (i - 1), v & 0xFFFF) end
    end
  end
  -- the evolution lists worked out above
  for t, r in pairs(rows) do ctx:write_bytes(tables.entry("EVOLUTION_PATHS", t), string.char(table.unpack(r))) end
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
do
  local new_types = {}
  for t, b in pairs(built) do
    new_types[#new_types + 1] = t
    chart.stage[t] = b.chart_stage -- 6 = the Mega section (none yet)
    if dwrc.options.test_raised then limits.raised_new[t] = true end
  end
  if test_clone then new_types[#new_types + 1] = CLONE end
  table.sort(new_types)
  chart.install(new_types)
end
if dwrc.options.check_evolution then
  evolution.compare(0x800DD7AC, 200) -- from partnerTick, every frame in the field
else
  evolution.install()
end
