-- Vemmon as partner 17: its record (Partner, in the mod's RAM) starts as
-- initNewGameData starts the game's partners: its name from the Digimon
-- names text (in the player's language), level 1, HP, MP, battle stats and
-- resistances from its DigimonData (entry 55), locked until the DRI Agent
-- gets Vemmon DDNA. A save made without the mod loads the same way.

local eu = require("lib.eu")
local ext = require("lib.ext")
local forms = require("lib.forms")
local save = require("lib.save")
local tables = require("lib.tables")
local text = require("lib.text")

local M = {}

local LANGUAGE = 0x8005CCA8         -- s32: the text files' language (TEXT_FILE adds it)
local names = {}                    -- LANGUAGE -> Vemmon's name (font codes)

function M.build()
  for lang, off in pairs(eu.LANG_OFFSET) do
    local list = text.strings(eu.TEXT_DIGIMON_NAMES + off)
    names[off] = list[forms.NAME[forms.VEMMON]]
  end
end

function M.init(ctx)
  save.clear(ctx)
  local info = ext.VEMMON + ext.P_INFO
  local name = names[ctx:read32(LANGUAGE)] or names[eu.LANG_OFFSET.en] or ""
  ctx:write_bytes(info, (name .. string.rep("\0", 0x18)):sub(1, 0x17) .. "\0")
  local d = tables.DIGIMON + forms.VEMMON * eu.DIGIMON_SIZE
  local stats = info + 0x1C
  local hp, mp = ctx:read8(d + 0x3F), ctx:read8(d + 0x40)
  ctx:write16(stats + 0 * 2, 1)                  -- level
  ctx:write16(stats + 2 * 2, hp)
  ctx:write16(stats + 3 * 2, hp)
  ctx:write16(stats + 4 * 2, mp)
  ctx:write16(stats + 5 * 2, mp)
  for j = 0, 5 do ctx:write16(stats + (6 + j) * 2, ctx:read16(d + 0x02 + 2 * j)) end
  for j = 0, 6 do ctx:write16(stats + (12 + j) * 2, ctx:read16(d + 0x0E + 2 * j)) end
end

function M.install()
  save.on_no_data = M.init
  dwrc.on_exec(eu.initNewGameData, function(ctx)
    M.init(ctx)
    return false
  end)
end

return M
