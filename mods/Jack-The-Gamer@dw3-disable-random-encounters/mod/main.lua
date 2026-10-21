-- DW3 Disable Random Encounters: R switches random battles off, R again
-- switches them back on. While they are off, a red sign sits in the top
-- right corner of the screen.
--
-- How the game decides on a random battle: a countdown (a word in the
-- executable's data, 0x30 after the start of the play time clock block;
-- 0x80048D64 in Digimon World 2003) loses a few points with every step you
-- take on the field, how many depending on the ground (a table of costs: 3,
-- 4, 6, 9, 18). The field code does it like this:
--
--   lw   v1, 0(v1)        the cost of this step
--   lw   v0, 48(a0)       the countdown (a0 = the clock block)
--   nop
--   subu v0, v0, v1
--   bgtz v0, done         still above zero: no battle
--   sw   v0, 48(a0)
--   ...                   zero or below: a battle (if the map has them),
--                         then a new random countdown
--
-- While encounters are off, the mod sets the step's cost to nothing just
-- before the subtraction, so the countdown stays where it was: switching
-- them back on carries on exactly from there.
--
-- Some field screens also have battle spots (the Wire Forest has one; about
-- 16 maps on the Digimon World 2003 disc do): walk onto one and the map
-- starts one of its events, event 9000, which stops you and calls a small
-- function that starts a battle with one of the area's random encounters
-- (entry 6 of its table; Kuwagamon in the Wire Forest). That battle doesn't
-- touch the countdown. Events start in one function (0x800853F8 in Digimon
-- World 2003, a0 = the event's number), which finds the event in the map's
-- list (a pointer at 36 in a block of map data, 0x80099D80; entries of 20
-- bytes: number, script, condition, function, ...; -1 ends the list), sets
-- up an object to run it and stops you:
--
--   addiu sp, sp, -40
--   ...
--   lui   v1, <map data>; addiu a0, v1, <map data>
--   lw    a1, 36(a0)                the list
--   ...                             (s1 or s2 = the number, by release)
--
-- The battle function (0x8008BF38) starts like this and returns 0:
--
--   lui  v0, ...; lw v0, ...(v0)    the area's encounter tables
--   addiu sp, sp, -24
--   sw   ra, 16(sp)
--   lw   v0, 24(v0)
--   nop
--   lw   a0, 24(v0)                 that encounter
--   ...
--   jal  <start a battle>
--   nop
--   addiu a0, zero, 15
--
-- While encounters are off, the mod returns 0 at once from the event
-- function for an event whose function is the battle function, so the spot
-- neither stops you nor starts anything (the map just asks again while you
-- stand on it, which costs nothing), and returns from the battle function
-- at once (with 0, as it does after starting the battle) should anything
-- else call it. Battles the story starts, and bosses, are not random
-- encounters and still happen.
--
-- All of this code is in the field's overlay (at 0x8008xxxx-0x8009xxxx on
-- all three discs; a copy also passes through a load buffer higher up while
-- it loads), so the mod looks for it (by the patterns below, which hold no
-- addresses) in that part of RAM and hooks every place it turns up: every 5
-- frames while the step code is not where a hook already waits for it, so
-- the first steps on a new screen are covered too, and every 50 frames
-- otherwise. Each pattern is on all three discs (Digimon World 2003
-- SLES-03936, Digimon World 3 SLUS-01436 and SLPS-03446), once each.

local STEP = "8c43000c 3c02???? 8c630000 2442???? 00031880 00621821 8c630000 8c820030 00000000 00431023 1c40000a ac820030"
local SUBU = 9 * 4            -- offset of `subu v0, v0, v1` in STEP
local SUBU_WORD, BGTZ_WORD = 0x00431023, 0x1c40000a
local SPOT = "3c0280?? 8c42???? 27bdffe8 afbf0010 8c420018 00000000 8c440018 3c0280?? 8c830004 2442???? ac43000c 8c830008 00000000 ac430014 8c840000 0c?????? 00000000 2404000f"
local SPOT_SP, SPOT_A0 = 0x27bdffe8, 0x2404000f   -- words 2 and 17 of SPOT
local EVENT = "27bdffd8 afb?001? 0080??21 3c0480?? 2484???? 24050154 24060038 afbf0024 afb40020 afb3001c afb?001? 0c?????? afb00010 3c0380?? 2464???? 8c850024 00408021 8ca30000 2402ffff 1062???? 0080??21 3c0280?? 2446???? 24130001 26?2e0c0 2c5403e8 24a40008 8ca20000 00000000 145????? 2402ffff ae1?0050 8c82fffc 00000000 ae020054 8c820004 00000000 ae020058"
local EVENT_SP, EVENT_LIST = 0x27bdffd8, 0x8c850024   -- words 0 and 15 of EVENT
local FROM, TO = 0x80080000, 0x800c0000
local KEY = "R"

