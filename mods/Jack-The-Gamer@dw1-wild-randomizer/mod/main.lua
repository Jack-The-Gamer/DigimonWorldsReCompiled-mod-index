-- DW1 Wild Digimon Randomizer: the wild Digimon on each map become other
-- Digimon of the same stage that share at least two of their specialties.
--
-- How Digimon World (USA, SLUS-01032) puts Digimon on a map (dw_decomp names):
-- loadMap reads the map's .MAP file; loadMapEntities (0x800A9A68) copies its
-- 120-byte exit table, then loadMapDigimon(data, mapId) (0x800B5D0C, called
-- from 0x800A9BD0) fills MAP_DIGIMON_TABLE (0x8013CB50, 8 x 0xC4: typeId +0,
-- followMode +0xBC) and NPC_ENTITIES (0x80155828, 8 x 0x68: Stats from +0x38,
-- moves[4] +0x44) from a list of up to 8 Digimon, when the map's MAP_ENTRIES
-- (0x801292D4, 16 bytes, flags +12) flag 0x80 is set. Slots past the list
-- keep the previous map's values (clearMapDigimon only resets the paths).
-- The map's scripts then load a model by type when they need it (script op
-- LOAD_DIGIMON -> scriptLoadModel 0x801069C0, remembered in
-- LOADED_DIGIMON_MODELS 0x801BE7EC and unloaded by scriptUnloadModel
-- 0x80106C08; every model goes at map change) and place slot n with
-- SET_DIGIMON(type, n) (scriptSetDigimon 0x800B6118), which does nothing
-- unless `type` is the slot's typeId. Battles use the placed Digimon with
-- the map's stats.
--
-- An enemy's moves[] are animation numbers 0x2E + k, k an index into its
-- DIGIMON_DATA moves[16] (technique numbers; boneCount +20, level +29,
-- special[3] +30); slot 3 is its finisher (techniques 0x3A and up, used when
-- the finisher gauge fills). MOVE_DATA's specialty is at +9.
--
-- Wild: Digimon that roam and chase (followMode 2 or 12), of a type below 128
-- (128..179 are the game's own copies of the partner Digimon, used for
-- recruits and story fights), Rookie to Ultimate with techniques. Story
-- Digimon and recruits stand still (followMode 1: the Beach's Coelamon,
-- Seadramon, Palmon) and stay. A type that also has a non-wild Digimon on
-- the map stays (they share one loaded model).
--
-- The mod: after loadMapDigimon (hook at 0x800A9BD8) it marks the wild slots
-- in typeId's padding (+2: 0x4000 | type; the game never uses it, and save
-- states keep it), the map's list length in slot 0's padding (+194, with
-- 0x5A at +195) and the map number in slot 1's (+194). When a script loads a wild type's model, it picks the
-- replacement for every slot of that type (one model, as before), writes it
-- to typeId, marks them 0x8000 | original type and turns their moves into
-- the new Digimon's own (the same technique where it has it, otherwise one
-- of its own of the same kind, its finisher for a finisher). With Random
-- techniques (option), every wild Digimon's regular slots, also those of one
-- that stays itself, then get techniques drawn from all its own that its
-- model can play, per Digimon and visit (per area with Fixed). Stats, bits and
-- behaviour stay the map's. LOAD_DIGIMON, UNLOAD_DIGIMON and SET_DIGIMON
-- with the original type then get the replacement.
--
-- Memory: NPC models (and each NPC's bone data: boneCount x 136 + 82 bytes)
-- come from the heap (malloc3; K&R free list, freep at 0x80115A24, headers
-- {next, size in 8-byte units}, taken from the top). A map's scripts load
-- only some of its listed Digimon on a visit (Gear Savanna lists six kinds
-- and loads two), and which ones isn't known in advance, so a replacement
-- may take as much heap as the original (model + bone data) did, and more
-- only when the largest free block still holds every model of the map not
-- loaded yet, every NPC's bone data and a margin. Model sizes come from
-- FILE_OFFSET_TABLE (0x8011FE1C, {sector, size, name*}). A replacement of
-- the game's own loads a light copy of its model (see "Light copies"), and
-- once a map's loads are known (see "Learning") only the models its
-- scripts loaded before are counted, plus the biggest of the others.
--
-- DW1 Expanded Roster: that mod moves the per-Digimon tables (and raises the
-- type limit) and rewrites the game's code to use them, so the tables are
-- read through the game's own instructions: DIGIMON_DATA (lui/addiu at
-- 0x800AA374/8), PTR_DIGIMON_FILE_NAMES (0x800A2120/8), MOVE_DATA
-- (0x800BC3F0/8) and the NPC model limit (slti at 0x800A1F98). Its new
-- Digimon join the pool (option). Its files aren't in FILE_OFFSET_TABLE: it
-- loads a smaller copy of each new Digimon's model on a map (NAME.NPC: only
-- the animations a wild Digimon plays, its finisher and up to three other
-- techniques) and describes that copy in the file name's 16 bytes (name,
-- kept technique slots u16 at +6, "NPC" at +8, size at +12); without that (versions
-- up to 0.11.0) a new Digimon counts as the largest model a partner can
-- have. None of its hooks share an address with these.

