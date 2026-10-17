-- DW1 Expanded Stats: adds a tiredness meter, care mistakes and battles to
-- the Digimon's status screen.
--
-- Everything is drawn by the game's own status screen code, called from a
-- hook at the start of its drawing part (RenderStatsMenu), so it looks like
-- the rest of the screen:
--
-- * Tiredness row: a sweat drop in the style and palette of the game's own
--   sweat drops (the feelings effect texture, always in video memory),
--   "Tired" written with the same text routine and colour as "Life",
--   "Disc." and "Vir.", and a bar like the virus bar (tiredness 0-100).
--   To make room, the Life, Happiness, Disc. and Vir. rows move up one row
--   (15 pixels), which lines them up with MP, Off, Def and SPEED; Tired sits
--   next to BRAINS. The condition bubbles move up 2 pixels to clear Life.
-- * MISTAKES and BATTLES: labels in the NAME / DIGI / AGE / WEIGHT lettering
--   (one-pixel strokes, outlined), boxes and numbers like AGE and WEIGHT.
--   The game has no S, K, B or L in that lettering, so the two words are
--   drawn here in the same style. They and the drop are copied into free
--   rows of the menu text texture each frame the screen is shown; the game
--   clears those rows before writing the status screen's words.
--
-- Made for Digimon World (USA, SLUS-01032). Every instruction and table entry
-- the mod relies on is checked first; on anything else it does nothing.

local SERIAL = "SLUS-01032"

-- Partner values (signed 16-bit)
local TIREDNESS, CARE_MISTAKES, BATTLES = 0x80138482, 0x801384b2, 0x801384b4

-- Game functions and places (SLUS-01032)
local F = {
  number = 0x800e5444, -- (colour, x, y, digits, value, depth)
  square = 0x800be734, -- (x, y, w, h, depth), screen coordinates
  segbar = 0x800be85c, -- (x, y, length, height, r, g, b, flags, depth)
  sprite = 0x800e5b50, -- text sprite: (colour, x, y, w, h, u, v, depth, shadow)
  rect   = 0x800b8928, -- (x, y, w, h, u, v, tpage, clut, depth, flags)
  string = 0x8010cf24, -- write text into the menu text texture: (str, u, v)
}
local DRAW_BRANCH  = 0x800bb684 -- RenderStatsMenu, first instruction of its drawing part
local STRINGS_DONE = 0x800bb678 -- RenderStatsMenu, just after its words were written
local WORK_PTR     = 0x80136fe4 -- next free byte of the frame's primitive buffer
local OT_HOLDER    = -0x6c5c    -- gp-relative pointer; +4 holds the order table
local DEPTH = 5                 -- order table entry of the status screen

-- Each entry: address, the word the game has there.
local CHECKS = {
  { DRAW_BRANCH, 0x3c048012 }, { STRINGS_DONE, 0x24020001 }, { STRINGS_DONE - 0x14, 0x0c02fab4 },
  { 0x800bb884, 0x0c039511 }, { 0x800bc29c, 0x0c02f9cd }, { 0x800bc264, 0x0c02fa17 },
  { 0x800bb6ec, 0x0c0396d4 }, { 0x800bb778, 0x0c02e24a }, { 0x800beb44, 0x0c0433c9 },
  { 0x800bb620, 0x3c188012 }, { 0x80098c38, 0x3c028013 }, { 0x80098c3c, 0x8c426fe4 },
  { 0x800b896c, 0x8f8293a4 },
}

