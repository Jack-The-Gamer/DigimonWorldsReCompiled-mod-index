-- Vemmon's exercise animations in the gyms, drawn from its battle model
-- while the mod loads (render.lua).
--
-- A training file (TRANIN##.BIN) starts with 9 offsets: image sets 0-7
-- (the partners, Guilmon's is 5) and 8 (the effect). A set: {count, bank,
-- anims[6], images[count - 7]}, then the offset of the bank's first sprite
-- (from the bank) and the bank's size. Bank {801, 0, sprite count}, then
-- sprites: a count and that many parts {u8 u, v, x, y; u16 clut (bits 6-14
-- the CLUT row, 15 semi-transparent); u16 tpage (bits 0-4 the image, its
-- page; 5-8 getTPage's abr and depth); u16 w, h; 4 s16 nothing reads},
-- drawn last to first. Animations {0x124, frame count, frames {s16 sprite,
-- u8 ticks, pad, s16 x, y}}: 0 and 1 the training, 2 it worked, 3 it
-- didn't, 4 and 5 the ends (optional). Images: 256x256 4-bit TIMs (RLEN)
-- that the gym loads 0x40 halfwords apart, each with its CLUT block (16
-- rows) at the CLUT position plus 16 x its number; a part's image numbers
-- past the set's own reach the effect set's, loaded right after.
--
-- Guilmon's sprites are pieces (bodies, heads, tails) in its colours, in
-- tinted copies (silhouettes, a ghost, a poisoned purple) and props
-- (splashes, sparks, swooshes). Vemmon's set copies Guilmon's animations
-- (timing and movement, which the effect set follows) and sprites, with
-- each sprite's Guilmon pieces replaced by one picture of Vemmon standing
-- where they stood, in its colours or the same tint. Its first image holds
-- the pictures and the props that were in Guilmon's; its second is
-- Guilmon's (props). The gym reads it in place of Guilmon's when Vemmon
-- trains (partner.lua).

local render = require("lib.render")
local sprites = require("lib.sprites")
local disc = require("lib.disc")
local bin = require("lib.bin")

local M = {}

M.MODEL_FILE = 1821              -- M465SNAT: the enemy Vemmon (fighter 0x1D1)
M.MODEL_BONES = 46
M.MODEL_MOTIONS = 0
M.GUILMON = 5
M.VIEW = { yaw = 0.5, pitch = -0.3, ss = 2, ambient = 0.5, light = { -0.5, -0.7, -0.6 }, cull = 1 }   -- three-quarters, facing right, from a little above
M.OUTLINE = 0x181020               -- the dark line around each picture, as the game's sprites have
M.SIZE = 1.0                     -- Vemmon's height to Guilmon's standing frame's

-- Vemmon's motion for each animation: idle (0) to start, its claw lunge
-- (16) as the effort, arms out (15) when it works, a hit (14) when it
-- doesn't, its other idle (1) and a stagger (4) at the ends.
M.ANIM_MOTIONS = { [0] = 0, [1] = 16, [2] = 15, [3] = 14, [4] = 1, [5] = 4 }

-- The training files, and the kinds of Guilmon's parts ("image:row:semi")
-- that are Guilmon: "G" its colours, "T" a tinted Guilmon, "t" the same
-- where the kind also has small props (parts under 768 pixels stay).
-- Every other kind is a prop and stays.
M.FILES = {
  [606] = { ["0:0:0"] = "G", ["0:0:1"] = "G", ["1:0:0"] = "G" },
  [1086] = { ["0:0:0"] = "G" },
  [640] = { ["0:0:0"] = "G", ["0:1:0"] = "T" },
  [641] = { ["0:0:0"] = "G", ["1:0:0"] = "T" },
  [642] = { ["0:0:0"] = "G", ["1:2:0"] = "T" },
  [643] = { ["0:0:0"] = "G", ["0:1:0"] = "T" },
  [770] = { ["0:0:0"] = "G", ["0:0:1"] = "G" },
  [771] = { ["0:0:0"] = "G", ["0:0:1"] = "G", ["0:4:1"] = "T" },
  [1087] = { ["0:0:0"] = "G", ["0:1:0"] = "T" },
  [644] = { ["0:0:0"] = "G", ["0:1:1"] = "T", ["0:3:0"] = "t", ["0:3:1"] = "t", ["1:0:0"] = "T" },
  [645] = { ["0:0:0"] = "G", ["0:2:1"] = "t" },
  [772] = { ["0:0:0"] = "G", ["0:1:0"] = "T", ["0:1:1"] = "T" },
}
M.ORDER = { 606, 1086, 640, 641, 642, 643, 770, 771, 1087, 644, 645, 772 }
local SMALL = 768

local function u32(s, o) return (string.unpack("<I4", s, o + 1)) end

-- A TIM (maybe RLEN): flags, CLUT block (position, size, rows) and image
-- block (position, size in halfwords, 4-bit texels as [v * 256 + u]).
local function read_tim(data, o)
  local t = data:sub(o + 1, o + 0x20000)
  if t:sub(1, 4) == "RLEN" then t = sprites.rlen_unpack(t) end
  local tim = { flags = u32(t, 4), clut = {}, clut_w = 16, clut_h = 0, clut_x = 0, clut_y = 0 }
  local p = 8
  if tim.flags & 8 ~= 0 then
    tim.clut_x, tim.clut_y, tim.clut_w, tim.clut_h = string.unpack("<I2I2I2I2", t, p + 5)
    for r = 0, tim.clut_h - 1 do
      local row = {}
      for i = 0, tim.clut_w - 1 do row[i] = bin.u16(t, p + 12 + 2 * (r * tim.clut_w + i)) end
      tim.clut[r] = row
    end
    p = p + u32(t, p)
  end
  tim.x, tim.y, tim.w, tim.h = string.unpack("<I2I2I2I2", t, p + 5)
  tim.px = {}
  local at = p + 12
  for v = 0, tim.h - 1 do
    for x = 0, tim.w - 1 do
      local hw = bin.u16(t, at + 2 * (v * tim.w + x))
      for k = 0, 3 do tim.px[v * 256 + x * 4 + k] = (hw >> (4 * k)) & 15 end
    end
  end
  return tim
end

local function write_tim(tim)
  local out = { string.pack("<I4I4", 0x10, tim.flags) }
  if tim.flags & 8 ~= 0 then
    out[#out + 1] = string.pack("<I4I2I2I2I2", 12 + 2 * tim.clut_w * tim.clut_h, tim.clut_x, tim.clut_y, tim.clut_w, tim.clut_h)
    for r = 0, tim.clut_h - 1 do
      for i = 0, tim.clut_w - 1 do out[#out + 1] = string.pack("<I2", tim.clut[r][i] or 0) end
    end
  end
  out[#out + 1] = string.pack("<I4I2I2I2I2", 12 + 2 * tim.w * tim.h, tim.x, tim.y, tim.w, tim.h)
  for v = 0, tim.h - 1 do
    for x = 0, tim.w - 1 do
      local o = v * 256 + x * 4
      out[#out + 1] = string.pack("<I2", tim.px[o] | (tim.px[o + 1] << 4) | (tim.px[o + 2] << 8) | (tim.px[o + 3] << 12))
    end
  end
  return sprites.rlen_pack(table.concat(out))
end

-- Set `s` of a training file.
local function read_set(data, s)
  local so = u32(data, 4 * s)
  local set = { at = so }
  set.count, set.bank = string.unpack("<i4I4", data, so + 1)
  set.anims, set.images = {}, {}
  for i = 0, 5 do set.anims[i] = u32(data, so + 8 + 4 * i) end
  for i = 0, set.count - 8 do set.images[i] = u32(data, so + 0x20 + 4 * i) end
  set.bank_off = u32(data, so + 4 * (set.count + 1))
  set.head = data:sub(set.bank + 1, set.bank + 8)
  local n = bin.u16(data, set.bank + 4)
  set.sprites = {}
  local p = set.bank + set.bank_off
  for i = 0, n - 1 do
    local c = bin.s32(data, p)
    p = p + 4
    local parts = {}
    for j = 1, c do
      local u, v, x, y, clut, tp, w, h = string.unpack("<BBBBI2I2I2I2", data, p + 1)
      parts[j] = { u = u, v = v, x = x, y = y, clut = clut, tp = tp, w = w, h = h, extra = data:sub(p + 13, p + 20) }
      p = p + 20
    end
    set.sprites[i] = parts
  end
  set.frames = {}
  for i = 0, 5 do
    local a = set.anims[i]
    if a ~= 0 then
      local unk, fc = string.unpack("<i2i2", data, a + 1)
      local frames = { unk = unk }
      for k = 0, fc - 1 do
        local sp, ticks, x, y = string.unpack("<i2Bxi2i2", data, a + 4 + 8 * k + 1)
        frames[k + 1] = { sprite = sp, ticks = ticks, x = x, y = y }
      end
      set.frames[i] = frames
    end
  end
  return set
end

local function kind(p) return string.format("%d:%d:%d", p.tp & 31, (p.clut >> 6) & 0x1FF, p.clut >> 15) end

-- A part's role: "G", "T" (Vemmon, in its colours or tinted) or nil (a prop).
local function role(roles, set, p)
  if (p.tp & 31) > set.count - 8 then return nil end
  local r = roles[kind(p)]
  if r == "t" then return p.w * p.h >= SMALL and "T" or nil end
  return r
end

-- 15-bit colours ----------------------------------------------------------

local function c15(rgb) return ((rgb >> 19) & 31) | (((rgb >> 11) & 31) << 5) | (((rgb >> 3) & 31) << 10) end

-- Median cut of weighted 15-bit colours into n.
local function median_cut(hist, n)
  local boxes = { {} }
  -- weights flattened (square roots), so small details (eyes, marks) get colours of their own
  for c, w in pairs(hist) do boxes[1][#boxes[1] + 1] = { c & 31, (c >> 5) & 31, (c >> 10) & 31, math.sqrt(w) } end
  while #boxes < n do
    local best, bi, bch = -1, nil, nil
    for i, b in ipairs(boxes) do
      if #b > 1 then
        for ch = 1, 3 do
          local lo, hi, tw = 99, -1, 0
          for _, e in ipairs(b) do
            if e[ch] < lo then lo = e[ch] end
            if e[ch] > hi then hi = e[ch] end
            tw = tw + e[4]
          end
          local score = (hi - lo) * tw
          if score > best then best, bi, bch = score, i, ch end
        end
      end
    end
    if not bi then break end
    local b = boxes[bi]
    table.sort(b, function(x, y) return x[bch] < y[bch] end)
    local total, acc, cut = 0, 0, 1
    for _, e in ipairs(b) do total = total + e[4] end
    for i, e in ipairs(b) do
      acc = acc + e[4]
      if acc * 2 >= total then cut = math.min(i, #b - 1) break end
    end
    local left, right = {}, {}
    for i, e in ipairs(b) do if i <= cut then left[#left + 1] = e else right[#right + 1] = e end end
    boxes[bi] = left
    boxes[#boxes + 1] = right
  end
  local pal = {}
  for i, b in ipairs(boxes) do
    local r, g, bl, tw = 0, 0, 0, 0
    for _, e in ipairs(b) do r, g, bl, tw = r + e[1] * e[4], g + e[2] * e[4], bl + e[3] * e[4], tw + e[4] end
    pal[i] = { math.floor(r / tw + 0.5), math.floor(g / tw + 0.5), math.floor(bl / tw + 0.5) }
  end
  return pal
end

local function nearest(pal, c)
  local r, g, b = c & 31, (c >> 5) & 31, (c >> 10) & 31
  local best, bi = math.huge, 1
  for i, p in ipairs(pal) do
    local d = (p[1] - r) ^ 2 * 3 + (p[2] - g) ^ 2 * 4 + (p[3] - b) ^ 2 * 2
    if d < best then best, bi = d, i end
  end
  return bi
end

local function luma(c) return 0.3 * (c & 31) + 0.59 * ((c >> 5) & 31) + 0.11 * ((c >> 10) & 31) end

-- Vemmon's palette in a tint of Guilmon's colours (`from` -> `to`): per
-- channel, the line that best takes one to the other, where lines fit and
-- rise (a tint: dimmed, faded); else by brightness, along a ramp from the
-- tinted colours' darkest third to their lightest (a silhouette, an
-- X-ray, frozen pale).
local function tint(pal, from, to)
  local pairs_ = {}
  for i = 1, 15 do
    if (from[i] or 0) ~= 0 and (to[i] or 0) ~= 0 then pairs_[#pairs_ + 1] = { from[i] & 0x7FFF, to[i] & 0x7FFF } end
  end
  local out = {}
  local lines, err = {}, 0
  for ch = 0, 2 do
    local sx, sy, sxx, sxy, n = 0, 0, 0, 0, #pairs_
    for _, q in ipairs(pairs_) do
      local x, y = (q[1] >> (5 * ch)) & 31, (q[2] >> (5 * ch)) & 31
      sx, sy, sxx, sxy = sx + x, sy + y, sxx + x * x, sxy + x * y
    end
    local a, b = 1, 0
    if n > 1 and n * sxx - sx * sx ~= 0 then
      a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
      b = (sy - a * sx) / n
    elseif n > 0 then
      a, b = 0, sy / n
    end
    for _, q in ipairs(pairs_) do
      local x, y = (q[1] >> (5 * ch)) & 31, (q[2] >> (5 * ch)) & 31
      err = err + (a * x + b - y) ^ 2
    end
    lines[ch] = { a, b }
  end
  local rising = true
  for ch = 0, 2 do if lines[ch][1] < 0.2 then rising = false end end
  if #pairs_ > 0 and rising and math.sqrt(err / (3 * #pairs_)) <= 2 then
    for i, p in ipairs(pal) do
      local c = 0
      for ch = 0, 2 do
        local v = math.max(0, math.min(31, math.floor(lines[ch][1] * p[ch + 1] + lines[ch][2] + 0.5)))
        c = c | (v << (5 * ch))
      end
      out[i] = c
    end
  else
    -- a ramp from the tinted colours' darkest third to their lightest
    local cs = {}
    for _, q in ipairs(pairs_) do cs[#cs + 1] = q[2] end
    table.sort(cs, function(x, y) return luma(x) < luma(y) end)
    local third = math.max(1, #cs // 3)
    local function mean(i0, i1)
      local r, g, b = 0, 0, 0
      for i = i0, i1 do r, g, b = r + (cs[i] & 31), g + ((cs[i] >> 5) & 31), b + ((cs[i] >> 10) & 31) end
      local n = i1 - i0 + 1
      return { r / n, g / n, b / n }
    end
    local dark, light = mean(1, third), mean(#cs - third + 1, #cs)
    local own, vlo, vhi = {}, math.huge, -math.huge
    for i, p in ipairs(pal) do
      own[i] = luma(p[1] | (p[2] << 5) | (p[3] << 10))
      vlo, vhi = math.min(vlo, own[i]), math.max(vhi, own[i])
    end
    for i in ipairs(pal) do
      local t = vhi > vlo and (own[i] - vlo) / (vhi - vlo) or 0.5
      local c = 0
      for ch = 1, 3 do
        c = c | (math.floor(dark[ch] + (light[ch] - dark[ch]) * t + 0.5) << (5 * (ch - 1)))
      end
      out[i] = c
    end
  end
  local stp = 0
  for i = 1, 15 do if (to[i] or 0) & 0x8000 ~= 0 then stp = stp + 1 end end
  for i = 1, #pal do
    if out[i] == 0 then out[i] = 0x0421 end
    if stp > 7 then out[i] = out[i] | 0x8000 end
  end
  return out
end

-- Packing -----------------------------------------------------------------

-- A page of placed pictures: the props' texels (a summed-area table, made
-- once) and the pictures placed since.
local function new_page(used)
  local S, sat = 257, {}
  for i = 0, 256 do sat[i * S] = 0 sat[i] = 0 end
  for y = 1, 256 do
    local row = 0
    for x = 1, 256 do
      if used[(y - 1) * 256 + x - 1] then row = row + 1 end
      sat[y * S + x] = sat[(y - 1) * S + x] + row
    end
  end
  return { sat = sat, rects = {} }
end

-- The first spot (top to bottom, left to right) for a w x h picture on a
-- page; marks it taken.
local function place(page, w, h)
  local S, sat, rects = 257, page.sat, page.rects
  for y = 0, 256 - h do
    local x = 0
    while x <= 256 - w do
      local hit
      for _, r in ipairs(rects) do
        if x < r[1] + r[3] and r[1] < x + w and y < r[2] + r[4] and r[2] < y + h then hit = r break end
      end
      if hit then
        x = hit[1] + hit[3]
      elseif sat[(y + h) * S + x + w] - sat[y * S + x + w] - sat[(y + h) * S + x] + sat[y * S + x] ~= 0 then
        x = x + 1
      else
        rects[#rects + 1] = { x, y, w, h }
        return x, y
      end
    end
  end
end

-- Building ----------------------------------------------------------------

local function bbox(parts)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(parts) do
    x0, y0 = math.min(x0, p.x), math.min(y0, p.y)
    x1, y1 = math.max(x1, p.x + p.w), math.max(y1, p.y + p.h)
  end
  return x0, y0, x1, y1
end

-- Each file's Guilmon set and the scale that makes Vemmon M.SIZE times
-- Guilmon's standing height (its first frame's Guilmon parts).
local function plan(n, unit_height)
  local data = disc.read_file(n)
  local set = read_set(data, M.GUILMON)
  local job = { n = n, data = data, set = set, roles = M.FILES[n], images = {} }
  for i = 0, set.count - 8 do job.images[i] = read_tim(data, set.images[i]) end
  local g = {}
  for _, p in ipairs(set.sprites[set.frames[0][1].sprite]) do
    if role(job.roles, set, p) then g[#g + 1] = p end
  end
  local _, gy0, _, gy1 = bbox(g)
  job.scale = (gy1 - gy0) * M.SIZE / unit_height
  -- each animation's distinct sprites, in the order they first show
  job.order = {}
  for a = 0, 5 do
    local frames = set.frames[a]
    if frames then
      local order, seen = {}, {}
      for _, f in ipairs(frames) do
        if not seen[f.sprite] then
          seen[f.sprite] = true
          order[#order + 1] = f.sprite
        end
      end
      job.order[a] = order
    end
  end
  return job
end

-- Which frame of Vemmon's motion each sprite of each animation shows, with
-- at most `budget` pictures in all: an animation of n sprites gets its
-- share k of them, k poses spread over the motion, n / k sprites each.
local function poses(job, model, budget)
  local total = 0
  for _, order in pairs(job.order) do total = total + #order end
  job.poses = {}
  for a, order in pairs(job.order) do
    local n = #order
    local k = math.max(1, math.min(n, budget * n // total))
    local f0, f1 = render.motion_span(model, M.ANIM_MOTIONS[a])
    local pose = {}
    for i, s in ipairs(order) do
      local j = (i - 1) * k // n
      -- on even frames, so files share pictures
      pose[s] = k == 1 and f0 or f0 + (f1 - f0) * j // (k - 1) // 2 * 2
    end
    job.poses[a] = pose
  end
end

-- Vemmon's set for a file (planned, posed, pictures drawn): the file's new
-- bytes, the set's offset and its sprite and picture counts; nil when the
-- pictures don't fit.
local function build_set(job, pal)
  local set, roles, data = job.set, job.roles, job.data
  local base = job.images[0].clut[0]

  -- the images: each keeps its props' texels; a placeholder (smaller than a
  -- page) becomes a whole page
  local imgs, used, prop_rows = {}, {}, {}
  for i, src in pairs(job.images) do
    local img = { flags = src.flags | 8, clut_x = src.clut_x, clut_y = src.clut_y, clut_w = 16,
      clut_h = math.max(16, src.clut_h), clut = {}, x = src.x, y = src.y, w = 64, h = 256, px = {} }
    if src.flags & 8 == 0 then img.clut_x = 16 * i end
    for r = 0, img.clut_h - 1 do img.clut[r] = src.clut[r] or {} end
    for o = 0, 65535 do img.px[o] = 0 end
    imgs[i], used[i], prop_rows[i] = img, {}, {}
  end
  for _, parts in pairs(set.sprites) do
    for _, p in ipairs(parts) do
      local i = p.tp & 31
      if imgs[i] and not role(roles, set, p) then
        prop_rows[i][(p.clut >> 6) & 0x1FF] = true
        local src = job.images[i]
        for y = p.v, math.min(255, p.v + p.h - 1) do
          for x = p.u, math.min(255, p.u + p.w - 1) do
            imgs[i].px[y * 256 + x] = src.px[y * 256 + x] or 0
            used[i][y * 256 + x] = true
          end
        end
      end
    end
  end

  -- CLUT rows, by image and colours ("base" or a tinted kind), in rows no
  -- prop uses
  local stp = 0
  for i = 1, 15 do if (base[i] or 0) & 0x8000 ~= 0 then stp = stp + 1 end end
  local own = { [0] = 0 }
  for i = 1, 15 do
    local p = pal[i] or pal[#pal]
    local c = p[1] | (p[2] << 5) | (p[3] << 10)
    if c == 0 then c = 0x0421 end
    own[i] = stp > 7 and (c | 0x8000) or c
  end
  local rows = {}
  local function row_for(i, colours)
    rows[i] = rows[i] or {}
    if rows[i][colours] then return rows[i][colours] end
    local free
    for r = 0, imgs[i].clut_h - 1 do
      local taken = prop_rows[i][r]
      for _, t in pairs(rows[i]) do if t == r then taken = true end end
      if not taken then free = r break end
    end
    assert(free, "no free CLUT row in training file " .. job.n)
    local row
    if colours == "base" then
      row = own
    else
      local img, r = colours:match("^(%d+):(%d+)")
      local target = job.images[tonumber(img)].clut[tonumber(r)]
      row = tint(pal, base, target)
      row[0] = 0
    end
    imgs[i].clut[free] = row
    rows[i][colours] = free
    return free
  end

  -- the pictures, tallest first, in the first image with room
  local frames = {}
  for _, pose in pairs(job.poses) do
    for _, f in pairs(pose) do frames[f] = true end
  end
  local list = {}
  for f in pairs(frames) do list[#list + 1] = { f = f, pic = job.pictures[f] } end
  table.sort(list, function(a, b)
    if a.pic.h ~= b.pic.h then return a.pic.h > b.pic.h end
    return a.f < b.f
  end)
  local at, cache, pages = {}, {}, {}
  for i = 0, #imgs do pages[i] = new_page(used[i]) end
  for _, e in ipairs(list) do
    local pic = e.pic
    local x, y, i
    for k = 0, #imgs do
      x, y = place(pages[k], pic.w, pic.h)
      if x then i = k break end
    end
    if not x then return nil end
    for yy = 0, pic.h - 1 do
      for xx = 0, pic.w - 1 do
        local o = (y + yy) * 256 + x + xx
        local c = pic.px[yy * pic.w + xx]
        if c then
          local k = c15(c)
          local n = cache[k]
          if not n then
            n = nearest(pal, k)
            cache[k] = n
          end
          imgs[i].px[o] = n
        end
      end
    end
    at[e.f] = { i = i, u = x, v = y, w = pic.w, h = pic.h }
  end

  -- the sprites: Guilmon's parts out, Vemmon's picture in
  local new_sprites, index = {}, {}
  local function sprite_bytes(parts)
    local out = { string.pack("<i4", #parts) }
    for _, p in ipairs(parts) do
      out[#out + 1] = string.pack("<BBBBI2I2I2I2", p.u, p.v, p.x, p.y, p.clut, p.tp, p.w, p.h) .. p.extra
    end
    return table.concat(out)
  end
  local function new_sprite(s, f)
    local parts = set.sprites[s]
    local g, out, first = {}, {}, nil
    for i, p in ipairs(parts) do
      if role(roles, set, p) then
        g[#g + 1] = p
        if not first then first = i end
      end
    end
    if #g > 0 then
      local big = g[1]
      for _, p in ipairs(g) do if p.w * p.h > big.w * big.h then big = p end end
      local x0, _, x1, y1 = bbox(g)
      local pic = at[f]
      local colours = role(roles, set, big) == "T" and kind(big) or "base"
      local row = row_for(pic.i, colours)
      local vx = math.max(0, math.min(255 - pic.w, math.floor((x0 + x1 - pic.w) / 2 + 0.5)))
      local vy = math.max(0, math.min(255 - pic.h, y1 - pic.h))
      for i, p in ipairs(parts) do
        if i == first then
          out[#out + 1] = { u = pic.u, v = pic.v, x = vx, y = vy, clut = (row << 6) | (big.clut & 0x8000),
            tp = (big.tp & 0xFFE0) | pic.i, w = pic.w, h = pic.h, extra = big.extra }
        end
        if not role(roles, set, p) then out[#out + 1] = p end
      end
    else
      out = parts
    end
    local b = sprite_bytes(out)
    if not index[b] then
      new_sprites[#new_sprites + 1] = b
      index[b] = #new_sprites - 1
    end
    return index[b]
  end
  local anims = {}
  for a = 0, 5 do
    local fr = set.frames[a]
    if fr then
      local out = { string.pack("<i2i2", fr.unk, #fr) }
      for _, f in ipairs(fr) do
        out[#out + 1] = string.pack("<i2Bxi2i2", new_sprite(f.sprite, job.poses[a][f.sprite]), f.ticks, f.x, f.y)
      end
      anims[a] = table.concat(out)
    end
  end

  -- the set at the file's end: header, bank, animations, images
  local nimg = set.count - 7
  local start = (#data + 3) & ~3
  local bank = table.concat(new_sprites)
  local bank_head = set.head:sub(1, 4) .. string.pack("<I2", #new_sprites) .. "\0\0"
  local pos = start + 0x20 + 4 * nimg + 8
  local bank_at = pos
  pos = pos + #bank_head + #bank
  local anim_at, blobs = {}, {}
  for a = 0, 5 do
    if anims[a] then
      anim_at[a] = pos
      blobs[#blobs + 1] = bin.pad(anims[a], 4)
      pos = pos + #blobs[#blobs]
    else
      anim_at[a] = 0
    end
  end
  local image_at = {}
  for i = 0, nimg - 1 do
    image_at[i] = pos
    blobs[#blobs + 1] = bin.pad(write_tim(imgs[i]), 4)
    pos = pos + #blobs[#blobs]
  end
  local head = { string.pack("<i4I4", set.count, bank_at) }
  for a = 0, 5 do head[#head + 1] = string.pack("<I4", anim_at[a]) end
  for i = 0, nimg - 1 do head[#head + 1] = string.pack("<I4", image_at[i]) end
  head[#head + 1] = string.pack("<I4I4", #bank_head, #bank_head + #bank)
  local out = data .. string.rep("\0", start - #data) .. table.concat(head) .. bank_head .. bank .. table.concat(blobs)
  return out, start, #new_sprites, #list
end

-- A picture with a one-pixel outline around what it shows.
local function outline(pic)
  local w, h = pic.w + 2, pic.h + 2
  local px = {}
  for o, c in pairs(pic.px) do px[(o // pic.w + 1) * w + o % pic.w + 1] = c end
  local edge = {}
  for o in pairs(px) do
    for _, d in ipairs({ -1, 1, -w, w }) do
      local q = o + d
      if not px[q] then edge[q] = true end
    end
  end
  for o in pairs(edge) do px[o] = M.OUTLINE end
  return { w = w, h = h, px = px }
end

-- The texels a file's set has for Vemmon: its images' (a placeholder
-- counts as a whole page) less the props'.
local function room(job)
  local free = 0
  for i in pairs(job.images) do
    local used, n = {}, 0
    for _, parts in pairs(job.set.sprites) do
      for _, p in ipairs(parts) do
        if (p.tp & 31) == i and not role(job.roles, job.set, p) then
          for y = p.v, math.min(255, p.v + p.h - 1) do
            for x = p.u, math.min(255, p.u + p.w - 1) do
              if not used[y * 256 + x] then
                used[y * 256 + x] = true
                n = n + 1
              end
            end
          end
        end
      end
    end
    free = free + 65536 - n
  end
  return free
end

-- Renders, colours and writes Vemmon's sets; returns { [file] = set offset }.
function M.build(log)
  local model = render.load(disc.read_file(M.MODEL_FILE), M.MODEL_BONES, M.MODEL_MOTIONS)
  local view = { yaw = M.VIEW.yaw, pitch = M.VIEW.pitch, ss = M.VIEW.ss, ambient = M.VIEW.ambient, cull = M.VIEW.cull,
    light = M.VIEW.light }
  local idle = render.motion_span(model, 0)
  local unit_height = render.trim(render.draw(model, idle, { yaw = view.yaw, pitch = view.pitch, scale = 1, ss = 1 })).h

  -- one scale for every file: Guilmon's usual standing height
  local jobs, counts = {}, {}
  for _, n in ipairs(M.ORDER) do
    local job = plan(n, unit_height)
    jobs[#jobs + 1] = job
    counts[job.scale] = (counts[job.scale] or 0) + 1
  end
  local scale, most = nil, 0
  for s, c in pairs(counts) do
    if c > most or (c == most and s < scale) then scale, most = s, c end
  end
  view.scale = scale

  local hist, drawn = {}, {}
  local function draw_all(job)
    for _, pose in pairs(job.poses) do
      for _, f in pairs(pose) do
        if not drawn[f] then
          local pic = outline(render.trim(render.draw(model, f, view)))
          drawn[f] = pic
          if hist then
            for _, c in pairs(pic.px) do
              local k = c15(c)
              hist[k] = (hist[k] or 0) + 1
            end
          end
        end
      end
    end
    job.pictures = drawn
  end
  -- each file's first try: as many pictures as its room holds, by the
  -- size of Vemmon standing
  local stand = outline(render.trim(render.draw(model, idle, view)))
  for _, job in ipairs(jobs) do
    local total = 0
    for _, order in pairs(job.order) do total = total + #order end
    job.budget = math.max(6, math.min(total, room(job) // (stand.w * stand.h)))
    poses(job, model, job.budget)
    draw_all(job)
  end
  local pal = median_cut(hist, 15)
  hist = nil

  local offsets = {}
  for _, job in ipairs(jobs) do
    while true do
      local data, at, nsprites, npics = build_set(job, pal)
      if data then
        disc.replace_file(job.n, data)
        offsets[job.n] = at
        if log then log(string.format("training file %d: %d pictures, %d sprites", job.n, npics, nsprites)) end
        break
      end
      job.budget = job.budget * 9 // 10
      assert(job.budget >= 6, "no room for Vemmon's pictures in training file " .. job.n)
      poses(job, model, job.budget)
      draw_all(job)
    end
  end
  return offsets
end

-- The gym overlay (STGTRAIN) reads Vemmon's set when Vemmon trains: its
-- createActor(set, ...) gets partner 17 as Guilmon's set (5) and notes it
-- in a word of its own; readSet, where it takes the set's offset from the
-- file's table (`lw v0, 0(v1)`, v1 = file + set * 4, s0 = set), takes
-- Vemmon's for set 5 while that word is set, from a table by the gym's
-- file index (STGTRAIN_state.fileIndex) of the offsets build() returned.
local STGTRAIN_FILES = 0x8008CE3C      -- TrainFile {file, x, y, effectSameDepth}[25]
local FILE_INDEXES = 25
local FILE_INDEX = 0x8008CFD4          -- STGTRAIN_state.fileIndex
local CREATE_ACTOR = 0x8008A274        -- addiu sp, sp, -40; sw s0, 16(sp)
local READ_SET_OFFSET = 0x8008BDE4     -- lw v0, 0(v1); nop (load delay)

function M.install(offsets)
  local files = require("lib.files")
  local mips = require("lib.mips")
  local tables = require("lib.tables")
  local ext = require("lib.ext")
  local eu = require("lib.eu")
  local R = mips.R
  local ovl = files.overlay(eu.FILE_STGTRAIN)
  ovl.ext:align(4)
  local flag = ovl.ext:addr()
  ovl.ext:u32(0)
  local sets = ovl.ext:addr()
  for i = 0, FILE_INDEXES - 1 do ovl.ext:u32(offsets[ovl:read32(STGTRAIN_FILES + 16 * i)] or 0) end

  local actor = tables.routine("vemmon_gym_actor", {
    mips.lui(R.t0, mips.hi(flag)),
    mips.addiu(R.at, R.zero, ext.VEMMON_ID),
    mips.bne_to(R.a0, R.at, "other"),
    mips.sw(R.zero, mips.lo(flag), R.t0),
    mips.addiu(R.at, R.zero, 1),
    mips.sw(R.at, mips.lo(flag), R.t0),
    mips.addiu(R.a0, R.zero, M.GUILMON),
    "other",
    0x27BDFFD8,
    0xAFB00010,
    mips.j(CREATE_ACTOR + 8),
    mips.NOP,
  })
  files.patch32(eu.FILE_STGTRAIN, CREATE_ACTOR, 0x27BDFFD8, mips.j(actor))
  files.patch32(eu.FILE_STGTRAIN, CREATE_ACTOR + 4, 0xAFB00010, mips.NOP)

  local offset = tables.routine("vemmon_gym_set", {
    mips.lw(R.v0, 0, R.v1),
    mips.lui(R.t0, mips.hi(flag)),
    mips.lw(R.t0, mips.lo(flag), R.t0),
    mips.addiu(R.t1, R.zero, M.GUILMON),
    mips.beq_to(R.t0, R.zero, "done"),
    mips.NOP,
    mips.bne_to(R.s0, R.t1, "done"),
    mips.NOP,
    mips.lui(R.t0, mips.hi(FILE_INDEX)),
    mips.lw(R.t0, mips.lo(FILE_INDEX), R.t0),
    mips.lui(R.t1, mips.hi(sets)),
    mips.sll(R.t0, R.t0, 2),
    mips.addu(R.t1, R.t1, R.t0),
    mips.lw(R.t1, mips.lo(sets), R.t1),
    mips.NOP,
    mips.beq_to(R.t1, R.zero, "done"),
    mips.NOP,
    mips.addu(R.v0, R.t1, R.zero),
    "done",
    mips.jr(R.ra),
    mips.NOP,
  })
  files.patch32(eu.FILE_STGTRAIN, READ_SET_OFFSET, 0x8C620000, mips.jal(offset))
end

M.debug = { read_set = read_set, read_tim = read_tim }


return M
