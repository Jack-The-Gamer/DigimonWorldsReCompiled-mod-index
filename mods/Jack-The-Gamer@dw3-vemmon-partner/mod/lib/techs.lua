-- The mod's techniques: TECHS (TechData, 18 bytes, technique n is
-- TECHS[n - 1]) moves to the mod's RAM with the game's 443 and the mod's
-- after them (74 lui/addiu pairs address it, sites_techs.lua: 22 at TECHS
-- itself or a technique, 52 at TECHS - 18, the base of `TECHS[id - 1]` as
-- the compiler folds it, nearly all in the battle code); their names
-- and descriptions are strings n of the technique texts (SKLNAM: the same
-- in every language; SKLINF: by language).
--
-- The Vemmon line's official techniques, fitted to the game's: a form has
-- a basic attack (physical, script 5), techniques it learns at levels
-- (scripts 6 physical, 9 magic, 13 three hits, from its fighter's generic
-- scripts) and a signature (script 11, its own). Names fit the game's
-- 16-letter technique windows ("Triple Cannon Shot" is Triple Cannon,
-- "Long-Range Buster Cannon" Buster Cannon). The line is Machine-aligned
-- (element 7), with Dark (8) and Thunder (6) as its other strengths; stages
-- and effects as the game's Machine (48-49), Thunder (45-46) and Dark (51-52)
-- techniques.

local disc = require("lib.disc")
local eu = require("lib.eu")
local text = require("lib.text")

local M = {}

M.TECHS = 0x80042BDC
M.COUNT = 443
M.SIZE = 18
M.FIRST_NEW = 444

M.TEXT_NAMES = 162          -- MSSKLNAM (the Japanese copy; + LANG_OFFSET)
M.TEXT_INFO = 155           -- MSSKLINF

-- { name, { mp, power, icon (2 physical, 3 magic), kind, accuracy, element,
--   elementPower, family, effect, effectChance, effectPower, scriptStage,
--   scriptEffect, scriptSound, script, hitCount }, descriptions }
local function t(name, data, info) return { name = name, data = data, info = info } end
local BASIC = "a"           -- the game's basic attacks' name and description

