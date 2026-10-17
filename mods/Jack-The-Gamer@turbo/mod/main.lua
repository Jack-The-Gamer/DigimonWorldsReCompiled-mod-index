-- Turbo: hold the turbo button (R2 by default), then hold one or two other
-- buttons. Those buttons are pressed and released rapidly for as long as you
-- keep holding them, even after you let go of the turbo button. The game
-- never sees the turbo button itself.
--
-- L2 and R2 are never turboed. Pressing them together (within about 1/8 s)
-- is left alone, so it reaches the game or another mod (Fast-Forward uses
-- L2 + R2 to change speed).

-- R2 or L2 (a choice saved by an older version, like R1, falls back to R2).
local hold = dwrc.options.hold == "L2" and "L2" or "R2"
local trigger = dwrc.buttons[hold]
local rate = math.max(2, math.floor(dwrc.options.rate or 4))
local MAX = 2   -- buttons on turbo at once
local GRACE = 4 -- frames: a button pressed just before the turbo button still joins
local TRIGGERS = dwrc.buttons.L2 | dwrc.buttons.R2
local partner = TRIGGERS & ~trigger -- the other of L2 / R2
local TOGETHER = 8 -- frames between the turbo button and its partner that count as together

-- Every button that can be turboed (not L2 or R2), in a fixed order.
local masks = {}
for _, m in pairs(dwrc.buttons) do
  if (m & TRIGGERS) == 0 then masks[#masks + 1] = m end
end
table.sort(masks)

local turbo = {}   -- [mask] = frames that button has been on turbo
local active = 0   -- how many buttons are on turbo
local held = {}    -- [mask] = frames the button has been held (0 on the frame it goes down)
local was_trigger = false
local trig_frames, partner_frames = nil, nil -- frames each has been held
local aside = false -- L2 + R2 pressed together: both pass through until the turbo button is let go
local joined = {}   -- buttons that joined turbo during this press of the turbo button

dwrc.on_input(function(b)
  local trig = (b & trigger) ~= 0
  local just_pressed = trig and not was_trigger
  was_trigger = trig
  trig_frames = trig and (trig_frames or -1) + 1 or nil
  partner_frames = (b & partner) ~= 0 and (partner_frames or -1) + 1 or nil
  if just_pressed then joined = {} end

  -- The turbo button and its partner pressed together (in real time, at any
  -- speed): stand aside until the turbo button is let go.
  local window = TOGETHER * (dwrc.speed and dwrc.speed() or 1)
  if not trig then
    aside = false
  elseif not aside and partner_frames ~= nil
      and ((just_pressed and partner_frames < window) or (partner_frames == 0 and trig_frames < window)) then
    aside = true
    for m in pairs(joined) do -- undo what this press started
      if turbo[m] ~= nil then turbo[m] = nil; active = active - 1 end
    end
  end
  if not aside then b = b & ~trigger end -- hide the turbo button from the game

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
  if trig and not aside then
    for _, m in ipairs(masks) do
      if active >= MAX then break end
      local f = held[m]
      if f ~= nil and turbo[m] == nil and (f == 0 or (just_pressed and f <= GRACE)) then
        turbo[m] = 0
        active = active + 1
        joined[m] = true
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

dwrc.log("Turbo ready: hold " .. hold .. ", then the buttons to turbo")
