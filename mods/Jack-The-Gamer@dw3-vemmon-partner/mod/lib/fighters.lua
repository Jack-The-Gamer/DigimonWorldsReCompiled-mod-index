-- Partner fighters for the mod's Digimon (FIGHTSTG's fighters file,
-- SMDLDATA.PRO, file 460).
--
-- The file: { base, entries, partners, enemies } (offsets; base is the
-- address FighterInfo.face assumes the file is at), the entries
-- { id s16, index u8, kind u8 } up to an id 0 (kind 0x3A and up: an enemy,
-- found in the enemies' table, else in the partners'; nothing else reads
-- kind), the partners' FighterInfo (0xC4 bytes: model, motions, effects as
-- file << 16 | entry, face, distance, height, 12 cameras) and the enemies'
-- (0x48 bytes, 3 cameras). The mod adds its entries and partner infos at the
-- end of the file (a copy of the lists with its own after them) and points
-- the header there; the file is read where the file cache has it.
--
-- A partner made from an enemy's model (Vemmon, Galacticmon) needs more of
-- its model's motions and its action scripts than the enemy has:
--   motions (setMotion reads entry motion - 1 of the motions' archive, and
--   an absent one is garbage): a partner's scripts 6, 7 and 8 play motions
--   20-24, 26-30 and 32-36 the way script 5 (its attack) plays 14-18; the
--   item script 10 plays 44-45, script 11 50-51, the Digimon change 13.
--   The enemy's motions archive is copied with every absent motion pointing
--   at the one that takes its place (the attack's, the entrance's, the idle);
--   scripts: the enemy's own (0-4 the reactions, 5 its attack), and a
--   template partner's generic ones that the battle code asks for by number
--   (6 and 8 attack variants, 10, 14, 15 and 17 items).
-- Both go in the model's file as new entries; cameras come from a partner of
-- about the same size.

local bin = require("lib.bin")
local disc = require("lib.disc")
local sprites = require("lib.sprites")

local M = {}

M.FILE = 460
M.PARTNER_INFO = 0xC4
M.ENEMY_INFO = 0x48
M.PARTNER_KIND = 0x38            -- any kind under 0x3A is a partner's

