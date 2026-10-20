-- DW1 Un-Rigged Bonus Try: the gym slot machine stops each reel on the
-- picture that was in the middle of the window when X was pressed.
--
-- How the game rigs it (TRN_REL.BIN at 0x8008e824, TRN2_REL.BIN at
-- 0x8008d1fc, both loaded at 0x80088800): pressing X calls a "stop reel"
-- function with the reel (a0, 0-2) and the slot state (a1). It sets how many
-- more pictures the reel rolls before stopping (byte 14+reel), according to
-- a mode picked for the round before it starts (byte 34): in one mode, when
-- the first two reels match and the third would match too, it rolls the
-- third reel one or two pictures further (rand()), so the round can't be
-- won; the other modes steer reels onto a match or the jackpot instead.
--
-- Slot state: byte 8+reel = picture index (0-12) on the reel's strip,
-- halfword 18+2*reel = scroll offset (0-31 px), halfword 24+2*reel = speed
-- (offset step = speed >> 6, 16 px). Every game step (3 frames) a moving
-- reel scrolls by one step; on passing 32 the next picture (index - 1)
-- arrives and a stopping reel stops there unless it still has pictures to
-- roll. Strips: three tables of 13 picture ids, read from the function.
--
-- This mod replaces the stop function: it works out the picture that was on
-- screen (the screen shows the reel one step behind the game) and sets the
-- reel up to stop on exactly that picture at the next step.

local STOP = "27bdffe0 afbf0018 afb10014 afb00010 24010002 108100?? 00a08021 24010001 108100?? 00000000 1480???? 00000000 82020022"
local FROM, TO = 0x80088000, 0x80098000
local PICTURES = 13

local hooked = {}

-- The strip table address, from the function's `lui v0, hi` / `addiu v0, v0, lo`.
local function strips_of(ctx, fn)
  local lui, add = ctx:read32(fn + 0x7c), ctx:read32(fn + 0x80)
  if (lui >> 16) ~= 0x3c02 or (add >> 16) ~= 0x2442 then return nil end
  local lo = add & 0xffff
  if lo >= 0x8000 then lo = lo - 0x10000 end
  return ((lui & 0xffff) << 16) + lo
end

local function hook(fn, strips)
  local first, second = 0x27bdffe0, 0xafbf0018
  local fn_at, strips_at = fn, strips -- per-copy locals for the closure
  dwrc.on_exec(fn_at, function(c)
    -- Another overlay may be loaded here now: check before changing anything.
    if c:read32(fn_at) ~= first or c:read32(fn_at + 4) ~= second or strips_of(c, fn_at) ~= strips_at then
      return false
    end
    local reel, s = c:reg("a0"), c:reg("a1")
    if reel > 2 then return false end
    local sym = c:read8(s + 8 + reel)
    local pos = c:read_s16(s + 18 + 2 * reel)
    local step = c:read_s16(s + 24 + 2 * reel) >> 6
    if sym >= PICTURES or step <= 0 or step > 31 or pos < 0 or pos > 31 then return false end
    -- What the player saw: the reel one step earlier.
    local seen_pos, seen = pos - step, sym
    if seen_pos < 0 then
      seen_pos = seen_pos + 32
      seen = (sym + 1) % PICTURES
    end
    -- More than half scrolled: the next picture is the one in the middle.
    if seen_pos >= 16 then seen = (seen + PICTURES - 1) % PICTURES end
    -- Stop on it at the next step: one picture before it, scrolled so that
    -- one more step passes 32 (exactly 32 would be held at 31).
    c:write8(s + 8 + reel, (seen + 1) % PICTURES)
    c:write16(s + 18 + 2 * reel, 33 - step)
    c:write8(s + 14 + reel, 0)
    c:write8(s + 11 + reel, c:read8(strips_at + PICTURES * reel + seen))
    return c:ret(0)
  end)
end

dwrc.on_frame(function(ctx)
  if ctx:frame() % 20 ~= 0 then return end
  local at = ctx:find(STOP, FROM, TO)
  while at do
    if not hooked[at] then
      local strips = strips_of(ctx, at)
      if strips then
        hooked[at] = true
        hook(at, strips)
        dwrc.log(string.format("DW1 Un-Rigged Bonus Try: slot machine found at %08x", at))
      end
    end
    at = ctx:find(STOP, at + 4, TO)
  end
end)
