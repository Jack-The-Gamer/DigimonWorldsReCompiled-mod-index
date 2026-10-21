-- DW3 Auction Notifications: a notice slides in at the bottom right of the
-- screen when an auction opens in Asuka City, and while one is open a yellow
-- "!" stands above Asuka City on the world map (Start, MAP).
--
-- When the game holds an auction: entering Cargo Tower, Asuka City's code
-- goes through a table of the sixteen auctions of the game. Each has a story
-- stage (a word in the executable's data, 0x8004B370 in Digimon World 2003),
-- an event flag set once it has been held (flags 0x0400 to 0x040F: bits 0 to
-- 15 from 0x8004B38A) and a condition "at least so much BIT" (conditions
-- 0x7074 to 0x707D, amounts from a table at 0x80048C44; your BIT are at
-- 0x80048DA0). An auction starts when the story is at its stage, its flag is
-- clear and you have the BIT:
--
--   stage  5    8    12    14    16    22    24    26    28    30
--   BIT    800  800  1600  1600  2700  2700  4000  4000  6000  6000
--   stage  31    34    36     37     38     39
--   BIT    8700  8700  11500  17500  24000  32000
--
-- That table is the same on all three discs (it is in AUCTIONS below); the
-- addresses are not, so the mod reads them from the game's own condition
-- code, found by the patterns below, which hold no addresses:
--   STORY_TEST  "is the story at stage n" (lui/lw of the stage)
--   FLAG_GROUP  the event flag group 0x04xx (lui/addiu of its first byte)
--   BIT_TEST    "at least table[n] BIT" (lui/addiu of the table, lui/lw of BIT)
-- The play time clock starts 0x6C before the BIT (hours, minutes and seconds
-- at +0x4C, +0x4E, +0x50); it jumps when a save is loaded, and the mod only
-- announces auctions that open while you play, not one already open in the
-- save you load (the "!" shows for those).
--
-- An auction usually opens as a story scene ends, on the way to a black
-- screen and an area title. The notice waits for the field: FIELD_LOOP (the
-- field's loop over its characters, 0x80085EDC in Digimon World 2003) runs
-- every frame while a field is on screen (also under menus and talk), not on
-- area titles, in battle or on the world map, and it starts about 70 frames
-- before an area title goes away, so the notice slides in once it has run
-- for FIELD_WAIT frames in a row.
--
-- The world map is drawn by a function in its own overlay (MAP_DRAW, at
-- 0x80098B84 in Digimon World 2003), called once a frame while the map is on
-- screen with a0 = the map's state, a block the map allocates when it opens.
-- The map's hit test (MAP_HIT) shows where that block keeps the scroll, the
-- cursor and "the cursor is on a place" (Digimon World 3 USA has one more
-- field before them than the other two); the place you are in comes 8 bytes
-- after the scroll, the place under the cursor 8 after "on a place". Asuka
-- City sits at (186, 119) on the map, its icon's middle at (198, 131) (where
-- you are, when you are there) and its top at (198, 136) plus the scroll on
-- the picture. The picture shows a frame two frames after the game draws it,
-- so the "!" follows the values from two frames back.
--
-- The "!" stands over the middle of the icon. When you are in Asuka City the
-- game's "you are here" bubble is beside it, and the "!" moves over the
-- other half of the icon. Digimon World 3 USA always puts the bubble on the
-- right; the other two put it on the right when the cursor (or the place
-- under it) is left of you, else on the left (MAP_SIDE: slt, then sprite 59
-- or 53). The "!" steps aside while the cursor or the name of a place would
-- be over it.

local STORY_TEST = "10a00007 3c02???? 8c42???? 00000000 14440008 00001021 03e00008 24020001 8c43???? 00000000 14640002 24020001"
local FLAG_GROUP = "14620004 24020006 3c04???? 08?????? 2484????"
local BIT_TEST = "3c02???? 2442???? 00051880 00621821 3c02???? 8c630000 8c42???? 00000000 0043102a"
local FIELD_LOOP = "27bdffd0 afb40020 0080a021 afb50024 00a0a821 afbf002c afb60028 afb3001c afb20018 afb10014 0040f809 afb00010 1440004a 00009021 241300ff"
local MAP_DRAW = "27bdff30 afb100b4 00808821 afbf00c8 afb500c4 afb400c0 afb300bc afb200b8 afb000b0 8e2201?? 00000000 1040002c"
local MAP_HIT = "8e0a01?? 8e0301?? 8e0200?? 8e0401?? 00004021 ae0001?? 00624823 3c03???? 8e0200?? 8c63???? 00822023"
local MAP_SIDE = "0082102a 10400002 2410003b 24100035"

-- Story stage of each auction, and which amount of BIT it asks for (0 = the
-- table's first). The n-th entry's flag is bit n-1 of the flag group.
local AUCTIONS = {
  { 5, 0 }, { 8, 0 }, { 12, 1 }, { 14, 1 }, { 16, 2 }, { 22, 2 }, { 24, 3 }, { 26, 3 },
  { 28, 4 }, { 30, 4 }, { 31, 5 }, { 34, 5 }, { 36, 6 }, { 37, 7 }, { 38, 8 }, { 39, 9 },
}

local BANNER_W, BANNER_H = 124, 22
local MARGIN_X, MARGIN_Y = 6, 8
local SLIDE, HOLD = 12, 240          -- frames
local QUIET = 180                    -- frames after a save is loaded
local FIELD_WAIT = 90                -- frames of field before the notice
local MARK_W, MARK_H = 10, 18
local ASUKA_X, ASUKA_Y = 198, 131    -- Asuka City's icon's middle, on the map
local ASUKA_TOP = 136                -- its top on the picture, before scrolling
local BESIDE_RIGHT, BESIDE_LEFT = 7, -8 -- the "!" beside the bubble: this far from the icon's middle
local NAME_BOX = { 8, 19, 246, 57 }  -- where a place's name shows (left, top, right, bottom)

local A = nil                        -- the game's addresses, once found
local hooked = {}                    -- MAP_DRAW and FIELD_LOOP addresses hooked so far
local field_hooked = false
local field_now, field_run = false, 0 -- the field ran this frame; frames in a row
local M = nil                        -- the map block's offsets, from MAP_HIT
local drawn = nil                    -- what the map drew this frame
local shown = { nil, nil, nil }      -- ... this frame, one and two frames ago
local mark = nil                     -- where the "!" is ("x,y"), nil when hidden
local last_open, last_stage, last_time = nil, nil, nil
local quiet = 0                      -- frames left without notices
local pending = false                -- an auction opened, the notice waits for the field
local popup = nil                    -- frames since the notice started
local frames = 0

-- A lui at `hi` and an addiu/lw at `lo` make an address.
local function lui_lo(ctx, hi, lo)
  local l = ctx:read32(lo) & 0xffff
  if l >= 0x8000 then l = l - 0x10000 end
  return (((ctx:read32(hi) & 0xffff) << 16) + l) & 0xffffffff
end

local function find_addresses(ctx)
  local st = ctx:find(STORY_TEST, 0x80010000, 0x80040000)
  local fl = ctx:find(FLAG_GROUP, 0x80010000, 0x80040000)
  local bt = ctx:find(BIT_TEST, 0x80010000, 0x80040000)
  if not (st and fl and bt) then return end
  local a = { stage = lui_lo(ctx, st + 4, st + 8), flags = lui_lo(ctx, fl + 8, fl + 16),
              amounts = lui_lo(ctx, bt, bt + 4), bit = lui_lo(ctx, bt + 16, bt + 24) }
  for _, v in pairs(a) do
    if v < 0x80010000 or v >= 0x80200000 then return end
  end
  a.clock = a.bit - 0x6c
  A = a
  dwrc.log(string.format("DW3 Auction Notifications: story stage at %08x, auction flags at %08x, BIT at %08x", a.stage, a.flags, a.bit))
end

-- The auction open right now (its number), or nil.
local function open_auction(ctx)
  local stage = ctx:read32(A.stage)
  for i, au in ipairs(AUCTIONS) do
    if au[1] == stage then
      local n = i - 1
      if ctx:read8(A.flags + (n >> 3)) & (1 << (n & 7)) ~= 0 then return nil end
      if ctx:read_s32(A.bit) < ctx:read_s32(A.amounts + 4 * au[2]) then return nil end
      return i
    end
  end
  return nil
end

-- Play time in seconds, or nil if the clock doesn't look like one.
local function play_time(ctx)
  local h, m, s = ctx:read16(A.clock + 0x4c), ctx:read16(A.clock + 0x4e), ctx:read16(A.clock + 0x50)
  if m > 59 or s > 59 then return nil end
  return h * 3600 + m * 60 + s
end

local function notice(ctx)
  local stage, t = ctx:read32(A.stage), play_time(ctx)
  -- A save (or a save state) is being loaded: the clock jumped or the story
  -- went back. A save comes in over a few frames, so stay quiet a while.
  if last_stage == nil or stage < last_stage or (t == nil) ~= (last_time == nil)
    or (t and last_time and (t < last_time or t > last_time + 2)) then
    quiet, pending = QUIET, false
    if popup then
      dwrc.hide_image("notice")
      popup = nil
    end
  end
  local open = open_auction(ctx)
  if quiet > 0 then
    quiet = quiet - 1
  elseif open and open ~= last_open then
    pending = true
    dwrc.log(string.format("DW3 Auction Notifications: auction %d is open (story stage %d)", open, stage))
  end
  if not open then pending = false end
  if pending and (field_run >= FIELD_WAIT or not field_hooked) then
    pending, popup = false, 0
  end
  last_open, last_stage, last_time = open, stage, t
  return open
end

local function slide_banner()
  if not popup then return end
  popup = popup + 1
  local p
  if popup <= SLIDE then
    p = popup / SLIDE
  elseif popup <= SLIDE + HOLD then
    p = 1
  elseif popup <= 2 * SLIDE + HOLD then
    p = (2 * SLIDE + HOLD - popup) / SLIDE
  else
    dwrc.hide_image("notice")
    popup = nil
    return
  end
  p = 1 - (1 - p) ^ 3               -- slows down as it comes in
  local x = -BANNER_W + (MARGIN_X + BANNER_W) * p
  dwrc.show_image("notice", "banner.png", { corner = "bottom_right", x = math.floor(x + 0.5), y = MARGIN_Y })
end

local function overlaps(l, t, r, b, l2, t2, r2, b2) return l < r2 and l2 < r and t < b2 and t2 < b end

local function place_mark(open)
  local m = shown[3]
  local want = nil
  if open and m then
    local dx = 0
    if math.abs(m.px - ASUKA_X) <= 16 and math.abs(m.py - ASUKA_Y) <= 16 then
      -- You are in Asuka City: the "you are here" bubble is beside the icon.
      local right = not M.flips or (m.hover and m.hx or m.cx) < m.px + m.x
      dx = right and BESIDE_LEFT or BESIDE_RIGHT
    end
    local x, y = ASUKA_X + dx - MARK_W // 2 + m.x, ASUKA_TOP - 2 - MARK_H + m.y
    local covered = (m.hover and overlaps(x, y, x + MARK_W, y + MARK_H, table.unpack(NAME_BOX)))
      or overlaps(x, y, x + MARK_W, y + MARK_H, m.cx - 1, m.cy + 15, m.cx + 14, m.cy + 37)
    if not covered then want = x .. "," .. y end
    if want and want ~= mark then
      dwrc.show_image("mark", "auction-mark.png", { x = x, y = y })
    end
  end
  if not want and mark then dwrc.hide_image("mark") end
  mark = want
end

local function hook_map(ctx, at)
  local hit = ctx:find(MAP_HIT, at - 0x2000, at + 0x2000)
  if not hit then return end
  local w = function(k) return ctx:read32(hit + 4 * k) & 0xffff end
  M = { hover = w(0), cx = w(1), x = w(2), cy = w(3), y = w(8) }
  M.px, M.py, M.hx = M.x + 8, M.y + 8, M.hover + 8
  M.flips = ctx:find(MAP_SIDE, at, at + 0x1000) ~= nil
  local first, tenth = ctx:read32(at), ctx:read32(at + 36)
  dwrc.on_exec(at, function(c)
    -- Another overlay may have been loaded over this address since.
    if c:read32(at) ~= first or c:read32(at + 36) ~= tenth then return false end
    local b = c:reg("a0")
    drawn = { x = c:read_s32(b + M.x), y = c:read_s32(b + M.y), cx = c:read_s32(b + M.cx), cy = c:read_s32(b + M.cy),
              hover = c:read32(b + M.hover) ~= 0, hx = c:read_s32(b + M.hx), px = c:read_s32(b + M.px), py = c:read_s32(b + M.py) }
    return false
  end)
  hooked[at] = true
  dwrc.log(string.format("DW3 Auction Notifications: world map code at %08x", at))
end

local function hook_field(_, at)
  dwrc.on_exec(at, function(c)
    if c:read32(at) ~= 0x27bdffd0 or c:read32(at + 48) ~= 0x1440004a then return false end
    field_now = true
    return false
  end)
  hooked[at], field_hooked = true, true
  dwrc.log(string.format("DW3 Auction Notifications: field code at %08x", at))
end

dwrc.on_frame(function(ctx)
  frames = frames + 1
  if not A then
    if frames % 30 == 1 then find_addresses(ctx) end
    return
  end
  if frames % 10 == 1 then
    -- Old copies of this code can stay in RAM; hook every copy found.
    for _, s in ipairs({ { MAP_DRAW, hook_map }, { FIELD_LOOP, hook_field } }) do
      local at = ctx:find(s[1], 0x80040000, 0x80200000)
      while at do
        if not hooked[at] then s[2](ctx, at) end
        at = ctx:find(s[1], at + 4, 0x80200000)
      end
    end
  end
  field_run = field_now and field_run + 1 or 0
  field_now = false
  shown[3], shown[2], shown[1], drawn = shown[2], shown[1], drawn, nil
  local open = notice(ctx)
  slide_banner()
  place_mark(open)
end)