-- The partner scripts the battle code or techniques start by number, taken
-- from the template where the enemy has none (Galacticmon's body has no
-- basic attack, 5: an absent script reads the archive's offsets as commands)
local GENERIC_SCRIPTS = { 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17 }
-- absent motion -> the one that stands in for it
local MOTION_STAND_INS = { [13] = 12, [38] = 14, [39] = 15, [44] = 0, [45] = 1, [50] = 16, [51] = 17 }
for k = 0, 4 do
  MOTION_STAND_INS[20 + k] = 14 + k
  MOTION_STAND_INS[26 + k] = 14 + k
  MOTION_STAND_INS[32 + k] = 14 + k
end
local MOTION_SLOTS = 62

local file                       -- the fighters file, being changed
local new_entries, new_infos = {}, {}
local faceless = {}              -- new infos (by number) whose face is none (commit)

local function load()
  if file then return end
  file = { data = disc.read_file(M.FILE) }
  file.base, file.entries, file.partners, file.enemies = string.unpack("<I4I4I4I4", file.data)
  file.list = {}
  local o = file.entries
  while true do
    local id, index, kind = string.unpack("<i2BB", file.data, o + 1)
    if id == 0 then break end
    file.list[#file.list + 1] = { id = id, index = index, kind = kind }
    o = o + 4
  end
  file.partner_count = 0
  for _, e in ipairs(file.list) do
    if e.kind < 0x3A and e.index + 1 > file.partner_count then file.partner_count = e.index + 1 end
  end
end

-- A fighter's entry and info bytes.
function M.info(id)
  load()
  for _, e in ipairs(file.list) do
    if e.id == id then
      if e.kind >= 0x3A then
        local o = file.enemies + e.index * M.ENEMY_INFO
        return e, file.data:sub(o + 1, o + M.ENEMY_INFO), true
      end
      local o = file.partners + e.index * M.PARTNER_INFO
      return e, file.data:sub(o + 1, o + M.PARTNER_INFO), false
    end
  end
  for _, n in ipairs(new_entries) do
    if n.id == id then return n, new_infos[n.index - file.partner_count + 1], false end
  end
  error(string.format("no fighter %x", id))
end

-- An archive entry's offset table (count = first / 4).
local function offsets(entry)
  local n = bin.u32(entry, 0) // 4
  local t = {}
  for i = 0, n - 1 do t[i] = bin.u32(entry, 4 * i) end
  return t, n
end

-- A model's copy, scaled: the model's bone list (entry `bone_entry` of the
-- model file's archive `list`: texture entry, count, then parent, mesh entry
-- and keys entry per bone) again, with its meshes' vertices and its keys'
-- positions times `scale`, and `offset` added to the top bones' positions
-- (those under the implicit root). Mesh entry: archive [0] vertices (the
-- count in the first 6-byte vector's x, then 6-byte vectors), [1] normals,
-- [2] polygons; keys entry: archive [0] positions, [1] rotations, [2] scales,
-- keys of x, y, z, frame up to a frame >= 30000. The copies go at the end of
-- `list`; returns the new bone list's entry.
local function round(v)
  v = math.floor(v + 0.5)
  if v > 32767 then return 32767 elseif v < -32768 then return -32768 end
  return v
end

local function scaled_model(list, bone_entry, scale, offset)
  local bones = list[bone_entry + 1]
  local tex, count = string.unpack("<I4I4", bones)
  local copies = {}
  local function copy(e, key, f)
    if copies[key] == nil then
      list[#list + 1] = f(list[e + 1])
      copies[key] = #list - 1
    end
    return copies[key]
  end
  local function mesh(m)
    local vo = bin.u32(m, 0)
    local n = bin.s16(m, vo)
    local out = {}
    for k = 0, n - 1 do
      local x, y, z = string.unpack("<i2i2i2", m, vo + 6 + 6 * k + 1)
      out[k + 1] = string.pack("<i2i2i2", round(x * scale), round(y * scale), round(z * scale))
    end
    return m:sub(1, vo + 6) .. table.concat(out) .. m:sub(vo + 6 + 6 * n + 1)
  end
  local function keys(top)
    return function(kd)
      local po = bin.u32(kd, 0)
      assert(po ~= 0 or not top, "a top bone without positions")
      if po == 0 then return kd end
      local e = #kd
      for j = 0, po // 4 - 1 do
        local o = bin.u32(kd, 4 * j)
        if o > po and o < e then e = o end
      end
      local out, p = {}, po
      while p + 8 <= e do
        local x, y, z, f = string.unpack("<i2i2i2i2", kd, p + 1)
        x, y, z = x * scale, y * scale, z * scale
        if top then x, y, z = x + offset[1], y + offset[2], z + offset[3] end
        out[#out + 1] = string.pack("<i2i2i2i2", round(x), round(y), round(z), f)
        p = p + 8
        if f >= 30000 then break end
      end
      return kd:sub(1, po) .. table.concat(out) .. kd:sub(p + 1)
    end
  end
  local out = { string.pack("<I4I4", tex, count) }
  for b = 0, count - 1 do
    local parent, m, k = string.unpack("<I4I4I4", bones, 8 + 12 * b + 1)
    local top = parent == 0
    out[#out + 1] = string.pack("<I4I4I4", parent, copy(m, "m" .. m, mesh),
      copy(k, (top and "t" or "k") .. k, keys(top)))
  end
  list[#list + 1] = table.concat(out)
  return #list - 1
end

-- Adds a partner fighter `id` made from enemy fighter `enemy`'s model, with
-- the generic scripts and the cameras of partner fighter `template`.
-- opts: distance (the template's by default), copies {[dst] = src} of
-- scripts, scale and offset (a scaled copy of the model, scaled_model).
-- Returns its info's address-independent description.
function M.add_partner_from_enemy(id, enemy, template, opts)
  opts = opts or {}
  load()
  local _, einfo, is_enemy = M.info(enemy)
  assert(is_enemy, string.format("fighter %x isn't an enemy", enemy))
  local _, tinfo = M.info(template)
  local model, motions, effects, face = string.unpack("<I4I4I4I4", einfo)
  local mfile = model >> 16
  assert(motions >> 16 == mfile and effects >> 16 == mfile, "the enemy's model, motions and scripts aren't in one file")

  local list = sprites.read_archive(disc.read_file(mfile))
  if opts.scale then
    model = (mfile << 16) | scaled_model(list, model & 0xFFFF, opts.scale, opts.offset or { 0, 0, 0 })
  end

  -- motions: every slot, absent ones pointing at their stand-ins
  local mot = list[(motions & 0xFFFF) + 1]
  local mo, mn = offsets(mot)
  assert(mn >= MOTION_SLOTS, "a motions archive with fewer slots than a partner's")
  local new_mo = {}
  for i = 0, mn - 1 do
    local o = mo[i]
    if o == 0 then
      local s = MOTION_STAND_INS[i] or 0
      if mo[s] == 0 then s = 0 end
      o = mo[s]
    end
    new_mo[i + 1] = string.pack("<I4", o)
  end
  local motions_entry = table.concat(new_mo) .. mot:sub(4 * mn + 1)

  -- scripts: the enemy's, then the template's generic ones it lacks
  local function scripts_of(info_bytes)
    local m2, _, ef = string.unpack("<I4I4I4", info_bytes)
    local l = sprites.read_archive(disc.read_file(ef >> 16))
    return sprites.read_archive(l[(ef & 0xFFFF) + 1])
  end
  local own = scripts_of(einfo)
  local tmpl = scripts_of(tinfo)
  local count = math.max(#own, #tmpl)
  local scripts = {}
  for i = 1, count do scripts[i] = own[i] or false end
  for _, s in ipairs(GENERIC_SCRIPTS) do
    if not scripts[s + 1] then scripts[s + 1] = tmpl[s + 1] or false end
  end
  for dst, src in pairs(opts.copies or {}) do scripts[dst + 1] = scripts[src + 1] end
  -- an archive of scripts ends with an offset of 0 only where the game's do;
  -- keep every slot (an absent one stays 0)
  local effects_entry = sprites.build_archive(scripts)

  -- the model's file with the two new entries
  local mentry = #list
  list[#list + 1] = motions_entry
  list[#list + 1] = effects_entry
  disc.replace_file(mfile, sprites.build_archive(list))

  -- the partner info: the enemy's model and face, the template's cameras
  local distance = opts.distance or string.unpack("<i2", tinfo, 0x10 + 1)
  local info = string.pack("<I4I4I4I4", model, (mfile << 16) | mentry, (mfile << 16) | (mentry + 1), face)
    .. string.pack("<i2", distance) .. tinfo:sub(0x12 + 1, M.PARTNER_INFO)
  local index = file.partner_count + #new_infos
  new_entries[#new_entries + 1] = { id = id, index = index, kind = M.PARTNER_KIND }
  new_infos[#new_infos + 1] = info
  return { model = model, motions = (mfile << 16) | mentry, effects = (mfile << 16) | (mentry + 1) }
end

-- Adds a partner fighter `id` that is a copy of partner fighter `template`
-- (its model, motions, scripts and cameras).
function M.add_partner_copy(id, template)
  load()
  local _, info, is_enemy = M.info(template)
  assert(not is_enemy, string.format("fighter %x isn't a partner", template))
  local index = file.partner_count + #new_infos
  new_entries[#new_entries + 1] = { id = id, index = index, kind = M.PARTNER_KIND }
  new_infos[#new_infos + 1] = info
end

-- Adds a partner fighter `id` that is partner fighter `template` with its
-- model, motions and scripts read from file `model_file` instead (a copy of
-- the template's model file with other meshes and texture, models.lua).
function M.add_partner_model(id, template, model_file)
  load()
  local _, info, is_enemy = M.info(template)
  assert(not is_enemy, string.format("fighter %x isn't a partner", template))
  local model, motions, effects = string.unpack("<I4I4I4", info)
  info = string.pack("<I4I4I4", (model_file << 16) | (model & 0xFFFF), (model_file << 16) | (motions & 0xFFFF),
    (model_file << 16) | (effects & 0xFFFF)) .. info:sub(13)
  local index = file.partner_count + #new_infos
  new_entries[#new_entries + 1] = { id = id, index = index, kind = M.PARTNER_KIND }
  new_infos[#new_infos + 1] = info
  -- no face: the template's FaceRects (eyes blinking by copying rectangles of
  -- its texture, FIGHTSTG_createFace) would scribble on the new texture
  faceless[#new_infos] = true
end

-- A partner fighter's model file (its FighterInfo.model's file).
function M.model_file(id)
  local _, info = M.info(id)
  return string.unpack("<I4", info) >> 16
end

-- Writes the fighters file: its data, then the entries (game's and mod's,
-- 0-ended) and the partners' infos (game's and mod's), the header pointing
-- at them.
function M.commit()
  if not file or #new_entries == 0 then return end
  local d = bin.pad(file.data, 4)
  local entries = {}
  for _, e in ipairs(file.list) do entries[#entries + 1] = string.pack("<i2BB", e.id, e.index, e.kind) end
  for _, e in ipairs(new_entries) do entries[#entries + 1] = string.pack("<i2BB", e.id, e.index, e.kind) end
  entries[#entries + 1] = string.pack("<i2BB", 0, 0, 0)
  local o_entries = #d
  d = d .. table.concat(entries)
  d = bin.pad(d, 4)
  local o_partners = #d
  d = d .. file.data:sub(file.partners + 1, file.partners + file.partner_count * M.PARTNER_INFO) .. table.concat(new_infos)
  d = bin.put(d, 4, string.pack("<I4I4", o_entries, o_partners))
  -- an empty FaceRects (x 0xFF ends it) for the faceless ones; FighterInfo.face
  -- is an address, the file's base + an offset
  local o_face = #d
  d = d .. string.rep(string.char(0xFF), 8)
  for k in pairs(faceless) do
    d = bin.put32(d, o_partners + (file.partner_count + k - 1) * M.PARTNER_INFO + 12, file.base + o_face)
  end
  disc.replace_file(M.FILE, d)
end

return M
