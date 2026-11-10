-- The game's files, as the mod changes them while it loads: the executable
-- (its code and its file table) and any file by number. Changes go to the
-- virtual disc (dwrc.disc, Re:Compiled 1.5); the player's image is never
-- touched, and nothing of the game's is shipped with the mod.
--
-- The game reads every file by number through the executable's file table:
-- the first sector and the sector count of each (FILE_SECTORS,
-- FILE_SECTOR_COUNTS, 2382 files). A file that grows past its sectors is
-- appended after the end of the disc and its table entry rewritten. New
-- files get the numbers from 2382 on: four small functions read the table
-- (fileExists, getFileSectorCount, getFileSector, getFilePos), and the mod
-- answers them for those numbers (install_hooks).

local bin = require("lib.bin")
local eu = require("lib.eu")

local M = {}

local exe = nil         -- the executable, header included
local exe_dirty = false
local extra = {}        -- number -> { lba, sectors } for the new files
local next_file = eu.FILE_COUNT

local function exe_off(addr) return addr - eu.EXE_LOAD + 0x800 end

function M.exe()
  if not exe then
    exe = dwrc.disc.read(eu.EXE_LBA, (eu.EXE_SIZE + 2047) // 2048):sub(1, eu.EXE_SIZE)
    assert(exe:sub(1, 8) == "PS-X EXE", "the executable isn't where Digimon World 2003 (Europe) has it")
  end
  return exe
end

function M.exe_read32(addr) return bin.u32(M.exe(), exe_off(addr)) end
function M.exe_read(addr, n) return M.exe():sub(exe_off(addr) + 1, exe_off(addr) + n) end

-- Writes a word of the executable, after checking that it holds `expect`.
function M.exe_patch32(addr, expect, value)
  local v = M.exe_read32(addr)
  if expect ~= nil and v ~= expect then
    error(string.format("unexpected code at %08x: %08x, not %08x (is this Digimon World 2003, Europe?)", addr, v, expect))
  end
  exe = bin.put32(exe, exe_off(addr), value)
  exe_dirty = true
end

function M.exe_write(addr, data)
  M.exe()
  exe = bin.put(exe, exe_off(addr), data)
  exe_dirty = true
end

-- A file's first sector and sector count.
function M.file(n)
  if n >= eu.FILE_COUNT then
    local e = assert(extra[n], "no file " .. n)
    return e.lba, e.sectors
  end
  local e = M.exe()
  return bin.s32(e, exe_off(eu.FILE_SECTORS) + 4 * n), bin.u16(e, exe_off(eu.FILE_SECTOR_COUNTS) + 2 * n)
end

function M.set_file(n, lba, sectors)
  if n >= eu.FILE_COUNT then
    extra[n] = { lba = lba, sectors = sectors }
    return
  end
  M.exe()
  exe = bin.put32(exe, exe_off(eu.FILE_SECTORS) + 4 * n, lba)
  exe = bin.put16(exe, exe_off(eu.FILE_SECTOR_COUNTS) + 2 * n, sectors)
  exe_dirty = true
end

-- A file's bytes, whole sectors.
function M.read_file(n)
  local lba, count = M.file(n)
  return dwrc.disc.read(lba, count)
end

-- Gives file `n` new contents: in its place if they fit, else after the end
-- of the disc.
function M.replace_file(n, data)
  local lba, count = M.file(n)
  local need = math.max(1, (#data + 2047) // 2048)
  if need <= count then
    dwrc.disc.write(lba, data)
  else
    M.set_file(n, dwrc.disc.append(data), need)
  end
end

-- Adds a file; returns its number.
function M.add_file(data)
  local n = next_file
  next_file = next_file + 1
  M.set_file(n, dwrc.disc.append(data), math.max(1, (#data + 2047) // 2048))
  return n
end

-- Writes the changed executable to the virtual disc (once, at the end).
function M.commit()
  if exe_dirty then
    dwrc.disc.write(eu.EXE_LBA, exe)
    exe_dirty = false
  end
end

-- The file table's readers answer for the new files' numbers.
function M.install_hooks()
  if next(extra) == nil then return end
  local first = eu.FILE_COUNT
  dwrc.on_exec(eu.fileExists, function(ctx)
    local f = ctx:reg("a0")
    if f < first then return false end
    return ctx:ret(extra[f] and 1 or 0)
  end)
  dwrc.on_exec(eu.getFileSectorCount, function(ctx)
    local f = ctx:reg("a0")
    if f < first then return false end
    return ctx:ret(extra[f] and extra[f].sectors or 0)
  end)
  dwrc.on_exec(eu.getFileSector, function(ctx)
    local f = ctx:reg("a0")
    if f < first then return false end
    return ctx:ret(extra[f] and extra[f].lba or 0)
  end)
  -- getFilePos(file, offset, pos) is CdIntToPos(sector + offset, pos).
  dwrc.on_exec(eu.getFilePos, function(ctx)
    local f = ctx:reg("a0")
    if f < first then return false end
    ctx:set_reg("a0", (extra[f] and extra[f].lba or 0) + ctx:reg("a1"))
    ctx:set_reg("a1", ctx:reg("a2"))
    ctx:set_pc(eu.CdIntToPos)
    return true
  end)
end

return M
