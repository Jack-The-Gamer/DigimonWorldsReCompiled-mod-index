-- The mod's Digimon: entries 55-58 of the moved DIGIMON_DATA (tables.lua),
-- after the game's 55. Vemmon is partner 17's own Digimon (its Rookie);
-- Snatchmon, Destromon and Galacticmon are forms every partner can learn,
-- kept in each partner's three extra entries (entries.lua), in this order.

local bin = require("lib.bin")

local M = {}

M.VEMMON = 55
M.SNATCHMON = 56
M.DESTROMON = 57
M.GALACTICMON = 58
M.COUNT = 59
M.NEW_FORMS = { M.SNATCHMON, M.DESTROMON, M.GALACTICMON }   -- extra entry k = NEW_FORMS[k + 1]

-- Their ids (DigimonData.id, also their fighters' ids): after the game's
-- last (AncientGreymon, 0x1D6).
M.ID = { [M.VEMMON] = 0x1D7, [M.SNATCHMON] = 0x1D8, [M.DESTROMON] = 0x1D9, [M.GALACTICMON] = 0x1DA }

-- Their names in the Digimon names text (DigimonData.nameId): the game has
-- Vemmon (248) and Galacticmon (225); Snatchmon and Destromon are added
-- after its last (250).
M.NAME = { [M.VEMMON] = 248, [M.SNATCHMON] = 251, [M.DESTROMON] = 252, [M.GALACTICMON] = 225 }

-- The extra entry (0-2) a Digimon id goes in, or nil.
function M.extra_slot(id)
  for k, d in ipairs(M.NEW_FORMS) do
    if M.ID[d] == id then return k - 1 end
  end
  return nil
end

-- The four new DigimonData entries (0x58 bytes each), from the game's 55
-- (`game`, 55 * 0x58 bytes). Each takes its battle stats, status
-- resistances, exp and growth from a game Digimon of its level and kind
-- (Vemmon: Guilmon, a Rookie; Snatchmon: Devimon; Destromon: Myotismon;
-- Galacticmon: Diaboromon, the strongest Megas, as it comes after Destromon
-- at 99). The line is Machine-aligned: the Machine family (5, as
-- MetalGreymon's), its best resistance Machine, then Dark and Thunder
-- (resistances: fire, water, ice, wind, thunder, machine, dark).
-- skills[0] is the basic attack, [1]-[6] are learnt at skillLevels ([6]
-- the signature; a Rookie has its basic attack and signature only).
local techs = require("lib.techs")
local T = techs.ID

local DATA = {
  [M.VEMMON] = { template = 5,
    resist = { 80, 80, 80, 80, 110, 130, 110 },
    skills = { 6, 0, 0, 0, 0, 0, T["Messer Claw"] },
    -- what a blast turns Vemmon into, by its level's tier (from 1)
    blast = { M.SNATCHMON + 1, M.DESTROMON + 1, M.GALACTICMON + 1, M.GALACTICMON + 1, M.GALACTICMON + 1 } },
  [M.SNATCHMON] = { template = 16,
    resist = { 20, 20, 20, 20, 50, 70, 50 },
    skills = { techs.BASIC_SNATCHMON, T["Tooth Spear"], 156, 164, T["Fusionize"], 0, T["Ruin Laser"] },   -- 156 Thunder Bolt, 164 Dark Matter
    levels = { 5, 10, 25, 40, 0, 60 }, known = { 15, 30, 60, 90, 0 } },
  [M.DESTROMON] = { template = 28,
    resist = { 20, 20, 30, 20, 60, 90, 70 },
    skills = { techs.BASIC_DESTROMON, T["Triple Cannon"], 158, T["Buster Cannon"], 165, T["Fusionize"], T["Juggernaut Blast"] },   -- 158 Electro Bolt, 165 Dark Fear
    levels = { 10, 25, 40, 55, 65, 85 }, known = { 30, 50, 60, 90, 95 } },
  [M.GALACTICMON] = { template = 51,
    resist = { 30, 30, 40, 30, 90, 120, 90 },
    skills = { techs.BASIC_GALACTICMON, T["Gimlet Gun"], T["Space Laser"], T["Shuttle Scissors"], T["Satellite Buster"], T["Fusionize"], T["Ragnarok Cannon"] },
    levels = { 5, 20, 35, 50, 60, 99 }, known = { 15, 40, 70, 80, 90 } },
}
M.FAMILY = 5

function M.entries(game)
  local out = {}
  for d = M.VEMMON, M.GALACTICMON do
    local s = DATA[d]
    local t = s.template
    local e = game:sub(t * 0x58 + 1, t * 0x58 + 0x58)
    e = bin.put16(e, 0x00, M.ID[d])
    e = bin.put(e, 0x0E, string.pack("<HHHHHHH", table.unpack(s.resist)))
    e = bin.put(e, 0x1C, string.pack("<HHHHHHH", table.unpack(s.skills)))
    e = bin.put16(e, 0x2A, 0)                -- no pair technique
    e = bin.put8(e, 0x3D, 0)
    if s.levels then e = bin.put(e, 0x31, bin.bytes(s.levels)) end
    if s.known then e = bin.put(e, 0x37, bin.bytes(s.known)) end
    e = bin.put(e, 0x50, bin.bytes(s.blast or { 0, 0, 0, 0, 0 }))
    e = bin.put8(e, 0x55, M.NAME[d])
    e = bin.put8(e, 0x56, M.FAMILY)
    out[#out + 1] = e
  end
  return table.concat(out)
end

return M
