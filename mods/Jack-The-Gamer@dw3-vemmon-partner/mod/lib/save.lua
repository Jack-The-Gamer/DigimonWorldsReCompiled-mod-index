-- The mod's game data on the memory card, next to each save.
--
-- The save file is 4 blocks (0x8000 bytes); the game writes its header, up
-- to three icons, the info section and three slots of 0x2700 bytes, each
-- the 0x26C4 bytes of GAME's saved part and 0x3C more of the save buffer
-- (STGMCARD's dataBuf, 0x2780 bytes) that nothing reads. The mod keeps a
-- slot's extension in those 0x3C bytes and in 0x280 bytes of the file's
-- unused end (0x7800 + slot * 0x280): 700 bytes a slot.
--
-- Writing: when the game writes a slot's data (writeSave(port, dataBuf,
-- 0x26C4, 2 + slot), a step a call, 1 when done), the mod puts the
-- extension in the buffer's spare bytes and its staging area, and when the
-- data is written answers "still running" (0) once more, so that the
-- game's next call writes the staging area at the file's end (section =
-- offset << 8, which writeSave takes as is). Reading is the same with
-- readSave, whose default case is patched to take its offset the same way.
-- The return address of those calls goes through a stub in the mod's RAM,
-- where the mod sees their results.
--
-- An extension holds a CRC-32 of the save it belongs to: a slot saved
-- without the mod (or over by the game alone) loads with no Vemmon and no
-- extra entries, as a new game starts.

local eu = require("lib.eu")
local ext = require("lib.ext")
local files = require("lib.files")
local forms = require("lib.forms")
local mips = require("lib.mips")
local tables = require("lib.tables")

local M = {}

local SLACK = eu.SAVE_DATA_SIZE - eu.GAME_SAVE_SIZE       -- 0x3C
M.CAPACITY = SLACK + ext.STAGING_SIZE                     -- 700
local MAGIC = "VMX1"
local VERSION = 1

-- CRC-32 (IEEE)
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if c & 1 ~= 0 then c = 0xEDB88320 ~ (c >> 1) else c = c >> 1 end
  end
  CRC[i] = c