local POST_LOAD = 0x800A9BD8
local JAL_LOAD_MAP_DIGIMON = 0x0C02D743   -- at 0x800A9BD0
local SCRIPT_LOAD_MODEL, SCRIPT_UNLOAD_MODEL, SCRIPT_SET_DIGIMON = 0x801069C0, 0x80106C08, 0x800B6118
local FIRST_WORDS = { [SCRIPT_LOAD_MODEL] = 0x27BDFFE8, [SCRIPT_UNLOAD_MODEL] = 0x27BDFFE8, [SCRIPT_SET_DIGIMON] = 0x27BDFFD0 }

local MAP_DIGIMON_TABLE, MAP_DIGIMON_SIZE, FOLLOW_MODE, LIST_LENGTH = 0x8013CB50, 0xC4, 0xBC, 194
local NPC_ENTITIES, NPC_SIZE, NPC_MOVES = 0x80155828, 0x68, 0x44
local LOADED_DIGIMON_MODELS = 0x801BE7EC
local MAP_ENTRIES = 0x801292D4
local FREEP = 0x80115A24
local FILE_OFFSET_TABLE = 0x8011FE1C
local VANILLA_ORIGINAL_TYPES = 0x8012A84C  -- s16 per type below 180, -1 = itself

local REFS = {
  data = { 0x800AA374, 0x800AA378, 0x8012CEB4 },
  names = { 0x800A2120, 0x800A2128, 0x8011D19C },
  moves = { 0x800BC3F0, 0x800BC3F8, 0x8012623C },
}
local LIMIT_SLTI, VANILLA_TYPES = 0x800A1F98, 180

local PARA_SIZE = 0x34
local MAX_MODEL = 0x18800       -- the partner model buffer: no Digimon's model is bigger
local NPC_TAG = 0x0043504E      -- "NPC\0": Expanded Roster's map copy of a model, its size after it
local MARGIN = 0x2000           -- heap kept free beyond what the map still needs
local WILD, CHOSEN, LIST_SIGN = 0x4000, 0x8000, 0x5A

local EVERY_VISIT = dwrc.options.reroll ~= "Fixed"
local WITH_ROSTER = dwrc.options.expanded_roster ~= false
local RANDOM_TECHNIQUES = dwrc.options.techniques ~= "Matched"

if not dwrc.data.seed then
  dwrc.data.seed = math.random(1, 0x7FFFFFFF)
  dwrc.save()
end
local visit = 0                            -- counts map loads (Every visit)
local session = math.random(0, 0x7FFFFFFF)  -- so each play session differs

-- Numbers ---------------------------------------------------------------------

local function mix(x)
  x = x ~ (x >> 33)
  x = x * 0xFF51AFD7ED558CCD
  x = x ~ (x >> 33)
  x = x * 0xC4CEB9FE1A85EC53
  return x ~ (x >> 33)
end

local function sext16(v) return v >= 0x8000 and v - 0x10000 or v end
local function padded(size) return (size + 0x7FF) & ~0x7FF end
local function block(bytes) return ((bytes + 7) & ~7) + 8 end  -- one malloc3 with its header

-- `lui r, hi` + `addiu r, r, lo` -> the address, or the game's own when the
-- words aren't that.
local function ref(ctx, r)
  local lui, add = ctx:read32(r[1]), ctx:read32(r[2])
  if (lui >> 26) ~= 0x0F or (add >> 26) ~= 0x09 or ((lui >> 16) & 31) ~= ((add >> 21) & 31) then return r[3] end
  return ((lui & 0xFFFF) << 16) + sext16(add & 0xFFFF)
end

local function cstring(ctx, at, max)
  if at < 0x80000000 or at >= 0x80200000 then return "" end
  return ctx:read_bytes(at, max or 24):match("^[^%z]*")
end

-- Models' animations ---------------------------------------------------------------
--
-- An MMD is {u32 TMD offset, u32 animation table offset}, the TMD, then the
-- table (u32 offsets from the table, 0 = none; the first is the table's
-- size). A Digimon that walks the field and fights needs the animations the
-- game's own wild Digimon all have: 0 1 2 4 19 33-37 40-44, and 0x2E + k for
-- each technique k it uses. The game's copies of the partner Digimon
-- (128..179) were cut down for their own scenes: Kuwagamon's (EKUW.MMD) has
-- 28 animations and fell apart in a battle. Read from the disc while the mod
-- loads (CHDAT\MMD0..5); Expanded Roster's models (added past the disc's end)
-- carry a partner's whole animation table.

