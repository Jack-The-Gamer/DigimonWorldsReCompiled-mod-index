-- Turbo: hold the turbo button (R2 by default), then hold one or two other
-- buttons. Those buttons are pressed and released rapidly for as long as you
-- keep holding them, even after you let go of the turbo button. The game
-- never sees the turbo button itself.

local trigger = dwrc.buttons[dwrc.options.hold] or dwrc.buttons.R2
local rate = math.max(2, math.floor(dwrc.options.rate or 4))
local MAX = 2   -- buttons on turbo at once
local GRACE = 4 -- frames: a button pressed just before the turbo button still joins

-- Every other button, in a fixed order.
local masks = {}
for _, m in pairs(dwrc.buttons) do
  if m ~= trigger then masks[#masks + 1] = m end
end
table.sort(masks)

local turbo = {}   -- [mask] = frames that button has been on turbo
local active = 0   -- how many buttons are on turbo
local held = {}    -- [mask] = frames the button has been held (0 on the frame it goes down)
local was_trigger = false

dwrc.on_input(function(b)
  local trig = (b & trigger) ~= 0
  local just_pressed = trig and not was_trigger
  was_trigger = trig
  b = b & ~trigger -- hide the turbo button from the game

  -- Track how long each button has been held; a released button leaves turbo.
  for _, m in ipairs(masks) do
    if (b & m) ~= 0 then
      held[m] = (held[m] or -1) + 1
    else
      held[m] = nil
      if turbo[m] ~= nil then
        turbo[m] = nil
        active = active - 1
      end
    end
  end

  -- While the turbo button is held, a button that goes down joins turbo
  -- (up to MAX). When the turbo button itself goes down, buttons pressed in
  -- the last few frames join too, so pressing both at once works.
  if trig then
    for _, m in ipairs(masks) do
      if active >= MAX then break end
      local f = held[m]
      if f ~= nil and turbo[m] == nil and (f == 0 or (just_pressed and f <= GRACE)) then
        turbo[m] = 0
        active = active + 1
      end
    end
  end

  -- Each turbo button is pressed for the first half of every `rate` frames,
  -- counted from when it joined, so it responds at once.
  for m, n in pairs(turbo) do
    if (n % rate) < (rate // 2) then b = b | m else b = b & ~m end
    turbo[m] = n + 1
  end
  return b
end)

dwrc.log("Turbo ready: hold " .. dwrc.options.hold .. ", then the buttons to turbo")
