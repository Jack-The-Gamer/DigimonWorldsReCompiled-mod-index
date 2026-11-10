-- The DRI Agent who studies Vemmon, on the upper floor of Asuka City's
-- Cargo Tower, by the crates (map position 242, 139, where the game itself
-- puts a character at one story point).
--
-- Cargo Tower is FIELDSTG's own stage (mode 528): FIELDSTG_setupField sets
-- the field's characters to FIELDSTG_actorList. The mod appends a longer
-- list (the game's 115 characters and the agent) to the FIELDSTG overlay
-- and points the setup at it. The agent is character 0x2B, the DRI agents'
-- (sprite file 778, P042LABO), in image slot 5: the slot of one of the
-- auction's crowd, who are only there at the auctions' story points, when
-- the agent is not (his condition list is the downstairs lift panel's,
-- without the lift).
--
-- He talks as the game's DRI Agents do (DRI Johann, wstag405, is the
-- model): without the DDNA he asks for it, with Vemmon DDNA he makes Vemmon
-- a partner (SPECIAL actions, see specials.lua) and plays the item-get icon,
-- and afterwards he asks the player to raise Vemmon well.

local codes = require("lib.codes")
local eu = require("lib.eu")
local mips = require("lib.mips")
local specials = require("lib.specials")
local text = require("lib.text")

local M = {}

M.VEMMON_DDNA = 0x1A
M.CHARACTER = 0x2B
M.IMAGE = 5
M.X, M.Y, M.DIR = 242, 139, 1
M.ASIDE_PROGRESS = 0x09                 -- STORY_AGUMON_SUITS
M.ASIDE_X, M.ASIDE_Y = 272, 156

local NAME = { en = "DRI Marcus", fr = "Marcus de l'IRD", it = "Marcus del DRI", de = "DRI Marcus", es = "DRI Marcus" }

-- Pages of each talk, by language; {nl} breaks a line.
local TALKS = {
  ask = {
    en = { "I'm Marcus. I'm{nl}researching{nl}Vemmon.",
           "It's a strange{nl}Digimon that lurks{nl}in the network...",
           "If I can get Vemmon's{nl}DDNA, I can proceed{nl}with my research...",
           "If you ever defeat{nl}Vemmon, can you get{nl}its DDNA for me?",
           "I'll add Vemmon as{nl}your partner as a{nl}reward!" },
    fr = { "Je suis Marcus.{nl}J'étudie{nl}Vemmon.",
           "C'est un Digimon{nl}étrange qui rôde{nl}dans le réseau...",
           "Avec l'ADNN de Vemmon,{nl}je pourrai poursuivre{nl}mes recherches...",
           "Si tu bats Vemmon,{nl}peux-tu lui prendre{nl}son ADNN ?",
           "En récompense, je{nl}t'ajouterai Vemmon{nl}comme partenaire !" },
    it = { "Sono Marcus.{nl}Studio{nl}Vemmon.",
           "È un Digimon{nl}misterioso che si{nl}aggira nella rete...",
           "Se mi porti il{nl}suo DDNA, posso{nl}procedere.",
           "Se sconfiggi Vemmon{nl}potresti prendere{nl}il suo DDNA?",
           "Ti darò Vemmon{nl}come Partner!" },
    de = { "Ich bin Marcus.{nl}Ich erforsche{nl}Vemmon.",
           "Ein seltsames{nl}Digimon, das im{nl}Netzwerk lauert...",
           "Wenn ich Vemmon-{nl}DDNA habe, kann ich{nl}weiter forschen.",
           "Wenn du Vemmon be-{nl}siegst, besorgst du{nl}mir seine DDNA?",
           "Als Belohnung be-{nl}kommst du Vemmon{nl}als Partner!" },
    es = { "Soy Marcus.{nl}Estoy investigando{nl}a Vemmon.",
           "Es un Digimon{nl}extraño que acecha{nl}en la red...",
           "Si consigo DADN de{nl}Vemmon, podré{nl}seguir mi investigación",
           "¡Oh! Si derrotas a{nl}Vemmon, ¿cogerás su{nl}DADN para mí?",
           "¡Haré que Vemmon{nl}te acompañe{nl}como recompensa!" },
  },
  give = {
    en = { "Yes! That is{nl}Vemmon's DDNA!",
           "Then I'll add Vemmon{nl}as your partner like I{nl}promised!",
           "Go to Piximon or{nl}Dr. Kadomatsu at{nl}the lab!",
           "Vemmon should be{nl}in the list under{nl}Switch Digimon!",
           "Good luck and raise{nl}a strong Vemmon!" },
    fr = { "Oui ! Voici l'ADNN{nl}de Vemmon !",
           "Comme promis, je vais{nl}t'ajouter Vemmon{nl}comme partenaire !",
           "Va voir Piximon ou{nl}le Dr. Kadomatsu au{nl}labo !",
           "Vemmon doit être{nl}dans la liste pour{nl}Changer de Digimon.",
           "Bonne chance{nl}avec Vemmon !" },
    it = { "Sì! DDNA di{nl}Vemmon!",
           "Ti darò Vemmon{nl}come ti ho{nl}promesso!",
           "Vai da Piximon o{nl}da Kadomatsu al{nl}laboratorio!",
           "Vemmon è nella{nl}lista sotto Cambia{nl}Digimon!",
           "Buona fortuna e{nl}crescilo bene!" },
    de = { "Ja! Das ist Vemmon-{nl}DDNA!",
           "Wie versprochen be-{nl}kommst du Vemmon{nl}als Partner!",
           "Geh zu Piximon{nl}oder Dr. Kadomatsu{nl}im Labor!",
           "Vemmon ist unter{nl}Digimon tauschen{nl}aufgelistet.",
           "Viel Glück und züchte{nl}einen starken Vemmon!" },
    es = { "¡Sí! Ese es el DADN{nl}de Vemmon.",
           "Haré que Vemmon{nl}te acompañe{nl}como prometí.",
           "Busca a Piximon o{nl}Dr. Kadomatsu en{nl}el Laboratorio.",
           "Vemmon debería{nl}estar en la lista de{nl}Switch Digimon.",
           "Buena suerte, consigue{nl}un Vemmon fuerte." },
  },
  after = {
    en = { "I'm counting on{nl}you!", "Please raise a{nl}strong Vemmon!" },
    fr = { "Je compte sur{nl}toi !", "Rends Vemmon{nl}fort !" },
    it = { "Conto su di{nl}te!", "Cresci un{nl}forte Vemmon!" },
    de = { "Ich zähl' auf{nl}dich!", "Züchte einen{nl}starken Vemmon!" },
    es = { "¡Cuento{nl}contigo!", "Consigue un{nl}Vemmon fuerte." },
  },
}

