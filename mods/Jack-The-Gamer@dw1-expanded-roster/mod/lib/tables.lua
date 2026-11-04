-- The game's per-Digimon tables (Digimon World, USA: SLUS-01032; addresses
-- and names from the dw_decomp decompilation), moved to the bottom of the
-- heap with room for CAPACITY types.
--
-- The game sizes them for its own 180 types (66 for the ones that can be a
-- partner). The heap (0x801BFB70..0x801EFF00) is filled from the top, and
-- its bottom 136 KiB were never touched through loading a save, a field and
-- a battle, so the mod raises the heap's start past the moved tables when
-- the game sets the heap up (InitHeap3, the first thing main() does, before
-- anything reads these tables) and copies them there.

local M = {}

M.CAPACITY = 200            -- Digimon types after the move (the game has 180)
M.INIT_HEAP3 = 0x80090F24   -- InitHeap3(start, size), called by initializeHeap()
M.HEAP_START = 0x801BFB70   -- what initializeHeap() passes (from _end)

-- name, address, entries, entry size, entries after the move, fill byte for new entries
local DEFS = {
  { "DIGIMON_DATA",           0x8012CEB4, 180, 0x34, M.CAPACITY },
  { "DIGIMON_SKELETONS",      0x8011CE60, 180, 4,    M.CAPACITY },
  { "PTR_DIGIMON_FILE_NAMES", 0x8011D19C, 180, 4,    M.CAPACITY },
  { "ORIGINAL_DIGIMON_TYPES", 0x8012A84C, 180, 2,    M.CAPACITY },
  { "TOURNAMENT_SCHEDULE",    0x80130198, 180, 1,    M.CAPACITY },
  { "DIGIMON_VBALL_SOUND_ID", 0x80127F40, 180, 1,    M.CAPACITY },
  { "RAISE_DATA",             0x801225BC, 66,  0x1C, M.CAPACITY },
  { "ITEM_TAKE_DISTANCE",     0x80122D24, 66,  1,    M.CAPACITY },
  { "DIGIMON_VLALL_SOUND_ID", 0x80127EFC, 66,  1,    M.CAPACITY },
  { "CARD_DATA",              0x8012FFD8, 66,  4,    M.CAPACITY },
  { "EVOLUTION_REQS",         0x8012ABEC, 63,  0x1C, M.CAPACITY },
  { "EVOLUTION_STATS_GAINS",  0x8012B2D0, 66,  0xE,  M.CAPACITY },
  -- indexed by type - 1; -1 (0xFF) means "no Digimon"
  { "EVOLUTION_PATHS",        0x8012B66C, 62,  11,   M.CAPACITY - 1, 0xFF },
  -- by technique, not by type (`techniques`): names (char *) and Move
  -- {power, mpCost, ...}, room for MOVES
  { "MOVE_NAMES",             0x80126054, 122, 4,    0xF9, nil, true },
  { "MOVE_DATA",              0x8012623C, 122, 0x10, 0xF9, nil, true },
}

-- Techniques: 0x00..0x39 learnable, 0x3A..0x70 finishers, 0x71..0x78 the
-- In-Training Bubbles, 0x79 the generic attack; a Digimon names them by
-- number (DigimonPara.moves[], u8, 0xFF none). A finisher is any number
-- from 0x3A below a bound (0x71), checked by number in 32 places, so the
-- bound goes up to FINISHER_END (lib/limits.lua) and the Bubbles and the
-- generic attack move past it: new finishers get 0x71..FINISHER_END - 1.
M.GAME_MOVES = 122
M.FINISHER_END = 0xF0
M.FIRST_NEW_FINISHER = 0x71
M.MOVED_MOVES = {}            -- old number -> new (0x71..0x79 -> 0xF0..0xF8)
for n = 0x71, 0x79 do M.MOVED_MOVES[n] = n - 0x71 + M.FINISHER_END end
M.MOVES = M.FINISHER_END + 9  -- 0xF9 techniques

