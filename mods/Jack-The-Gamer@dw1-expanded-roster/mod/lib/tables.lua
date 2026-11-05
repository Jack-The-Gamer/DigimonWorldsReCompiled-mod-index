-- The game's per-Digimon tables (Digimon World, USA: SLUS-01032; addresses
-- and names from the dw_decomp decompilation), moved with room for CAPACITY
-- types, and the mod's other data in the game's RAM.
--
-- The game sizes them for its own 180 types (66 for the ones that can be a
-- partner). They move when the game sets its heap up (InitHeap3, the first
-- thing main() does, before anything reads these tables), and no longer to
-- the bottom of the heap: wild Digimon's models share the heap (DW1 Wild
-- Digimon Randomizer fits fewer when it's smaller). Instead:
--  1. the stack's reserve: initializeHeap ends the heap 64 KiB below the
--     stack top (0x801FFFF0, the linker's _stack_size), and the stack never
--     went deeper than ~4.3 KiB (a probe marking the reserve at InitHeap3:
--     boot, loading a save, fields, menus, the chart, evolutions, battles
--     with finishers); its top STACK_KEEP bytes stay the stack's;
--  2. the old tables themselves, unread once the code is patched, except
--     ORIGINAL_DIGIMON_TYPES (DW1 Wild Digimon Randomizer reads it there);
--  3. only what doesn't fit: the bottom of the heap, whose start is raised
--     past it.

local M = {}

M.CAPACITY = 260            -- Digimon types after the move (the game has 180)
M.INIT_HEAP3 = 0x80090F24   -- InitHeap3(start, size), called by initializeHeap()
M.HEAP_START = 0x801BFB70   -- what initializeHeap() passes (from _end)
M.HEAP_END = 0x801EFF00     -- where it ends: 64 KiB below the stack top
M.STACK_TOP = 0x801FFFF0
M.STACK_KEEP = 0x4000       -- the stack's own (16 KiB, ~4x the deepest seen)

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
for _, d in ipairs(DEFS) do
  local t = { name = d[1], old = d[2], size = d[3] * d[4], entry = d[4], count = d[5], new_size = d[5] * d[4], fill = d[6] or 0, techniques = d[7] }
  M.list[#M.list + 1] = t
  M.by_name[t.name] = t
end
-- The mod's other data:
-- the new Digimon's strings (4-letter file names: the game keeps pointers to
-- them in PTR_DIGIMON_FILE_NAMES);
M.STRINGS_SIZE = 16 * (M.CAPACITY - 180)
-- names of the new finishers (MOVE_NAMES points here), 24 bytes each;
M.MOVE_STRING_BYTES = 24
M.NEW_FINISHERS = M.FINISHER_END - M.FIRST_NEW_FINISHER
-- a few bytes for text the mod draws (lib/chart.lua: "Mega");
-- the evolution scene's shard buffer (lib/limits.lua: EVL_setScratchTop):
-- 6 bytes per vertex and per polygon of the Digimon evolving away (the
-- game's, EVL_D_80066274, 0x153C bytes, holds 906; the backports need up to
-- ~1400). The chart also stages its icons here (no evolution while it's
-- open; lib/chart.lua);
M.EVL_SCRATCH_SIZE = 0x3000
-- translated effect start points (lib/limits.lua: borrow), 12 bytes each:
-- {type, bone, x, y, z} and -1.
M.BORROW_SLOTS = 32
local extra = {
  { "STRINGS", M.STRINGS_SIZE }, { "MOVE_STRINGS", M.MOVE_STRING_BYTES * M.NEW_FINISHERS },
  { "TEXT", 16 }, { "EVL_SCRATCH", M.EVL_SCRATCH_SIZE }, { "BORROW", 12 * M.BORROW_SLOTS },
}

-- Placing them, biggest first, each in the first free place it fits (8-byte
-- aligned): the stack's reserve, then the old tables (adjacent ones joined),
-- then the bottom of the heap.
local free = { { M.HEAP_END, M.STACK_TOP - M.STACK_KEEP } }
do
  local olds = {}
  for _, t in ipairs(M.list) do
    if t.name ~= "ORIGINAL_DIGIMON_TYPES" then olds[#olds + 1] = { t.old, t.old + t.size } end
  end
  table.sort(olds, function(a, b) return a[1] < b[1] end)
  for _, r in ipairs(olds) do
    local last = free[#free]
    if #free > 1 and last[2] == r[1] then last[2] = r[2] else free[#free + 1] = { r[1], r[2] } end
  end
end
local items = {}
for _, t in ipairs(M.list) do items[#items + 1] = { t = t, size = t.new_size } end
for _, e in ipairs(extra) do items[#items + 1] = { name = e[1], size = e[2] } end
table.sort(items, function(a, b) return a.size > b.size end)
local heap_at = M.HEAP_START
M.placed = {}                 -- {address, size, name}, for the log
for _, it in ipairs(items) do
  local addr
  for _, r in ipairs(free) do
    local a = (r[1] + 7) & ~7
    if a + it.size <= r[2] then addr = a; r[1] = a + it.size; break end
  end
  if not addr then addr = (heap_at + 7) & ~7; heap_at = addr + it.size end
  if it.t then it.t.new = addr else M[it.name] = addr end
  M.placed[#M.placed + 1] = { addr, it.size, it.t and it.t.name or it.name }
end
M.END = (heap_at + 15) & ~15  -- the heap starts here (HEAP_START when nothing went there)
M.BYTES = M.END - M.HEAP_START -- heap bytes taken

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
-- start the heap after whatever went there. Every old table is read before
-- anything is written (new places can be old ones). `wipe` also blanks the
-- old copies first, so a reference the patching missed shows at once
-- instead of reading stale data. `setup(ctx)` then fills in the new
-- Digimon's entries. Should InitHeap3 run again with the old places already
-- reused (the exe not reloaded), the tables are left as they are.
local originals = nil
function M.install(wipe, setup)
  dwrc.on_exec(M.INIT_HEAP3, function(ctx)
    local start, size = ctx:reg("a0"), ctx:reg("a1")
    if start > M.HEAP_START or start + size < M.END + 0x10000 or start + size ~= M.HEAP_END then
      dwrc.log(string.format("the heap is at %08X (+%X), not where the mod expects it: the moved tables are not set up", start, size))
      return false
    end
    local olds = {}
    for i, t in ipairs(M.list) do olds[i] = ctx:read_bytes(t.old, t.size) end
    local all = table.concat(olds)
    if originals and all ~= originals then
      dwrc.log("InitHeap3 again with the tables in place: left as they are")
      ctx:set_reg("a0", M.END)
      ctx:set_reg("a1", size - (M.END - start))
      return false
    end
    originals = all
    if wipe then
      for _, t in ipairs(M.list) do ctx:write_bytes(t.old, string.rep("\0", t.size)) end
    end
    for i, t in ipairs(M.list) do
      ctx:write_bytes(t.new, olds[i] .. string.rep(string.char(t.fill), t.new_size - t.size))
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
