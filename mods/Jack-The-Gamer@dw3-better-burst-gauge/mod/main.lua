-- DW3 Better Burst Gauge: the burst gauge keeps its progress when you load
-- a save, even after the console was switched off.
--
-- How the game keeps it: each partner Digimon has a gauge (a halfword from
-- 0 to 1000; at 1000 it burst digivolves), eight in all, in the game's own
-- memory. They are never written to the memory card, and the game clears
-- them when it starts up (before the title screen), so every load starts
-- from empty gauges.
--
-- The mod remembers the gauges whenever the game saves, under the save's
-- play time, and puts them back when a save with that play time is loaded.
-- What it remembers is kept in this mod's data, so it survives closing the
-- program. Saves made without the mod load as before.
--
-- * Saving: the game builds the save in memory (with a copy of the play
--   time clock) when you confirm, then writes it to the card with the BIOS
--   write() call (B0:35; the file's descriptor, 128 bytes at a time; the
--   game also writes debug text to descriptor 1), dozens of times while the clock
--   keeps running. At the first write the mod takes the play time from that
--   copy (the hours and minutes of the live clock, with the seconds a moment
--   before), so it is exactly the time the save will load with.
-- * Loading: the load sets the clock, which jumps. If the gauges are empty
--   then (a save state loaded instead carries its own gauges), the mod puts
--   back the ones remembered for that play time.
--
-- Two functions of the game's executable give the addresses. Neither holds
-- an address other than the one the mod reads out of it, so other releases
-- of the game should match too:
--   * clearing the gauges: v0 = base; 8 times sh zero, 88(v0)  (gauges at base + 88)
--   * clearing the play time clock (base + 72 sub-second count, base + 76
--     hours, + 78 minutes, + 80 seconds)
-- In Digimon World 2003 (SLES-03936): gauges at 0x80042B74, clock at 0x80048D34.

local CLEAR_GAUGES = "24030007 3c02???? 2442???? 2442000e a4400058 2463ffff 0461fffd 2442fffe 03e00008"
local CLEAR_CLOCK = "3c02???? 2442???? a4400052 a4400050 a440004e a440004c 03e00008 ac400048"
local EXE_FROM, EXE_TO = 0x80010000, 0x80080000
local GAUGES = 8
local KEEP = 200            -- saves remembered (the oldest are forgotten)
local SAVE_GAP = 180        -- frames without a write that end a save
local BEFORE = 10           -- how many seconds before the first write the save may be built

local gauges, clock         -- addresses, once found
local frames = 0
local last_time             -- play time last frame, in seconds
local last_write            -- frame of the last write of the save being written

local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

-- The address a `lui reg, hi` / `addiu reg, reg, lo` pair at `at` loads.
local function address(ctx, at)
  return ((ctx:read32(at) & 0xFFFF) << 16) + s16(ctx:read32(at + 4) & 0xFFFF)
end

local function find(ctx)
  local g = ctx:find(CLEAR_GAUGES, EXE_FROM, EXE_TO)
  local c = ctx:find(CLEAR_CLOCK, EXE_FROM, EXE_TO)
  if not (g and c) then return false end
  gauges = address(ctx, g + 4) + 88
  clock = address(ctx, c)
  dwrc.log(string.format("DW3 Better Burst Gauge: gauges at %08x, play time at %08x", gauges, clock))
  return true
end

local function seconds(h, m, s) return h * 3600 + m * 60 + s end

local function play_time(ctx)
  return seconds(ctx:read16(clock + 76), ctx:read16(clock + 78), ctx:read16(clock + 80))
end