M.LIST = {
  -- 444-446: the forms' basic attacks (as the game's forms': physical, script 5)
  t(BASIC, { 0, 130, 2, 2, 110, 1, 1, 1, 1, 1, 1, 0, 2, 57, 5, 1 }),
  t(BASIC, { 0, 200, 2, 2, 110, 1, 1, 1, 1, 1, 1, 0, 2, 57, 5, 1 }),
  t(BASIC, { 0, 400, 2, 2, 110, 1, 1, 1, 1, 1, 1, 0, 2, 57, 5, 1 }),
  -- 447: Vemmon's signature (a Rookie's: mp 20-30, power 75-120)
  t("Messer Claw", { 22, 110, 2, 2, 127, 7, 32, 1, 11, 1, 60, 0, 2, 62, 11, 1 }, {
    en = "Pierce with its sharp claws.", fr = "Transperce de ses griffes.", it = "Trafigge con gli artigli.",
    de = "Durchbohrt mit den Krallen.", es = "Atraviesa con sus garras." }),
  -- 448-450: the forms' signatures
  t("Ruin Laser", { 50, 280, 3, 2, 127, 7, 48, 1, 1, 1, 1, 0, 2, 63, 11, 1 }, {
    en = "Fire a laser from the arms.", fr = "Tire un laser des bras.", it = "Spara un laser dalle braccia.",
    de = "Laser aus den Armen.", es = "Dispara un láser de los brazos." }),
  t("Juggernaut Blast", { 100, 520, 3, 2, 127, 7, 56, 1, 1, 1, 1, 0, 2, 64, 11, 1 }, {
    en = "Energy beam from chest cannon.", fr = "Rayon du canon du torse.", it = "Raggio dal cannone del petto.",
    de = "Energiestrahl der Brustkanone.", es = "Rayo del cañón del pecho." }),
  t("Ragnarok Cannon", { 280, 850, 3, 2, 127, 7, 72, 1, 1, 1, 1, 0, 2, 64, 11, 1 }, {
    en = "Huge beam from chest cannon.", fr = "Énorme rayon du torse.", it = "Enorme raggio dal petto.",
    de = "Riesiger Strahl der Brust.", es = "Rayo enorme del pecho." }),
  -- 451: Fusionize (all three forms): drains HP (effect 8, in 128ths of the damage)
  t("Fusionize", { 60, 200, 3, 2, 110, 8, 32, 1, 8, 128, 64, 51, 26, 50, 9, 1 }, {
    en = "Feed on the enemy's data.", fr = "Se nourrit des données adv.", it = "Si nutre dei dati nemici.",
    de = "Zehrt von Feindesdaten.", es = "Se alimenta de datos rivales." }),
  -- 452: Snatchmon
  t("Tooth Spear", { 24, 140, 2, 2, 110, 7, 32, 1, 1, 1, 1, 48, 17, 62, 6, 1 }, {
    en = "Tear with the tail's tip.", fr = "Déchire du bout de la queue.", it = "Lacera con la punta della coda.",
    de = "Zerreißt mit der Schwanzspitze.", es = "Desgarra con la cola." }),
  -- 453-454: Destromon
  t("Triple Cannon", { 70, 180, 3, 2, 100, 7, 40, 1, 9, 1, 1, 48, 65, 64, 13, 3 }, {
    en = "Fire the turrets on its arms.", fr = "Tire avec ses tourelles.", it = "Spara con le torrette.",
    de = "Feuert die Armgeschütze ab.", es = "Dispara sus torretas." }),
  t("Buster Cannon", { 80, 460, 3, 2, 110, 7, 40, 1, 1, 1, 1, 48, 65, 64, 9, 1 }, {
    en = "Fire the cannon on its back.", fr = "Tire le canon de son dos.", it = "Spara il cannone sul dorso.",
    de = "Feuert die Rückenkanone ab.", es = "Dispara el cañón de su lomo." }),
  -- 455-458: Galacticmon
  t("Gimlet Gun", { 70, 420, 2, 2, 110, 7, 64, 1, 1, 1, 1, 49, 17, 62, 6, 1 }, {
    en = "Pierce the foe with its tail.", fr = "Transperce de sa queue.", it = "Trafigge con la coda.",
    de = "Durchbohrt mit dem Schwanz.", es = "Atraviesa con la cola." }),
  t("Space Laser", { 160, 680, 3, 2, 110, 6, 72, 1, 1, 1, 1, 46, 15, 46, 9, 1 }, {
    en = "Huge laser from its head.", fr = "Laser géant de la tête.", it = "Laser enorme dalla testa.",
    de = "Riesiger Laser aus dem Kopf.", es = "Láser enorme de la cabeza." }),
  t("Shuttle Scissors", { 100, 520, 2, 2, 110, 7, 48, 1, 11, 1, 60, 49, 17, 62, 6, 1 }, {
    en = "Seize and sever with the arm.", fr = "Saisit et tranche du bras.", it = "Afferra e trancia col braccio.",
    de = "Packt und zerschneidet.", es = "Atrapa y corta con el brazo." }),
  t("Satellite Buster", { 190, 360, 3, 2, 100, 7, 72, 1, 9, 1, 1, 49, 65, 64, 13, 3 }, {
    en = "Shoulder guns hit many times.", fr = "Tirs multiples des épaules.", it = "Colpi multipli dalle spalle.",
    de = "Schulterkanonen, viele Treffer.", es = "Disparos de los hombros." }),
}

-- Technique ids by name (the basic attacks by their form)
M.ID = {}
for i, e in ipairs(M.LIST) do
  if e.name ~= BASIC then M.ID[e.name] = M.FIRST_NEW + i - 1 end
end
M.BASIC_SNATCHMON, M.BASIC_DESTROMON, M.BASIC_GALACTICMON = 444, 445, 446

-- The table the mod's RAM holds (tables.lua writes it), and the names.
function M.build()
  local game = disc.exe_read(M.TECHS, M.COUNT * M.SIZE)
  local new = {}
  for _, e in ipairs(M.LIST) do new[#new + 1] = string.pack("<HHBBBBBBBBBBBBBB", table.unpack(e.data)) end
  M.data = game .. table.concat(new)

  for lang, off in pairs(eu.LANG_OFFSET) do
    if lang ~= "ja" then
      for i, e in ipairs(M.LIST) do
        local id = M.FIRST_NEW + i - 1
        text.set(M.TEXT_NAMES + off, id, text.encode(e.name))
        local info = e.info and (e.info[lang] or e.info.en) or BASIC
        text.set(M.TEXT_INFO + off, id, text.encode(info))
      end
    end
  end
end

return M
