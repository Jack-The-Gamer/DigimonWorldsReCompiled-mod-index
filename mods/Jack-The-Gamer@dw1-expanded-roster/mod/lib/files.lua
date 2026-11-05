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
--
-- A model can also have a smaller version for the field's NPCs (`add_npc`,
-- NAME.NPC: lib/convert.lua's npc_model). loadMMD's NPC branch builds the
-- path CHDAT\MMDn\NAME.MMD at sp+40, then calls lookupFileSize(path) and
-- readFile(path) (0x800A2190, 0x800A21C8). When the load comes from a map
-- script (scriptLoadModel -> loadNPCModel -> thunkLoadMMD -> loadMMD, all
-- tail calls, so loadMMD's saved ra at sp+36 is scriptLoadModel's
-- 0x80106A04), the path's extension becomes .NPC. Vs mode loads its
-- opponent through the same branch from its own code and keeps the whole
-- model.

local M = {}

local LOOKUP_FILE_TABLE = 0x800A31F8           -- lookupFileTable(FileLookup *lookup, char *path) -> 1 found / 0
local ADD_FILE_READ_REQUEST_PATH = 0x800E3938   -- (path, buffer, isRunning, callback, param)
local ADD_FILE_READ_REQUEST_LOOKUP = 0x800E3BB4 -- the same, through lookupFileTable
local NPC_PATH_DONE = 0x800A2188                -- loadMMD's NPC branch, its path built
-- addi v0,v0,48; sb v0,49(sp); jal lookupFileSize; addiu a0,sp,40
local NPC_PATH_WORDS = { 0x20420030, 0xA3A20031, 0x0C028CB3, 0x27A40028 }
local FROM_SCRIPT = 0x80106A04                  -- scriptLoadModel, after `jal loadNPCModel`
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

-- The field NPC version of the model `name` (NAME.MMD -> NAME.NPC).
function M.add_npc(name, data)
  return M.add((name:gsub("%.[^.]*$", "")) .. ".NPC", data)
end

local function bcd(v) return (v // 10) * 16 + v % 10 end

function M.install()
  dwrc.on_exec(NPC_PATH_DONE, function(ctx)
    for i, w in ipairs(NPC_PATH_WORDS) do
      if ctx:read32(NPC_PATH_DONE + 4 * (i - 1)) ~= w then return false end
    end
    local sp = ctx:reg("sp")
    if ctx:read32(sp + 36) ~= FROM_SCRIPT then return false end
    local path = ctx:read_bytes(sp + 40, 32)
    path = path:sub(1, (path:find("\0", 1, true) or 33) - 1)
    local name = (path:match("([^\\]+)$") or path):upper()
    if name:sub(-4) == ".MMD" and files[name:sub(1, -5) .. ".NPC"] then
      ctx:write_bytes(sp + 40 + #path - 4, ".NPC")
    end
    return false
  end)
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
