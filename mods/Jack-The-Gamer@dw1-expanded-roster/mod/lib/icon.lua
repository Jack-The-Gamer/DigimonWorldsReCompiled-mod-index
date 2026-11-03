-- A Digivolution Chart icon for a new Digimon, drawn while the mod loads
-- from the model it built (lib/convert.lua: the polygons at the rest pose,
-- the texture and its CLUTs, all from the player's own disc), in the style
-- of the game's icons: 16 x 16, a three-quarter view facing left, a dark
-- outline, a few bold colours, and a second frame (the upper body one
-- pixel lower, a breath: the chart blinks between the two on the selected
-- Digimon).
--
-- The model is drawn 4 times bigger with a depth test and gentle lighting
-- (so its shape reads at that size), each 4 x 4 block becomes one pixel of
-- its most common colour, the colours are reduced to 14, and a 1-pixel
-- outline in the game's outline colour goes round it.

local M = {}

local SS = 4                         -- supersampling
local BOX = 14                       -- the figure's size inside the 16 x 16 icon (1 pixel of outline round it)
local OUTLINE = 0x0444               -- the game's icon outline colour (index 14 of the chart CLUTs)
local YAW, PITCH = math.rad(45), math.rad(15) -- turned to face left, seen a little from above
local SATURATION = 1.35              -- the game's icons are bold, flat colours
local COLOURS = 8                    -- besides transparent and the outline (the game's use about 6-8)
local INNER_EDGE = 0.1               -- a part this far in front of its neighbour (share of the height) gets an outline behind it
local SALIENT = 0.12                 -- weight for colours that stand out in a block (eyes, dark markings, claws)
local LIGHT = { -0.45, -0.65, -0.62 } -- from the top left, towards the viewer
do
  local l = math.sqrt(LIGHT[1] ^ 2 + LIGHT[2] ^ 2 + LIGHT[3] ^ 2)
  LIGHT = { LIGHT[1] / l, LIGHT[2] / l, LIGHT[3] / l }
end

-- model space (y down, -z the front) -> view (x right, y down, depth away)
local function view(p)
  local ca, sa, cp, sp = math.cos(YAW), math.sin(YAW), math.cos(PITCH), math.sin(PITCH)
  local x, y, z = p[1], p[2], p[3]
  local xr, zr = x * ca - z * sa, x * sa + z * ca
  return { -xr, y * cp - zr * sp, zr * cp + y * sp }
end

-- One frame: { [y][x] = {r, g, b} } on a BOX*SS square; `squash` shrinks
-- the height towards the feet.
local WHITE, GREY_SPREAD = 16, 6     -- white (or shaded white): every channel >= 16 (of 31), all within 6

local function draw(faces, px, fit, squash, no_white)
  local W = BOX * SS
  local col, depth = {}, {}
  local function texel(u, v)
    local h = string.unpack("<I2", px, (v * 64 + (u >> 2)) * 2 + 1)
    return (h >> ((u & 3) * 4)) & 15
  end
  local function clut(c, i) return string.unpack("<I2", px, (c + i) * 2 + 1) end
  local function screen(p)
    local v = view(p)
    local x = (v[1] - fit.x0) * fit.k + fit.dx
    local y = fit.bottom - (fit.bottom - ((v[2] - fit.y0) * fit.k + fit.dy)) * squash
    return { x, y, v[3] }
  end
  for _, f in ipairs(faces) do
    local s = {}
    for k = 1, #f.pts do s[k] = screen(f.pts[k]) end
    -- lighting: the face's normal turned towards the viewer
    local a, b, c = s[1], s[2], s[3]
    local e1 = { b[1] - a[1], b[2] - a[2], (b[3] - a[3]) * fit.k }
    local e2 = { c[1] - a[1], c[2] - a[2], (c[3] - a[3]) * fit.k }
    local n = { e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3], e1[1] * e2[2] - e1[2] * e2[1] }
    local nl = math.sqrt(n[1] ^ 2 + n[2] ^ 2 + n[3] ^ 2)
    local light = 1
    if nl > 0 then
      if n[3] > 0 then nl = -nl end
      local d = (n[1] * LIGHT[1] + n[2] * LIGHT[2] + n[3] * LIGHT[3]) / nl
      light = 0.85 + 0.25 * d
    end
    local drop_white = no_white and no_white[f.bone]
    local tris = { { 1, 2, 3 } }
    if #f.pts == 4 then tris[2] = { 2, 4, 3 } end
    for _, t in ipairs(tris) do
      local p0, p1, p2 = s[t[1]], s[t[2]], s[t[3]]
      local uv0, uv1, uv2 = f.uv[t[1]], f.uv[t[2]], f.uv[t[3]]
      local area = (p1[1] - p0[1]) * (p2[2] - p0[2]) - (p2[1] - p0[1]) * (p1[2] - p0[2])
      if area ~= 0 then
        local xa = math.max(0, math.floor(math.min(p0[1], p1[1], p2[1])))
        local xb = math.min(W - 1, math.ceil(math.max(p0[1], p1[1], p2[1])))
        local ya = math.max(0, math.floor(math.min(p0[2], p1[2], p2[2])))
        local yb = math.min(W - 1, math.ceil(math.max(p0[2], p1[2], p2[2])))
        for y = ya, yb do
          local cy = y + 0.5
          for x = xa, xb do
            local cx = x + 0.5
            local w0 = ((p1[1] - cx) * (p2[2] - cy) - (p2[1] - cx) * (p1[2] - cy)) / area
            local w1 = ((p2[1] - cx) * (p0[2] - cy) - (p0[1] - cx) * (p2[2] - cy)) / area
            local w2 = 1 - w0 - w1
            if w0 >= 0 and w1 >= 0 and w2 >= 0 then
              local z = w0 * p0[3] + w1 * p1[3] + w2 * p2[3]
              local key = y * W + x
              if not depth[key] or z < depth[key] then
                local u = math.floor(w0 * uv0[1] + w1 * uv1[1] + w2 * uv2[1]) & 255
                local v = math.floor(w0 * uv0[2] + w1 * uv1[2] + w2 * uv2[2]) & 255
                local c = clut(f.clut, texel(u, v))
                if c ~= 0 then
                  depth[key] = z
                  local r, g, b = (c & 31) * light, ((c >> 5) & 31) * light, ((c >> 10) & 31) * light
                  local grey = (r + g + b) / 3
                  local function sat(x) return math.max(0, math.min(31, grey + (x - grey) * SATURATION)) end
                  local cr, cg, cb = sat(r), sat(g), sat(b)
                  local lo, hi = math.min(cr, cg, cb), math.max(cr, cg, cb)
                  col[key] = { cr, cg, cb, z, drop = drop_white and lo >= WHITE and hi - lo <= GREY_SPREAD }
                end
              end
            end
          end
        end
      end
    end
  end
  return col
end

-- The figure's 16 x 16 pixels (nil = empty) from a supersampled frame.
local function shrink(col)
  local W = BOX * SS
  local out = {}
  for iy = 0, BOX - 1 do
    for ix = 0, BOX - 1 do
      local count, first, n, near, mean, kept, dropped = {}, {}, 0, math.huge, { 0, 0, 0 }, 0, nil
      for y = iy * SS, iy * SS + SS - 1 do
        for x = ix * SS, ix * SS + SS - 1 do
          local c = col[y * W + x]
          if c then
            n = n + 1
            near = math.min(near, c[4])
            if c.drop then
              dropped = dropped or c
            else
              kept = kept + 1
              mean[1], mean[2], mean[3] = mean[1] + c[1], mean[2] + c[2], mean[3] + c[3]
              local k = (math.floor(c[1]) << 10) | (math.floor(c[2]) << 5) | math.floor(c[3])
              count[k] = (count[k] or 0) + 1
              first[k] = first[k] or c
            end
          end
        end
      end
      local best, bests = nil, -1
      if kept == 0 and dropped then
        best = { dropped[1] * 0.55, dropped[2] * 0.55, dropped[3] * 0.55 } -- only white there: a shade instead
      elseif kept > 0 then
        mean = { mean[1] / kept, mean[2] / kept, mean[3] / kept }
        for k, cnt in pairs(count) do
          local c = first[k]
          local dist = math.sqrt((c[1] - mean[1]) ^ 2 + (c[2] - mean[2]) ^ 2 + (c[3] - mean[3]) ^ 2)
          local sc = cnt * (1 + SALIENT * dist)
          if sc > bests or (sc == bests and k < (best and best.k or math.huge)) then best, bests = { c[1], c[2], c[3], k = k }, sc end
        end
      end
      if n >= 7 then out[(iy + 1) * 16 + (ix + 1) + 1] = { best[1], best[2], best[3], near } end -- 1 pixel in from the top and left
    end
  end
  return out
end

-- Up to `k` colours for `pixels` (k-means from the most varied start).
local function palette(pixels, k)
  local pts = {}
  for _, frame in ipairs(pixels) do for _, c in pairs(frame) do pts[#pts + 1] = c end end
  local cent = {}
  -- start from points spread out: the first, then each farthest from the chosen
  if #pts == 0 then return cent end
  cent[1] = { pts[1][1], pts[1][2], pts[1][3] }
  local function d2(a, b) return (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2 end
  while #cent < k do
    local far, fd = nil, 0.5
    for _, p in ipairs(pts) do
      local m = math.huge
      for _, c in ipairs(cent) do m = math.min(m, d2(p, c)) end
      if m > fd then far, fd = p, m end
    end
    if not far then break end
    cent[#cent + 1] = { far[1], far[2], far[3] }
  end
  for _ = 1, 12 do
    local sum = {}
    for i = 1, #cent do sum[i] = { 0, 0, 0, 0 } end
    for _, p in ipairs(pts) do
      local bi, bd = 1, math.huge
      for i, c in ipairs(cent) do local d = d2(p, c); if d < bd then bi, bd = i, d end end
      local s = sum[bi]
      s[1], s[2], s[3], s[4] = s[1] + p[1], s[2] + p[2], s[3] + p[3], s[4] + 1
    end
    for i, s in ipairs(sum) do
      if s[4] > 0 then cent[i] = { s[1] / s[4], s[2] / s[4], s[3] / s[4] } end
    end
  end
  return cent
end

-- faces, px: lib/convert.lua's info.faces and info.texture.
-- Returns the pixels (two 16 x 16 frames side by side, 4 bits each, 16
-- bytes a row) and the CLUT (16 RGB555 colours; 0 transparent, 1 outline).
-- opts: head = {DW1 bones} drawn bigger (head_scale, around the first
-- one's pivot: the game's icons are drawn with big heads), pivots = the
-- donor's bone pivots (lib/convert.lua info.pivots), split = {DW3 bones}
-- moved apart sideways (split_factor: their distance from their middle
-- across is multiplied), for parts that would hide each other in the
-- three-quarter view, no_white = {DW1 bones} whose near-white colours are
-- left out (the block takes its other colours: e.g. teeth in a small face).
function M.render(faces, px, opts)
  opts = opts or {}
  if opts.split and #opts.split > 1 then
    local centre, n = {}, {}
    for _, b in ipairs(opts.split) do centre[b], n[b] = 0, 0 end
    for _, f in ipairs(faces) do
      if centre[f.dw3_bone] then
        for _, p in ipairs(f.pts) do centre[f.dw3_bone] = centre[f.dw3_bone] + p[1]; n[f.dw3_bone] = n[f.dw3_bone] + 1 end
      end
    end
    local mid, m = 0, 0
    for _, b in ipairs(opts.split) do
      if n[b] > 0 then centre[b] = centre[b] / n[b]; mid = mid + centre[b]; m = m + 1 end
    end
    mid = mid / math.max(1, m)
    local factor = opts.split_factor or 1.8
    local moved = {}
    for _, f in ipairs(faces) do
      local b = f.dw3_bone
      if centre[b] and n[b] > 0 then
        local dx = (centre[b] - mid) * (factor - 1)
        local pts = {}
        for k, p in ipairs(f.pts) do pts[k] = { p[1] + dx, p[2], p[3] } end
        moved[#moved + 1] = { pts = pts, uv = f.uv, clut = f.clut, bone = f.bone, dw3_bone = b }
      else
        moved[#moved + 1] = f
      end
    end
    faces = moved
  end
  if opts.head and opts.pivots then
    local hs, c = opts.head_scale or 1.35, opts.pivots[opts.head[1]]
    local is_head = {}
    for _, b in ipairs(opts.head) do is_head[b] = true end
    local scaled = {}
    for _, f in ipairs(faces) do
      if is_head[f.bone] then
        local pts = {}
        for k, p in ipairs(f.pts) do pts[k] = { c[1] + (p[1] - c[1]) * hs, c[2] + (p[2] - c[2]) * hs, c[3] + (p[3] - c[3]) * hs } end
        scaled[#scaled + 1] = { pts = pts, uv = f.uv, clut = f.clut, bone = f.bone, dw3_bone = f.dw3_bone }
      else
        scaled[#scaled + 1] = f
      end
    end
    faces = scaled
  end
  -- fit the figure (frame 1) in the box by its height, feet on the bottom,
  -- centred on its middle (the median across): a long tail or wings may run
  -- off the edge, as on the game's icons
  local xs, y0, y1 = {}, math.huge, -math.huge
  for _, f in ipairs(faces) do
    for _, p in ipairs(f.pts) do
      local v = view(p)
      xs[#xs + 1] = v[1]
      y0, y1 = math.min(y0, v[2]), math.max(y1, v[2])
    end
  end
  table.sort(xs)
  local mid = xs[(#xs + 1) // 2]
  local W = BOX * SS
  local k = (W - 1) / (y1 - y0)
  local fit = { x0 = mid, y0 = y0, k = k, dx = W / 2, dy = W - 1 - (y1 - y0) * k, bottom = W - 1 }
  local no_white
  if opts.no_white then
    no_white = {}
    for _, b in ipairs(opts.no_white) do no_white[b] = true end
  end
  local frames = { shrink(draw(faces, px, fit, 1.0, no_white)) }
  local cent = palette(frames, COLOURS)
  local colours = { 0, OUTLINE }
  for i, c in ipairs(cent) do
    local v = (math.floor(c[3] + 0.5) << 10) | (math.floor(c[2] + 0.5) << 5) | math.floor(c[1] + 0.5)
    colours[i + 2] = v ~= 0 and v or 0x8000 -- black that isn't transparent
  end
  for i = #colours + 1, 16 do colours[i] = 0 end
  local function nearest(c)
    local bi, bd = 1, math.huge
    for i, q in ipairs(cent) do
      local d = (c[1] - q[1]) ^ 2 + (c[2] - q[2]) ^ 2 + (c[3] - q[3]) ^ 2
      if d < bd then bi, bd = i, d end
    end
    return bi + 1 -- CLUT index (0 transparent, 1 outline)
  end
  -- indices, with the outline round each frame, and inside it wherever a
  -- part lies well in front of the one next to it (behind it, the outline)
  local edge = INNER_EDGE * (y1 - y0)
  local idx = {}
  for f = 1, 1 do
    local img, dep = {}, {}
    for y = 0, 15 do
      for x = 0, 15 do
        local c = frames[f][y * 16 + x + 1]
        img[y * 16 + x] = c and nearest(c) or 0
        dep[y * 16 + x] = c and c[4]
      end
    end
    local inner = {}
    for y = 0, 15 do
      for x = 0, 15 do
        local d = dep[y * 16 + x]
        if d then
          for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local xx, yy = x + o[1], y + o[2]
            local dn = xx >= 0 and xx < 16 and yy >= 0 and yy < 16 and dep[yy * 16 + xx]
            if dn and d - dn > edge then inner[y * 16 + x] = true end
          end
        end
      end
    end
    for key in pairs(inner) do img[key] = 1 end
    local out = {}
    for y = 0, 15 do
      for x = 0, 15 do
        local i = img[y * 16 + x]
        if i == 0 then
          local function filled(xx, yy) return xx >= 0 and xx < 16 and yy >= 0 and yy < 16 and img[yy * 16 + xx] > 1 end
          if filled(x - 1, y) or filled(x + 1, y) or filled(x, y - 1) or filled(x, y + 1) then i = 1 end
        end
        out[y * 16 + x] = i
      end
    end
    idx[f] = out
  end
  -- the second frame: rows 0..8 one lower (the upper body breathes), the legs still
  local second = {}
  for y = 0, 15 do
    for x = 0, 15 do
      if y == 0 then second[x] = 0
      elseif y <= 9 then second[y * 16 + x] = idx[1][(y - 1) * 16 + x]
      else second[y * 16 + x] = idx[1][y * 16 + x] end
    end
  end
  idx[2] = second
  local rows = {}
  for y = 0, 15 do
    local bytes = {}
    for f = 1, 2 do
      for x = 0, 15, 2 do bytes[#bytes + 1] = idx[f][y * 16 + x] | (idx[f][y * 16 + x + 1] << 4) end
    end
    rows[#rows + 1] = string.char(table.unpack(bytes))
  end
  local clut = {}
  for i = 1, 16 do clut[i] = string.pack("<I2", colours[i]) end
  return table.concat(rows), table.concat(clut)
end

return M
