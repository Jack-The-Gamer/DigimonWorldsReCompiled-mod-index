-- The new Digimon in File City's Arena (the stadium overlay STD_REL.BIN,
-- loaded at 0x80052AE0; names as in dw_decomp's std_main.c).
--
-- The tournament's bracket draws each participant (PARTICIPANT_TYPES,
-- 0x80135150, 8 types) as a 16 x 16 sprite from a sheet the overlay loads
-- (STDTIM.BIN): STD_renderBracketDigimon takes tile = type, texture page
-- x 0x380 + (tile / 64) * 64, cell (tile - 1) % 64 of an 8 x 8 grid of
-- 32 x 32 cells (four 16 x 16 frames), CLUT x 0x120 + (tile / 64) * 16, row
-- 0x1E0 + STD_DIGIMON_SPRITE_CLUT[tile] (112 entries). A new type points
-- past the sheet. The Arena's other per-type data is read through the
-- moved tables (DIGIMON_DATA: stage, size, specialties), and the USA
-- release never draws the names (STD_renderIntroNameChar adds no
-- primitive, the bracket shows pictures only).
--
-- So a new Digimon in the bracket (an opponent DW1 Wild Digimon Randomizer
-- put there, or the partner) gets a cell the sheet leaves empty, tiles
-- 117..127 (page 1, cells 52..62; 113..116 hold the bracket's hit flash
-- and other sprites), with its chart icon (lib/icon.lua: two 16 x 16
-- frames, shown as frames 0/1 and again as 2/3) and its CLUT in row
-- 0x1E7 + k of page 1's CLUT column (rows 0x1E7.. are unused there). The
-- icons and CLUTs are uploaded when the bracket is shown (STD_addBracket,
-- 0x8005DEEC: after STD_setupParticipants and the sheet's load); the
-- renderer's tile (s1, at 0x8005D5B0) and GetClut's row (a1, when called
-- from 0x8005D604) are redirected. Cells are dealt in PARTICIPANT_TYPES
-- order, so a save state mid-tournament finds the same ones.

local M = {}

local PARTICIPANT_TYPES = 0x80135150
local ADD_BRACKET = 0x8005DEEC              -- STD_addBracket(track)
local ADD_BRACKET_WORDS = { 0x27BDFFE8, 0x3C018013, 0xAFBF0014 }
local RENDER_TILE = 0x8005D5B0              -- STD_renderBracketDigimon: addu s4, s1, zero (s1 = tile)
local RENDER_WORDS = { [0x8005D578] = 0x90510000, [0x8005D5B0] = 0x0220A021, [0x8005D5FC] = 0x0C024AAF }
local GET_CLUT = 0x80092ABC                 -- GetClut(x, y)
local FROM_RENDER = 0x8005D604              -- its return address in STD_renderBracketDigimon
local LOAD_IMAGE = 0x800948A8               -- LoadImage(RECT *, u_long *)
local DRAW_SYNC = 0x800947B0                -- DrawSync(0)
local FIRST_TILE, TILES = 117, 11
local CLUT_X, CLUT_ROW = 0x130, 0x1E7

local function words_at(ctx, list)
  for a, w in pairs(list) do
    if ctx:read32(a) ~= w then return false end
  end
  return true
end

-- type -> k (its tile FIRST_TILE + k and CLUT row CLUT_ROW + k)
local function deal(ctx, icons)
  local out, k = {}, 0
  for i = 0, 7 do
    local t = ctx:read8(PARTICIPANT_TYPES + i)
    if icons[t] and out[t] == nil and k < TILES then out[t], k = k, k + 1 end
  end
  return out
end

-- Calls game functions from a hook on a stack frame below the game's (each
-- returns to `at`), then puts every register back and lets the code at
-- `at` run (lib/chart.lua's way).
local function caller(at, start)
  local co, saved, frame
  dwrc.on_exec(at, function(ctx)
    local v0
    if not co then
      local fn = start(ctx)
      if not fn then return false end
      saved = {}
      for r = 1, 31 do saved[r] = ctx:reg(r) end
      frame = (saved[29] - 0x60) & ~7
      co = coroutine.create(fn)
    else
      v0 = ctx:reg("v0")
    end
    local ok, req = coroutine.resume(co, ctx, v0, frame)
    if not ok then dwrc.log("arena: " .. tostring(req)) req = nil end
    if req and coroutine.status(co) ~= "dead" then
      ctx:set_reg("sp", frame)
      for k = 2, #req do ctx:set_reg(2 + k, req[k] & 0xFFFFFFFF) end
      ctx:set_reg("ra", at)
      ctx:set_pc(req[1])
      return true
    end
    co = nil
    for r = 1, 31 do ctx:set_reg(r, saved[r]) end
    return false
  end)
end

-- icons: type -> {pixels (two 16 x 16 frames side by side, 4bpp: 8 x 16
-- VRAM pixels), clut (16 colours)}; scratch: RAM the uploads go through.
function M.install(icons, scratch, scratch_size)
  local entry = { [ADD_BRACKET] = ADD_BRACKET_WORDS[1], [ADD_BRACKET + 4] = ADD_BRACKET_WORDS[2], [ADD_BRACKET + 8] = ADD_BRACKET_WORDS[3] }
  caller(ADD_BRACKET, function(ctx)
    if not words_at(ctx, entry) or not words_at(ctx, RENDER_WORDS) then return nil end
    local dealt = deal(ctx, icons)
    if next(dealt) == nil then return nil end
    return function(c)
      -- each call comes back in a new hook: its ctx replaces the last one
      local call = function(fn, ...) local nc, v0 = coroutine.yield({ fn, ... }) c = nc return v0 end
      local at = 0
      for t, k in pairs(dealt) do
        local tile = FIRST_TILE + k
        local p = (tile - 1) % 64
        local x, y = 0x380 + (tile // 64) * 64 + (p % 8) * 8, ((p // 8) % 8) * 32
        for _, up in ipairs({
          { string.pack("<i2i2i2i2", x, y, 8, 16), icons[t].pixels },
          { string.pack("<i2i2i2i2", x, y + 16, 8, 16), icons[t].pixels },
          { string.pack("<i2i2i2i2", CLUT_X, CLUT_ROW + k, 16, 1), icons[t].clut },
        }) do
          local need = 8 + #up[2]
          if at + need > scratch_size then call(DRAW_SYNC, 0) at = 0 end
          c:write_bytes(scratch + at, up[1] .. up[2])
          call(LOAD_IMAGE, scratch + at, scratch + at + 8)
          at = (at + need + 3) & ~3
        end
      end
      call(DRAW_SYNC, 0)
    end
  end)

  dwrc.on_exec(RENDER_TILE, function(ctx)
    local t = ctx:reg("s1")
    if t < 112 or not icons[t] or not words_at(ctx, RENDER_WORDS) then return false end
    local k = deal(ctx, icons)[t]
    if k then ctx:set_reg("s1", FIRST_TILE + k) end
    return false
  end)

  dwrc.on_exec(GET_CLUT, function(ctx)
    if ctx:reg("ra") ~= FROM_RENDER or not words_at(ctx, RENDER_WORDS) then return false end
    local tile = ctx:reg("s1")
    if tile < FIRST_TILE or tile >= FIRST_TILE + TILES then return false end
    ctx:set_reg("a1", CLUT_ROW + tile - FIRST_TILE)
    return false
  end)
end

return M
