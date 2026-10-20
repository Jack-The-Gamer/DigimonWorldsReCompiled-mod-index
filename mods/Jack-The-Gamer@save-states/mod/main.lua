-- Save States: keys 1 to 5 save the console to slots 1 to 5, Shift + 1 to 5
-- load them. Re:Compiled does the saving and loading between frames, keeps
-- the slots per release (in its data folder, under states/), shows "Saved
-- state 1" and the like on screen, and refuses a slot saved with another
-- release or BIOS. Memory cards are not part of a state, so loading one never
-- takes your saves back.

local SLOTS = 5

dwrc.on_key(function(ctx, key, mods)
  local slot = tonumber(key)
  if not slot or slot < 1 or slot > SLOTS or mods.ctrl or mods.alt then
    return
  end
  if mods.shift then
    dwrc.load_state(slot)
  else
    dwrc.save_state(slot)
  end
end)