-- A talk as the game writes one: {c7}name{c7}page{wait 2}{page}page{wait 2}
local function talk_text(lang, pages)
  return "{c7}" .. NAME[lang] .. "{c7}" .. table.concat(pages, "{wait 2}{page}") .. "{wait 2}"
end

-- Adds the agent's talks to Cargo Tower's text (every language); returns
-- their string numbers.
local function add_texts()
  local first = nil
  for _, lang in ipairs(eu.LANGS) do
    local _, n = text.strings(eu.TEXT_TALKS_05 + eu.LANG_OFFSET[lang])
    if first == nil then first = n end
    assert(n == first, "Cargo Tower's talks differ in length between languages")
  end
  local entries = {}
  for k, key in ipairs({ "ask", "give", "after" }) do
    local by_lang = {}
    for _, lang in ipairs(eu.LANGS) do by_lang[lang] = talk_text(lang, TALKS[key][lang]) end
    text.set_all(eu.TEXT_TALKS_05, first + k - 1, by_lang)
    entries[key] = first + k - 1
  end
  return entries
end

-- Builds the agent into the FIELDSTG overlay `ovl` (overlay.lua).
function M.build(ovl)
  local entries = add_texts()
  local b = ovl.ext
  local SP = codes.SPECIAL
  -- When he is there: after the first battle (as the lift panel), never at
  -- an auction's story point. At STORY_AGUMON_SUITS the game has a character
  -- of its own on his spot (0x33), and he stands a step aside.
  local present = { codes.SPECIAL_STORY_SINCE_GENJI_BEATEN, 1 }
  for _, p in ipairs(codes.AUCTION_PROGRESS) do
    present[#present + 1] = codes.PROGRESS(p)
    present[#present + 1] = 0
  end
  local aside = { table.unpack(present) }
  present[#present + 1] = codes.PROGRESS(M.ASIDE_PROGRESS)
  present[#present + 1] = 0
  present[#present + 1] = codes.END
  aside[#aside + 1] = codes.PROGRESS(M.ASIDE_PROGRESS)
  aside[#aside + 1] = 1
  aside[#aside + 1] = codes.END
  local cond_present = b:u16s(present)
  local cond_aside = b:u16s(aside)
  local cond_after = b:u16s({ SP(specials.VEMMON_UNLOCKED), 1, codes.END })
  local cond_give = b:u16s({ codes.ITEM(0, M.VEMMON_DDNA), 1, codes.END })
  local act_give = b:u16s({ SP(specials.UNLOCK_VEMMON), 1, codes.SPECIAL_SHOW_ITEM_GET_ICON, 1, codes.END })
  -- His talks, tried in order (FieldTalk: conditions, actions, entry).
  b:align(4)
  local talks = b:addr()
  b:u32(cond_after):u32(0):u32(entries.after)
  b:u32(cond_give):u32(act_give):u32(entries.give)
  b:u32(0):u32(0):u32(entries.ask)
  b:u32(0):u32(0):u32(0)
  -- FieldActorEntry: conditions, talks, id, image, x, y, dir
  local actor = b:addr()
  b:u32(cond_present):u32(talks):u16(M.CHARACTER):u16(M.IMAGE):u16(M.X):u16(M.Y):u16(M.DIR)
  b:align(4)
  local actor_aside = b:addr()
  b:u32(cond_aside):u32(talks):u16(M.CHARACTER):u16(M.IMAGE):u16(M.ASIDE_X):u16(M.ASIDE_Y):u16(M.DIR)
  b:align(4)
  -- The field's characters: the game's, then the agent.
  local list = b:addr()
  for i = 0, eu.FIELDSTG_ACTOR_COUNT - 1 do
    b:u32(ovl:read32(eu.FIELDSTG_actorList + 4 * i))
  end
  assert(ovl:read32(eu.FIELDSTG_actorList + 4 * eu.FIELDSTG_ACTOR_COUNT) == 0, "Cargo Tower's character list isn't the one this mod knows")
  b:u32(actor):u32(actor_aside):u32(0)
  -- FIELDSTG_setupField: FIELDSTG_state.actors = the new list.
  local v0 = mips.R.v0
  ovl:patch32(eu.FIELDSTG_SETUP_ACTORS_LUI, mips.lui(v0, mips.hi(eu.FIELDSTG_actorList)), mips.lui(v0, mips.hi(list)))
  ovl:patch32(eu.FIELDSTG_SETUP_ACTORS_ADDIU, mips.addiu(v0, v0, mips.lo(eu.FIELDSTG_actorList)), mips.addiu(v0, v0, mips.lo(list)))
end

return M
