-- Addresses in Digimon World 2003 (Europe, SLES-03936), by the names of the
-- ReGame-Labs/dw3_decomp decompilation (config/eu/symbols*.txt). The mod
-- checks the code it changes before changing it (see disc.lua and hooks).

local M = {}

M.EXE_LBA = 24                 -- SLES_039.36 on the disc
M.EXE_SIZE = 923648
M.EXE_LOAD = 0x80010000        -- the PS-X EXE header is 0x800 bytes before it

-- The executable's file table: the first sector and the sector count of
-- each file, by number (s32[2382], u16[2382]).
M.FILE_SECTORS = 0x80044F6C
M.FILE_SECTOR_COUNTS = 0x800474A4
M.FILE_COUNT = 2382
-- The four functions that read it (file_table.c): fileExists(file),
-- getFileSectorCount(file), getFileSector(file), getFilePos(file, offset, pos).
M.fileExists = 0x800141E4
M.getFileSectorCount = 0x80014200
M.getFileSector = 0x8001421C
M.getFilePos = 0x80014238
M.CdIntToPos = 0x8002E10C

-- initHeap: HEAP_END (0x801FF000) and its end block (0x801FEFF4) as the
-- immediates of two `ori`s.
M.initHeap = 0x80017C5C
M.HEAP_END_ORI = 0x80017C60
M.HEAP_LAST_ORI = 0x80017C68

M.GAME = 0x80048D34            -- GameState
M.GAME_PARTY = M.GAME + 0x70   -- s32 party[3]: partner numbers, -1 for none
M.GAME_ITEMS = M.GAME + 0x7C   -- s8 counts by item
M.GAME_PROGRESS = M.GAME + 0x263C
M.GAME_MODE = M.GAME + 0x26C4
M.GAME_NEXT_MODE = M.GAME + 0x26C8
M.MODE_BATTLE = 0x600
M.BATTLE_SETUP = 0x80042B1C
M.BATTLE_RESULT = 0x80042B84

-- Conditions and actions (game/events.c)
M.checkPartner = 0x80015754            -- (op, partner)
M.checkSpecialCondition = 0x80015D90   -- (id, expected)
M.checkCondition = 0x800163B0
M.applyAction = 0x800165AC

-- The overlays: the mode's at OVERLAY_VRAM, and a stage or WFIGHTMN at
-- STAGE_VRAM; the heap starts at 0x800AB800.
M.OVERLAY_VRAM = 0x80082CB0
M.STAGE_VRAM = 0x800A5DE0
M.HEAP_START = 0x800AB800

-- FIELDSTG (file 358): the field, and Asuka City's Cargo Tower (mode 528).
M.FILE_FIELDSTG = 358
M.FIELDSTG_setupField = 0x80091E60
M.FIELDSTG_SETUP_ACTORS_LUI = 0x80091EF4   -- lui v0, %hi(FIELDSTG_actorList)
M.FIELDSTG_SETUP_ACTORS_ADDIU = 0x80091EF8 -- addiu v0, v0, %lo(FIELDSTG_actorList)
M.FIELDSTG_actorList = 0x800994F4          -- FieldActorEntry *[116], NULL-ended
M.FIELDSTG_ACTOR_COUNT = 115
M.FIELDSTG_state = 0x80099D80
M.TEXT_TALKS_05 = 232                      -- Cargo Tower's talks (TALK05)

-- The other overlays the mod changes, and the ones of them that load at
-- STAGE_VRAM (files.lua).
M.FILE_FIGHTSTG = 359          -- battles
M.FILE_STFGTREP = 465          -- the battle report
M.FILE_STGDGLAB = 492          -- the Digimon Lab
M.FILE_STGTRAIN = 498          -- the gyms
M.FILE_STITSHOP = 517          -- the shops
M.FILE_STSTATUS = 519          -- the field menu
M.FILE_WFIGHTMN = 520          -- normal battles
M.STAGE_FILES = { [520] = true, [521] = true, [1619] = true, [1620] = true }

-- DIGIMON_DATA: DigimonData[55] (0x58 bytes): the 8 partners' Rookies, the 44
-- forms, the 3 DNA forms. findDigimon(id) searches the first 52; its miss
-- path is `jr ra; addiu v0, zero, -1`.
M.DIGIMON_DATA = 0x8003EF5C
M.DIGIMON_COUNT = 55
M.DIGIMON_SIZE = 0x58
M.findDigimon = 0x800134AC
M.FIND_DIGIMON_MISS = 0x800134D8

-- New games: newGame (at start-up: zeroes GAME's saved part, then
-- initNewGameData), initNewGameData (the partners' names and stats).
M.newGame = 0x80016A94
M.initNewGameData = 0x80016BAC

-- partner.c, reached through GAME.funcs
M.findPartnerEntry = 0x8001764C
M.getPartnerSlots = 0x800176AC
M.setPartnerSlots = 0x800177D0
M.listPartnerEntries = 0x80017898
M.addPartnerEntry = 0x80017924
M.getPartnerEntry = 0x80017A1C
M.setPartnerEntry = 0x80017AB4
M.getPartnerStats = 0x80017B4C

-- The memory card (memcard.c): readSave/writeSave(port, buf, size, section)
-- run one step a call (0 while running, 1 done, else error + 1); sections
-- 2-4 are the slots' data, 0 the header (writeSave takes its offset from
-- section >> 8; readSave's default case is patched to do the same).
M.readSave = 0x80014D04
M.writeSave = 0x80014FC4
M.READ_SAVE_DEFAULT = 0x80014DC8       -- lui v0, 0x8005; j 80014e70; sw zero, MEMCARD.offset
M.SAVE_SECTION_DATA = 2
M.GAME_SAVE_SIZE = 0x26C4
M.SAVE_DATA_SIZE = 0x2700              -- a slot's section: the save, then 0x3C bytes the game leaves alone
M.SAVE_FILE_END = 0x7800               -- the save file (4 blocks) uses 0x7800 of its 0x8000 bytes

-- Text files: the European disc has each text file once per language, in
-- this order from the Japanese copy (the number the USA version uses is one
-- more than the Japanese one).
M.LANGS = { "en", "fr", "it", "de", "es" }
M.LANG_OFFSET = { ja = 0, us = 1, en = 2, fr = 3, it = 4, de = 5, es = 6 }
-- The first (Japanese) file of each text the mod changes.
M.TEXT_DIGIMON_NAMES = 78      -- ..DIGNAM
M.TEXT_ITEM_INFO = 99          -- ..ITMINF
M.TEXT_ITEM_NAMES = 106        -- ..ITMNAM

return M
