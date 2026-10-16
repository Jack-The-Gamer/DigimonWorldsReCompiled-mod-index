-- Fast-Forward: press Select and Start together to play at double speed,
-- again for triple speed, and a third time to return to normal speed.
--
-- The music keeps its normal speed. All three games play music with Sony's
-- sound library (libsnd), whose sequencer runs once per tick from an
-- interrupt (240 times a second in Digimon World, once a frame in the
-- others). While sped up, this mod lets the sequencer play the music on only
-- one tick in two (or three), so it keeps time with the real world, and asks
-- the emulator to play the music's voices on the sound chip at real-time
-- pitch.
--
-- Sound effects, by option:
--   Normal pitch: every voice keeps real-time pitch, and sequenced effects
--                 keep real time like the music.
--   Sped up:      only the music's voices keep real time; effects play
--                 faster and higher, like everything else.

local SELECT, START = dwrc.buttons.Select, dwrc.buttons.Start
local BOTH = SELECT | START
-- With a shoulder button held, Select + Start goes to the game untouched
-- (L1 + L2 + R1 + R2 + Select + Start is a common reset combination).
local SHOULDERS = dwrc.buttons.L1 | dwrc.buttons.L2 | dwrc.buttons.R1 | dwrc.buttons.R2
local HOLD = 8          -- frames a lone Select or Start waits for the other (~1/8 s)
local MAX_SPEED = 3
local sped_up_effects = dwrc.options.effects == "Sped up"

-- ---------------------------------------------------------------------------
-- Finding the sound library

-- The start of SsSeqCalledTbyT (the sequencer tick), with the addresses of
-- its variables left out: the same code in all three games.
local SIG = "27bdffc8 3c02???? 8c42???? 24030001 afbf0034 afbe0030 afb7002c " ..
            "afb60028 afb50024 afb40020 afb3001c afb20018 afb10014 10430082 " ..
            "afb00010 3c01???? ac23???? 0c?????? 0000b821"
local AFTER_FLUSH = 0x4C  -- after `jal _SsVmFlush` (key-ons are written)
local SEQ_LOOP    = 0x68  -- the loop over open sequences (s7 = sequence)
local SEQ_NEXT    = 0x220 -- ...its "next sequence"
local DONE        = 0x238 -- clears the busy flag and returns

-- Sequences that play sound effects rather than music (libsnd's own
-- SsUtKeyOn effects never belong to a sequence). Digimon World 2 plays its
-- effects as sequences 0 to 3.
local EFFECT_SEQS = ({ dw2 = { [0] = true, [1] = true, [2] = true, [3] = true } })[dwrc.game] or {}
local ALL_VOICES = 0xFFFFFF

local entry, flush_call      -- SsSeqCalledTbyT, and its `jal _SsVmFlush` word
local voices, stride         -- libsnd's voice table
local searches = 0

local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

local function find_sound_driver(ctx)
  local at = ctx:find(SIG, 0x80010000, 0x80200000)
  if not at then return false end
  local call = ctx:read32(at + 0x44)
  local flush = 0x80000000 | ((call & 0x03FFFFFF) << 2)
  -- _SsVmFlush walks the voice table: lui s2, hi / addiu s2, s2, lo ...
  -- addiu s2, s2, stride.
  local lui, add, step = ctx:read32(flush + 0x70), ctx:read32(flush + 0x74), ctx:read32(flush + 0xC4)
  if (lui >> 16) == 0x3c12 and (add >> 16) == 0x2652 and (step >> 16) == 0x2652 then
    voices = ((lui & 0xFFFF) << 16) + s16(add & 0xFFFF)
    stride = step & 0xFFFF
  elseif sped_up_effects then
    dwrc.log("Fast-Forward: couldn't read the voice table; sound effects will keep normal pitch")
    sped_up_effects = false
  end
  entry, flush_call = at, call
  return true
end

