-- Vemmon's small sprites in the menus' sprite sheets.
--
-- The menus draw the partners from sprite sheets (gfx.h SpriteDrawer): a
-- sheet ("..CS.BIN", an archive entry) lists parts (rectangles of its
-- texture, with a CLUT position) and frames made of parts, found by a frame
-- id; its texture ("..TM.BIN") is an archive of 4-bit TIMs (RLEN-packed)
-- that the game's TIM loader puts side by side in VRAM, 0x40 halfwords
-- apart, from a position the menu sets (timLoaderLoadArchive); the CLUTs
-- are rows of the same images. Each menu has a table of every partner's
-- animation (frame ids), which partner.lua extends to Vemmon.
--
-- Vemmon's frames come from its own field sprite on the player's disc
-- (P148SNAC, file 995: frames 6-8, its side-on idle, turned to face east),
-- with that sprite's CLUT. For a sheet the
-- mod finds room in its texture that no part of the sheet uses and that
-- holds one plain value (the images' unused areas), puts each frame and
-- the CLUT there, and adds parts and frames (with new frame ids) to the
-- sheet.

local bin = require("lib.bin")
local disc = require("lib.disc")

local M = {}

M.FIELD_SPRITE_FILE = 995
M.FRAMES = { 6, 7, 8 }              -- entries of the field sprite file: its side-on idle (facing west)
M.MIRROR = true                     -- turned to face east
M.FRONT_FRAME = 12                  -- facing the camera (12-14): the helmet's red triangle, the visor, green eyes

-- Archives ---------------------------------------------------------------

-- An archive's entries: u32 offsets from its start (count = first / 4);
-- an offset of 0 is an absent entry (or the end of a list of TIMs).
function M.read_archive(data)
  local count = bin.u32(data, 0) // 4
  local offs = {}
  for i = 0, count - 1 do offs[i] = bin.u32(data, 4 * i) end
  local list = {}
  for i = 0, count - 1 do
    local o = offs[i]
    if o == 0 then
      list[i + 1] = false
    else
      local e = #data
      for j = 0, count - 1 do
        if offs[j] > o and offs[j] < e then e = offs[j] end
      end
      list[i + 1] = data:sub(o + 1, e)
    end
  end
  return list
end

-- Entries (false = absent) -> archive bytes, entries 4-aligned.
function M.build_archive(list)
  local head = 4 * #list
  local offs, body, pos = {}, {}, head
  for i, e in ipairs(list) do
    if e then
      offs[i] = string.pack("<I4", pos)
      local padded = bin.pad(e, 4)
      body[#body + 1] = padded
      pos = pos + #padded
    else
      offs[i] = string.pack("<I4", 0)
    end
  end
  return table.concat(offs) .. table.concat(body)
end

-- RLEN ------------------------------------------------------------------

-- "RLEN", the unpacked size, then runs: 0x80|n and a byte (n copies), or n
-- and n bytes; 0 ends.
function M.rlen_unpack(e)
  local out, i = {}, 9
  while i <= #e do
    local c = e:byte(i)
    if c == 0 then break end
    if c & 0x80 ~= 0 then
      out[#out + 1] = string.rep(e:sub(i + 1, i + 1), c & 0x7F)
      i = i + 2
    else
      out[#out + 1] = e:sub(i + 1, i + c)
      i = i + 1 + c
    end
  end
  return table.concat(out)
end

function M.rlen_pack(data)
  local out = { "RLEN", string.pack("<I4", #data) }
  local lit_from = nil
  local function flush(upto)
    while lit_from and lit_from <= upto do
      local n = math.min(upto - lit_from + 1, 127)
      out[#out + 1] = string.char(n) .. data:sub(lit_from, lit_from + n - 1)
      lit_from = lit_from + n
      if lit_from > upto then lit_from = nil end
    end
  end
  local i, n = 1, #data
  while i <= n do
    local c = data:byte(i)
    local j = i
    while j < n and j - i < 126 and data:byte(j + 1) == c do j = j + 1 end
    if j - i + 1 >= 3 then
      if lit_from then flush(i - 1) end
      out[#out + 1] = string.char(0x80 | (j - i + 1), c)
      i = j + 1
    else
      lit_from = lit_from or i
      i = i + 1
    end
  end
  if lit_from then flush(n) end
  out[#out + 1] = "\0"
  return table.concat(out)
end

-- TIMs -------------------------------------------------------------------

-- A TIM (plain or RLEN-packed) -> { mode, clut = {colors}, w (halfwords), h, pixels }
function M.read_tim(e)
  if e:sub(1, 4) == "RLEN" then e = M.rlen_unpack(e) end
  assert(bin.u32(e, 0) == 0x10, "not a TIM")
  local flags = bin.u32(e, 4)
  local p = 8
  local t = { mode = flags & 7 }
  if flags & 8 ~= 0 then
    local ln, cw = bin.u32(e, p), bin.u16(e, p + 8)
    t.clut = {}
    for i = 0, cw - 1 do t.clut[i] = bin.u16(e, p + 12 + 2 * i) end
    p = p + ln
  end
  t.w, t.h = bin.u16(e, p + 8), bin.u16(e, p + 10)
  t.pixels = e:sub(p + 13, p + 12 + t.w * t.h * 2)
  return t
end

local function px4(t, x, y)
  local b = t.pixels:byte(y * t.w * 2 + (x >> 1) + 1)
  if x & 1 == 0 then return b & 15 end
  return b >> 4
end

-- Vemmon's frames -------------------------------------------------------

-- { w (pixels), h, frames = { rows of pixel indices }, clut = { 16 colors } }
local art
function M.art()
  if art then return art end
  local list = M.read_archive(disc.read_file(M.FIELD_SPRITE_FILE))
  art = { frames = {} }
  for k, entry in ipairs(M.FRAMES) do
    local t = M.read_tim(list[entry + 1])
    assert(t.mode == 0, "Vemmon's field frames aren't 4-bit")
    art.w, art.h, art.clut = t.w * 4, t.h, t.clut
    local rows = {}
    for y = 0, t.h - 1 do
      local r = {}
      local last = t.w * 4 - 1
      for x = 0, last do r[x] = px4(t, M.MIRROR and last - x or x, y) end
      rows[y] = r
    end
    art.frames[k] = rows
  end
  return art
end

-- Sheets -----------------------------------------------------------------

-- A sheet -> { parts = {{u, v, w, h, cx, cy, mode}}, ids = {byte}, frames = {{row, semi, items = {{part, x, y}}}} }
function M.read_sheet(s)
  local o_parts, o_ids = bin.u32(s, 0), bin.u32(s, 4)
  local count = (math.min(o_parts, o_ids) - 8) // 4
  local frame_offs = {}
  for i = 0, count - 1 do frame_offs[i + 1] = bin.u32(s, 8 + 4 * i) end
  local sh = { parts = {}, ids = {}, frames = {} }
  local parts_end = #s
  for _, o in ipairs(frame_offs) do if o > o_parts and o < parts_end then parts_end = o end end
  if o_ids > o_parts and o_ids < parts_end then parts_end = o_ids end
  for q = o_parts, parts_end - 14, 14 do
    sh.parts[#sh.parts + 1] = { string.unpack("<hhhhhhh", s, q + 1) }
  end
  local i = o_ids
  while s:byte(i + 1) ~= 0xFF do
    sh.ids[#sh.ids + 1] = s:byte(i + 1)
    i = i + 1
  end
  for _, o in ipairs(frame_offs) do
    local n, row, semi = string.unpack("<hhh", s, o + 1)
    local items = {}
    for k = 0, n - 1 do items[#items + 1] = { string.unpack("<hhh", s, o + 7 + 6 * k) } end
    sh.frames[#sh.frames + 1] = { row = row, semi = semi, items = items }
  end
  assert(#sh.ids == #sh.frames, "a sheet with " .. #sh.ids .. " ids and " .. #sh.frames .. " frames")
  return sh
end

function M.build_sheet(sh)
  local n = #sh.frames
  local head = 8 + 4 * n
  local parts = {}
  for _, p in ipairs(sh.parts) do parts[#parts + 1] = string.pack("<hhhhhhh", table.unpack(p, 1, 7)) end
  parts = bin.pad(table.concat(parts), 4)
  local ids = {}
  for _, id in ipairs(sh.ids) do ids[#ids + 1] = string.char(id) end
  ids = bin.pad(table.concat(ids) .. "\255", 4)
  local o_parts = head
  local o_ids = o_parts + #parts
  local pos = o_ids + #ids
  local offs, body = {}, {}
  for i, f in ipairs(sh.frames) do
    offs[i] = string.pack("<I4", pos)
    local items = {}
    for _, it in ipairs(f.items) do items[#items + 1] = string.pack("<hhh", table.unpack(it, 1, 3)) end
    local rec = bin.pad(string.pack("<hhh", #f.items, f.row, f.semi) .. table.concat(items), 4)
    body[#body + 1] = rec
    pos = pos + #rec
  end
  return string.pack("<I4I4", o_parts, o_ids) .. table.concat(offs) .. parts .. ids .. table.concat(body)
end

-- An unused frame id of a sheet (from the top).
local function free_id(sh, taken)
  local used = {}
  for _, id in ipairs(sh.ids) do used[id] = true end
  for id = 0xFE, 0, -1 do
    if not used[id] and not taken[id] then return id end
  end
  error("a sheet with no free frame id")
end

-- Textures ---------------------------------------------------------------

-- A texture archive's images as halfword grids, where the loader puts them:
-- { x, y (VRAM), w, h, hw = {[y * w + x] = value}, raw, at, packed }
local function load_images(list, load_x, load_y)
  local imgs = {}
  for i, e in ipairs(list) do
    if not e then break end
    local packed = e:sub(1, 4) == "RLEN"
    local raw = packed and M.rlen_unpack(e) or e
    assert(bin.u32(raw, 0) == 0x10, "not a TIM")
    local flags = bin.u32(raw, 4)
    local p = 8
    if flags & 8 ~= 0 then p = p + bin.u32(raw, p) end
    local w, h = bin.u16(raw, p + 8), bin.u16(raw, p + 10)
    local hw = {}
    for k = 0, w * h - 1 do hw[k] = bin.u16(raw, p + 12 + 2 * k) end
    imgs[i] = { x = load_x + 0x40 * (i - 1), y = load_y, w = w, h = h, hw = hw, raw = raw, at = p + 12, packed = packed, changed = false }
  end
  return imgs
end

local function save_image(img, original)
  if not img.changed then return original end
  local parts = {}
  for k = 0, img.w * img.h - 1 do parts[k + 1] = string.pack("<I2", img.hw[k]) end
  local raw = img.raw:sub(1, img.at) .. table.concat(parts) .. img.raw:sub(img.at + img.w * img.h * 2 + 1)
  return img.packed and M.rlen_pack(raw) or raw
end

-- The halfwords (VRAM y * 1024 + x) the sheets' parts and CLUTs use.
local function used_halfwords(sheets, tex_x, tex_y)
  local used = {}
  for _, sh in ipairs(sheets) do
    for _, p in ipairs(sh.parts) do
      local u, v, w, h, cx, cy, mode = table.unpack(p, 1, 7)
      local per = mode == 0 and 4 or 2
      for y = tex_y + v, tex_y + v + h - 1 do
        for x = tex_x + u // per, tex_x + (u + w + per - 1) // per - 1 do used[y * 1024 + x] = true end
      end
      for x = tex_x + cx, tex_x + cx + (mode == 0 and 15 or 255) do used[(tex_y + cy) * 1024 + x] = true end
    end
  end
  return used
end

-- A free w x h halfword rectangle (x aligned to `align`): no part uses it
-- and it holds one value, 0 or 0xFFFF. Marks it used.
local function find_room(imgs, used, w, h, align)
  for _, img in ipairs(imgs) do
    for y = 0, img.h - h do
      for x = 0, img.w - w, align do
        local fill = img.hw[y * img.w + x]
        if fill == 0 or fill == 0xFFFF then
          local ok = true
          for yy = y, y + h - 1 do
            for xx = x, x + w - 1 do
              if img.hw[yy * img.w + xx] ~= fill or used[(img.y + yy) * 1024 + img.x + xx] then ok = false break end
            end
            if not ok then break end
          end
          if ok then
            for yy = y, y + h - 1 do
              for xx = x, x + w - 1 do used[(img.y + yy) * 1024 + img.x + xx] = true end
            end
            return img, x, y
          end
        end
      end
    end
  end
  return nil
end

-- Adds Vemmon's frames to a menu's sheet and texture. `spec`:
--   sheet_file, sheet_entry: the sheet (an entry of an archive file)
--   tex_file, tex_entry: the texture archive the menu loads (an entry of an
--     archive file, a list of TIMs ending with a 0 offset)
--   load_x, load_y: where the menu's TIM loader starts that archive
--   tex_x, tex_y: the sprite drawer's setTexture position for the sheet
--   like: a frame id of the sheet whose offsets Vemmon's frames copy
--   dx, dy: added to those offsets
-- Returns Vemmon's frame ids, one per frame.
function M.add(spec)
  local a = M.art()
  local sheets_raw = M.read_archive(disc.read_file(spec.sheet_file))
  local sheets = {}
  for _, e in ipairs(sheets_raw) do
    if e and #e >= 12 then
      local ok, sh = pcall(M.read_sheet, e)
      if ok then sheets[#sheets + 1] = sh end
    end
  end
  local sh = M.read_sheet(sheets_raw[spec.sheet_entry + 1])
  local used = used_halfwords(sheets, spec.tex_x, spec.tex_y)

  local tex = M.read_archive(disc.read_file(spec.tex_file))
  local list = M.read_archive(tex[spec.tex_entry + 1])
  local imgs = load_images(list, spec.load_x, spec.load_y)
  if spec.extra_image then
    -- a texture with no room: one more TIM in the archive, which the loader
    -- puts 0x40 halfwords right of the last (a VRAM column the menu must not
    -- use); the drawer takes each part's page from its u, so parts there
    -- have u >= 256
    local w, h = spec.extra_image[1], spec.extra_image[2]
    local raw = string.pack("<I4I4I4I2I2I2I2", 0x10, 2, 12 + w * h * 2, 0, 0, w, h) .. string.rep("\0", w * h * 2)
    local hw = {}
    for k = 0, w * h - 1 do hw[k] = 0 end
    table.insert(list, #imgs + 1, raw)
    imgs[#imgs + 1] = { x = spec.load_x + 0x40 * #imgs, y = spec.load_y, w = w, h = h, hw = hw, raw = raw, at = 20,
      packed = true, changed = true }
  end

  -- the CLUT, then each frame (6 halfwords x 32 rows for 24 pixels)
  local cimg, cx, cy = find_room(imgs, used, 16, 1, 16)
  assert(cimg, "no room for Vemmon's CLUT in file " .. spec.tex_file)
  for i = 0, 15 do cimg.hw[cy * cimg.w + cx + i] = a.clut[i] or 0 end
  cimg.changed = true
  local fw = (a.w + 3) // 4
  local cells = {}
  for k, rows in ipairs(a.frames) do
    local img, x, y = find_room(imgs, used, fw, a.h, 1)
    assert(img, "no room for Vemmon's frame " .. k .. " in file " .. spec.tex_file)
    for yy = 0, a.h - 1 do
      for xx = 0, fw - 1 do
        local v = 0
        for n = 0, 3 do v = v | ((rows[yy][xx * 4 + n] or 0) << (4 * n)) end
        img.hw[(y + yy) * img.w + x + xx] = v
      end
    end
    img.changed = true
    cells[k] = { img.x + x, img.y + y }
  end
  for i, img in ipairs(imgs) do list[i] = save_image(img, list[i]) end
  tex[spec.tex_entry + 1] = M.build_archive(list)
  disc.replace_file(spec.tex_file, M.build_archive(tex))

  -- the sheet: a part and a frame for each of Vemmon's frames
  local like
  for i, id in ipairs(sh.ids) do if id == spec.like then like = sh.frames[i] end end
  assert(like, "no frame " .. spec.like .. " in sheet " .. spec.sheet_file)
  local base = like.items[#like.items]
  local ids, taken = {}, {}
  for k, cell in ipairs(cells) do
    local u, v = (cell[1] - spec.tex_x) * 4, cell[2] - spec.tex_y
    assert(v >= 0 and v + a.h <= 256 and u >= 0, "Vemmon's frame is outside the sheet's texture page")
    sh.parts[#sh.parts + 1] = { u, v, a.w, a.h, cimg.x + cx - spec.tex_x, cimg.y + cy - spec.tex_y, 0 }
    local id = free_id(sh, taken)
    taken[id] = true
    sh.ids[#sh.ids + 1] = id
    sh.frames[#sh.frames + 1] = {
      row = 0, semi = -1,
      items = { { #sh.parts - 1, base[2] + (32 - a.w) // 2 + (spec.dx or 0), base[3] + (spec.dy or 0) } },
    }
    ids[k] = id
  end
  sheets_raw[spec.sheet_entry + 1] = M.build_sheet(sh)
  disc.replace_file(spec.sheet_file, M.build_archive(sheets_raw))
  return ids
end

-- Save list cards -------------------------------------------------------

-- The halfword at VRAM (x, y) of the loaded images.
local function vram_hw(imgs, x, y)
  for _, img in ipairs(imgs) do
    if x >= img.x and x < img.x + img.w and y >= img.y and y < img.y + img.h then
      return img.hw[(y - img.y) * img.w + x - img.x]
    end
  end
  return 0
end

-- Vemmon's card colours: the label's and stripes' indices of Agumon's card
-- (2 and 7 the label, 9 the stripes, 8, 13, 14 the card) in purple, and a
-- purple ramp for the portrait (1, 3-6, 12) with its red (10, 15) and
-- green (11).
local CARD_CLUT = {
  [0] = 0x0000, { 40, 24, 72 }, { 88, 40, 136 }, { 64, 40, 112 }, { 96, 64, 152 }, { 136, 96, 192 }, { 176, 144, 224 },
  { 152, 104, 208 }, { 200, 200, 200 }, { 200, 168, 240 }, { 200, 48, 64 }, { 0, 200, 96 }, { 224, 208, 240 },
  { 224, 224, 224 }, { 248, 248, 248 }, { 136, 0, 48 },
}
-- the field frame's colours -> the card's
local CARD_MAP = { [1] = 4, [2] = 1, [3] = 11, [4] = 1, [5] = 10, [6] = 6, [7] = 4, [8] = 5, [9] = 3, [10] = 1, [11] = 5,
  [12] = 15, [13] = 12, [14] = 6, [15] = 12 }

local function rgb555(c)
  if type(c) == "number" then return c end
  return (c[1] >> 3) | ((c[2] >> 3) << 5) | ((c[3] >> 3) << 10)
end

-- Adds Vemmon's card to a save list's sheet: frame `spec.base`'s card (a
-- 4-bit picture: the portrait left of x 29 above y 19, stripes right of it,
-- the "DIGIMON" label below) with the portrait cleared and Vemmon's head
-- from its front-facing field frame drawn there. spec: as add's (sheet,
-- texture, positions). Returns the new frame's id.
function M.add_icon(spec)
  local sheets_raw = M.read_archive(disc.read_file(spec.sheet_file))
  local sheets = {}
  for _, e in ipairs(sheets_raw) do
    if e and #e >= 12 then
      local ok, sh = pcall(M.read_sheet, e)
      if ok then sheets[#sheets + 1] = sh end
    end
  end
  local sh = M.read_sheet(sheets_raw[spec.sheet_entry + 1])
  local used = used_halfwords(sheets, spec.tex_x, spec.tex_y)
  local tex = M.read_archive(disc.read_file(spec.tex_file))
  local list = M.read_archive(tex[spec.tex_entry + 1])
  local imgs = load_images(list, spec.load_x, spec.load_y)

  local base
  for i, id in ipairs(sh.ids) do if id == spec.base then base = sh.frames[i] end end
  assert(base and #base.items == 1, "no card frame " .. spec.base .. " in sheet " .. spec.sheet_file)
  local item = base.items[1]
  local u0, v0, w, h = table.unpack(sh.parts[item[1] + 1], 1, 4)
  assert(w % 4 == 0, "a card not a whole number of halfwords wide")
  local px = {}
  for y = 0, h - 1 do
    px[y] = {}
    for x = 0, w - 1 do
      local word = vram_hw(imgs, spec.tex_x + (u0 + x) // 4, spec.tex_y + v0 + y)
      px[y][x] = (word >> (((u0 + x) & 3) * 4)) & 15
    end
  end
  for y = 0, 18 do
    for x = 0, 28 do
      local c = px[y][x]
      if c ~= 0 and c ~= 8 and c ~= 13 then px[y][x] = 14 end
    end
  end
  local field = M.read_archive(disc.read_file(M.FIELD_SPRITE_FILE))
  local t = M.read_tim(field[M.FRONT_FRAME + 1])
  for y = 2, math.min(19, t.h - 1) do
    for x = 0, t.w * 4 - 1 do
      local c = px4(t, x, y)
      if c ~= 0 and x + 2 <= 28 then px[y - 1][x + 2] = CARD_MAP[c] end
    end
  end

  local cimg, cx, cy = find_room(imgs, used, 16, 1, 16)
  assert(cimg, "no room for Vemmon's card CLUT in file " .. spec.tex_file)
  for i = 0, 15 do cimg.hw[cy * cimg.w + cx + i] = rgb555(CARD_CLUT[i]) end
  cimg.changed = true
  local img, ix, iy = find_room(imgs, used, w // 4, h, 1)
  assert(img, "no room for Vemmon's card in file " .. spec.tex_file)
  for y = 0, h - 1 do
    for x = 0, w // 4 - 1 do
      local v = 0
      for n = 0, 3 do v = v | (px[y][x * 4 + n] << (4 * n)) end
      img.hw[(iy + y) * img.w + ix + x] = v
    end
  end
  img.changed = true
  for i, im in ipairs(imgs) do list[i] = save_image(im, list[i]) end
  tex[spec.tex_entry + 1] = M.build_archive(list)
  disc.replace_file(spec.tex_file, M.build_archive(tex))

  sh.parts[#sh.parts + 1] = { (img.x + ix - spec.tex_x) * 4, img.y + iy - spec.tex_y, w, h,
    cimg.x + cx - spec.tex_x, cimg.y + cy - spec.tex_y, 0 }
  local id = free_id(sh, {})
  sh.ids[#sh.ids + 1] = id
  sh.frames[#sh.frames + 1] = { row = 0, semi = base.semi, items = { { #sh.parts - 1, item[2], item[3] } } }
  sheets_raw[spec.sheet_entry + 1] = M.build_sheet(sh)
  disc.replace_file(spec.sheet_file, M.build_archive(sheets_raw))
  return id
end

-- Digivolve Chart icons -------------------------------------------------

M.CHART_BACK = 0x0421               -- the icons' near-black (their CLUTs' entry 0)

-- Adds Vemmon's icon to the Lab's chart sheet: 32x32 8-bit parts (mode 1),
-- each with its own 256-colour CLUT row at the drawer's setAltClut position,
-- whose y the drawer lowers by 0x100. Vemmon's is its front-facing field
-- frame centred on the icons' near-black; it uses indices 0-15 only, so its
-- CLUT needs 16 halfwords and goes in the texture's unused room like the
-- picture. spec: as add's, plus clut_x, clut_y (setAltClut). Returns the
-- new frame's id.
function M.add_chart_icon(spec)
  local sheets_raw = M.read_archive(disc.read_file(spec.sheet_file))
  local sh = M.read_sheet(sheets_raw[spec.sheet_entry + 1])
  local used = used_halfwords({ sh }, spec.tex_x, spec.tex_y)
  local tex = M.read_archive(disc.read_file(spec.tex_file))
  local list = M.read_archive(tex[spec.tex_entry + 1])
  local imgs = load_images(list, spec.load_x, spec.load_y)

  local field = M.read_archive(disc.read_file(M.FIELD_SPRITE_FILE))
  local t = M.read_tim(field[M.FRONT_FRAME + 1])
  local fw, fh = t.w * 4, t.h
  -- the frame's opaque box, so the picture is centred on what's drawn
  local x0, x1, y0, y1 = fw, -1, fh, -1
  for y = 0, fh - 1 do
    for x = 0, fw - 1 do
      if px4(t, x, y) ~= 0 then
        x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
      end
    end
  end
  assert(x1 >= 0, "Vemmon's front frame is empty")
  local dx = (32 - (x1 - x0 + 1)) // 2 - x0
  local dy = (32 - (y1 - y0 + 1)) // 2 - y0
  local px = {}
  for y = 0, 31 do
    px[y] = {}
    for x = 0, 31 do
      local sx, sy = x - dx, y - dy
      px[y][x] = (sx >= 0 and sx < fw and sy >= 0 and sy < fh) and px4(t, sx, sy) or 0
    end
  end

  local cimg, cx, cy = find_room(imgs, used, 16, 1, 16)
  assert(cimg, "no room for Vemmon's chart CLUT in file " .. spec.tex_file)
  for i = 0, 15 do
    local c = i == 0 and M.CHART_BACK or (t.clut[i] or 0)
    if c == 0 then c = 0x8000 end                -- opaque black
    cimg.hw[cy * cimg.w + cx + i] = c
  end
  cimg.changed = true
  local img, ix, iy = find_room(imgs, used, 16, 32, 1)
  assert(img, "no room for Vemmon's chart icon in file " .. spec.tex_file)
  for y = 0, 31 do
    for x = 0, 15 do img.hw[(iy + y) * img.w + ix + x] = px[y][2 * x] | (px[y][2 * x + 1] << 8) end
  end
  img.changed = true
  for i, im in ipairs(imgs) do list[i] = save_image(im, list[i]) end
  tex[spec.tex_entry + 1] = M.build_archive(list)
  disc.replace_file(spec.tex_file, M.build_archive(tex))

  sh.parts[#sh.parts + 1] = { (img.x + ix - spec.tex_x) * 2, img.y + iy - spec.tex_y, 32, 32,
    cimg.x + cx - spec.clut_x, cimg.y + cy - spec.clut_y + 0x100, 1 }
  local id = free_id(sh, {})
  sh.ids[#sh.ids + 1] = id
  sh.frames[#sh.frames + 1] = { row = 0, semi = -1, items = { { #sh.parts - 1, 0, 0 } } }
  sheets_raw[spec.sheet_entry + 1] = M.build_sheet(sh)
  disc.replace_file(spec.sheet_file, M.build_archive(sheets_raw))
  return id
end

return M
