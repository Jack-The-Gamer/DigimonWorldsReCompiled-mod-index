-- Vemmon DDNA comes from beating Vemmon in the story: the battle in Asuka
-- City's Admin Center 2F (wstag300, event 571, story point 0x16) is
-- encounter 322, Vemmon alone, which the player can't run from. The game
-- gives a battle's prize through BATTLE_SETUP (hasPrize, prize: the battle
-- report announces it and puts it in the bag); FIELDSTG_startEncounter
-- clears hasPrize and sets BATTLE_SETUP.battle for every encounter, and
-- while encounter 322 is on the mod makes Vemmon DDNA its prize, unless the
-- player has one already.

local eu = require("lib.eu")

local M = {}

M.ENCOUNTER = 322
M.ITEM = 0x1A

local BATTLE_SETUP = eu.BATTLE_SETUP
local BATTLE = BATTLE_SETUP + 0x10
local HAS_PRIZE = BATTLE_SETUP + 0x4C
local PRIZE = BATTLE_SETUP + 0x50

function M.install()
  dwrc.on_frame(function(ctx)
    if ctx:read32(BATTLE) ~= M.ENCOUNTER then return end
    if (ctx:read32(eu.GAME_MODE) & 0xFF00) ~= eu.MODE_BATTLE then return end
    if ctx:read8(eu.GAME_ITEMS + M.ITEM) ~= 0 then return end
    if ctx:read32(HAS_PRIZE) ~= 1 or ctx:read32(PRIZE) ~= M.ITEM then
      ctx:write32(HAS_PRIZE, 1)
      ctx:write32(PRIZE, M.ITEM)
      dwrc.log("DW3 Vemmon Partner: the battle with Vemmon gives Vemmon DDNA")
    end
  end)
end

return M