-- ---------------------------------------------------------------------------
-- Slowing the music to real time

local tick = 0
local skip = false      -- this tick plays no music
local function intact(ctx) return ctx:read32(entry + 0x44) == flush_call end

local function owner_is_music(o)
  return o < 32 and not EFFECT_SEQS[o]
end

local function install_hooks()
  dwrc.on_exec(entry + AFTER_FLUSH, function(ctx)
    local speed = dwrc.speed()
    if speed == 1 or not intact(ctx) then
      skip = false
      return false
    end
    tick = tick + 1
    skip = tick % speed ~= 0
    if not sped_up_effects then
      dwrc.set_realtime_voices(ALL_VOICES)
      if skip then
        ctx:set_pc(entry + DONE) -- no sequence plays on this tick
        return true
      end
      return false
    end
    -- Only the music's voices keep real time. Each voice's owner (byte 10):
    -- a sequence number, 33 for an SsUtKeyOn effect, 255 when free.
    local mask = 0
    for v = 0, 23 do
      if owner_is_music(ctx:read8(voices + v * stride + 0x0A)) then
        mask = mask | (1 << v)
      end
    end
    dwrc.set_realtime_voices(mask)
    return false
  end)
  if sped_up_effects then
    dwrc.on_exec(entry + SEQ_LOOP, function(ctx)
      if skip and owner_is_music(ctx:reg("s7")) and intact(ctx) then
        ctx:set_pc(entry + SEQ_NEXT) -- this music sequence waits a tick
        return true
      end
      return false
    end)
  end
end

dwrc.on_frame(function(ctx)
  if entry then return end
  if ctx:frame() % 60 ~= 0 then return end
  searches = searches + 1
  if find_sound_driver(ctx) then
    install_hooks()
    dwrc.log(string.format("Fast-Forward: sound driver at %08x", entry))
  elseif searches == 30 then
    dwrc.log("Fast-Forward: sound driver not found yet; music will speed up too until it is")
  end
end)

-- ---------------------------------------------------------------------------
-- Select + Start

local prev = 0       -- Select/Start as pressed on the previous frame
local pending = 0    -- a lone Select or Start held back from the game
local wait = 0       -- ...for this many frames
local combo = false  -- both are down: hidden from the game until released
local replay, replay_left = 0, 0 -- a short tap held back, shown late

local function switch_speed()
  local speed = dwrc.speed() % MAX_SPEED + 1
  dwrc.set_speed(speed)
  if speed == 1 then dwrc.set_realtime_voices(0) end
  tick = 0
  dwrc.log(speed == 1 and "Fast-Forward: normal speed" or ("Fast-Forward: " .. speed .. "x speed"))
end

dwrc.on_input(function(b)
  local s = b & BOTH
  local new = s & ~prev
  prev = s
  if combo then
    if s == 0 then combo = false end
    return b & ~BOTH
  end
  local free = (b & SHOULDERS) == 0
  if pending ~= 0 then
    if s == BOTH then
      pending, combo = 0, true
      switch_speed()
      return b & ~BOTH
    elseif (s & pending) == 0 then
      -- Let go before the other came: the game gets the tap now.
      replay, replay_left = pending, 2
      pending = 0
    else
      -- Wait a little longer for the other (in real time, at any speed).
      wait = wait + 1
      if wait < HOLD * dwrc.speed() then return b & ~pending end
      pending = 0
    end
  elseif free and s == BOTH and new == BOTH then
    combo = true
    switch_speed()
    return b & ~BOTH
  elseif free and new ~= 0 and s == new then
    pending, wait = new, 0
    return b & ~new
  end
  if replay_left > 0 then
    replay_left = replay_left - 1
    b = b | replay
  end
  return b
end)

dwrc.log("Fast-Forward ready: press Select + Start to change speed (sound effects: " ..
         (sped_up_effects and "sped up" or "normal pitch") .. ")")
