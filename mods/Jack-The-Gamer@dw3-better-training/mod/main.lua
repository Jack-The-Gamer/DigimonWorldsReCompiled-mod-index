-- DW3 Better Training: every round of gym training succeeds.
--
-- Each round of training rolls the game's random number generator:
--
--     r = rand() % 100
--     success = (r <= chance)        -- chance is about 75, or 50 for the bonus
--
-- The gym's code lives in an overlay that is loaded when you visit the gym
-- (a second copy sits in a load buffer), so the mod looks for the roll's
-- machine code every half second and hooks the comparison wherever it is,
-- making the roll equal the chance. The code it looks for holds no
-- addresses, so other releases of the game should match too. The random
-- number is still drawn, so everything else stays exactly as random as it was.

-- From `r = rand() % 100` to `success = !(chance < r)`, registers only.
local ROLL = "3c0351eb 3463851f 00430018 00021fc3 00004010 00082143 00832023 " ..
             "00041840 00641821 000318c0 00641821 00031880 8e24009c 00431023 " ..
             "0082202a 38900001"
local CMP = 0x38          -- offset of `slt a0, a0, v0` (chance < r?)
local SLT = 0x0082202a
local XORI = 0x38900001

-- Overlays load in this part of RAM; searching it takes well under a frame.
local FROM, TO = 0x80040000, 0x800f0000
local CHECK_EVERY = 30    -- frames

local hooked = {}         -- [address] = true

local function intact(ctx, at)
  return ctx:read32(at) == SLT and ctx:read32(at + 4) == XORI
end

local function hook(at)
  if hooked[at] then return end
  hooked[at] = true
  dwrc.on_exec(at, function(ctx)
    -- Some other overlay may use this address: only act on the roll.
    if not intact(ctx, at) then return false end
    -- a0 = chance, v0 = r. Make r the chance: (chance < r) is false.
    ctx:set_reg("v0", ctx:reg("a0"))
    return false
  end)
end

dwrc.on_frame(function(ctx)
  if ctx:frame() % CHECK_EVERY ~= 0 then return end
  -- Every copy (hooking one that never runs costs nothing).
  local at = ctx:find(ROLL, FROM, TO)
  while at do
    if not hooked[at + CMP] then
      dwrc.log(string.format("DW3 Better Training: training code found at %08x", at + CMP))
      hook(at + CMP)
    end
    at = ctx:find(ROLL, at + 4, TO)
  end
end)

dwrc.log("DW3 Better Training ready: gym training always succeeds")
