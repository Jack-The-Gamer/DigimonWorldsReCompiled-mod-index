-- DW1 Re-Usable Monzaemon Suit: the Monzaemon suit in Jijimon's House turns
-- Numemon into Monzaemon, as the one in Toy Town does.
--
-- Map scripts live in SCN/DG.SCN (Europe: DG0..DG4.SCN, one per language;
-- each is patched with its own text): u32 file offsets by script id, then each
-- script is a u16 code offset and {u16 section, u16 offset} entries up to
-- 0xFFFF, offsets from the script start. A map's NPCs run the section with
-- their script id (slot + 5), section 254 runs on entering the map. Opcodes
-- from dw_decomp (include/dw/script.h; u16 arguments sit at even offsets).
-- Numbers below are Digimon World (USA) SLUS-01032, where this was found:
--
-- * Toy Town's costume room (map 145, script 139, the suit = type 138 in
--   slot 0, script id 5). Examining it (section 81) with Numemon (type 11):
--     IF pstat[103] == 11 (STORE_DIGIMON_TYPE 103 just before)
--     the partner walks to the suit, "What happened, <name>?!",
--     UNLOAD_ENTITY 5, SET_PSTAT 254 = 14 (Monzaemon),
--     CALL_DIGIMON_ROUTINE 10 (EVOLUTION_TARGET = pstat 254, partner state 13:
--     the whole evolution scene), WAIT_FOR_ENTITY 255 (until it ends),
--     "Did you turn into another Digimon?"
--   Trigger 270 (the Gear from Toy Town's story) closes that event for good.
-- * Jijimon's House, the side room (map 206, script 166). Once Monzaemon
--   joins the city (trigger 214, script 140: "Monzaemon's Stuffed Animal
--   joins the city!") the map head places type 138 in slot 1 (script id 6);
--   section 254 plays its animation 30, section 6 only says "It's empty."
--
-- The mod rewrites script 166 on the virtual disc (its 2048-byte slot uses
-- 0x290 bytes; the rest is unused and loaded with it):
--   section 6 -> new code in the free space: the original "It's empty.",
--     then for Numemon Toy Town's "There's a zipper on the back." and its
--     whole Numemon event, copied from script 139 with the suit's script id
--     changed from 5 to 6;
--   option hide_while_worn: section 254's PLAY_ANIMATION 6 30 (only reached
--     with trigger 214) jumps to new code that plays it, then unloads the
--     suit while the partner is Monzaemon (type 14), like Toy Town's map head
--     does for its suit.
-- Everything is found by pattern on the player's disc (the scripts and their
-- text are read from it, nothing of the game's is shipped); if a pattern
-- isn't there the disc is left as it is and the log says why.

local HIDE = dwrc.options.hide_while_worn ~= false

local NUMEMON, MONZAEMON = 11, 14
local TYPE_PSTAT = 103 -- the scratch pstat the game's own scripts use for the partner's type
local JOINED = 214 -- trigger: Monzaemon's Stuffed Animal joined the city

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o) local a, b = s:byte(o + 1, o + 2) return a | b << 8 end
local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4) return a | b << 8 | c << 16 | d << 24 end
local function le16(v) return string.char(v & 0xFF, v >> 8 & 0xFF) end

local function fail(why)
  dwrc.log("Re-Usable Monzaemon Suit: " .. why .. "; the game is left as it is")
end

