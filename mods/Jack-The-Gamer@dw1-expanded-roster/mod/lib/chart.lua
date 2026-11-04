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
-- The detail page (renderEvoChartDetail 0x800BA930) is still the game's for
-- its text, frames and centre icon, but its two lists are drawn here: the
-- game has 5 places for the Digimon a Digimon comes from and 6 for those it
-- becomes, reads them as signed bytes (types 128 and up never show) and
-- takes icons from its 61 boxes. Here a list can be any length: the game's
-- own places while it fits, then the same arc spread to fit the page (the
-- icons shrink once they'd touch), with the entries past the stored 5 / 6
-- from evolution.extra_from / evolution.extra.

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
local DRAW_LINE_3P = 0x800E3D14     -- (color, x1, y1, x2, y2, x3, y3, depth, 0)
local DRAW_LINE_2P = 0x800E3E7C     -- (color, x1, y1, x2, y2, depth, 0)
local DRAW_CHART_STRINGS = 0x800C0718 -- drawEvoChartStrings(int8_t type)
local DETAIL_CENTRE_ICON = 0x800BAF1C -- renderEvoChartDetail: the selected Digimon's icon ...
local DETAIL_CENTRE_ICON_END = 0x800BAF8C -- ... up to its border box
local DETAIL_END = 0x800BB4D0       -- renderEvoChartDetail's epilogue (lw ra, 76(sp))
local EVO_CHART_DETAIL_COLORS = 0x80123E6C -- 5 CLUT ids for the detail page's icons
local CHART_FROM_SPRITES = { [0] = 0x80124AA8, [1] = 0x80124AC8 } -- even (4 places), odd (5), {s16 x, s16 y} per 8 bytes
local CHART_TO_SPRITES = { [0] = 0x80124AF0, [1] = 0x80124B20 }   -- even (6), odd (5)
local CHART_FROM_LINES = { [0] = 0x80124944, [1] = 0x80124984 }   -- {x1..x4, y1..y4} s16 per 16 bytes
local CHART_TO_LINES = { [0] = 0x801249D4, [1] = 0x80124A34 }
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
-- opens: {RECT address, data address} pairs (the page clears its text area,
-- where they live, when it sets up).
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
  for i = 0, 60 do
    local b = EVO_CHART_BOXES + 8 * i
    local level = ctx:read8(tables.entry("DIGIMON_DATA", i + 1) + 29)
    if level >= 1 and level <= 5 then
      local s = stages[level]
      s[#s + 1] = { type = i + 1, px = ctx:read_s16(b), py = ctx:read_s16(b + 2), u = ctx:read8(b + 4), v = ctx:read8(b + 5), clut = ctx:read8(b + 6) }
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
  local news = {}
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
    for _, up in ipairs(M.uploads) do call(LOAD_IMAGE, up[1], up[2]) end
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

-- --- the detail page's lists -------------------------------------------------------
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

-- Where list entry i of n goes, {x, y (top left of a 16 cell), size, line
-- points}: the game's own places and lines while the list fits them (5 or
-- 4 from, 5 or 6 to, centred as stored), else the same arc spread over the
-- page's height: rows 24 apart while they fit, the inner ones stepped 18
-- towards the middle per row from the centre (less when there are more
-- rows), lines leaving each icon level, turning 45 degrees and reaching the
-- centre icon 3 apart.
local function detail_place(ctx, side_from, i, n)
  local fits = side_from and n <= 5 or (not side_from and n <= 6)
  if fits then
    local odd = n % 2
    local span = odd == 1 and 5 or (side_from and 4 or 6)
    local slot = (span - n) // 2 + i - 1
    local sp = (side_from and CHART_FROM_SPRITES or CHART_TO_SPRITES)[odd] + 8 * slot
    local ln = (side_from and CHART_FROM_LINES or CHART_TO_LINES)[odd] + 16 * slot
    local p = {}
    for k = 0, 7 do p[k + 1] = ctx:read_s16(ln + 2 * k) end
    return { x = ctx:read_s16(sp), y = ctx:read_s16(sp + 2), size = 16, slot = slot,
      line = { p[1], p[5], p[2], p[6], p[3], p[7], p[4], p[8] } }
  end
  local step = math.min(24, 120 / (n - 1))
  local c = (n + 1) / 2
  local y = math.floor(-21 + (i - c) * step + 0.5)
  local size = math.min(16, math.floor(step) - 2)
  local dist = math.abs(i - c)
  local fd, F = math.floor(dist), math.max(2, math.floor((n - 1) / 2))
  local off = math.floor(18 * fd * 2 / F + 0.5)
  local e = math.floor(-12 + (i - c) * math.min(3, 15 / (n - 1)))
  local bend = math.floor(27 * (F - fd) * 2 / F + 0.5)
  local yi = y + 9
  local line
  if side_from then
    local x = -120 + off
    local sx, x3 = x + 18, -10 - bend
    local x2 = math.max(sx, x3 - math.abs(yi - e))
    line = { sx, yi, x2, yi, x3, e, -10, e }
    return { x = x, y = y, size = size, slot = (i - 1) % 6, line = line }
  end
  local x = 102 - off
  local xa = 9 + bend
  local xb = math.min(x - 2, xa + math.abs(e - yi))
  line = { 9, e, xa, e, xb, yi, x - 2, yi }
  return { x = x, y = y, size = size, slot = (i - 1) % 6, line = line }
end

-- An icon (16 cell at x, y; drawn `size` big in its middle) for type t.
local function detail_icon(call, ctx, t, x, y, size)
  local o = (16 - size) // 2
  if t <= 61 then
    local b = EVO_CHART_BOXES + 8 * (t - 1)
    local clut = ctx:read16(EVO_CHART_DETAIL_COLORS + 2 * ctx:read8(b + 6))
    sprite(ctx, x + o, y + o, size, size, ctx:read8(b + 4), ctx:read8(b + 5), 0x10, 0x10, 0x18, clut, 4)
  elseif M.icons[t] then
    local ic = M.icons[t]
    sprite(ctx, x + o, y + o, size, size, ic.u, ic.v, 0x10, 0x10, ic.tpage, ic.clut, 4)
  end
end

local function draw_detail(call, ctx, t)
  local from, to = detail_lists(ctx, t)
  for side = 1, 2 do
    local list, side_from = side == 1 and from or to, side == 1
    for i, id in ipairs(list) do
      local p = detail_place(ctx, side_from, i, #list)
      local l = p.line
      local dark, light
      if side_from then
        dark, light = FROM_LINE_DARK, FROM_LINE_LIGHT
      else
        local function rgb(k)
          local a = CHART_TO_LINE_COLORS + 3 * k
          return ctx:read8(a) | (ctx:read8(a + 1) << 8) | (ctx:read8(a + 2) << 16)
        end
        light, dark = rgb(p.slot * 2), rgb(p.slot * 2 + 1)
      end
      for dy = -1, 1 do
        local col = dy == 0 and light or dark
        call(DRAW_LINE_3P, col, l[1], l[2] + dy, l[3], l[4] + dy, l[5], l[6] + dy, 4, 0)
        call(DRAW_LINE_2P, col, l[5], l[6] + dy, l[7], l[8] + dy, 4, 0)
      end
      local o = (16 - p.size) // 2
      if call(HAS_DIGIMON_RAISED, id) ~= 0 then detail_icon(call, ctx, id, p.x, p.y, p.size) end
      call(RENDER_BORDER_BOX, p.x + o + 0x9f, p.y + o + 0x77, p.size + 2, p.size + 2, 0xbebebe, 0x3c3c3c, 0x87, 0x87, 0x87, 4)
    end
  end
  if t > 61 then detail_icon(call, ctx, t, -8, -20, 16) end -- the game's centre icon is skipped for it
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

  -- The detail page: the lists are drawn first, then the game's page runs
  -- with the selected Digimon's lists blanked (put back at its end), so it
  -- draws only its own parts.
  local passing, blanked = false, nil
  caller(RENDER_CHART_DETAIL, function(ctx)
    if passing then passing = false; return nil end
    return runner(function(call, cx)
      local t = cx:read_s16(CHART_SELECTED_DIGIMON)
      draw_detail(call, cx, t)
      local at = tables.entry("EVOLUTION_PATHS", t)
      blanked = { at = at, bytes = cx:read_bytes(at, 11) }
      cx:write_bytes(at, string.rep("\xFF", 11))
    end)
  end, function() passing = true; return RENDER_CHART_DETAIL end)
  dwrc.on_exec(DETAIL_END, function(ctx)
    if blanked then ctx:write_bytes(blanked.at, blanked.bytes); blanked = nil end
    return false
  end)
  -- A new Digimon's centre icon is drawn above; the game's would read past
  -- its 61 boxes.
  dwrc.on_exec(DETAIL_CENTRE_ICON, function(ctx)
    if ctx:read_s16(CHART_SELECTED_DIGIMON) <= 61 then return false end
    ctx:set_pc(DETAIL_CENTRE_ICON_END)
    return true
  end)
  -- drawEvoChartStrings gets the type as a signed byte (its name on the
  -- detail page): a type of 128 and up comes in negative.
  dwrc.on_exec(DRAW_CHART_STRINGS, function(ctx)
    if ctx:reg("a0") >= 0x80000000 then ctx:set_reg("a0", ctx:read_s16(CHART_SELECTED_DIGIMON) & 0xFFFF) end
    return false
  end)
end

return M
