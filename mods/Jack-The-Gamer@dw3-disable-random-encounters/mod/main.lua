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
-- them back on carries on exactly from there. Battles the story starts,
-- and bosses, are not random encounters and still happen.
--
-- That code is in the field's overlay, so the mod looks for it (by the
-- pattern below, which holds no addresses) every second and hooks each
-- place it turns up. The pattern is on all three discs (Digimon World 2003
-- SLES-03936, Digimon World 3 SLUS-01436 and SLPS-03446), once each.

local PATTERN = "8c43000c 3c02???? 8c630000 2442???? 00031880 00621821 8c630000 8c820030 00000000 00431023 1c40000a ac820030"
local SUBU = 9 * 4            -- offset of `subu v0, v0, v1` in the pattern
local SUBU_WORD, BGTZ_WORD = 0x00431023, 0x1c40000a
local KEY = "R"

local off = false
local hooked = {}             -- addresses hooked so far
local frames = 0

local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end

local function hook(at)
  dwrc.on_exec(at, function(ctx)
    -- Another overlay may have been loaded over this address since.
    if not off or ctx:read32(at) ~= SUBU_WORD or ctx:read32(at + 4) ~= BGTZ_WORD then return false end
    ctx:set_reg("v1", 0)
    -- A new countdown can start at 0: keep it above zero.
    if s32(ctx:reg("v0")) <= 0 then ctx:set_reg("v0", 1) end
    return false
  end)
  hooked[at] = true
  dwrc.log(string.format("DW3 Disable Random Encounters: field step code at %08x", at))
end

dwrc.on_frame(function(ctx)
  frames = frames + 1
  if frames % 50 ~= 1 then return end
  local at = ctx:find(PATTERN)
  if at and not hooked[at + SUBU] then hook(at + SUBU) end
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
