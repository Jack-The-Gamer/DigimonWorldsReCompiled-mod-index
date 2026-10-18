-- DW3 Better DV EXP: every won battle gives 5 DV EXP.
--
-- After a battle, the results screen works out the DV EXP for each
-- digivolution used in the battle with one function (in an overlay loaded
-- for that screen): a value for the battle, scaled down by the Digimon's
-- level, kept between 1 and 10 (or 50 once the digivolution's level is high
-- enough). The mod finds the end of that function by its machine code (no
-- addresses in it, so other releases of the game should match too) and
-- makes the answer 5 just before it returns. Normal EXP is worked out
-- elsewhere and is not touched, and digivolutions that the game gives no DV
-- EXP to still get none.

local DV_EXP = 5

-- From `if (gain <= 0) gain = 1` to the function's return: `v0 = gain`,
-- then `lw ra, 56(sp)`. `?` marks the two jumps, whose targets are addresses.
local GAIN = "1e000003 00000000 08?????? 24100001 83a20012 9223003c 00000000 " ..
             "0043102a 10400005 2a02000b 14400008 02001021 08?????? 2410000a " ..
             "2a020033 14400003 02001021 24100032 02001021 8fbf0038"
local RETURN = 19 * 4      -- offset of `lw ra, 56(sp)`: v0 holds the answer
local LW_RA = 0x8fbf0038
local MOVE = 0x02001021    -- addu v0, s0, zero (the instruction before it)

-- The results overlay loads into this part of RAM; it arrives seconds
-- before the DV EXP is handed out, so checking a few times a second is plenty.
local FROM, TO = 0x80040000, 0x800f0000
local CHECK_EVERY = 10    -- frames

local hooked = {}

local function intact(ctx, at)
  return ctx:read32(at) == LW_RA and ctx:read32(at - 4) == MOVE
end

local function hook(at)
  hooked[at] = true
  dwrc.on_exec(at, function(ctx)
    if not intact(ctx, at) then return false end -- other code lives here now
    ctx:set_reg("v0", DV_EXP)
    return false
  end)
end

dwrc.on_frame(function(ctx)
  if ctx:frame() % CHECK_EVERY ~= 0 then return end
  local at = ctx:find(GAIN, FROM, TO)
  while at do
    if not hooked[at + RETURN] then
      dwrc.log(string.format("DW3 Better DV EXP: DV EXP code found at %08x", at + RETURN))
      hook(at + RETURN)
    end
    at = ctx:find(GAIN, at + 4, TO)
  end
end)

dwrc.log("DW3 Better DV EXP ready: battles give " .. DV_EXP .. " DV EXP")
