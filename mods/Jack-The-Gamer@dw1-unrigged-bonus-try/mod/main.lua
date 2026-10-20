-- DW1 Un-Rigged Bonus Try: takes the rigging out of the gym slot machine.
--
-- How the game does it (TRN_REL.BIN at 0x8008e824, TRN2_REL.BIN at
-- 0x8008d1fc, both loaded at 0x80088800): pressing X calls a "stop reel"
-- function with the reel (a0, 0-2) and the slot state (a1). It sets how many
-- more pictures the reel rolls before stopping (byte 14+reel), according to
-- a mode picked for the round before it starts (byte 34):
--   0: the reels stop on the next picture, except that when the first two
--      reels match and the third would match too, the third rolls one or
--      two pictures further (rand()): the round can't be won;
--   1: the second and third reels are steered onto a match within two
--      pictures, except a jackpot: when the first two reels show it and
--      the third would too, the third rolls one or two pictures further;
--   2: reels are steered onto the jackpot picture.
-- Slot state: byte 8+reel = picture index (0-12) on the reel's strip,
-- halfword 18+2*reel = scroll offset, byte 11+reel = the picture the reel is
-- expected to stop on (used by the later reels' decisions). A stopping reel
-- stops on the first picture boundary it passes after X, plus the extra
-- pictures. Strips: three tables of 13 picture ids, read from the function.
--
-- Option "Slot machine":
--   Original - No Rigging: the function runs as shipped, help included,
--     except where it rolls the third reel past a match (mode 0, and mode 1
--     with two jackpots): the third reel then just stops on the next picture.
--   True Slots: every reel stops on the next picture after X (no extra
--     pictures, no steering), whatever the mode.

local STOP = "27bdffe0 afbf0018 afb10014 afb00010 24010002 108100?? 00a08021 24010001 108100?? 00000000 1480???? 00000000 82020022"
local FROM, TO = 0x80088000, 0x80098000
local PICTURES = 13
local TRUE_SLOTS = dwrc.options.mode == "True Slots"

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
    if TRUE_SLOTS then
      local sym = c:read8(s + 8 + reel)
      if sym >= PICTURES then return false end
      c:write8(s + 14 + reel, 0)
      c:write8(s + 11 + reel, c:read8(strips_at + PICTURES * reel + (sym + PICTURES - 1) % PICTURES))
      return c:ret(0)
    end
    -- Original - No Rigging: only the cases that roll past a match go.
    if reel == 2 then
      local mode = c:read8(s + 34)
      local jackpots = c:read_s8(s + 11) == 7 and c:read_s8(s + 12) == 7
      if mode == 0 or (mode == 1 and jackpots) then
        c:write8(s + 14 + reel, 0)
        return c:ret(0)
      end
    end
    return false
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
        dwrc.log(string.format("DW1 Un-Rigged Bonus Try: slot machine found at %08x (%s)", at, dwrc.options.mode))
      end
    end
    at = ctx:find(STOP, at + 4, TO)
  end
end)
