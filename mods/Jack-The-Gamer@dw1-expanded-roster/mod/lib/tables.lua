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
}

-- The moved tables: name -> { old, size (old bytes), new, new_size, fill }.
M.list = {}
M.by_name = {}
local at = M.HEAP_START
for _, d in ipairs(DEFS) do
  local t = { name = d[1], old = d[2], size = d[3] * d[4], entry = d[4], count = d[5], new = at, new_size = d[5] * d[4], fill = d[6] or 0 }
  M.list[#M.list + 1] = t
  M.by_name[t.name] = t
  at = (at + t.new_size + 7) & ~7
end
-- Room for the new Digimon's strings (4-letter file names: the game keeps
-- pointers to them in PTR_DIGIMON_FILE_NAMES).
M.STRINGS = at
M.STRINGS_SIZE = 16 * (M.CAPACITY - 180)
at = at + M.STRINGS_SIZE
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
    if f >= 0 and f < t.count and d >= 0 and d < t.count then
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
    if setup then setup(ctx) end
    ctx:set_reg("a0", M.END)
    ctx:set_reg("a1", size - (M.END - start))
    return false
  end)
end

return M