-- Rows move up by DY: 16-bit values in tables and in `addiu a1, zero, y`
-- (or `addi s4/v0, v0, -0x78` for the bubbles), each with its original value.
local DY = -15
local MOVES = {
  -- text table (x, y, w, u, v): Life, Disc., Vir.
  { 0x80124336, 34 }, { 0x8012433e, 64 }, { 0x80124346, 79 },
  -- picture table (x, y, w, h, u, v): HAPPINES, virus icon (two layers)
  { 0x80124406, 49 }, { 0x801243ce, 79 }, { 0x8012441e, 79 },
  -- boxes behind the happiness, discipline and virus bars (screen y)
  { 0x801242ee, 171 }, { 0x801242f6, 186 }, { 0x801242fe, 201 },
  -- hearts, happiness icon and bar, discipline icon and bar, virus bar
  { 0x800bbde0, 0x22 }, { 0x800bbe20, 0x22 }, { 0x800bbea4, 0x31 }, { 0x800bbef0, 0x31 },
  { 0x800bbf78, 0x35 }, { 0x800bbfc4, 0x35 }, { 0x800bc048, 0x35 }, { 0x800bc0ac, 0x40 },
  { 0x800bc0fc, 0x40 }, { 0x800bc16c, 0x44 }, { 0x800bc1b8, 0x44 }, { 0x800bc218, 0x44 },
  { 0x800bc260, 0x52 },
}
local BUBBLE_DY = -2
local BUBBLES = { { 0x800bed8c, 0xff88 }, { 0x800bee74, 0xff88 } }

-- ---------------------------------------------------------------------
-- Lettering in the NAME / DIGI / AGE / WEIGHT style: one-pixel strokes,
-- eight rows tall, one column between letters, outlined all round.
local LETTERS = {
  A = { ".##.", "#..#", "#..#", "####", "#..#", "#..#", "#..#", "#..#" },
  B = { "###.", "#..#", "#..#", "###.", "#..#", "#..#", "#..#", "###." },
  E = { "###", "#..", "#..", "###", "#..", "#..", "#..", "###" },
  I = { "#", "#", "#", "#", "#", "#", "#", "#" },
  K = { "#..#", "#..#", "#.#.", "##..", "#.#.", "#..#", "#..#", "#..#" },
  L = { "#..", "#..", "#..", "#..", "#..", "#..", "#..", "###" },
  M = { "#...#", "##.##", "#####", "#.#.#", "#...#", "#...#", "#...#", "#...#" },
  S = { ".###", "#...", "#...", ".##.", "...#", "...#", "...#", "###." },
  T = { "###", ".#.", ".#.", ".#.", ".#.", ".#.", ".#.", ".#." },
}

-- 10 rows of palette indices (0 clear, 1 outline, 2 stroke) and the width.
local function word(text)
  local w = 1
  for i = 1, #text do w = w + #LETTERS[text:sub(i, i)][1] + 1 end
  local px = {}
  for y = 0, 9 do px[y] = {} for x = 0, w - 1 do px[y][x] = 0 end end
  local x0 = 1
  for i = 1, #text do
    local g = LETTERS[text:sub(i, i)]
    for r = 1, 8 do
      for c = 1, #g[r] do
        if g[r]:sub(c, c) == "#" then px[r][x0 + c - 1] = 2 end
      end
    end
    x0 = x0 + #g[1] + 1
  end
  for y = 0, 9 do
    for x = 0, w - 1 do
      if px[y][x] == 0 then
        for dy = -1, 1 do for dx = -1, 1 do
          local r = px[y + dy]
          if r and r[x + dx] == 2 then px[y][x] = 1 end
        end end
      end
    end
  end
  return px, w
end

-- Sweat drop, 7 x 11, in the colours of the feelings effect texture's
-- blue palette (272, 481). The game's own drops are 7 x 9 and 5 x 12; this
-- one sits between the two. It gets a one-pixel near-black outline (palette
-- index 1) around its sides, like the status screen's other icons, which
-- makes it 9 x 13.
local DROP_SHAPE = {
  "...6...",
  "..545..",
  "..a74..",
  ".a9745.",
  ".797a6.",
  "5797a65",
  "77ab767",
  "9abb763",
  "44b5462",
  "9344629",
  ".59335.",
}
local DROP_CLUT = 0x7851

-- Rows of palette indices: the shape plus its outline (every clear pixel
-- next to the shape above, below, left or right of it).
local function outlined(shape)
  local h, w = #shape + 2, #shape[1] + 2
  local px = {}
  for y = 0, h - 1 do px[y] = {} for x = 0, w - 1 do px[y][x] = 0 end end
  for y, row in ipairs(shape) do
    for x = 1, #row do
      local ch = row:sub(x, x)
      if ch ~= "." then px[y][x] = tonumber(ch, 16) end
    end
  end
  local inside = function(y, x) return px[y] and (px[y][x] or 0) > 1 end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if px[y][x] == 0 and (inside(y - 1, x) or inside(y + 1, x) or inside(y, x - 1) or inside(y, x + 1)) then
        px[y][x] = 1
      end
    end
  end
  return px, w, h
