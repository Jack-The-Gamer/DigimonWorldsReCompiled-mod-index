-- Long Digimon names on the Digimon page (SLUS-01032), fitted to the box.
--
-- renderDigimonStatsView (src/main/game_menu.c) shows the name from the text
-- area, where drawDigimonStatsStrings drew it in full (row 0x48 from x 0),
-- with renderString(0, -0x6C, -0x32, w, 12, 0, 0x48, 5, 0): one textured quad,
-- as many texels wide as pixels on screen, w = 10 per letter but at most 120.
-- The font is proportional (drawString adds each glyph's width), so a name of
-- 14 letters or more was cut off ("MasterTyrannom"), and the last letter of a
-- 120-pixel one ran under the specialty icons (from x 9).
--
-- A name wider than the room before the icons (BOX) is now drawn one quad
-- per letter, each letter whole and the letters moved closer together so the
-- last one ends at BOX: the name is narrowed without losing a stroke (the
-- text's background is transparent, so neighbours only overlap blank edges).
-- Tried first: one quad squeezed to BOX (the GPU samples the nearest texel,
-- so whole one-pixel strokes dropped out: PlatinumSukamon's l), and drawing
-- the glyphs a pixel closer in the text area (each glyph's cell erases the
-- last column of the one before). Names that fit stay as they were.
--
-- The letters come from drawString (each glyph's x and width as it draws);
-- the quads from the game's own renderString, called once per letter from the
-- name's call site: its stack arguments (height, u, v, page, flag) are the
-- caller's, only u changes per letter, and it returns to NAME_DONE, where the
-- next letter is set up. Each hooked instruction is checked first (M.check).

local M = {}

local DRAW_STRING = 0x8010CF24      -- drawString(str, x, y): a1 x, a2 y
local GLYPH_ADVANCE = 0x8010D004    -- addu v0, s1, v0: s1 the glyph's x, v0 its width
local DRAW_STRING_END = 0x8010D01C  -- its return: s2 y
local NAME_CALL = 0x800BB85C        -- jal renderString (the name)
local NAME_DONE = 0x800BB864        -- after it
local RENDER_STRING = 0x800E5B50    -- renderString(color, x, y, w, h, u, v, page, flag)
local NAME_ROW = 0x48
local NAME_X, NAME_Y = -0x6C, -0x32 -- where the page puts the name
M.BOX = 115                         -- x -108 up to the icons at 9, a pixel apart

M.CODE = {
  [DRAW_STRING] = 0x27BDFFE0,       -- addiu sp, sp, -32
  [GLYPH_ADVANCE] = 0x02221021,     -- addu v0, s1, v0
  [DRAW_STRING_END] = 0x8FBF001C,   -- lw ra, 28(sp)
  [NAME_CALL] = 0x0C0396D4,         -- jal 0x800E5B50 (renderString)
  [NAME_DONE] = 0x3C018014,         -- lui at, 0x8014
  [RENDER_STRING] = 0x27BDFFC0,     -- addiu sp, sp, -64
}

-- word(addr): the executable's instruction there; false if one isn't as expected.
function M.check(word)
  for addr, w in pairs(M.CODE) do
    if word(addr) ~= w then return false, string.format("%08X: %08X, not %08X", addr, word(addr), w) end
  end
  return true
end

-- Where each letter goes ({x in the text area, width} each, in order): the
-- first at 0, the last ending at `box`, the others spread evenly between.
function M.layout(glyphs, box)
  local n = #glyphs
  local last = glyphs[n]
  local span = box - last[2]          -- where the last letter starts
  local from = last[1] - glyphs[1][1] -- where it starts in the text
  local out = {}
  for i, g in ipairs(glyphs) do out[i] = (g[1] - glyphs[1][1]) * span // from end
  return out
end

-- One letter's renderString: x, w in registers, u (sp + 20) on the stack.
local function letter(ctx, g, at)
  ctx:set_reg("a0", 0)
  ctx:set_reg("a1", (NAME_X + at) & 0xFFFFFFFF)
  ctx:set_reg("a2", NAME_Y & 0xFFFFFFFF)
  ctx:set_reg("a3", g[2])
  ctx:write32(ctx:reg("sp") + 20, g[1])
end

function M.install()
  local glyphs, drawing, name = {}, false, nil
  local pending, k, at = nil, 0, nil
  dwrc.on_exec(DRAW_STRING, function(ctx)
    drawing = ctx:reg("a2") == NAME_ROW
    if drawing then glyphs = {} end
    return false
  end)
  dwrc.on_exec(GLYPH_ADVANCE, function(ctx)
    if drawing then glyphs[#glyphs + 1] = { ctx:reg("s1") & 0xFFFF, ctx:reg("v0") & 0xFFFF } end
    return false
  end)
  dwrc.on_exec(DRAW_STRING_END, function(ctx)
    if drawing and ctx:reg("s2") == NAME_ROW then name = glyphs end
    drawing = false
    return false
  end)
  dwrc.on_exec(NAME_CALL, function(ctx)
    pending = nil
    local n = name and #name or 0
    if n >= 2 then
      local last = name[n]
      if last[1] + last[2] - name[1][1] > M.BOX and last[1] + last[2] < 256 then
        pending, k, at = name, 1, M.layout(name, M.BOX)
        letter(ctx, pending[1], at[1]) -- the call goes ahead with the first letter
      end
    end
    return false
  end)
  dwrc.on_exec(NAME_DONE, function(ctx)
    if not pending then return false end
    if k < #pending then
      k = k + 1
      letter(ctx, pending[k], at[k])
      ctx:set_reg("ra", NAME_DONE)
      ctx:set_pc(RENDER_STRING)
      return true
    end
    ctx:write32(ctx:reg("sp") + 20, 0) -- u as the caller left it
    pending = nil
    return false
  end)
end

return M
