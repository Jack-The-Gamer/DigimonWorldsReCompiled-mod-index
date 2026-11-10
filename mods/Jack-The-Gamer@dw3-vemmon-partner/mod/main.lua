-- DW3 Vemmon Partner: Vemmon as a ninth partner (its DDNA from the story
-- battle, a DRI Agent in Asuka City's Cargo Tower), and the Vemmon line
-- (Vemmon, Snatchmon, Destromon, Galacticmon) for every partner.
--
-- Made for Digimon World 2003 (Europe, SLES-03936). The game's own data
-- (models, animations, text) is read from the player's disc while the mod
-- loads and changed there (dwrc.disc); the mod ships only its own work.

local disc = require("lib.disc")
local entries = require("lib.entries")
local eu = require("lib.eu")
local ext = require("lib.ext")
local files = require("lib.files")
local save = require("lib.save")
local specials = require("lib.specials")
local tables = require("lib.tables")
local text = require("lib.text")
local vemmon = require("lib.vemmon")

-- Free RAM for the mod: the heap ends 9 KiB lower (0x801FCC00 instead of
-- 0x801FF000), for the techniques' table (ext.lua).
disc.exe_patch32(eu.HEAP_END_ORI, 0x3463F000, 0x3463CC00)
disc.exe_patch32(eu.HEAP_LAST_ORI, 0x34A5EFF4, 0x34A5CBF4)

-- Vemmon DDNA: key item 0x1A, unused in the European release (its name was
-- left in Japanese). The names follow the other DDNAs' in each language.
local VEMMON_DDNA = 0x1A
text.set_all(eu.TEXT_ITEM_NAMES, VEMMON_DDNA, {
  en = "Vemmon DDNA", fr = "ADNN Vemmon", it = "DDNA Vemmon", de = "Vemmon-DDNA", es = "DADN Vemmon",
})
text.set_all(eu.TEXT_ITEM_INFO, VEMMON_DDNA, {
  en = "Vemmon's digital DNA.", fr = "ADN numérique Vemmon", it = "DNA digitale di Vemmon.",
  de = "Digital-DNA von Vemmon.", es = "ADN digital de Vemmon",
})

-- The names of the two new Digimon (the same in every language, as the
-- game's are).
local forms = require("lib.forms")
for _, d in ipairs({ forms.SNATCHMON, forms.DESTROMON }) do
  local name = d == forms.SNATCHMON and "Snatchmon" or "Destromon"
  text.set_all(eu.TEXT_DIGIMON_NAMES, forms.NAME[d], { en = name, fr = name, it = name, de = name, es = name })
end

-- Partner 17 and the new Digimon in the game's code, the partners' extra
-- entries, the save's extension.
tables.build()
entries.build()
save.build()
require("lib.partner").build()
require("lib.evolutions").build()
vemmon.build()

-- The battle fighters. Vemmon: the enemy Vemmon's model (0x1D1), with
-- Agumon's (3) generic scripts and cameras, its claw attack (script 5) also
-- as Messer Claw's (script 11). For now Snatchmon and Destromon fight with
-- the models of Growlmon (0x16F) and Cannondramon (0x189), whose
-- skeletons and motions their own models use, and Galacticmon with its
-- enemy body (0x1D2, the last battle's "body" phase) and Diaboromon's
-- (0x97) generic scripts and cameras. The boss body is 23,500 units tall
-- and 19,100 deep (Diaboromon 6,500 tall, 6,000 deep; partner cameras
-- sit close behind): its partner copy is 0.22 of it, raised so its lowest
-- point (y 13,558 at its idle pose) stands on the ground and centred in
-- depth (z -7,609..11,504).
local GALACTICMON_SCALE = 0.22
local fighters = require("lib.fighters")
local models = require("lib.models")
fighters.add_partner_from_enemy(forms.ID[forms.VEMMON], 0x1D1, 0x3, { copies = { [11] = 5 } })
-- Snatchmon: its own model (models/snatchmon.lua) on Devimon's (6) skeleton,
-- motions, scripts and cameras
fighters.add_partner_model(forms.ID[forms.SNATCHMON], 0x6,
  models.build(fighters.model_file(0x6), require("models.snatchmon")))
-- Destromon: its own model (models/destromon.lua) on Cannondramon's (0x189)
fighters.add_partner_model(forms.ID[forms.DESTROMON], 0x189,
  models.build(fighters.model_file(0x189), require("models.destromon")))
fighters.add_partner_from_enemy(forms.ID[forms.GALACTICMON], 0x1D2, 0x97, {
  copies = { [11] = 5 }, scale = GALACTICMON_SCALE,
  offset = { 0, math.floor(-13558 * GALACTICMON_SCALE), math.floor(-(11504 - 7609) / 2 * GALACTICMON_SCALE) } })

-- The DRI Agent in Cargo Tower (FIELDSTG's own stage).
require("lib.dri").build(files.overlay(eu.FILE_FIELDSTG))

specials.define(specials.VEMMON_UNLOCKED, function(ctx) return ext.vemmon_unlocked(ctx) and 1 or 0 end)
specials.define(specials.UNLOCK_VEMMON, function(ctx)
  ext.unlock_vemmon(ctx)
  dwrc.log("DW3 Vemmon Partner: Vemmon is a partner now")
  return 1
end)

tables.finish()
save.set_digimon(tables.parts.digimon)

text.commit()
files.commit()
fighters.commit()
disc.commit()

disc.install_hooks()
tables.install()
vemmon.install()
entries.install()
save.install()
require("lib.partner").install()
specials.install()
require("lib.ddna").install()
dwrc.log("DW3 Vemmon Partner: loaded")
