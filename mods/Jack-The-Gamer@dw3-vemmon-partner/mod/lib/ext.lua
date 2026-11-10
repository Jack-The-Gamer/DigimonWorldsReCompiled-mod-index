-- The mod's RAM.
--
-- At the heap's end, 0x801FCC00-0x801FEFFF (9 KiB, freed by ending the heap
-- there, main.lua):
--   0x0000  header: MAGIC once the game data area is set up, STAMP of the
--           tables (tables.lua; rewritten when it differs: a save state of
--           another build)
--   0x0010  TECHS, the game's techniques and the mod's (techs.lua)
-- In the game's old DIGIMON_DATA (0x8003EF5C, 4840 bytes, unused once it
-- moves, tables.lua):
--   0x0000  game data, saved in the memory card's spare room (save.lua):
--           Vemmon's Partner record, the extra entries
--   0x0700  the save's staging buffer
-- The other tables and routines sit in the game's old TECHS (tables.lua).
-- Save states keep all of it as RAM.

local M = {}

M.BASE = 0x801FCC00
M.END = 0x801FF000

M.MAGIC = M.BASE                -- MAGIC_VALUE once the game data area is set up
M.MAGIC_VALUE = 0x314E4D56      -- "VMN1"
M.STAMP = M.BASE + 4            -- the tables' build (tables.lua)
M.TECHS = M.BASE + 0x10

-- Game data (cleared by a new game, filled by a load)
M.DATA = 0x8003EF5C
M.VEMMON = M.DATA               -- Vemmon's Partner record, as GAME.partners' (0x3DC bytes)
M.PARTNER_SIZE = 0x3DC
M.EXTRA = M.DATA + 0x3E0        -- the extra entries: [9 partners][3] PartnerEntry (0x14 bytes)
M.EXTRA_COUNT = 3
M.ENTRY_SIZE = 0x14
M.DATA_END = M.DATA + 0x700

M.STAGING = M.DATA + 0x700      -- the save extension on its way to or from the card
M.STAGING_SIZE = 0x280
assert(M.STAGING + M.STAGING_SIZE <= 0x80040244)

M.VEMMON_ID = 17                -- Vemmon's partner number (the game's are 0-7; 17 puts its
                                -- burst gauge, BATTLE_SETUP.gauges[17], on unused padding)
M.PARTNER_COUNT = 8

-- Partner record fields (game_state.h, Partner)
M.P_UNLOCKED = 0x4              -- partner number + 3, 0 while locked
M.P_INFO = 0xC                  -- PartnerStats
M.P_ENTRIES = 0x5C              -- info.entries[44]
M.ENTRY_COUNT = 44

-- The game's partner records: GAME.partners[8], then Vemmon's here.
M.GAME_PARTNERS = 0x80049490

function M.record(partner)
  if partner == M.VEMMON_ID then return M.VEMMON end
  return M.GAME_PARTNERS + partner * M.PARTNER_SIZE
end

-- The extra entries' row of a partner (0-7, Vemmon 8).
function M.extra(partner, k)
  local row = partner == M.VEMMON_ID and 8 or partner
  return M.EXTRA + (row * M.EXTRA_COUNT + k) * M.ENTRY_SIZE
end

function M.is_partner(p)
  return (p >= 0 and p < M.PARTNER_COUNT) or p == M.VEMMON_ID
end

function M.vemmon_unlocked(ctx)
  return ctx:read32(M.VEMMON + M.P_UNLOCKED) ~= 0
end

function M.unlock_vemmon(ctx)
  ctx:write32(M.VEMMON + M.P_UNLOCKED, M.VEMMON_ID + 3)
end

return M