end
local DROP, DROP_W, DROP_H = outlined(DROP_SHAPE)

-- The menu text texture: page at video memory (704, 256), 4-bit. The game
-- writes the status screen's words in rows 24-83 and clears rows 24-223
-- first; the mod uses rows 200-219.
local TEXT_TPAGE = 0x1b
local TIRED_U, TIRED_V = 0, 200
local GLYPH_U, GLYPH_V, GLYPH_W, GLYPH_H = 128, 200, 52, 20
local DROP_U, DROP_V = GLYPH_U + 40, GLYPH_V
local LABEL_CLUT = 0x7c46 -- the NAME / DIGI palette, (96, 497)

local labels = {}
local upload -- GP0 "copy to video memory" command and pixels, after the tag word
do
  local t = {}
  for y = 0, GLYPH_H - 1 do t[y] = {} for x = 0, GLYPH_W - 1 do t[y][x] = 0 end end
  local v = 0
  for _, name in ipairs({ "MISTAKES", "BATTLES" }) do
    local px, w = word(name)
    for y = 0, 9 do for x = 0, w - 1 do t[v + y][x] = px[y][x] end end
    labels[name] = { u = GLYPH_U, v = GLYPH_V + v, w = w }
    v = v + 10
  end
  for y = 0, DROP_H - 1 do
    for x = 0, DROP_W - 1 do t[DROP_V - GLYPH_V + y][DROP_U - GLYPH_U + x] = DROP[y][x] end
  end
  local vx, vy = 704 + GLYPH_U // 4, 256 + GLYPH_V
  local words = { 0xA0000000, (vy << 16) | vx, (GLYPH_H << 16) | (GLYPH_W // 4) }
  local hw = {}
  for y = 0, GLYPH_H - 1 do
    for x = 0, GLYPH_W - 1, 4 do
      hw[#hw + 1] = t[y][x] | (t[y][x + 1] << 4) | (t[y][x + 2] << 8) | (t[y][x + 3] << 12)
    end
  end
  for i = 1, #hw, 2 do words[#words + 1] = hw[i] | ((hw[i + 1] or 0) << 16) end
  local parts = {}
  for i, w in ipairs(words) do parts[i] = string.pack("<I4", w) end
  upload = table.concat(parts)
end

-- Adds the copy to this frame's order table, ahead of everything already in
-- the status screen's entry, so the labels drawn there find their pixels.
local function link_upload(c)
  local ot = c:read32(c:read32(c:reg("gp") + OT_HOLDER) + 4) + DEPTH * 4
  local p = c:read32(WORK_PTR)
  c:write_bytes(p + 4, upload)
  local head = c:read32(ot)
  c:write32(p, ((#upload // 4) << 24) | (head & 0xFFFFFF))
  c:write32(ot, (head & 0xFF000000) | (p & 0xFFFFFF))
  c:write32(WORK_PTR, p + 4 + #upload)
end

-- ---------------------------------------------------------------------
-- Calls game functions from a hook: ra points back at the hook, so each
-- return brings the next call; afterwards every register is put back.
local function call_chain(at, build, finish)
  local calls, i, saved
  dwrc.on_exec(at, function(c)
    if not calls then
      calls = build(c)
      if not calls then return false end
      saved = {}
      for r = 1, 31 do saved[r] = c:reg(r) end
      i = 1
    end
    local call = calls[i]
    if call then
      i = i + 1
      for k = 2, #call do
        if k <= 5 then c:set_reg(2 + k, call[k])                    -- a0..a3
        else c:write32(saved[29] + 0x10 + (k - 6) * 4, call[k]) end -- stack arguments
      end
      c:set_reg("ra", at)
      c:set_pc(call[1])
      return true
    end
    if finish then finish(c) end
    for r = 1, 31 do c:set_reg(r, saved[r]) end
    calls = nil
    return false
  end)
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Moves the rows (again, if something put the original values back).
local function ensure_moved(c)
  if c:read16(MOVES[#MOVES][1]) ~= MOVES[#MOVES][2] then return end
  for _, m in ipairs(MOVES) do c:write16(m[1], (m[2] + DY) & 0xFFFF) end
  for _, b in ipairs(BUBBLES) do c:write16(b[1], (b[2] + BUBBLE_DY) & 0xFFFF) end
end

-- Layout. x is relative to the screen centre, except for boxes (screen x).
local TIRED_BAR = { 0x40, 0x98, 0xe8 }
local MISTAKES_X, MISTAKES_BOX = 157 - 160, 196
local BATTLES_X, BATTLES_BOX = 234 - 160, 268
local ROW_Y, BOX_Y = -34, 84 -- AGE / WEIGHT row
local TIRED_Y = 79           -- the old virus row

local function install()
  call_chain(STRINGS_DONE, function(c)
    local sp = c:reg("sp")
    c:write_bytes(sp + 0x38, "Tired\0") -- RenderStatsMenu's palette copy, unused in this part
    return { { F.string, sp + 0x38, TIRED_U, TIRED_V } }
  end)

  call_chain(DRAW_BRANCH, function(c)
    ensure_moved(c)
    local t = clamp(c:read_s16(TIREDNESS), 0, 100)
    local m = clamp(c:read_s16(CARE_MISTAKES), 0, 999)
    local b = clamp(c:read_s16(BATTLES), 0, 999)
    local ml, bl = labels.MISTAKES, labels.BATTLES
    -- Within one depth the game draws what was added last first, so numbers
    -- go in before their boxes and bars before theirs.
    return {
      { F.rect, -137, TIRED_Y - 1, DROP_W, DROP_H, DROP_U, DROP_V, TEXT_TPAGE, DROP_CLUT, DEPTH, 0 },
      { F.sprite, 3, -126, TIRED_Y + 1, 40, 12, TIRED_U, TIRED_V, DEPTH, 1 },
      { F.segbar, -84, TIRED_Y + 3, t // 2, 6, TIRED_BAR[1], TIRED_BAR[2], TIRED_BAR[3], 0, DEPTH },
      { F.square, 75, 201, 50, 8, DEPTH },
      { F.number, 0, MISTAKES_BOX - 160 + 2, ROW_Y, 3, m, DEPTH },
      { F.number, 0, BATTLES_BOX - 160 + 2, ROW_Y, 3, b, DEPTH },
      { F.rect, MISTAKES_X, ROW_Y, ml.w, 10, ml.u, ml.v, TEXT_TPAGE, LABEL_CLUT, DEPTH, 0 },
      { F.rect, BATTLES_X, ROW_Y, bl.w, 10, bl.u, bl.v, TEXT_TPAGE, LABEL_CLUT, DEPTH, 0 },
      { F.square, MISTAKES_BOX, BOX_Y, 26, 14, DEPTH },
      { F.square, BATTLES_BOX, BOX_Y, 26, 14, DEPTH },
    }
  end, link_upload)
end

local state = "waiting" -- waiting / on / off
dwrc.on_frame(function(c)
  if state ~= "waiting" or c:frame() % 30 ~= 0 then return end
  if dwrc.serial ~= SERIAL then
    state = "off"
    dwrc.log("DW1 Expanded Stats: made for Digimon World (USA, " .. SERIAL .. "); this disc is " .. tostring(dwrc.serial) .. ", so it does nothing")
    return
  end
  if c:read32(CHECKS[1][1]) ~= CHECKS[1][2] then return end -- program not loaded yet
  for _, k in ipairs(CHECKS) do
    if c:read32(k[1]) ~= k[2] then
      state = "off"
      dwrc.log(string.format("DW1 Expanded Stats: unexpected code at %08x; status screen left as it is", k[1]))
      return
    end
  end
  for _, m in ipairs(MOVES) do
    if c:read16(m[1]) ~= m[2] then
      state = "off"
      dwrc.log(string.format("DW1 Expanded Stats: unexpected value at %08x; status screen left as it is", m[1]))
      return
    end
  end
  for _, b in ipairs(BUBBLES) do
    if c:read16(b[1]) ~= b[2] then state = "off" return end
  end
  ensure_moved(c)
  install()
  state = "on"
  dwrc.log("DW1 Expanded Stats ready")
end)