local function name(t)
  return string.format("%d:%02d:%02d", t // 3600, t // 60 % 60, t % 60)
end

-- The play time the save being written holds: its copy of the clock block
-- (same hours and minutes, seconds up to BEFORE earlier, and the same data
-- after the clock), or nil if not found.
local function saved_time(ctx)
  local h, m, now = ctx:read16(clock + 76), ctx:read16(clock + 78), play_time(ctx)
  local after = ctx:read32(clock + 84)
  local word = string.format("%08x", (m << 16) | h)
  local best
  local at = ctx:find(word, 0x80000000, 0x80200000)
  while at do
    if at ~= clock + 76 and ctx:read32(at + 8) == after then
      local t = seconds(h, m, ctx:read16(at + 4))
      if t <= now and t >= now - BEFORE and (not best or t < best) then best = t end
    end
    at = ctx:find(word, at + 4, 0x80200000)
  end
  return best
end

local function read_gauges(ctx)
  local g = {}
  for i = 1, GAUGES do g[i] = ctx:read16(gauges + 2 * (i - 1)) end
  return g
end

local function empty(g)
  for i = 1, GAUGES do if g[i] ~= 0 then return false end end
  return true
end

-- dwrc.data.saves["<serial> <play time>"] = { gauges = {...}, n = order, exact = bool }
dwrc.data.saves = dwrc.data.saves or {}
dwrc.data.count = dwrc.data.count or 0

local function remember(t, exact, g)
  local saves = dwrc.data.saves
  dwrc.data.count = dwrc.data.count + 1
  saves[dwrc.serial .. " " .. name(t)] = { gauges = g, n = dwrc.data.count, exact = exact }
  local n, oldest, oldest_n = 0, nil, math.huge
  for k, s in pairs(saves) do
    n = n + 1
    if s.n < oldest_n then oldest, oldest_n = k, s.n end
  end
  if n > KEEP then saves[oldest] = nil end
  dwrc.save()
end

-- The gauges remembered for a save loaded with play time t: saved at t (or
-- a second before, if the clock ticked before this frame), or else one
-- whose time is only known from the write, a few seconds after t.
local function recall(t)
  local saves = dwrc.data.saves
  for _, u in ipairs({ t, t - 1 }) do
    local s = saves[dwrc.serial .. " " .. name(u)]
    if s then return s end
  end
  for u = t, t + BEFORE do
    local s = saves[dwrc.serial .. " " .. name(u)]
    if s and not s.exact then return s end
  end
end

-- The game writing a save file: remember the gauges with it (once per save).
dwrc.on_exec(0xB0, function(ctx)
  if not gauges or (ctx:reg("t1") & 0xFF) ~= 0x35 then return false end
  local ra = ctx:reg("ra") & 0x1FFFFFFF
  if ra < 0x10000 or ra >= 0x800000 then return false end -- the game's calls only
  -- To a file on the card (not the debug console, fd 0/1), in 128-byte sectors.
  if ctx:reg("a0") < 2 or ctx:reg("a2") % 128 ~= 0 then return false end
  if not last_write then
    local t = saved_time(ctx)
    local g = read_gauges(ctx)
    remember(t or play_time(ctx), t ~= nil, g)
    dwrc.log(string.format("DW3 Better Burst Gauge: saved at %s%s: %s", name(t or play_time(ctx)),
      t and "" or " (from the clock)", table.concat(g, " ")))
  end
  last_write = frames
  return false
end)

dwrc.on_frame(function(ctx)
  frames = frames + 1
  if not gauges then
    if frames % 30 == 0 then find(ctx) end
    return
  end
  if last_write and frames - last_write > SAVE_GAP then last_write = nil end
  local t = play_time(ctx)
  if last_time and (t < last_time or t > last_time + 2) then
    -- The clock jumped: a save was loaded (or a new game started).
    local s = recall(t)
    if s and empty(read_gauges(ctx)) then
      for i = 1, GAUGES do ctx:write16(gauges + 2 * (i - 1), s.gauges[i] or 0) end
      dwrc.log("DW3 Better Burst Gauge: loaded the save at " .. name(t) .. ", gauges back: " .. table.concat(s.gauges, " "))
    end
  end
  last_time = t
end)

dwrc.log("DW3 Better Burst Gauge ready: burst gauges are kept with your saves")
