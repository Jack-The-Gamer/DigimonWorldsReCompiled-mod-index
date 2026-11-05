-- The Digivolution Chart (the Player menu's Chart page), rebuilt so it can
-- hold any number of Digimon (SLUS-01032; names as in dw_decomp).
--
-- The game's chart is laid out by hand: 61 boxes at fixed places
-- (EVO_CHART_BOXES {posX, posY, u, v, clut}), five stage panels of fixed
-- size, and a cursor that turns a fixed column/row into a position and looks
-- for the box there. This draws the same pieces (the game's border boxes and
-- panel colours, the icons from the chart's texture, the cursor sprite) from
-- a layout worked out from the data: each stage keeps the game's own
-- arrangement of its Digimon, new ones take the next free cell of their
-- stage, and when the stages don't fit the panels' padding shrinks first,
-- then the boxes and sprites. The "Select / Cancel" line is gone and the
-- panels use the whole height.
--
-- renderEvoChartView (0x800BD940) is answered here once the page is set up
-- (state 0 still runs the game's, which prepares the page's text), and the
-- chart's part of tickPlayerMenu (0x800B9654..0x800B9B88: the cursor, and
-- opening/closing a Digimon's detail page) is replaced.
--
-- The detail page (renderEvoChartDetail 0x800BA930, the box that opens on
-- a Digimon) is drawn here too, from the game's pieces: its side panels run
-- the page's height, the centre box sits at their middle with the stage and
-- name centred under it, and each list is a column of frames on the game's
-- arc, 19 apart like the chart's, shrinking as the list grows so it stays in
-- its panel. The game's page had 5 places for the Digimon a Digimon comes
-- from and 6 for those it becomes, read them as signed bytes (types 128 and
-- up never showed) and took icons from its 61 boxes; here a list is any
-- length (entries past the stored 5 / 6: evolution.extra_from / .extra).

local tables = require("lib.tables")
local evolution = require("lib.evolution")

local M = {}

local RENDER_CHART = 0x800BD940     -- renderEvoChartView()
local CHART_TICK = 0x800B9654       -- tickPlayerMenu: if (PLAYER_MENU_STATE == 1) {...}
local CHART_TICK_END = 0x800B9B88   -- the code after that block
local RENDER_BORDER_BOX = 0x800BE990 -- (x, y, w, h, light, dark, r, g, b, depth)
local IS_KEY_DOWN = 0x800FC054
local PLAY_SOUND = 0x800C6374       -- (bank, sound)
local HAS_DIGIMON_RAISED = 0x800FF824
local IS_UI_BOX_AVAILABLE = 0x800BA1D4
local CREATE_ANIMATED_UI_BOX = 0x800C3014 -- (id, ?, ?, &final, &start, NULL, render)
local REMOVE_ANIMATED_UI_BOX = 0x800C31FC -- (id, &final)
local RENDER_CHART_DETAIL = 0x800BA930
local LOAD_IMAGE = 0x800948A8       -- LoadImage(RECT *, u_long *): queued VRAM upload
local DRAW_SYNC = 0x800947B0        -- DrawSync(0): waits for the queued transfers
local DRAW_LINE_3P = 0x800E3D14     -- (color, x1, y1, x2, y2, x3, y3, depth, 0)
local DRAW_LINE_2P = 0x800E3E7C     -- (color, x1, y1, x2, y2, depth, 0)
local DRAW_CHART_STRINGS = 0x800C0718 -- drawEvoChartStrings(int8_t type)
local RENDER_STRING = 0x800E5B50     -- (colour, x, y, w, h, u, v, depth, 0): text from the page's text area
local DRAW_STRING = 0x8010CF24       -- drawString(str, x, y): text into the page's text area
local MEGA_TEXT_V = 0x48             -- "Mega" goes there (the US page writes nothing in rows 72..99)
local RENDER_INSET_BOX = 0x800BE734  -- (x, y, w, h, depth): the page's sunken frames (screen pixels)
local MENU_SUB_STATE = 0x80134D35    -- u8 (2: the detail page's name is drawn every frame)
local ASCII_TO_SJIS = 0x800F18C8     -- (char): what drawString (0x8010CF24) does per letter...
local SJIS_TO_FONT = 0x800F1AB0      -- (code)
local FONT_CODES = 0x801307E0        -- 80 x u16 (byte-swapped font codes): each glyph's code
local FONT_GLYPHS = 0x80130880       -- 80 x {u16 rows[11], u16 advance}: the glyph drawn for each
local EVO_CHART_DETAIL_COLORS = 0x80123E6C -- 5 CLUT ids for the detail page's icons
local CHART_TO_LINE_COLORS = 0x80124A84 -- 6 x 2 RGB8: each place's line colours
local FROM_LINE_DARK, FROM_LINE_LIGHT = 0x65db, 0x794e3

local MENU_STATE = 0x80134D34       -- u8: 0 setting up, 1 shown, 2 cursor, 3 detail open
local PLAYER_MENU_STATE = 0x80134D37 -- u8: 1 = the Chart page
local CHART_SELECTED_DIGIMON = 0x80134D40 -- s16
local MAIN_D_80134D46 = 0x80134D46
local CHANGED_INPUT = 0x80134EEC    -- buttons pressed this frame
local PLAYTIME_FRAMES = 0x80134F00
local EVO_CHART_BOXES = 0x80124544  -- 61 x {s16 posX, s16 posY, u8 u, u8 v, u8 clut, u8 pad}
local EVO_CHART_VIEW_COLORS = 0x80123E1C -- 5 CLUT ids
local GS_OUT_PACKET_P = 0x80136FE4  -- libgs's next free primitive (GsGetWorkBase)
local ACTIVE_ORDERING_TABLE = 0x80134ED0 -- GsOT * (org at +4)

local CONFIRM, CANCEL = 64, 16      -- isKeyDown codes
local LEFT, RIGHT, UP, DOWN = 0x8000, 0x2000, 0x1000, 0x4000

-- The area the panels share (screen pixels; the game's panels span these).
local X0, X1, Y0, Y1 = 0x15, 0x129, 0x27, 0xD7
local GAP = 3                        -- between panels
local PANEL_COLORS = {               -- {light, dark, r, g, b} per stage, the game's
  { 0xaaa0c8, 0x5a3c8c, 0xa5, 0x5a, 0x73 }, -- Fresh
  { 0xa078a5, 0x46144b, 0x6e, 0x2d, 0x5a }, -- In-Training
  { 0xc88250, 0x5f370a, 0x0f, 0x50, 0x82 }, -- Rookie
  { 0x6eaf5a, 0x285a00, 0x00, 0x87, 0x41 }, -- Champion
  { 0x6996d2, 0x1e4178, 0xaf, 0x64, 0x2d }, -- Ultimate
  { 0x78d2e6, 0x005a6e, 0xb4, 0x96, 0x14 }, -- Mega (the mod's: yellow; colours are 0xBBGGRR)
}
local STAGES = #PANEL_COLORS

-- --- calling the game's functions from a hook -----------------------------------
-- `start(ctx)` returns a function (run in a coroutine) or nil to let the
-- game's code run. The function calls `call(fn, args...)` -> v0; it runs
-- on a stack frame of its own below the game's, and when it ends every
-- register is put back and the CPU goes on at `done(saved)`.
local function caller(at, start, done)
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
    if not ok then
      dwrc.log("chart: " .. tostring(req))
      req = nil
    end
    if req and coroutine.status(co) ~= "dead" then
      ctx:set_reg("sp", frame)
      for k = 2, #req do
        if k <= 5 then ctx:set_reg(2 + k, req[k] & 0xFFFFFFFF)
        else ctx:write32(frame + 0x10 + (k - 6) * 4, req[k] & 0xFFFFFFFF) end
      end
      ctx:set_reg("ra", at)
      ctx:set_pc(req[1])
      return true
    end
    co = nil
    for r = 1, 31 do ctx:set_reg(r, saved[r]) end
    ctx:set_pc(done(saved))
    return true
  end)
end

-- --- the layout ------------------------------------------------------------------------
local layout = nil     -- built when the page first shows
-- Icons for Digimon the game has no box for: type -> {u, v, clut, tpage}
-- (clut and tpage as GPU ids), and what to upload to VRAM when the chart
-- opens: {rect = RECT (8 bytes), data = bytes} (the page clears its text
-- area, where most of them live, when it sets up).
M.icons = {}
M.uploads = {}
local dirty = true
-- type -> chart section for Digimon whose section isn't their DIGIMON_DATA
-- level: 6 is the Mega section (Digimon World has no level 6). A section
-- with no Digimon isn't drawn, so the Mega one only shows once it's used.
M.stage = {}

local function build_layout(ctx, new_types)
  -- every chart Digimon by stage, with its place in the game's arrangement
  local stages = {}
  for st = 1, STAGES do stages[st] = {} end
  local moved = {} -- the game's Digimon in another section (the Megas): placed like new ones
  for i = 0, 60 do
    local b = EVO_CHART_BOXES + 8 * i
    local level = ctx:read8(tables.entry("DIGIMON_DATA", i + 1) + 29)
    local d = { type = i + 1, px = ctx:read_s16(b), py = ctx:read_s16(b + 2), u = ctx:read8(b + 4), v = ctx:read8(b + 5), clut = ctx:read8(b + 6) }
    if M.stage[i + 1] then
      moved[#moved + 1] = { stage = M.stage[i + 1], d = d }
    elseif level >= 1 and level <= 5 then
      local s = stages[level]
      s[#s + 1] = d
    end
  end
  for st = 1, STAGES do
    local s = stages[st]
    local xs, cols = {}, {}
    for _, d in ipairs(s) do if not xs[d.px] then xs[d.px] = true; cols[#cols + 1] = d.px end end
    table.sort(cols)
    local col_of = {}
    for c, x in ipairs(cols) do col_of[x] = c - 1 end
    for _, d in ipairs(s) do d.c, d.r = col_of[d.px], (d.py - 0x2b) // 0x13 end
  end
  local news = moved
  for _, t in ipairs(new_types) do
    local level = M.stage[t] or ctx:read8(tables.entry("DIGIMON_DATA", t) + 29)
    if level >= 1 and level <= STAGES then
      local ic = M.icons[t] or {}
      news[#news + 1] = { stage = level, d = { type = t, u = ic.u, v = ic.v, clutid = ic.clut, tpage = ic.tpage, clut = 0, new = true } }
    end
  end

  -- the biggest pitch (and then padding) at which everything fits
  local H = Y1 - Y0
  for p = 19, 8, -1 do
    local s = p - 3                         -- sprite size (16 at the game's pitch)
    local hp = (p * 24 + 9) // 19           -- across: the game's columns are 24 apart
    local rows = (H - 4 - (s + 2)) // p + 1  -- cells that fit in a column
    -- place the new ones in the next free cells (by column, top to bottom)
    local grids = {}
    for st = 1, STAGES do
      local g = { items = {}, used = {}, stage = st }
      for _, d in ipairs(stages[st]) do
        g.items[#g.items + 1] = { d = d, c = d.c, r = d.r }
        g.used[d.c * 1000 + d.r] = true
      end
      grids[st] = g
    end
    local fits = true
    for _, n in ipairs(news) do
      local g = grids[n.stage]
      local placed = false
      for c = 0, 40 do
        for r = 0, rows - 1 do
          if not g.used[c * 1000 + r] then
            g.used[c * 1000 + r] = true
            g.items[#g.items + 1] = { d = n.d, c = c, r = r }
            placed = true
            break
          end
        end
        if placed then break end
      end
    end
    -- the sections drawn: the game's five, and the Mega one when it has any
    local shown = {}
    for st = 1, STAGES do
      if st <= 5 or #grids[st].items > 0 then shown[#shown + 1] = grids[st] end
    end
    local widths, total = {}, 0
    for st, g in ipairs(shown) do
      local nc, nr = 1, 1
      for _, it in ipairs(g.items) do nc = math.max(nc, it.c + 1); nr = math.max(nr, it.r + 1) end
      if nr > rows then fits = false end
      g.cols, g.rows = nc, nr
      widths[st] = (nc - 1) * hp + s + 2
      total = total + widths[st]
    end
    total = total + GAP * (#shown - 1)
    local room = (X1 - X0) - total
    if fits and room >= #shown * 2 * 3 then -- at least 3 pixels of padding a side
      -- share the room out as padding, so the panels fill the width
      local pad = room // (2 * #shown)
      local x = X0
      for st, g in ipairs(shown) do
        local w = widths[st] + 2 * pad
        if st == #shown then w = X1 - x end
        g.x, g.w = x, w
        -- spread a sparse stage the way the game does (Fresh, In-Training)
        local step = p * math.max(1, math.min(2, rows // math.max(1, g.rows)))
        if step > p and (g.rows - 1) * step + s + 2 > H - 4 then step = p end
        local left = x + (w - widths[st]) // 2 + 1
        for _, it in ipairs(g.items) do
          it.x, it.y = left + it.c * hp, Y0 + 4 + it.r * step
        end
        x = x + w + GAP
      end
      -- columns of cells for the cursor, left to right
      local columns = {}
      for _, g in ipairs(shown) do
        for c = 0, g.cols - 1 do
          local col = {}
          for _, it in ipairs(g.items) do if it.c == c then col[#col + 1] = it end end
          table.sort(col, function(a, b) return a.y < b.y end)
          if #col > 0 then columns[#columns + 1] = col end
        end
      end
      return { grids = shown, columns = columns, size = s, pitch = p }
    end
  end
  error("the chart can't fit its Digimon")
end

-- --- drawing -----------------------------------------------------------------------------
-- A textured quad straight into the frame's ordering table, as
-- renderRectPolyFT4 makes one but with its own size on screen.
local function sprite(ctx, x, y, w, h, u, v, uw, vh, tpage, clut, z)
  local p = ctx:read32(GS_OUT_PACKET_P)
  local function xy(o, a, b) ctx:write16(p + o, a & 0xFFFF); ctx:write16(p + o + 2, b & 0xFFFF) end
  ctx:write32(p + 4, 0x2C808080)
  xy(8, x, y); ctx:write8(p + 12, u); ctx:write8(p + 13, v); ctx:write16(p + 14, clut)
  xy(16, x + w, y); ctx:write8(p + 20, u + uw); ctx:write8(p + 21, v); ctx:write16(p + 22, tpage)
  xy(24, x, y + h); ctx:write8(p + 28, u); ctx:write8(p + 29, v + vh); ctx:write16(p + 30, 0)
  xy(32, x + w, y + h); ctx:write8(p + 36, u + uw); ctx:write8(p + 37, v + vh); ctx:write16(p + 38, 0)
  local slot = ctx:read32(ctx:read32(ACTIVE_ORDERING_TABLE) + 4) + 4 * z
  local tag = ctx:read32(slot)
  ctx:write32(p, (9 << 24) | (tag & 0xFFFFFF))
  ctx:write32(slot, (tag & 0xFF000000) | (p & 0xFFFFFF))
  ctx:write32(GS_OUT_PACKET_P, p + 40)
end

local cur = { col = 1, row = 1 }

local function selected(l)
  local col = l.columns[math.min(cur.col, #l.columns)]
  return col[math.min(cur.row, #col)]
end

local function draw(call, ctx, l)
  local state = ctx:read8(MENU_STATE)
  local s = l.size
  local k = s / 16
  local colors = {}
  for i = 0, 4 do colors[i] = ctx:read16(EVO_CHART_VIEW_COLORS + 2 * i) end
  local sel = selected(l)
  if dirty then
    -- through the evolution scene's buffer (there's no evolution while the
    -- chart is open), as many at a time as it holds
    local buf, room, at = tables.EVL_SCRATCH, tables.EVL_SCRATCH_SIZE, 0
    for _, up in ipairs(M.uploads) do
      local need = 8 + #up.data
      if at + need > room then call(DRAW_SYNC, 0); at = 0 end
      ctx:write_bytes(buf + at, up.rect .. up.data)
      call(LOAD_IMAGE, buf + at, buf + at + 8)
      at = (at + need + 3) & ~3
    end
    call(DRAW_SYNC, 0)
    dirty = false
  end
  -- the cursor sprite (24x20 for a 16 box, from the chart texture)
  if state >= 2 and state <= 4 and sel then
    sprite(ctx, sel.x - 0xa0 - math.floor(4 * k + 0.5), sel.y - 0x78 - math.floor(k + 0.5),
      math.floor(24 * k + 0.5), math.floor(20 * k + 0.5), 0, 0xe8, 0x18, 0x14, 0x18, 0x7dc7, 5)
  end
  local frames = ctx:read32(PLAYTIME_FRAMES)
  local raised = {}
  for _, g in ipairs(l.grids) do
    for _, it in ipairs(g.items) do
      local d = it.d
      if d.u then
        local r = call(HAS_DIGIMON_RAISED, d.type)
        raised[d.type] = r
        if r ~= 0 then
          local shift = (it == sel and state > 1 and frames % 10 < 5) and 0x10 or 0
          sprite(ctx, it.x - 0xa0, it.y - 0x78, s, s, d.u + shift, d.v, 0x10, 0x10, d.tpage or 0x18, d.clutid or colors[d.clut], 5)
        end
      end
    end
  end
  for _, g in ipairs(l.grids) do
    for _, it in ipairs(g.items) do
      call(RENDER_BORDER_BOX, it.x - 1, it.y - 1, s + 2, s + 2, 0xbebebe, 0x3c3c3c, 0x87, 0x87, 0x87, 5)
    end
  end
  for _, g in ipairs(l.grids) do
    local c = PANEL_COLORS[g.stage]
    call(RENDER_BORDER_BOX, g.x, Y0, g.w, Y1 - Y0, c[1], c[2], c[3], c[4], c[5], 5)
  end
end

-- --- the cursor and the detail page ----------------------------------------------
local function move(call, ctx, l)
  local input = ctx:read32(CHANGED_INPUT)
  local before = selected(l)
  local col = l.columns[cur.col]
  if input & UP ~= 0 then cur.row = math.max(1, cur.row - 1) end
  if input & DOWN ~= 0 then cur.row = math.min(#col, cur.row + 1) end
  if input & (LEFT | RIGHT) ~= 0 then
    local to = math.max(1, math.min(#l.columns, cur.col + ((input & LEFT ~= 0) and -1 or 1)))
    if to ~= cur.col then
      -- the Digimon at the nearest height in the next column
      local y, best, bd = before.y, 1, math.huge
      for i, it in ipairs(l.columns[to]) do
        local dd = math.abs(it.y - y)
        if dd < bd then best, bd = i, dd end
      end
      cur.col, cur.row = to, best
    end
  end
  local now = selected(l)
  if now ~= before then call(PLAY_SOUND, 0, 2) end
  ctx:write16(CHART_SELECTED_DIGIMON, now.d.type)
  return now
end

-- RECTs for the detail page's zoom, in the call frame (above its arguments).
local function rect(ctx, at, x, y, w, h)
  ctx:write16(at, x & 0xFFFF); ctx:write16(at + 2, y & 0xFFFF); ctx:write16(at + 4, w & 0xFFFF); ctx:write16(at + 6, h & 0xFFFF)
  return at
end

local function tick(call, ctx, frame, l)
  local state = ctx:read8(MENU_STATE)
  if state == 2 then
    local now = move(call, ctx, l)
    if call(IS_KEY_DOWN, CONFIRM) ~= 0 then
      if call(HAS_DIGIMON_RAISED, now.d.type) ~= 0 then
        if call(IS_UI_BOX_AVAILABLE, 2) == 1 then
          local final = rect(ctx, frame + 0x40, -0x96, -0x59, 0x12c, 0xbe)
          local start = rect(ctx, frame + 0x48, now.x - 0x9b, now.y - 0x70, 10, 10)
          ctx:write16(MAIN_D_80134D46, 0)
          call(CREATE_ANIMATED_UI_BOX, 2, 1, 0, final, start, 0, RENDER_CHART_DETAIL)
          call(PLAY_SOUND, 0, 3)
          ctx:write8(MENU_STATE, 3)
        end
      else
        call(PLAY_SOUND, 0, 4)
      end
    end
  elseif state == 3 then
    if call(IS_KEY_DOWN, CANCEL) ~= 0 then
      local now = selected(l)
      call(REMOVE_ANIMATED_UI_BOX, 2, rect(ctx, frame + 0x40, now.x - 0x9b, now.y - 0x70, 10, 10))
      call(PLAY_SOUND, 0, 3)
      ctx:write8(MENU_STATE, 2)
    end
  end
end

-- --- the detail page -----------------------------------------------------------------
-- Screen pixels (the page box spans 10..310 x 31..221). The game's panels
-- were 130 high from y 43, the centre box at 136, 85 with the stage and name
-- low on the left; here the panels run to the page's bottom, the centre box
-- sits at their middle and the stage and name are centred under it.
local PANEL_TOP, PANEL_H, PANEL_W = 43, 170, 78
local LEFT_X, RIGHT_X = 28, 214
local MID_Y = PANEL_TOP + PANEL_H // 2          -- 128: the centre icon's middle
local CENTRE_BOX = { 136, MID_Y - 23, 48, 46 }
local STAGE_Y, NAME_Y = MID_Y + 29, MID_Y + 48  -- text tops (12 high); their lines 9 lower
local STAGE_LINE_W, NAME_LINE_W = 96, 104
local TITLE_LINE = { 129, 50, 60, 4 }           -- under "Tree", as the game's
-- The stage names in the page's text area {w, u, v} by level (the US
-- game's own renderString calls; a stage without one shows none).
local STAGE_TEXT = { { 0x2e, 0x24, 0x18 }, { 0x3e, 0x52, 0x18 }, { 0x2f, 0, 0x24 }, { 0x41, 0x2f, 0x24 }, { 0x41, 0, 0x3c } }
local PITCH, MIN_PITCH = 19, 8                  -- frames apart, as on the chart
local INSET = 7                                 -- an icon's distance from its panel's sides
local ARC_STEP = 18                             -- the game's step in per row from the middle

-- A Digimon's lists: the stored ones (centred, 0xFF gaps) in order, then the
-- extra ones the mod keeps.
local function detail_lists(ctx, t)
  local at = tables.entry("EVOLUTION_PATHS", t)
  local from, to = {}, {}
  for i = 0, 4 do local v = ctx:read8(at + i); if v ~= 0xFF then from[#from + 1] = v end end
  for i = 5, 10 do local v = ctx:read8(at + i); if v ~= 0xFF then to[#to + 1] = v end end
  for _, v in ipairs(evolution.extra_from[t] or {}) do from[#from + 1] = v end
  for _, v in ipairs(evolution.extra[t] or {}) do to[#to + 1] = v end
  return from, to
end

-- Entry i of n in a side's column (coordinates from the screen's middle):
-- {x, y, size, line points}. Rows PITCH apart around the centre icon's
-- height, closer and smaller once they'd leave the panel; the middle rows
-- outermost and each row from the middle stepped in (at most ARC_STEP, less
-- if the column would reach the panel's other side). Lines leave each frame
-- level, turn 45 degrees and reach the centre icon, 3 apart (or closer).
local function detail_place(side_from, i, n)
  local room = PANEL_H - 2 * 4 - (16 + 2)
  local p = n > 1 and math.max(MIN_PITCH, math.min(PITCH, room // (n - 1))) or PITCH
  local size = math.min(16, p - 3)
  local c = (n + 1) / 2
  local mid = MID_Y - 120 + (i - c) * p          -- this row's middle
  local y = math.floor(mid - size / 2 + 0.5)
  local yi = y + size // 2
  local dist = math.abs(i - c)
  local fd, F = math.floor(dist), math.max(1, math.floor((n - 1) / 2))
  local span = PANEL_W - 2 * INSET - size
  local off = math.floor(math.min(ARC_STEP, span / F) * fd + 0.5)
  local e = math.floor(8 + (i - c) * (n > 1 and math.min(3, 14 / (n - 1)) or 0) + 0.5)
  local bend = math.floor(36 * (F - fd) / F + 0.5)
  local dy = math.abs(yi - e)
  if side_from then
    local x = LEFT_X - 160 + INSET + off
    local sx, x3 = x + size + 1, -10 - bend
    return { x = x, y = y, size = size, slot = (i - 1) % 6,
      line = { sx, yi, math.max(sx, x3 - dy), yi, x3, e, -10, e } }
  end
  local x = RIGHT_X + PANEL_W - 160 - INSET - size - off
  local xa = 9 + bend
  return { x = x, y = y, size = size, slot = (i - 1) % 6,
    line = { 9, e, xa, e, math.min(x - 2, xa + dy), yi, x - 2, yi } }
end

-- An icon `size` big at x, y (from the screen's middle) for type t.
local function detail_icon(ctx, t, x, y, size)
  if t <= 61 then
    local b = EVO_CHART_BOXES + 8 * (t - 1)
    local clut = ctx:read16(EVO_CHART_DETAIL_COLORS + 2 * ctx:read8(b + 6))
    sprite(ctx, x, y, size, size, ctx:read8(b + 4), ctx:read8(b + 5), 0x10, 0x10, 0x18, clut, 4)
  elseif M.icons[t] then
    local ic = M.icons[t]
    sprite(ctx, x, y, size, size, ic.u, ic.v, 0x10, 0x10, ic.tpage, ic.clut, 4)
  end
end

local function frame_box(call, x, y, size)
  call(RENDER_BORDER_BOX, x - 1 + 160, y - 1 + 120, size + 2, size + 2, 0xbebebe, 0x3c3c3c, 0x87, 0x87, 0x87, 4)
end

-- The width in pixels of the text at `at`, as drawString lays it out (the
-- letters' own advances; ' and . are its two special cases), or nil.
local name_widths = {}
local mega_width = nil
local function text_width(call, ctx, at)
  local w, i = 0, 0
  while i < 20 do
    local b = ctx:read8(at + i)
    if b == 0 then return w end
    local code
    if b < 0x80 then
      code = b == 0x2E and 0x8142 or b == 0x27 and 0x8175 or call(ASCII_TO_SJIS, b) & 0xFFFF
      i = i + 1
    else
      code = (b << 8) | ctx:read8(at + i + 1)
      i = i + 2
    end
    code = call(SJIS_TO_FONT, code) & 0xFFFF
    local key, k = ((code & 0xFF) << 8) | (code >> 8), 0
    while k < 80 and ctx:read16(FONT_CODES + 2 * k) ~= key do k = k + 1 end
    if k == 80 then return nil end
    w = w + ctx:read16(FONT_GLYPHS + 24 * k + 22)
  end
  return w
end

-- In the game's order (lines, icons, the centre, text, the sunken frames
-- last: the ordering table draws what's added later underneath).
local function draw_detail(call, ctx, t)
  ctx:write8(MENU_SUB_STATE, 2)
  call(DRAW_CHART_STRINGS, t) -- the name into the page's text area
  local from, to = detail_lists(ctx, t)
  for side = 1, 2 do
    local list, side_from = side == 1 and from or to, side == 1
    for i, id in ipairs(list) do
      local pl = detail_place(side_from, i, #list)
      local l = pl.line
      local dark, light
      if side_from then
        dark, light = FROM_LINE_DARK, FROM_LINE_LIGHT
      else
        local function rgb(k)
          local a = CHART_TO_LINE_COLORS + 3 * k
          return ctx:read8(a) | (ctx:read8(a + 1) << 8) | (ctx:read8(a + 2) << 16)
        end
        light, dark = rgb(pl.slot * 2), rgb(pl.slot * 2 + 1)
      end
      for dy = -1, 1 do
        local col = dy == 0 and light or dark
        call(DRAW_LINE_3P, col, l[1], l[2] + dy, l[3], l[4] + dy, l[5], l[6] + dy, 4, 0)
        call(DRAW_LINE_2P, col, l[5], l[6] + dy, l[7], l[8] + dy, 4, 0)
      end
      if call(HAS_DIGIMON_RAISED, id) ~= 0 then detail_icon(ctx, id, pl.x, pl.y, pl.size) end
      frame_box(call, pl.x, pl.y, pl.size)
    end
  end
  -- the selected Digimon in the centre box
  local cy = MID_Y - 8 - 120
  detail_icon(ctx, t, -8, cy, 16)
  frame_box(call, -8, cy, 16)
  -- "Tree", the stage and the name
  call(RENDER_STRING, 3, -0x14, -0x4f, 0x24, 0xc, 0, 0x18, 4, 0)
  local data = tables.entry("DIGIMON_DATA", t)
  local stage = M.stage[t] or ctx:read8(data + 29)
  local st = STAGE_TEXT[stage]
  if stage == 6 then
    -- the game has no "Mega": drawn into the text area's free rows
    ctx:write_bytes(tables.TEXT, "Mega ")
    call(DRAW_STRING, tables.TEXT, 0, MEGA_TEXT_V)
    mega_width = mega_width or text_width(call, ctx, tables.TEXT) or 0x30
    call(RENDER_STRING, 0, -(mega_width // 2), STAGE_Y - 120, mega_width, 0xc, 0, MEGA_TEXT_V, 4, 0)
  elseif st then
    call(RENDER_STRING, 0, -(st[1] // 2), STAGE_Y - 120, st[1], 0xc, st[2], st[3], 4, 0)
  end
  if not name_widths[t] then name_widths[t] = text_width(call, ctx, data) or 0x78 end
  local w = math.min(name_widths[t], 0x78)
  call(RENDER_STRING, 0, -(w // 2), NAME_Y - 120, w, 0xc, 0, 0x30, 4, 0)  -- the sunken frames
  for _, b in ipairs({
    { LEFT_X, PANEL_TOP, PANEL_W, PANEL_H }, { RIGHT_X, PANEL_TOP, PANEL_W, PANEL_H }, CENTRE_BOX, TITLE_LINE,
    { 160 - STAGE_LINE_W // 2, STAGE_Y + 9, STAGE_LINE_W, 4 }, { 160 - NAME_LINE_W // 2, NAME_Y + 9, NAME_LINE_W, 4 },
  }) do
    call(RENDER_INSET_BOX, b[1], b[2], b[3], b[4], 4)
  end
end

-- new_types: the mod's new Digimon (their DIGIMON_DATA level says the stage)
function M.install(new_types)
  -- A body gets `call` and a ctx that always reaches the current hook's
  -- (a hook's ctx only lasts that hook; each call comes back through a new one).
  local function runner(body)
    return function(ctx0, _, frame)
      local current = ctx0
      local function call(fn, ...)
        local c, v0 = coroutine.yield({ fn, ... })
        current = c
        return v0 & 0xFFFFFFFF
      end
      local ctx = setmetatable({}, { __index = function(_, k)
        return function(_, ...) return current[k](current, ...) end
      end })
      layout = layout or build_layout(ctx, new_types)
      body(call, ctx, frame)
    end
  end
  caller(RENDER_CHART, function(ctx)
    if ctx:read8(MENU_STATE) == 0 then dirty = true; return nil end -- the game sets the page up
    return runner(function(call, cx) draw(call, cx, layout) end)
  end, function(saved) return saved[31] end)
  caller(CHART_TICK, function(ctx)
    if ctx:read8(PLAYER_MENU_STATE) ~= 1 then return nil end
    return runner(function(call, cx, frame) tick(call, cx, frame, layout) end)
  end, function() return CHART_TICK_END end)

  -- The detail page, all drawn here (the game's code is skipped).
  caller(RENDER_CHART_DETAIL, function(ctx)
    return runner(function(call, cx) draw_detail(call, cx, cx:read_s16(CHART_SELECTED_DIGIMON)) end)
  end, function(saved) return saved[31] end)
  -- drawEvoChartStrings gets the type as a signed byte (its name on the
  -- detail page): a type of 128 and up comes in negative.
  dwrc.on_exec(DRAW_CHART_STRINGS, function(ctx)
    if ctx:reg("a0") >= 0x80000000 then ctx:set_reg("a0", ctx:read_s16(CHART_SELECTED_DIGIMON) & 0xFFFF) end
    return false
  end)
end

return M