-- ISO 9660: { lba, size } of a file by its path's parts.
local function find_file(parts)
  local pvd = dwrc.disc.read(16, 1)
  if pvd:sub(2, 6) ~= "CD001" then return nil end
  local lba, size = u32(pvd, 156 + 2), u32(pvd, 156 + 10)
  for i, want in ipairs(parts) do
    local dir = dwrc.disc.read(lba, (size + 2047) // 2048)
    local found
    local o = 0
    while o < #dir do
      local len = u8(dir, o)
      if len == 0 then
        o = (o // 2048 + 1) * 2048 -- records don't cross sectors
      else
        local name = dir:sub(o + 34, o + 33 + u8(dir, o + 32)):gsub(";1$", "")
        if name == want then found = { lba = u32(dir, o + 2), size = u32(dir, o + 10) } break end
        o = o + len
      end
    end
    if not found then return nil end
    lba, size = found.lba, found.size
  end
  return { lba = lba, size = size }
end

-- Length of the instruction at o (0-based) in s, for the few opcodes the
-- copied and checked code uses; nil for anything else.
local FIXED = { [0x1B] = 2, [0x1C] = 4, [0x1E] = 4, [0x27] = 2, [0x48] = 2, [0x49] = 2, [0x4A] = 2,
  [0x4C] = 4, [0x51] = 4, [0x56] = 4, [0x67] = 4, [0xFE] = 2 }
local function op_len(s, o)
  local op = u8(s, o)
  if FIXED[op] then return FIXED[op] end
  if op ~= 0x1A then return nil end
  -- SHOW_TEXTBOX: a pad byte, then text in byte pairs (code 3 takes four);
  -- 0D xx starts a line, 0D xx 00 00 ends the text (script_textbox.c showTextbox).
  local p = o + 2
  while p < #s do
    local c = u8(s, p)
    if c == 0x0D then
      p = p + 2
      if u8(s, p) == 0 then return p + 2 - o end
    elseif c == 3 then
      p = p + 4
    else
      p = p + 2
    end
  end
  return nil
end

-- The instructions of s[from, to) as { offset, ... }, or nil if one is unknown.
local function walk(s, from, to)
  local out, o = {}, from
  while o < to do
    local n = op_len(s, o)
    if not n then return nil end
    out[#out + 1] = o
    o = o + n
  end
  return o == to and out or nil
end

-- Script id -> { at, bytes } for every script in DG.SCN, in id order.
local function scripts(scn)
  local list = {}
  for i = 0, u32(scn, 0) // 4 - 2 do
    local a, b = u32(scn, 4 * i), u32(scn, 4 * i + 4)
    if b > a and b <= #scn then list[#list + 1] = { id = i, at = a, s = scn:sub(a + 1, b) } end
  end
  return list
end

-- { [section] = { offset, entry position } }
local function sections(s)
  local out, q = {}, 2
  while q + 4 <= #s do
    local id, at = u16(s, q), u16(s, q + 2)
    if id == 0xFFFF then return out end
    out[id] = { at = at, entry = q }
    q = q + 4
  end
  return nil
end

local function find(s, pat, from) return s:find(pat, (from or 0) + 1, true) end

-- Toy Town's suit event: the "zipper" textbox and the Numemon branch, with
-- the suit's script id, from the script that holds both.
local IS_NUMEMON = "\x19\0\x08\0" .. string.char(TYPE_PSTAT, NUMEMON) .. "\x18\0"
local EVOLVE = "\x1E\0\xFE" .. string.char(MONZAEMON) .. "\x49\x0A" -- SET_PSTAT 254 = Monzaemon; CALL_DIGIMON_ROUTINE 10
local function toy_town_event(list)
  for _, sc in ipairs(list) do
    local id, s = sc.id, sc.s
    local evo = find(s, EVOLVE)
    local cond = evo and find(s, IS_NUMEMON)
    if cond and cond < evo then
      local at = cond - 1 -- 0-based IF
      local after = u16(s, at + 8) -- where a partner that isn't Numemon goes
      if s:sub(at + 11, at + 12) ~= "\x19\0" or after <= evo or after > #s then return nil, "Toy Town's event isn't laid out as expected" end
      -- "There's a zipper on the back.": SET_DIALOG_OWNER 253, SHOW_TEXTBOX, FADEOUT_HUD 0, right before the IF.
      local zip, p = nil, 0
      while true do
        local q = find(s, "\x1B\xFD\x1A\0", p)
        if not q or q > at then break end
        zip, p = q - 1, q
      end
      if not zip or s:sub(at - 1, at) ~= "\x27\0" or not walk(s, zip, at) then return nil, "Toy Town's zipper line isn't where expected" end
      -- The Numemon branch, up to and with its END_SECTION.
      local from, to = at + 12, after
      local ops = walk(s, from, to)
      if not ops or s:sub(to - 1, to) ~= "\xFE\0" or u8(s, from) ~= 0x51 or from % 2 ~= 0 or zip % 2 ~= 0 then
        return nil, "Toy Town's Numemon event isn't laid out as expected"
      end
      return { id = id, zipper = s:sub(zip + 1, at), branch = s:sub(from + 1, to), ops = ops, from = from, suit = u8(s, from + 3) }
    end
  end
  return nil, "Toy Town's suit event wasn't found"
end

-- The branch with the suit's script id changed to `to`: in ENTITY_WALK_TO_ENTITY's
-- target, WAIT_FOR_ENTITY and UNLOAD_ENTITY.
local function retarget(ev, to)
  local b = { ev.branch:byte(1, -1) }
  for _, o in ipairs(ev.ops) do
    local r = o - ev.from + 1
    local op = b[r]
    if op == 0x51 and b[r + 3] == ev.suit then b[r + 3] = to end
    if (op == 0x4A or op == 0x48) and b[r + 1] == ev.suit then b[r + 1] = to end
  end
  return string.char(table.unpack(b))
end

-- Jijimon's side room: section 254 holds IF trigger 214 -> PLAY_ANIMATION e 30,
-- and section e (the suit's) is SET_TRIGGER 44, SET_DIALOG_OWNER 253,
-- SHOW_TEXTBOX "It's empty.", END_SECTION.
local function house(list)
  local IF_JOINED = "\x19\0\0\0" .. le16(JOINED) .. "\x18\0"
  for _, sc in ipairs(list) do
    local id, s = sc.id, sc.s
    local secs = sections(s)
    local entry = secs and secs[254]
    local c = entry and find(s, IF_JOINED, entry.at)
    if c then
      local at = c - 1
      local play = at + 12
      local e = u8(s, play + 2)
      local sec = secs[e]
      if s:sub(at + 11, at + 12) == "\x19\0" and u8(s, play) == 0x56 and sec
        and s:sub(sec.at + 1, sec.at + 8) == "\x1C\0\x2C\0\x1B\xFD\x1A\0" then
        local n = op_len(s, sec.at + 6)
        local fin = n and sec.at + 6 + n
        if fin and s:sub(fin + 1, fin + 2) == "\xFE\0" then
          -- The free space: after the END_SCRIPT that follows the last section.
          local last = 0
          for _, v in pairs(secs) do last = math.max(last, v.at) end
          local stop = find(s, "\xFE\0\xFF", last)
          if not stop then return nil, "the end of Jijimon's room script wasn't found" end
          local free = stop + 2 -- 0-based, just past the FF
          free = free + free % 2
          return { id = id, s = s, at = sc.at, suit = e, section = sec, empty = s:sub(sec.at + 1, fin), play = play, free = free }
        end
      end
    end
  end
  return nil, "the suit in Jijimon's House wasn't found"
end

local function patch(name, f)
  local function fail(why) return false, name .. ": " .. why end
  local sectors = (f.size + 2047) // 2048
  local scn = dwrc.disc.read(f.lba, sectors):sub(1, f.size)
  local list = scripts(scn)
  local ev, why = toy_town_event(list)
  if not ev then return fail(why) end
  local h, why2 = house(list)
  if not h then return fail(why2) end

  local s, free = h.s, h.free
  local code = {}
  local function emit(bytes) code[#code + 1] = bytes end
  local function here() return free + #table.concat(code) end

  -- The suit's section: "It's empty." for everyone; then, for Numemon, Toy Town's event.
  local new_section = here()
  emit(h.empty) -- SET_TRIGGER 44, SET_DIALOG_OWNER 253, SHOW_TEXTBOX "It's empty."
  emit(string.char(0x22, TYPE_PSTAT)) -- STORE_DIGIMON_TYPE 103
  local skip = #code + 1
  emit("") -- IF pstat[103] == Numemon -> end if false (filled in below)
  emit("\x27\0") -- FADEOUT_HUD 0
  emit(ev.zipper)
  emit(retarget(ev, h.suit))
  local done = here() + 12
  code[skip] = IS_NUMEMON .. le16(done) .. "\x19\0"
  emit("\xFE\0") -- END_SECTION

  -- Option: the suit's entry animation, then unload it while Monzaemon is the partner.
  local hide_at
  if HIDE then
    hide_at = here()
    emit(s:sub(h.play + 1, h.play + 4)) -- PLAY_ANIMATION suit 30
    emit(string.char(0x22, TYPE_PSTAT)) -- STORE_DIGIMON_TYPE 103
    local stop = here() + 12 + 2
    emit("\x19\0\x08\0" .. string.char(TYPE_PSTAT, MONZAEMON) .. "\x18\0" .. le16(stop) .. "\x19\0")
    emit(string.char(0x48, h.suit)) -- UNLOAD_ENTITY suit
    emit("\xFE\0") -- END_SECTION
  end

  local add = table.concat(code)
  if free + #add > #s then return fail(string.format("the new code (%d bytes) doesn't fit in Jijimon's room script", #add)) end
  local out = s:sub(1, free) .. add .. s:sub(free + #add + 1)
  -- Point the suit's section at the new code.
  local e = h.section.entry
  out = out:sub(1, e + 2) .. le16(new_section) .. out:sub(e + 5)
  if hide_at then
    -- PLAY_ANIMATION suit 30 (after IF trigger 214) -> JUMP_TO the new code; the code ends the section, as it did.
    if s:sub(h.play + 5, h.play + 6) ~= "\xFE\0" then return fail("Jijimon's room entry isn't laid out as expected") end
    out = out:sub(1, h.play) .. "\x16\0" .. le16(hide_at) .. out:sub(h.play + 5)
  end
  assert(#out == #s)

  -- Write back the sectors holding the script.
  local first, last = h.at // 2048, (h.at + #s - 1) // 2048
  local data = dwrc.disc.read(f.lba + first, last - first + 1)
  local o = h.at - first * 2048
  dwrc.disc.write(f.lba + first, data:sub(1, o) .. out .. data:sub(o + #out + 1))
  dwrc.log(string.format("Re-Usable Monzaemon Suit: %s: Toy Town's event (script %d, %#x) copied into Jijimon's room (script %d, suit id %d, %d bytes from %#x)%s",
    name, ev.id, ev.from, h.id, h.suit, #add, free, HIDE and ", hidden while worn" or ""))
  return true
end

-- USA and Japan have SCN/DG.SCN; Europe one file per language, DG0..DG4.SCN.
local found = false
for _, name in ipairs({ "DG.SCN", "DG0.SCN", "DG1.SCN", "DG2.SCN", "DG3.SCN", "DG4.SCN" }) do
  local f = find_file({ "SCN", name })
  if f then
    found = true
    local ok, why = patch(name, f)
    if not ok then fail(why) end
  end
end
if not found then fail("no SCN/DG.SCN on the disc") end