local off = false
local steps = {}              -- step code addresses hooked so far
local spots = {}              -- battle spot function addresses hooked so far
local events = {}             -- event function addresses hooked so far
local frames = 0

local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end

local function hook_step(at)
  dwrc.on_exec(at, function(ctx)
    -- Another overlay may have been loaded over this address since.
    if not off or ctx:read32(at) ~= SUBU_WORD or ctx:read32(at + 4) ~= BGTZ_WORD then return false end
    ctx:set_reg("v1", 0)
    -- A new countdown can start at 0: keep it above zero.
    if s32(ctx:reg("v0")) <= 0 then ctx:set_reg("v0", 1) end
    return false
  end)
  steps[at] = true
  dwrc.log(string.format("DW3 Disable Random Encounters: field step code at %08x", at))
end

local function hook_spot(at)
  dwrc.on_exec(at, function(ctx)
    if not off or ctx:read32(at + 8) ~= SPOT_SP or ctx:read32(at + 68) ~= SPOT_A0 then return false end
    return ctx:ret(0)
  end)
  spots[at] = true
  dwrc.log(string.format("DW3 Disable Random Encounters: battle spot code at %08x", at))
end

-- The function an event of the current map runs (0 if there is no such event).
local function event_function(ctx, at, id)
  -- The map data block, from `lui v1, hi; addiu a0, v1, lo` (words 13 and 14).
  local lo = ctx:read32(at + 56) & 0xffff
  if lo >= 0x8000 then lo = lo - 0x10000 end
  local list = ctx:read32(((ctx:read32(at + 52) & 0xffff) << 16) + lo + 36)
  for i = 0, 255 do
    local e = list + i * 20
    if e < 0x80000000 or e >= 0x80200000 then return 0 end
    local n = ctx:read32(e)
    if n == 0xffffffff then return 0 end
    if n == id then return ctx:read32(e + 12) end
  end
  return 0
end

local function hook_event(at)
  dwrc.on_exec(at, function(ctx)
    if not off or ctx:read32(at) ~= EVENT_SP or ctx:read32(at + 60) ~= EVENT_LIST then return false end
    if not spots[event_function(ctx, at, ctx:reg("a0"))] then return false end
    return ctx:ret(0)
  end)
  events[at] = true
  dwrc.log(string.format("DW3 Disable Random Encounters: event code at %08x", at))
end

-- Is the step code where a hook already waits for it?
local function in_place(ctx)
  for at in pairs(steps) do
    if ctx:read32(at) == SUBU_WORD and ctx:read32(at + 4) == BGTZ_WORD then return true end
  end
  return false
end

local function scan(ctx, pattern, offset, hooked, hook)
  local at = ctx:find(pattern, FROM, TO)
  while at do
    if not hooked[at + offset] then hook(at + offset) end
    at = ctx:find(pattern, at + 4, TO)
  end
end

dwrc.on_frame(function(ctx)
  frames = frames + 1
  if frames % 50 ~= 1 and (frames % 5 ~= 1 or in_place(ctx)) then return end
  scan(ctx, STEP, SUBU, steps, hook_step)
  scan(ctx, SPOT, 0, spots, hook_spot)
  scan(ctx, EVENT, 0, events, hook_event)
end)

dwrc.on_key(function(ctx, key, mods)
  if key ~= KEY or mods.ctrl or mods.alt or mods.shift then return end
  off = not off
  if off then
    dwrc.show_image("off", "encounters-off.png", { corner = "top_right", x = 6, y = 6, scale = 0.375 })
    dwrc.notify("Random encounters off")
  else
    dwrc.hide_image("off")
    dwrc.notify("Random encounters on")
  end
end)

dwrc.log("DW3 Disable Random Encounters ready: press R to switch random battles off or on")