local NEEDED_ANIMS = { 0, 1, 2, 4, 19, 33, 34, 35, 36, 37, 40, 41, 42, 43, 44 }
local anims = {}   -- "AGUM.MMD" -> { [index] = true }
local mmd_at = {}  -- "AGUM.MMD" -> its directory entry {lba, size}

local function u32(s, o) return string.unpack("<I4", s, o + 1) end

local function directory(lba, size)
  local data, out, o = dwrc.disc.read(lba, (size + 2047) // 2048), {}, 0
  while o < #data do
    local len = data:byte(o + 1)
    if len == 0 then
      o = (o // 2048 + 1) * 2048
    else
      local name = data:sub(o + 34, o + 33 + data:byte(o + 33)):gsub(";1$", "")
      out[name] = { lba = u32(data, o + 2), size = u32(data, o + 10), dir = (data:byte(o + 26) & 2) ~= 0 }
      o = o + len
    end
  end
  return out
end

local function read_animation_tables()
  local pvd = dwrc.disc.read(16, 1)
  if pvd:sub(2, 6) ~= "CD001" then return end
  local chdat = directory(u32(pvd, 156 + 2), u32(pvd, 156 + 10)).CHDAT
  if not chdat then return end
  for name, d in pairs(directory(chdat.lba, chdat.size)) do
    if d.dir and name:match("^MMD%d$") then
      for file, f in pairs(directory(d.lba, d.size)) do
        if file:match("%.MMD$") and f.size >= 16 then
          local at = u32(dwrc.disc.read(f.lba, 1), 4)
          if at < f.size then
            local s = dwrc.disc.read(f.lba + at // 2048, 2)
            local o = at % 2048
            local n = math.min(u32(s, o) // 4, (#s - o) // 4, 128)
            local present = {}
            for i = 0, n - 1 do
              if u32(s, o + 4 * i) ~= 0 then present[i] = true end
            end
            anims[file] = present
            mmd_at[file] = f
          end
        end
      end
    end
  end
end

local ok, err = pcall(read_animation_tables)
if not ok then
  anims = {}
  dwrc.log("DW1 Wild Randomizer: couldn't read the models' animations: " .. tostring(err))
end

-- Light copies -----------------------------------------------------------------------
--
-- The partner Digimon's models (Greymon's GREY.MMD: 93 KB) also hold their
-- care, training and menu motions, which a wild Digimon never plays. While
-- the mod loads, each model that can walk and fight gets a light copy
-- (NAME.WLD, added past the disc's end): the same TMD, the animations
-- above and every technique slot (0x2E..0x3D), the other motions left out,
-- when that saves at least 4 KB. A map script's load of a model only wild
-- Digimon of this map use (a replacement; no story Digimon of that type
-- there) reads the copy: loadMMD's NPC branch (0x800A1F68) has built the
-- path CHDAT\MMDn\NAME.MMD at sp+40 (type in s1) by the `jal
-- lookupFileSize` at 0x800A2190, hooked there (DW1 Expanded Roster hooks
-- 0x800A2188 for its own models), and lookupFileTable (0x800A31F8: `addiu
-- sp,sp,-40` first, so hooked at its second instruction, 0x800A31FC, after
-- Expanded Roster's at its first) answers NAME.WLD.

local SAVES_AT_LEAST = 4096
local light = {}   -- "GREY.MMD" -> { name = "GREY.WLD", lba, size }
local light_names = {}  -- "GREY.WLD" -> that entry

-- The motions no table entry plays any more left out: the rest in order,
-- each 4-aligned, the table pointed at their new places (`starts`: every
-- entry's original offset, for the motions' extents). From DW1 Expanded
-- Roster's lib/convert.lua.
local function prune_anims(anims_, count, starts)
  local table_, seen, bounds, used = {}, {}, {}, {}
  for a = 0, count - 1 do table_[a] = string.unpack("<I4", anims_, 4 * a + 1) end
  for a = 0, count - 1 do
    for _, o in ipairs({ starts[a] or 0, table_[a] }) do
      if o ~= 0 and not seen[o] then seen[o] = true; bounds[#bounds + 1] = o end
    end
    if table_[a] ~= 0 then used[table_[a]] = true end
  end
  table.sort(bounds)
  bounds[#bounds + 1] = #anims_
  local parts, len, moved = { anims_:sub(1, 4 * count) }, 4 * count, {}
  for i = 1, #bounds - 1 do
    local a, b = bounds[i], bounds[i + 1]
    if used[a] then
      local pad = (4 - len % 4) % 4
      parts[#parts + 1] = string.rep("\0", pad)
      len = len + pad
      moved[a] = len
      parts[#parts + 1] = anims_:sub(a + 1, b)
      len = len + (b - a)
    end
  end
  local out = table.concat(parts)
  local words = {}
  for a = 0, count - 1 do words[#words + 1] = string.pack("<I4", table_[a] ~= 0 and moved[table_[a]] or 0) end
  return table.concat(words) .. out:sub(4 * count + 1)
end

local function light_model(mmd)
  local anim_at = u32(mmd, 4)
  local anims_ = mmd:sub(anim_at + 1)
  local count = u32(anims_, 0) // 4
  local wanted, offs, words = {}, {}, {}
  for _, a in ipairs(NEEDED_ANIMS) do wanted[a] = true end
  for k = 0, 15 do wanted[0x2E + k] = true end
  for a = 0, count - 1 do
    offs[a] = u32(anims_, 4 * a)
    words[#words + 1] = string.pack("<I4", wanted[a] and offs[a] or 0)
  end
  return mmd:sub(1, anim_at) .. prune_anims(table.concat(words) .. anims_:sub(4 * count + 1), count, offs)
end

local function build_light_copies()
  local made, saved = 0, 0
  for file, f in pairs(mmd_at) do
    local ready = true
    for _, i in ipairs(NEEDED_ANIMS) do ready = ready and anims[file][i] == true end
    if ready then
      local mmd = dwrc.disc.read(f.lba, (f.size + 2047) // 2048):sub(1, f.size)
      local copy = light_model(mmd)
      if #copy + SAVES_AT_LEAST <= f.size then
        local entry = { name = file:sub(1, -5) .. ".WLD", size = #copy }
        entry.lba = dwrc.disc.append(copy)
        light[file], light_names[entry.name] = entry, entry
        made, saved = made + 1, saved + f.size - #copy
      end
    end
  end
  dwrc.log(string.format("DW1 Wild Randomizer: %d light copies of the game's models, %d KiB smaller in all", made, saved // 1024))
end

if next(anims) then
  local built, why = pcall(build_light_copies)
  if not built then
    light, light_names = {}, {}
    dwrc.log("DW1 Wild Randomizer: no light copies: " .. tostring(why))
  end
end

-- The game's tables -------------------------------------------------------------

local file_sizes   -- "AGUM.MMD" -> bytes (the game's own files)

local function read_file_sizes(ctx)
  file_sizes = {}
  for i = 0, 1199 do
    local e = FILE_OFFSET_TABLE + 12 * i
    local size = ctx:read32(e + 4)
    if size == 0 then break end
    file_sizes[cstring(ctx, ctx:read32(e + 8), 16)] = size
  end
end

-- Every Digimon type: name, level, specialties, techniques, bones, model
-- size, and group (one Digimon under several numbers: the game's partner
-- copies, Expanded Roster's raisable versions of the enemies).
local function read_types(ctx)
  if not file_sizes then read_file_sizes(ctx) end
  local data, names, moves = ref(ctx, REFS.data), ref(ctx, REFS.names), ref(ctx, REFS.moves)
  local limit = VANILLA_TYPES
  local slti = ctx:read32(LIMIT_SLTI)
  if WITH_ROSTER and (slti >> 16) == 0x2A21 then limit = math.max(VANILLA_TYPES, math.min(slti & 0xFFFF, 400)) end

  local raw = ctx:read_bytes(data, limit * PARA_SIZE)
  local types, by_name = {}, {}
  for t = 0, limit - 1 do
    local o = t * PARA_SIZE
    local spec, techs, any = {}, {}, false
    for i = 0, 2 do
      local s = raw:byte(o + 31 + i)
      if s ~= 0xFF then spec[s] = true end
    end
    for k = 0, 15 do
      local m = raw:byte(o + 36 + k)
      if m ~= 0xFF then
        techs[#techs + 1] = { k = k, tech = m, kind = ctx:read8(moves + 16 * m + 9) }
        if m ~= 0 then any = true end
      end
    end
    local name_at = ctx:read32(names + 4 * t)
    local file = cstring(ctx, name_at, 8)
    local size = file_sizes[file .. ".MMD"]
    local kept_slots   -- Expanded Roster's map copy: bit k = technique slot k there
    if not size and t >= VANILLA_TYPES and file ~= "" then
      -- Expanded Roster's map copy (NAME.NPC), its size and techniques beside the name
      local npc = ctx:read32(name_at + 12)
      if ctx:read32(name_at + 8) == NPC_TAG and npc > 0 and npc <= MAX_MODEL then
        size, kept_slots = npc, ctx:read16(name_at + 6)
      else
        size = MAX_MODEL
      end
    end
    if not any then techs = {} end  -- the town Digimon have zeros
    -- able to walk and fight (see "Models' animations")
    local a, ready = anims[file .. ".MMD"], true
    if a then
      for _, i in ipairs(NEEDED_ANIMS) do ready = ready and a[i] == true end
      local usable = {}
      for _, m in ipairs(techs) do if a[0x2E + m.k] then usable[#usable + 1] = m end end
      techs = usable
    elseif t < VANILLA_TYPES then
      ready = next(anims) == nil and t < 128  -- the tables couldn't be read: no cut-down copies
    elseif kept_slots then
      local usable = {}
      for _, m in ipairs(techs) do if (kept_slots >> m.k) & 1 == 1 then usable[#usable + 1] = m end end
      techs = usable
    end
    types[t] = {
      t = t, name = raw:sub(o + 1, o + 20):match("^[^%z]*"), level = raw:byte(o + 30), spec = spec,
      techs = techs, ready = ready, bones = string.unpack("<i4", raw, o + 21), size = size,
      light = t < VANILLA_TYPES and light[file .. ".MMD"] and light[file .. ".MMD"].size or nil,
    }
  end
  -- Groups: the game's partner copies (128..179) belong to their partner,
  -- other types are their own, and Expanded Roster's join the game's Digimon
  -- of the same name.
  for t = 0, VANILLA_TYPES - 1 do
    local orig = sext16(ctx:read16(VANILLA_ORIGINAL_TYPES + 2 * t))
    local g = (t >= 128 and orig >= 0 and orig < 128) and orig or t
    types[t].group = g
    if g == t and not by_name[types[t].name] then by_name[types[t].name] = t end
  end
  for t = VANILLA_TYPES, limit - 1 do types[t].group = by_name[types[t].name] or t end
  return types, limit
end

-- Choosing --------------------------------------------------------------------------

local function count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

-- The same level, and at least two shared specialties (all of them when the
-- wild Digimon has fewer than two).
local function fits(orig, cand)
  if not cand.ready or cand.level ~= orig.level or cand.name == "" or not cand.size or cand.size == 0 or #cand.techs == 0 then return false end
  if cand.bones < 1 or cand.bones > 64 then return false end
  local need, shared = math.min(2, count(orig.spec)), 0
  for s in pairs(orig.spec) do if cand.spec[s] then shared = shared + 1 end end
  return need > 0 and shared >= need
end

-- The model a wild Digimon of type c loads: its light copy, if it has one.
local function wild_size(c) return c.light or c.size end

-- The replacements for `orig`: one type per Digimon (group), the smallest
-- model among the types that are that Digimon under its own name; the
-- game's own before Expanded Roster's (its Gotsumon, Goburimon... are the
-- game's models on a partner's skeleton).
local function candidates(types, limit, orig)
  local best = {}
  for t = 0, limit - 1 do
    local c = types[t]
    if c.group ~= orig.group and fits(orig, c) and c.name == types[c.group].name then
      local b = best[c.group]
      local own, b_own = c.t < VANILLA_TYPES, b and b.t < VANILLA_TYPES
      if not b or (own and not b_own) or (own == b_own and wild_size(c) < wild_size(b)) then best[c.group] = c end
    end
  end
  local list = {}
  for _, c in pairs(best) do list[#list + 1] = c end
  return list
end

local function is_finisher(tech) return tech >= 0x3A end

-- The enemy's four move slots for its new type.
local function remap_moves(orig, cand, slots)
  local orig_by_k = {}
  for _, m in ipairs(orig.techs) do orig_by_k[m.k] = m end
  local regular, finisher, by_tech = {}, nil, {}
  for _, m in ipairs(cand.techs) do
    by_tech[m.tech] = m
    if is_finisher(m.tech) then finisher = finisher or m else regular[#regular + 1] = m end
  end
  local out, used, wanted = {}, {}, {}
  local function take(m)
    if not m or used[m.k] then return nil end
    used[m.k] = true
    return 0x2E + m.k
  end
  -- first the techniques the new Digimon has too, then the rest
  for j = 0, 3 do
    local a = slots[j]
    local m = (a ~= 0xFF and a >= 0x2E) and orig_by_k[a - 0x2E] or nil
    wanted[j] = m
    if m and by_tech[m.tech] and (j == 3) == is_finisher(m.tech) then out[j] = take(by_tech[m.tech]) end
  end
  for j = 0, 3 do
    local m = wanted[j]
    if m and not out[j] then
      if j == 3 and is_finisher(m.tech) then
        out[j] = take(finisher)
      else
        for _, r in ipairs(regular) do
          if r.kind == m.kind and not used[r.k] then out[j] = take(r) break end
        end
        if not out[j] then
          for _, r in ipairs(regular) do
            if not used[r.k] then out[j] = take(r) break end
          end
        end
      end
    end
    out[j] = out[j] or 0xFF
  end
  if out[0] == 0xFF and out[1] == 0xFF and out[2] == 0xFF and out[3] == 0xFF then
    out[0] = 0x2E + (regular[1] or cand.techs[1]).k
  end
  return out
end

-- Random techniques: the slots holding a regular technique get regular
-- techniques drawn at random (without repeats) from all the Digimon's own
-- that its model can play; the finisher slot keeps its finisher.
local function shuffle_moves(cand, out, seed)
  local pool, is_regular = {}, {}
  for _, m in ipairs(cand.techs) do
    if not is_finisher(m.tech) then
      pool[#pool + 1] = 0x2E + m.k
      is_regular[0x2E + m.k] = true
    end
  end
  for i = #pool, 2, -1 do
    local j = (mix(seed + i) & 0x7FFFFFFF) % i + 1
    pool[i], pool[j] = pool[j], pool[i]
  end
  local n = 0
  for j = 0, 3 do
    if is_regular[out[j]] then
      n = n + 1
      out[j] = pool[n]
    end
  end
  return out
end

-- Memory ------------------------------------------------------------------------------

local function largest_free(ctx)
  local start = ctx:read32(FREEP)
  local p, best = start, 0
  for _ = 1, 4096 do
    if p < 0x80000000 or p >= 0x80200000 then break end
    best = math.max(best, ctx:read32(p + 4) * 8)
    p = ctx:read32(p)
    if p == start then break end
  end
  return best
end

local function bone_data(bones) return block(bones * 136) + block(bones * 82) end

local function loaded(ctx, t)
  for i = 0, 7 do
    if ctx:read32(LOADED_DIGIMON_MODELS + 4 * i) == t then return true end
  end
  return false
end

-- The hooks --------------------------------------------------------------------------------

local function slot_at(i) return MAP_DIGIMON_TABLE + i * MAP_DIGIMON_SIZE end
local function mark(ctx, i) return ctx:read16(slot_at(i) + 2) end

local function listed(ctx)
  if ctx:read8(slot_at(0) + LIST_LENGTH + 1) ~= LIST_SIGN then return 0 end
  return math.min(ctx:read8(slot_at(0) + LIST_LENGTH), 8)
end

-- After loadMapDigimon: mark the wild slots.
local function mark_wild(ctx)
  if ctx:read32(POST_LOAD - 8) ~= JAL_LOAD_MAP_DIGIMON then return end
  visit = visit + 1
  local map = ctx:reg("s5") & 0xFFFF
  local n = ctx:read16(ctx:reg("s3"))
  for i = 0, 7 do ctx:write16(slot_at(i) + 2, 0) end
  ctx:write16(slot_at(0) + LIST_LENGTH, 0)
  if map > 254 or n < 1 or n > 8 or (ctx:read8(MAP_ENTRIES + 16 * map + 12) & 0x80) == 0 then return end
  ctx:write8(slot_at(0) + LIST_LENGTH, n)
  ctx:write8(slot_at(0) + LIST_LENGTH + 1, LIST_SIGN)
  ctx:write8(slot_at(1) + LIST_LENGTH, map)

  local types = read_types(ctx)
  local wild = {}
  for i = 0, n - 1 do
    local t = ctx:read16(slot_at(i))
    local follow = ctx:read8(slot_at(i) + FOLLOW_MODE)
    local ty = types[t]
    local ok = ty ~= nil and t < 128 and ty.level >= 3 and ty.level <= 5 and #ty.techs > 0
      and (follow == 2 or follow == 12)
    if wild[t] == nil then wild[t] = ok else wild[t] = wild[t] and ok end
  end
  for i = 0, n - 1 do
    local t = ctx:read16(slot_at(i))
    if wild[t] then ctx:write16(slot_at(i) + 2, WILD | t) end
  end
end

-- A wild type's model is about to load: choose its replacement.
local function choose(ctx, t)
  local n = listed(ctx)
  local slots = {}
  for i = 0, n - 1 do
    if mark(ctx, i) == (WILD | t) then slots[#slots + 1] = i end
  end
  if #slots == 0 then return nil end
  local types, limit = read_types(ctx)
  local orig = types[t]

  -- what the map still needs besides this model: the other types' models
  -- not loaded yet, and every Digimon's bone data. Once a map's loads are
  -- known (see "Learning"), only the models its scripts loaded before, and
  -- room for the biggest of the others in case one comes this time.
  local map = ctx:read8(slot_at(1) + LIST_LENGTH)
  local learned = dwrc.data.loads and dwrc.data.loads[tostring(map)]
  local others, unseen, seen, taken, story = 0, 0, { [t] = true }, {}, {}
  for i = 0, n - 1 do
    local u, mk = ctx:read16(slot_at(i)), mark(ctx, i)
    if (mk & CHOSEN) ~= 0 then taken[u] = true end
    if (mk & (WILD | CHOSEN)) == 0 then story[u] = true end
  end
  for i = 0, n - 1 do
    local u, mk = ctx:read16(slot_at(i)), mark(ctx, i)
    if not seen[u] then
      seen[u] = true
      if not loaded(ctx, u) then
        local ty = types[u]
        local size = padded(ty and ((mk & CHOSEN) ~= 0 and not story[u] and wild_size(ty) or ty.size) or MAX_MODEL) + 8
        local scripts_load = (mk & (WILD | CHOSEN)) ~= 0 and (mk & 0x3FFF) or u  -- the type the map's scripts ask for
        if not learned or learned[tostring(scripts_load)] then others = others + size
        else unseen = math.max(unseen, size) end
      end
    end
    if mk ~= (WILD | t) then others = others + bone_data(types[u] and types[u].bones or 32) end
  end
  local room = largest_free(ctx) - others - unseen - MARGIN - #slots * 8

  local nonce = EVERY_VISIT and (session + visit * 0x9E3779B9) or dwrc.data.seed
  local list = candidates(types, limit, orig)
  for _, c in ipairs(list) do c.order = mix(nonce * 0x100000 + map * 0x400 + t * 0x10000000 + c.t) end
  table.sort(list, function(a, b) return a.order < b.order end)
  local own = padded(orig.size) + #slots * bone_data(orig.bones)
  local pick, fallback
  for _, c in ipairs(list) do
    local takes = padded(story[c.t] and c.size or wild_size(c)) + #slots * bone_data(c.bones)
    if takes <= own or takes + 8 <= room then
      if not taken[c.t] then pick = c break end
      fallback = fallback or c
    end
  end
  pick = pick or fallback

  local techs = {}
  for _, i in ipairs(slots) do
    local at = NPC_ENTITIES + i * NPC_SIZE + NPC_MOVES
    local moves = {}
    for j = 0, 3 do moves[j] = ctx:read8(at + j) end
    local out = pick and remap_moves(orig, pick, moves) or moves  -- one that stays keeps its own
    if RANDOM_TECHNIQUES then out = shuffle_moves(pick or orig, out, mix(nonce * 0x100000 + map * 0x400 + t * 0x10 + i) * 0x40) end
    for j = 0, 3 do ctx:write8(at + j, out[j]) end
    if pick then
      ctx:write16(slot_at(i), pick.t)
      ctx:write16(slot_at(i) + 2, CHOSEN | t)
    else
      ctx:write16(slot_at(i) + 2, 0)
    end
    local named = {}
    for j = 0, 3 do
      for _, m in ipairs((pick or orig).techs) do if out[j] == 0x2E + m.k then named[#named + 1] = string.format("%d", m.tech) end end
    end
    techs[#techs + 1] = table.concat(named, " ")
  end
  local moves_note = RANDOM_TECHNIQUES and (", techniques " .. table.concat(techs, " / ")) or ""
  if learned then moves_note = ", loads known" .. moves_note end
  if pick then
    local model = (pick.light and not story[pick.t]) and string.format(", light copy %d KiB", pick.light // 1024) or string.format(", %d KiB", pick.size // 1024)
    dwrc.log(string.format("DW1 Wild Randomizer: map %d: %s -> %s (%d candidates, %d KiB free for it%s)%s", map, orig.name, pick.name, #list, room // 1024, model, moves_note))
  else
    dwrc.log(string.format("DW1 Wild Randomizer: map %d: %s stays (%d candidates, none fit in %d KiB)%s", map, orig.name, #list, room // 1024, moves_note))
  end
  return pick and pick.t
end

-- The replacement for an original type (in `slot`, or anywhere on the map).
local function replacement(ctx, t, slot)
  local from, to = slot or 0, slot or 7
  for i = from, to do
    if mark(ctx, i) == (CHOSEN | t) then return ctx:read16(slot_at(i)) end
  end
  return nil
end

-- Learning: the types a map's scripts load on a visit (Gear Savanna lists
-- six kinds and loads two) are kept in dwrc.data.loads[map] once the visit
-- is over (the next map load), joined with the earlier visits'.
local visiting   -- { map, types = { ["83"] = true } }

local function end_visit()
  if not visiting then return end
  dwrc.data.loads = dwrc.data.loads or {}
  local key, known, new = tostring(visiting.map), dwrc.data.loads[tostring(visiting.map)], false
  if not known then known, new = {}, true end
  for u in pairs(visiting.types) do
    if not known[u] then known[u], new = true, true end
  end
  if new then
    dwrc.data.loads[key] = known
    dwrc.save()
  end
  visiting = nil
end

dwrc.on_exec(POST_LOAD, function(ctx)
  if ctx:read32(POST_LOAD - 8) ~= JAL_LOAD_MAP_DIGIMON then return false end
  end_visit()
  mark_wild(ctx)
  if listed(ctx) > 0 then visiting = { map = ctx:read8(slot_at(1) + LIST_LENGTH), types = {} } end
  return false
end)

dwrc.on_exec(SCRIPT_LOAD_MODEL, function(ctx)
  if ctx:read32(SCRIPT_LOAD_MODEL) ~= FIRST_WORDS[SCRIPT_LOAD_MODEL] then return false end
  local t = ctx:reg("a0") & 0xFF
  if visiting and listed(ctx) > 0 and ctx:read8(slot_at(1) + LIST_LENGTH) == visiting.map then visiting.types[tostring(t)] = true end
  local r = replacement(ctx, t) or choose(ctx, t)
  if r then ctx:set_reg("a0", r) end
  return false
end)

dwrc.on_exec(SCRIPT_UNLOAD_MODEL, function(ctx)
  if ctx:read32(SCRIPT_UNLOAD_MODEL) ~= FIRST_WORDS[SCRIPT_UNLOAD_MODEL] then return false end
  local r = replacement(ctx, ctx:reg("a0") & 0xFF)
  if r then ctx:set_reg("a0", r) end
  return false
end)

dwrc.on_exec(SCRIPT_SET_DIGIMON, function(ctx)
  if ctx:read32(SCRIPT_SET_DIGIMON) ~= FIRST_WORDS[SCRIPT_SET_DIGIMON] then return false end
  local slot = ctx:reg("a1") & 0xFF
  if slot > 7 then return false end
  local r = replacement(ctx, ctx:reg("a0") & 0xFF, slot)
  if r then ctx:set_reg("a0", r) end
  return false
end)

-- The light copies (see "Light copies") ------------------------------------------------

local PATH_BUILT = 0x800A2190   -- loadMMD's NPC branch: jal lookupFileSize, the path complete
local PATH_WORDS = { [0x800A218C] = 0xA3A20031, [0x800A2190] = 0x0C028CB3, [0x800A2194] = 0x27A40028 }
local FROM_SCRIPT = 0x80106A04  -- loadMMD's saved ra (sp+36) for a map script's load
local LOOKUP_FILE_TABLE = 0x800A31F8   -- lookupFileTable(FileLookup *lookup, char *path)
local LOOKUP_WORDS = { [0x800A31F8] = 0x27BDFFD8, [0x800A31FC] = 0xAFBF0020 }  -- addiu sp,sp,-40; sw ra,32(sp)

-- Only wild Digimon of this map have type u, one of them a replacement.
local function only_wild(ctx, u)
  local chosen = false
  for i = 0, listed(ctx) - 1 do
    if ctx:read16(slot_at(i)) == u then
      local mk = mark(ctx, i)
      if (mk & CHOSEN) ~= 0 then chosen = true elseif (mk & WILD) == 0 then return false end
    end
  end
  return chosen
end

local function words_match(list)
  return function(ctx)
    for a, w in pairs(list) do if ctx:read32(a) ~= w then return false end end
    return true
  end
end
local path_code, lookup_code = words_match(PATH_WORDS), words_match(LOOKUP_WORDS)

local function bcd(v) return (v // 10) * 16 + v % 10 end

if next(light) then
  dwrc.on_exec(PATH_BUILT, function(ctx)
    if not path_code(ctx) then return false end
    local sp = ctx:reg("sp")
    if ctx:read32(sp + 36) ~= FROM_SCRIPT then return false end
    local path = cstring(ctx, sp + 40, 32)
    local file = (path:match("([^\\]+)$") or path):upper()
    local copy = light[file]
    if copy and only_wild(ctx, ctx:reg("s1")) then ctx:write_bytes(sp + 40 + #path - 4, ".WLD") end
    return false
  end)
  dwrc.on_exec(LOOKUP_FILE_TABLE + 4, function(ctx)
    if not lookup_code(ctx) then return false end
    local path = cstring(ctx, ctx:reg("a1"), 64)
    local copy = light_names[(path:match("([^\\]+)$") or path):upper()]
    if not copy then return false end
    -- FileLookup: CdlLOC {minute, second, sector (BCD), track}, then the size
    local lookup, i = ctx:reg("a0"), copy.lba + 150  -- CdIntToPos counts the 2-second pregap
    ctx:write8(lookup, bcd(i // 75 // 60))
    ctx:write8(lookup + 1, bcd(i // 75 % 60))
    ctx:write8(lookup + 2, bcd(i % 75))
    ctx:write32(lookup + 4, copy.size)
    ctx:set_reg("sp", ctx:reg("sp") + 40)  -- undo the first instruction
    ctx:ret(1)
    return true
  end)
end

dwrc.log(string.format("DW1 Wild Randomizer: %s%s", EVERY_VISIT and "new Digimon every visit" or "the same Digimon every visit",
  WITH_ROSTER and ", Expanded Roster's Digimon included when it is installed" or ""))