-- The moved tables: name -> { old, size (old bytes), new, new_size, fill }.
M.list = {}
M.by_name = {}
local at = M.HEAP_START
for _, d in ipairs(DEFS) do
  local t = { name = d[1], old = d[2], size = d[3] * d[4], entry = d[4], count = d[5], new = at, new_size = d[5] * d[4], fill = d[6] or 0, techniques = d[7] }
  M.list[#M.list + 1] = t
  M.by_name[t.name] = t
  at = (at + t.new_size + 7) & ~7
end
-- Room for the new Digimon's strings (4-letter file names: the game keeps
-- pointers to them in PTR_DIGIMON_FILE_NAMES).
M.STRINGS = at
M.STRINGS_SIZE = 16 * (M.CAPACITY - 180)
at = at + M.STRINGS_SIZE
-- Names of the new finishers (MOVE_NAMES points here), 24 bytes each.
M.MOVE_STRING_BYTES = 24
M.MOVE_STRINGS = at
M.NEW_FINISHERS = M.FINISHER_END - M.FIRST_NEW_FINISHER
at = at + M.MOVE_STRING_BYTES * M.NEW_FINISHERS
-- Room for the new Digimon's chart icons (lib/icon.lua), uploaded from here
-- to VRAM when the chart opens: per type 256 bytes of pixels (two 16x16
-- 4-bit frames), a 32-byte CLUT, and the two RECTs for LoadImage.
M.ICONS = (at + 7) & ~7
M.ICON_BYTES = 256 + 32 + 8 + 8
at = M.ICONS + M.ICON_BYTES * (M.CAPACITY - 180)
M.END = (at + 15) & ~15 -- the heap starts here after the move
M.BYTES = M.END - M.HEAP_START

-- The address of entry `i` of table `name` (after the move). EVOLUTION_PATHS
-- is indexed by type - 1, like the game does.
function M.entry(name, i)
  local t = M.by_name[name]
  if name == "EVOLUTION_PATHS" then i = i - 1 end
  assert(i >= 0 and i < t.count, name .. " has no entry " .. i)
  return t.new + i * t.entry
end

-- Copies entry `from` of every table to entry `to` (a new Digimon that
-- starts as a copy of an existing one).
function M.copy_entries(ctx, from, to)
  for _, t in ipairs(M.list) do
    local f, d = from, to
    if t.name == "EVOLUTION_PATHS" then f, d = f - 1, d - 1 end
    if not t.techniques and f >= 0 and f < t.count and d >= 0 and d < t.count then
      ctx:write_bytes(t.new + d * t.entry, ctx:read_bytes(t.new + f * t.entry, t.entry))
    end
  end
end

-- The new address of `addr`, or nil when it isn't in a moved table.
function M.move(addr)
  for _, t in ipairs(M.list) do
    if addr >= t.old and addr < t.old + t.size then return t.new + (addr - t.old) end
  end
  return nil
end

-- At InitHeap3: copy every table to its new place (new entries filled), then
-- start the heap after them. `wipe` also blanks the old copies, so a
-- reference the patching missed shows at once instead of reading stale data.
-- `setup(ctx)` then fills in the new Digimon's entries.
function M.install(wipe, setup)
  dwrc.on_exec(M.INIT_HEAP3, function(ctx)
    local start, size = ctx:reg("a0"), ctx:reg("a1")
    if start > M.HEAP_START or start + size < M.END + 0x10000 then
      dwrc.log(string.format("the heap is at %08X (+%X), not where the mod expects it: the moved tables are not set up", start, size))
      return false
    end
    for _, t in ipairs(M.list) do
      local data = ctx:read_bytes(t.old, t.size)
      ctx:write_bytes(t.new, data .. string.rep(string.char(t.fill), t.new_size - t.size))
      if wipe then ctx:write_bytes(t.old, string.rep("\0", t.size)) end
    end
    ctx:write_bytes(M.STRINGS, string.rep("\0", M.STRINGS_SIZE))
    ctx:write_bytes(M.MOVE_STRINGS, string.rep("\0", M.MOVE_STRING_BYTES * M.NEW_FINISHERS))
    -- the Bubbles and the generic attack to their new numbers: their
    -- entries, and every Digimon's moves[] (DigimonPara +35, 16 bytes)
    local names, data = M.by_name.MOVE_NAMES, M.by_name.MOVE_DATA
    for old, new in pairs(M.MOVED_MOVES) do
      ctx:write32(names.new + 4 * new, ctx:read32(names.new + 4 * old))
      ctx:write_bytes(data.new + 16 * new, ctx:read_bytes(data.new + 16 * old, 16))
    end
    local dd = M.by_name.DIGIMON_DATA
    for ty = 0, 179 do
      local at = dd.new + ty * dd.entry + 35
      local moves = { string.byte(ctx:read_bytes(at, 16), 1, 16) }
      local changed = false
      for i, m in ipairs(moves) do
        if M.MOVED_MOVES[m] then moves[i], changed = M.MOVED_MOVES[m], true end
      end
      if changed then ctx:write_bytes(at, string.char(table.unpack(moves))) end
    end
    if setup then setup(ctx) end
    ctx:set_reg("a0", M.END)
    ctx:set_reg("a1", size - (M.END - start))
    return false
  end)
end

return M
