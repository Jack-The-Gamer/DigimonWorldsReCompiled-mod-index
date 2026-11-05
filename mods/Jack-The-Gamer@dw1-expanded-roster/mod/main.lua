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
-- evolutions (lib/tree.lua, lib/evolution.lua, lib/chart.lua).

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
local dw1source = require("lib.dw1source")
local convert = require("lib.convert")
local chart = require("lib.chart")
local tree = require("lib.tree")
local icon = require("lib.icon")
local techniques = require("lib.techniques")

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
-- (files by number through each executable's own file table); "dw1" is this
-- disc (an NPC-only Digimon's own model on a partner's skeleton).
local sources = { dw1 = { info = { serial = dwrc.serial, title = "Digimon World" } } }
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
        local function skeleton(t)
          local out, count = {}, bin.s32(exe, exe_off(DIGIMON_DATA + t * 0x34 + 20))
          local sk = bin.u32(exe, exe_off(DIGIMON_SKELETONS + 4 * t))
          for i = 0, count - 1 do out[i] = { string.unpack("<i1i1", exe, exe_off(sk + 2 * i) + 1) }; out[i][3] = nil end
          return out
        end
        local skel = skeleton(b.donor)
        alltim = alltim or read_game_file("ALLTIM.TIM")
        local m3, mats
        local mapping = b.mapping
        if game == "dw1" then
          local mmd1, skel1 = read_game_file(spec.file), skeleton(spec.type)
          -- the donor's very skeleton (the Sukamon family on Sukamon): its
          -- rest pose takes the donor's rotations, and every bone maps to itself
          local same = #skel1 == #skel
          for i = 0, #skel do
            if not skel1[i] or skel1[i][1] ~= skel[i][1] or skel1[i][2] ~= skel[i][2] then same = false end
          end
          local donor_mmd = same and read_game_file(b.donor_file) or nil
          m3 = dw1source.read(mmd1, skel1, alltim:sub(spec.type * TEXTURE_SIZE + 1, (spec.type + 1) * TEXTURE_SIZE), same)
          mats = dw1source.pose(mmd1, skel1, donor_mmd)
          if same and not mapping then
            mapping = {}
            for i = 1, #skel do mapping[i] = { i, "core" } end
          end
        elseif game == "dw2" then
          m3 = dw2model.read(src.file(spec.model))
          mats = dw2model.pose(m3, src.file(spec.anim), 0, 0)
        else
          m3 = dw3model.read(src.file(spec.file), spec.bones, spec.motions)
          mats = dw3model.pose(m3, m3.idle_frame)
        end
        local entry = alltim:sub(b.donor * TEXTURE_SIZE + 1, (b.donor + 1) * TEXTURE_SIZE)
        -- a finisher playing another of the donor's motions (finisher.anim):
        -- technique slot k is animation 0x2E + k
        local alias
        local f = b.finisher
        -- a finisher playing another DW1 Digimon's motion, retargeted
        -- (finisher.motion.file / type: Veemon's dive from Tyrannomon's Buster Dive)
        local function other_motion()
          local mo = f.motion
          local other = mo.file and { mmd = read_game_file(mo.file), skel = skeleton(mo.type) } or nil
          return { motion = mo.anim, from = mo.from, other = other, travel = other and (mo.travel or 1) or nil }
        end
        if b.techniques and b.techniques.auto and not b.techniques.moves then
          -- techniques of its specialties (lib/techniques.lua), each on one of
          -- the donor's technique motions
          local kinds, dm = {}, {}
          for _, k in ipairs(b.specialties) do if k ~= 255 then kinds[#kinds + 1] = k end end
          for k = 0, 15 do dm[k + 1] = exe:byte(exe_off(DIGIMON_DATA + b.donor * 0x34 + 35 + k) + 1) end
          b.techniques.moves, b.techniques.motions = techniques.build(function(a) return exe:byte(exe_off(a) + 1) end, dm, kinds, f.from, f.anim)
        end
        if b.techniques then
          -- another Digimon's techniques (or a list of its own, `moves`), each
          -- on one of the donor's technique motions (slot k plays animation
          -- 0x2E + k); the finisher's with its dash (lunge) or its own jump
          -- and travel made bigger (leap: KingSukamon's King Stamp), or
          -- another Digimon's motion (motion)
          alias = {}
          local data = DIGIMON_DATA + (b.techniques.from or b.donor) * 0x34
          for k, m in ipairs(b.techniques.motions) do
            local slot = k - 1
            local tech = b.techniques.moves and b.techniques.moves[k] or exe:byte(exe_off(data + 35 + slot) + 1)
            local l, leap
            if f and tech == f.from then l, leap = f.lunge, f.leap end
            if f and tech == f.from and f.motion then
              alias[0x2E + slot] = other_motion()
            elseif l or leap then
              local lp = leap and { leap.from, leap.to, leap.up, leap.forward }
              alias[0x2E + slot] = { 0x2E + m, l and l.frame or false, l and l.frames, l and l.distance, lp }
            else
              alias[0x2E + slot] = 0x2E + m
            end
          end
        elseif f and f.motion then
          -- the finisher plays one of the source's own animations, retargeted
          -- (a DW1 source: Machinedramon's Infinity Cannon)
          local data = DIGIMON_DATA + b.donor * 0x34
          for k = 0, 15 do
            if exe:byte(exe_off(data + 35 + k) + 1) == f.from then alias = { [0x2E + k] = other_motion() } end
          end
        elseif f and f.anim then
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
        -- its size: `scale` times its own (PlatinumSukamon: 1), else model_height or height
        local size = b.scale and { scale = b.scale } or b.model_height or b.height
        local mmd, tim, info = convert.convert(mapping, m3, mats, skel, read_game_file(b.donor_file), entry, size, alias)
        if #mmd > 0x18800 then error(string.format("its model is %d bytes, more than the partner's 100,352", #mmd)) end
        -- the evolution scene shatters it (lib/limits.lua: 6 bytes a vertex and a polygon)
        if 6 * (info.verts + info.prims) > tables.EVL_SCRATCH_SIZE then
          error(string.format("its %d vertices and %d polygons don't fit the evolution scene's shard buffer", info.verts, info.prims))
        end
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
  if b.techniques then
    local from = b.techniques.from
    local f = from and string.unpack("<i2", exe, exe_off(ORIGINAL_DIGIMON_TYPES + 2 * from) + 1)
    limits.borrow[t] = { type = from and (f >= 0 and f or from), bones = b.techniques.bones or {}, fallback = b.techniques.fallback,
      points = b.techniques.points, near = b.techniques.auto }
  end
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

-- The game's own Digimon that change (backports.changes): HerculesKabuterimon
-- and Phoenixmon become Megas once a Digimon they come from is built
-- (`needs`), Whamon an Ultimate, and some requirements.
local changed = {}
local level_of = {} -- type -> its level once changed
for t, b in pairs(built) do chart.stage[t] = b.chart_stage end -- 6 = the Mega section
for _, c in ipairs(backports.changes) do
  local ok = true
  for _, n in ipairs(c.needs or {}) do if not built[n] then ok = false end end
  if not ok then
    dwrc.log(c.name .. " stays an Ultimate: none of the Digimon it would come from were built")
  else
    changed[#changed + 1] = c
    if c.chart_stage then chart.stage[c.type] = c.chart_stage end
    if c.level then level_of[c.type] = c.level end
  end
end

-- The tree (lib/tree.lua): each source's targets by name, as the game's
-- partner Digimon (types 1..61) and the built backports are named; the
-- others aren't in the mod yet and are skipped.
do
  local function level(t)
    if level_of[t] then return level_of[t] end
    if built[t] then return built[t].level end
    return exe:byte(exe_off(DIGIMON_DATA + t * 0x34 + 29) + 1)
  end
  local function stage(t) return chart.stage[t] or level(t) end
  local by_name = {}
  for t = 1, 61 do by_name[bin.cstr(exe, exe_off(DIGIMON_DATA + t * 0x34))] = t end
  for t, b in pairs(built) do by_name[b.name] = t end
  local function resolve(n) return by_name[tree.aliases[n] or n] end
  local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
  local game_to, all = {}, {}
  for t = 1, 62 do
    local r = row(t)
    game_to[t] = {}
    for i = 6, 11 do if r[i] ~= 0xFF then game_to[t][#game_to[t] + 1] = r[i] end end
    all[#all + 1] = t
  end
  local new_types = {}
  for t in pairs(built) do new_types[#new_types + 1] = t end
  table.sort(new_types)
  for _, t in ipairs(new_types) do all[#all + 1] = t end
  local to, seq, skipped = {}, {}, {}
  for _, e in ipairs(tree.tree) do
    local s = resolve(e[1])
    if s and not to[s] then
      seq[#seq + 1] = s
      to[s] = {}
      for _, n in ipairs(e[2]) do
        local x = resolve(n)
        if x then
          if not has(to[s], x) then to[s][#to[s] + 1] = x end
        elseif not skipped[n] then
          skipped[n] = true
          skipped[#skipped + 1] = n
        end
      end
    end
  end
  -- not in the tree: a Fresh keeps the game's evolutions, any other has none
  -- (Megas; Phoenixmon's row holds strays)
  for _, t in ipairs(all) do
    if not to[t] then
      to[t] = {}
      if t <= 62 and level(t) == 1 then for _, x in ipairs(game_to[t]) do to[t][#to[t] + 1] = x end end
    end
  end
  local function sourced(t)
    for _, s in ipairs(all) do if has(to[s], t) then return true end end
    return false
  end
  -- Until the whole tree is in the mod: a game Digimon nothing reaches keeps
  -- the game's sources (a stage below it), and a Champion with no Ultimate
  -- keeps the game's Ultimates.
  local interim = {}
  -- a new Digimon whose sources in the tree aren't in the mod yet comes from
  -- its stand-ins (`interim_from`: PlatinumSukamon from Tanemon's Rookies,
  -- where Gotsumon would be)
  for _, t in ipairs(new_types) do
    local b = built[t]
    if b.interim_from and not sourced(t) then
      for _, n in ipairs(b.interim_from) do
        local s = resolve(n)
        if s and not has(to[s], t) then
          to[s][#to[s] + 1] = t
          interim[#interim + 1] = n .. " -> " .. b.name
        end
      end
    end
  end
  for t = 1, 61 do
    local st = stage(t)
    if st >= 3 and st <= 5 and not sourced(t) then
      for s = 1, 61 do
        if has(game_to[s], t) and stage(s) == st - 1 then
          to[s][#to[s] + 1] = t
          interim[#interim + 1] = bin.cstr(exe, exe_off(DIGIMON_DATA + s * 0x34)) .. " -> " .. bin.cstr(exe, exe_off(DIGIMON_DATA + t * 0x34))
        end
      end
    end
  end
  for t = 1, 61 do
    if stage(t) == 4 and #to[t] == 0 then
      for _, x in ipairs(game_to[t]) do
        if stage(x) == 5 then
          to[t][#to[t] + 1] = x
          interim[#interim + 1] = bin.cstr(exe, exe_off(DIGIMON_DATA + t * 0x34)) .. " -> " .. bin.cstr(exe, exe_off(DIGIMON_DATA + x * 0x34))
        end
      end
    end
  end
  -- each Digimon's sources: the tree's order, then the rest by type
  local tree_sources = { table.unpack(seq) }
  local in_seq = {}
  for _, s in ipairs(seq) do in_seq[s] = true end
  for _, t in ipairs(all) do if not in_seq[t] then seq[#seq + 1] = t end end
  local from = {}
  for _, s in ipairs(seq) do
    for _, x in ipairs(to[s]) do
      from[x] = from[x] or {}
      from[x][#from[x] + 1] = s
    end
  end
  -- every row: a new type's other entries start as its donor's (setup)
  for _, t in ipairs(all) do
    if not rows[t] then
      local r = {}
      for i = 1, 11 do r[i] = 0xFF end
      rows[t] = r
    end
    set_list(t, 0, 5, from[t] or {}, false)
    set_list(t, 5, 6, to[t], true)
  end
  dwrc.log(string.format("evolution tree: %d Digimon with evolutions; not in the mod yet: %d (%s); for now (the game's routes and stand-ins): %s",
    #tree_sources, #skipped, table.concat(skipped, ", "), #interim > 0 and table.concat(interim, ", ") or "none"))
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

-- A Digimon's stat gains (EvoStatsGains {hp, mp, off, def, speed, brains})
-- and requirements (EvoRequirements: 13 int16 then flags), when given.
local function write_evolution(ctx, t, b)
  local gains = tables.entry("EVOLUTION_STATS_GAINS", t)
  if b.gains then for i, v in ipairs(b.gains) do ctx:write16(gains + 2 * (i - 1), v) end end
  if b.requirements then
    local r, reqs = b.requirements, tables.entry("EVOLUTION_REQS", t)
    for i, k in ipairs({ "digimon", "hp", "mp", "offense", "defense", "speed", "brain", "care", "weight", "discipline", "happiness", "battles", "techs" }) do
      if r[k] then ctx:write16(reqs + 2 * (i - 1), r[k] & 0xFFFF) end -- only the fields given
    end
    if r.flags then ctx:write8(reqs + 26, r.flags) end
  end
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
    -- another Digimon's techniques (DigimonPara.moves[16] at +35; their
    -- motions are aliased in the model, their start points translated by
    -- lib/limits.lua)
    if b.techniques and b.techniques.moves then
      local m = b.techniques.moves
      ctx:write_bytes(tables.entry("DIGIMON_DATA", t) + 35, string.char(table.unpack(m)) .. string.rep(string.char(0xFF), 16 - #m))
    elseif b.techniques then
      ctx:write_bytes(tables.entry("DIGIMON_DATA", t) + 35, ctx:read_bytes(tables.entry("DIGIMON_DATA", b.techniques.from) + 35, 16))
    end
    -- RaiseData (meals, sleep, poop, favourite food, training, default
    -- weight, the Digimon page's camera) from another Digimon: a Rookie on a
    -- Champion's skeleton cares like a Rookie
    if b.raise_from then
      ctx:write_bytes(tables.entry("RAISE_DATA", t), ctx:read_bytes(tables.entry("RAISE_DATA", b.raise_from), 0x1C))
    end
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
      -- its stats: the donor finisher's, or another technique's (f.stats)
      ctx:write_bytes(tables.entry("MOVE_DATA", id), ctx:read_bytes(tables.entry("MOVE_DATA", f.stats or f.from), 16))
      -- Move {s32 distance, s16 power, ...}: its own power (a Rookie's or an
      -- Ultimate's on a donor finisher of another level)
      if f.power then ctx:write16(tables.entry("MOVE_DATA", id) + 4, f.power) end
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
    ctx:write16(tables.entry("EVOLUTION_STATS_GAINS", t) + 12, t)
    write_evolution(ctx, t, b)
    -- RAISE_DATA: viewX/Y/Z at +22 (the Digimon page's camera)
    if b.view then
      local raise = tables.entry("RAISE_DATA", t)
      for i, v in ipairs(b.view) do ctx:write16(raise + 22 + 2 * (i - 1), v & 0xFFFF) end
    end
  end
  -- the game's Digimon that change (backports.changes: the Megas)
  for _, c in ipairs(changed) do
    write_evolution(ctx, c.type, c)
    if c.level then ctx:write8(tables.entry("DIGIMON_DATA", c.type) + 29, c.level) end -- DigimonPara.level
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
evolution.install_megas() -- Ultimates become Megas (lib/evolution.lua)