end
function M.crc32(s)
  local c = 0xFFFFFFFF
  for i = 1, #s, 64 do
    local bytes = { s:byte(i, math.min(i + 63, #s)) }
    for j = 1, #bytes do c = CRC[(c ~ bytes[j]) & 0xFF] ~ (c >> 8) end
  end
  return c ~ 0xFFFFFFFF
end

-- Encoding --------------------------------------------------------------

local digimon_skills = {}    -- DIGIMON_DATA index -> { skills[1..6] } (the six a form learns)
local index_of_id = {}       -- Digimon id -> DIGIMON_DATA index
local id_of = {}             -- DIGIMON_DATA index -> Digimon id

local function writer()
  local w = { parts = {} }
  function w.u8(v) w.parts[#w.parts + 1] = string.pack("<I1", v & 0xFF) end
  function w.s16(v) w.parts[#w.parts + 1] = string.pack("<i2", v) end
  function w.u32(v) w.parts[#w.parts + 1] = string.pack("<I4", v & 0xFFFFFFFF) end
  function w.raw(s) w.parts[#w.parts + 1] = s end
  function w.varint(v)
    v = v & 0xFFFFFFFF
    repeat
      local b = v & 0x7F
      v = v >> 7
      w.u8(v ~= 0 and (b | 0x80) or b)
    until v == 0
  end
  function w.data() return table.concat(w.parts) end
  return w
end

local function reader(s)
  local r = { s = s, o = 1 }
  local function need(n) if r.o + n - 1 > #s then error("short extension") end end
  function r.u8() need(1); local v = s:byte(r.o); r.o = r.o + 1; return v end
  function r.s16() need(2); local v = string.unpack("<i2", s, r.o); r.o = r.o + 2; return v end
  function r.u32() need(4); local v = string.unpack("<I4", s, r.o); r.o = r.o + 4; return v end
  function r.raw(n) need(n); local v = s:sub(r.o, r.o + n - 1); r.o = r.o + n; return v end
  function r.varint()
    local v, shift = 0, 0
    repeat
      local b = r.u8()
      v = v | ((b & 0x7F) << shift)
      shift = shift + 7
    until b & 0x80 == 0
    return v & 0xFFFFFFFF
  end
  return r
end

-- A PartnerEntry (0x14 bytes: id s16, level s8, pad, exp s32, skills s16[6])
-- in four bytes and its exp: the Digimon (DIGIMON_DATA index, 6 bits), the
-- level (7), each skill's present/known/marked bits (18), a "raw" bit;
-- a skill is "present" when it is the form's own (DigimonData.skills[i+1],
-- with SKILL_LAST on the sixth), as the game always gives them. Anything
-- else is kept raw: the id when the Digimon is unknown, the skills too.
local RAW_ID = 63

local function put_entry(w, e)
  local id, level, exp = string.unpack("<i2i1", e), e:byte(3), string.unpack("<I4", e, 5)
  local d = index_of_id[id]
  local base = d and digimon_skills[d]
  local packed, raw_skills = 0, false
  for i = 0, 5 do
    local v = string.unpack("<I2", e, 9 + 2 * i)
    if v ~= 0 then
      local last = i == 5 and 0x8000 or 0
      if base and (v & 0x1FFF) == base[i + 1] and base[i + 1] ~= 0 and (v & 0x8000) == last then
        packed = packed | ((1 | ((v >> 12) & 6)) << (3 * i))   -- bit 0 present, 1 known, 2 marked
      else
        raw_skills = true
      end
    end
  end
  if raw_skills then packed = 0 end
  local word = (d or RAW_ID) | ((level & 0x7F) << 6) | (packed << 13) | ((raw_skills and 1 or 0) << 31)
  w.u32(word)
  if not d then w.s16(id) end
  w.varint(exp)
  if raw_skills then w.raw(e:sub(9, 20)) end
end

local function get_entry(r)
  local word = r.u32()
  local d, level, packed, raw_skills = word & 0x3F, (word >> 6) & 0x7F, (word >> 13) & 0x3FFFF, (word >> 31) ~= 0
  local id = d == RAW_ID and r.s16() or id_of[d]
  local exp = r.varint()
  local skills
  if raw_skills then
    skills = r.raw(12)
  else
    local base = digimon_skills[d] or {}
    local t = {}
    for i = 0, 5 do
      local b = (packed >> (3 * i)) & 7
      local v = 0
      if b & 1 ~= 0 then v = (base[i + 1] or 0) | ((b & 6) << 12) | (i == 5 and 0x8000 or 0) end
      t[#t + 1] = string.pack("<I2", v)
    end
    skills = table.concat(t)
  end
  return string.pack("<i2I1I1I4", id, level, 0, exp) .. skills
end

local REC = ext.VEMMON
local INFO = REC + ext.P_INFO

-- The game data area (ext.DATA..DATA_END) -> the extension's payload.
local function encode(ctx)
  local w = writer()
  local rec = ctx:read_bytes(REC, ext.PARTNER_SIZE)
  local unlocked = string.unpack("<i4", rec, 0x4 + 1)
  w.u8(unlocked ~= 0 and 1 or 0)
  w.u32(string.unpack("<I4", rec, 0x8 + 1))                 -- battleDigivolve
  local info = rec:sub(ext.P_INFO + 1)
  local name = info:sub(1, 0x18)
  local z = name:find("\0", 1, true)
  name = z and name:sub(1, z - 1) or name
  w.u8(#name); w.raw(name)
  w.raw(info:sub(0x18 + 1, 0x50))                           -- exp, stats[19], status[3], slots[4]
  w.raw(info:sub(0x3C0 + 1, 0x3CD))                         -- equip[6], lastBonus
  -- the record's entries: contiguous from 0 as the game adds them
  local n = 0
  while n < ext.ENTRY_COUNT and string.unpack("<i2", info, 0x50 + n * 0x14 + 1) ~= 0 do n = n + 1 end
  local holes = false
  for i = n, ext.ENTRY_COUNT - 1 do
    if info:sub(0x50 + i * 0x14 + 1, 0x50 + i * 0x14 + 0x14) ~= string.rep("\0", 0x14) then holes = true end
  end
  if holes then
    w.u8(0xFF)
    for i = 0, ext.ENTRY_COUNT - 1 do
      local e = info:sub(0x50 + i * 0x14 + 1, 0x50 + i * 0x14 + 0x14)
      if e ~= string.rep("\0", 0x14) then w.u8(i); put_entry(w, e) end
    end
    w.u8(0xFF)
  else
    w.u8(n)
    for i = 0, n - 1 do put_entry(w, info:sub(0x50 + i * 0x14 + 1, 0x50 + i * 0x14 + 0x14)) end
  end
  -- the extra entries of the nine partners
  local extra = ctx:read_bytes(ext.EXTRA, 9 * ext.EXTRA_COUNT * ext.ENTRY_SIZE)
  for row = 0, 8 do
    local mask, list = 0, {}
    for k = 0, ext.EXTRA_COUNT - 1 do
      local o = (row * ext.EXTRA_COUNT + k) * ext.ENTRY_SIZE
      local e = extra:sub(o + 1, o + ext.ENTRY_SIZE)
      if e ~= string.rep("\0", ext.ENTRY_SIZE) then
        mask = mask | (1 << k)
        list[#list + 1] = e
      end
    end
    w.u8(mask)
    for _, e in ipairs(list) do put_entry(w, e) end
  end
  return w.data()
end

-- Payload -> the game data area (cleared first).
local function decode(ctx, payload)
  local r = reader(payload)
  local rec = {}
  local unlocked = r.u8()
  local battle = r.u32()
  local name = r.raw(r.u8())
  local stats = r.raw(0x50 - 0x18)
  local equip = r.raw(0x3CD - 0x3C0)
  local entries = string.rep("\0", ext.ENTRY_COUNT * 0x14)
  local function put(i, e)
    entries = entries:sub(1, i * 0x14) .. e .. entries:sub(i * 0x14 + 0x15)
  end
  local n = r.u8()
  if n == 0xFF then
    while true do
      local i = r.u8()
      if i == 0xFF then break end
      put(i, get_entry(r))
    end
  else
    for i = 0, n - 1 do put(i, get_entry(r)) end
  end
  local extra = {}
  for row = 0, 8 do
    local mask = r.u8()
    for k = 0, ext.EXTRA_COUNT - 1 do
      extra[row * ext.EXTRA_COUNT + k + 1] = (mask >> k) & 1 ~= 0 and get_entry(r) or string.rep("\0", ext.ENTRY_SIZE)
    end
  end
  -- the record
  local info = (name .. string.rep("\0", 0x18)):sub(1, 0x18) .. stats .. entries .. equip
  info = info .. string.rep("\0", ext.PARTNER_SIZE - ext.P_INFO - #info)
  local record = string.pack("<I4i4I4", 0, unlocked ~= 0 and (ext.VEMMON_ID + 3) or 0, battle) .. info
  M.clear(ctx)
  ctx:write_bytes(REC, record)
  ctx:write_bytes(ext.EXTRA, table.concat(extra))
end

-- What a load without the mod's data does (vemmon.lua: as a new game).
M.on_no_data = nil

function M.clear(ctx)
  ctx:write_bytes(ext.DATA, string.rep("\0", ext.DATA_END - ext.DATA))
  ctx:write32(ext.MAGIC, ext.MAGIC_VALUE)
end

-- The extension of the save in `save` (its 0x26C4 bytes), whole.
local function extension(ctx, save)
  local payload = encode(ctx)
  local head = MAGIC .. string.pack("<I1I4I2I4", VERSION, M.crc32(save), #payload, M.crc32(payload))
  local all = head .. payload
  if #all > M.CAPACITY then
    dwrc.log(string.format("DW3 Vemmon Partner: the save's extension is %d bytes, more than its %d; Vemmon's data is not saved", #all, M.CAPACITY))
    return string.rep("\0", M.CAPACITY)
  end
  return all .. string.rep("\0", M.CAPACITY - #all)
end

-- Reads an extension back (nil when it isn't this save's).
local function parse(all, save)
  if all:sub(1, 4) ~= MAGIC then return nil end
  local version, crc_save, len, crc_payload = string.unpack("<I1I4I2I4", all, 5)
  if version ~= VERSION or 15 + len > #all then return nil end
  local payload = all:sub(16, 15 + len)
  if crc_payload ~= M.crc32(payload) or crc_save ~= M.crc32(save) then return nil end
  return payload
end

-- Hooks -----------------------------------------------------------------

local function offset_section(slot) return (eu.SAVE_FILE_END + slot * ext.STAGING_SIZE) << 8 end

local frame = 0

-- The state of one direction (read or write) of a slot's data and extension.
local function op(name, fn, stub, on_data, on_done)
  local s = { phase = nil }
  local function reset() s.phase = nil end
  dwrc.on_exec(fn, function(ctx)
    if s.phase and frame - s.at > 120 then reset() end
    local section = ctx:reg("a3")
    if s.phase == "ext" then
      if section ~= s.section then reset() return false end
      ctx:set_reg("a1", ext.STAGING)
      ctx:set_reg("a2", ext.STAGING_SIZE)
      ctx:set_reg("a3", offset_section(s.slot))
    elseif section >= eu.SAVE_SECTION_DATA and section <= eu.SAVE_SECTION_DATA + 2 and ctx:reg("a2") == eu.GAME_SAVE_SIZE then
      if s.phase ~= "data" then
        s.phase, s.section, s.slot, s.buf = "data", section, section - eu.SAVE_SECTION_DATA, ctx:reg("a1")
        if on_data then on_data(ctx, s) end
      end
    else
      reset()
      return false
    end
    s.at = frame
    s.ra = ctx:reg("ra")
    ctx:set_reg("ra", stub)
    return false
  end)
  dwrc.on_exec(stub, function(ctx)
    local v0 = ctx:reg("v0")
    if s.phase == "data" then
      if v0 == 1 then s.phase = "ext"; v0 = 0 elseif v0 ~= 0 then reset() end
    elseif s.phase == "ext" then
      if v0 ~= 0 then v0 = on_done(ctx, s, v0); reset() end
    end
    ctx:set_reg("v0", v0)
    ctx:set_pc(s.ra)
    return true
  end)
end

function M.build()
  -- readSave's default case: offset = section >> 8, as writeSave's
  files.patch32("exe", eu.READ_SAVE_DEFAULT, 0x3C028005, mips.sra(mips.R.v1, mips.R.s5, 8))
  files.patch32("exe", eu.READ_SAVE_DEFAULT + 8, 0xAC408A54, mips.sw(mips.R.v1, -30124, mips.R.s1))
  M.write_stub = tables.stub("save_write_return")
  M.read_stub = tables.stub("save_read_return")
end

-- What encoding needs from the Digimon table (call once it's built).
function M.set_digimon(data)
  for d = 0, forms.COUNT - 1 do
    local o = d * eu.DIGIMON_SIZE
    local id = string.unpack("<I2", data, o + 1)
    if index_of_id[id] == nil then index_of_id[id] = d end
    id_of[d] = id
    digimon_skills[d] = { string.unpack("<I2I2I2I2I2I2", data, o + 0x1C + 2 + 1) }
    digimon_skills[d][7] = nil
  end
end

function M.install()
  dwrc.on_frame(function() frame = frame + 1 end)
  op("write", eu.writeSave, M.write_stub,
    function(ctx, s)
      local all = extension(ctx, ctx:read_bytes(s.buf, eu.GAME_SAVE_SIZE))
      ctx:write_bytes(s.buf + eu.GAME_SAVE_SIZE, all:sub(1, SLACK))
      ctx:write_bytes(ext.STAGING, all:sub(SLACK + 1))
    end,
    function(ctx, s, v0)
      if v0 ~= 1 then dwrc.log("DW3 Vemmon Partner: writing the save's extension failed (" .. (v0 - 1) .. ")") end
      return v0
    end)
  op("read", eu.readSave, M.read_stub, nil,
    function(ctx, s, v0)
      local save = ctx:read_bytes(s.buf, eu.GAME_SAVE_SIZE)
      local payload
      if v0 == 1 then
        payload = parse(ctx:read_bytes(s.buf + eu.GAME_SAVE_SIZE, SLACK) .. ctx:read_bytes(ext.STAGING, ext.STAGING_SIZE), save)
      else
        dwrc.log("DW3 Vemmon Partner: reading the save's extension failed (" .. (v0 - 1) .. ")")
      end
      local ok = payload and pcall(decode, ctx, payload)
      if not ok then (M.on_no_data or M.clear)(ctx) end
      dwrc.log(ok and "DW3 Vemmon Partner: loaded the save's Vemmon data" or "DW3 Vemmon Partner: the save has no Vemmon data")
      return 1       -- the save itself was read
    end)
end

return M
