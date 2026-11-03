-- New files for the game. Digimon World finds a file by its name alone:
-- lookupFileTable (0x800A31F8) takes the part of the path after the last
-- '\' and searches the executable's FILE_OFFSET_TABLE {sector, size, name}.
-- readFile, readFileSectors, lookupFileSize and the file queue's
-- addFileReadRequestSection/Lookup go through it, so answering it for new
-- names is enough: the data is appended past the end of the virtual disc
-- while the mod loads, and the hook fills in the file's position and size.
-- A name the game already has (ALLTIM.TIM) is answered too, which moves
-- that file. One exception: addFileReadRequestPath (loadMMDAsync, the
-- evolution's next model) leaves the size at -1 and the queue then looks the
-- full path up in the disc's ISO directory with CdSearchFile, retrying
-- forever when it isn't there; for the mod's files it is sent to
-- addFileReadRequestLookup, which takes the same arguments.

local M = {}

local LOOKUP_FILE_TABLE = 0x800A31F8           -- lookupFileTable(FileLookup *lookup, char *path) -> 1 found / 0
local ADD_FILE_READ_REQUEST_PATH = 0x800E3938   -- (path, buffer, isRunning, callback, param)
local ADD_FILE_READ_REQUEST_LOOKUP = 0x800E3BB4 -- the same, through lookupFileTable
local files = {}

local function find(ctx, path_addr)
  local path = ctx:read_bytes(path_addr, 64)
  path = path:sub(1, (path:find("\0", 1, true) or 65) - 1)
  return files[(path:match("([^\\]+)$") or path):upper()]
end

-- Adds (or replaces) the file `name` with `data`; returns its first sector.
function M.add(name, data)
  local lba = dwrc.disc.append(data)
  files[name:upper()] = { lba = lba, size = #data }
  return lba
end

local function bcd(v) return (v // 10) * 16 + v % 10 end

function M.install()
  dwrc.on_exec(ADD_FILE_READ_REQUEST_PATH, function(ctx)
    if not find(ctx, ctx:reg("a0")) then return false end
    ctx:set_pc(ADD_FILE_READ_REQUEST_LOOKUP)
    return true
  end)
  dwrc.on_exec(LOOKUP_FILE_TABLE, function(ctx)
    local f = find(ctx, ctx:reg("a1"))
    if not f then return false end
    -- FileLookup: CdlLOC pos {minute, second, sector (BCD), track}, then the size
    local lookup = ctx:reg("a0")
    local i = f.lba + 150 -- CdIntToPos counts from the start of the 2-second pregap
    ctx:write8(lookup, bcd(i // 75 // 60))
    ctx:write8(lookup + 1, bcd(i // 75 % 60))
    ctx:write8(lookup + 2, bcd(i % 75))
    ctx:write32(lookup + 4, f.size)
    ctx:ret(1)
    return true
  end)
end

return M
