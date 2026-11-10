-- A software renderer for the game's battle models (FIGHT/MODEL files),
-- for pictures the mod makes while it loads from the player's disc (the
-- gyms' exercise frames). Posing follows FIGHTSTG: each bone Rz * Ry * Rx
-- with its columns scaled, at its position, under its parent's; keys are
-- interpolated on the timeline all motions share; a bone scaled to 48/4096
-- or less is hidden. Pictures are orthographic, lit from the camera.
--
-- Model file: an archive. Bone list entry {texture entry, count, (parent,
-- mesh entry, keys entry) * count}, bone 0 an implicit root. Mesh entry:
-- archive [0] vertices (count in the first 6-byte vector's x), [1]
-- normals, [2] commands: 0x8n quads on/off, 0x9n textured, 0xCn lit, 0xDn
-- gouraud, 0xEn semi-transparency, 0x01 u uhi v cx cy tp (texture: base
-- UV, CLUT position inside the texture, depth), 0x02-0x05 + RGB, 0x00
-- polygons (indices, normal indices when lit, UVs when textured), more
-- while the next byte is 0, 0xFF ends. Keys entry: archive [0] positions,
-- [1] rotations (4096 = 360 degrees), [2] scales, each key x, y, z, frame,
-- a frame >= 30000 ending the track. Motions entry: archive of motions,
-- steps {index, count, frame, end frame} up to index 0x7FFF. Texture
-- entry: archive of TIMs; the first is 64x256 halfwords of 4-bit texels
-- with its CLUT rows inside it.

local bin = require("lib.bin")
local sprites = require("lib.sprites")

local M = {}

local function u32(s, o) return (string.unpack("<I4", s, o + 1)) end

-- entry i (0-based) of an archive, as a string
local function entry(data, i)
  local list = sprites.read_archive(data)
  return list[i + 1]
end

local function vecs(mesh, i)
  local e = entry(mesh, i)
  local n = bin.s16(e, 0)
  local out = {}
  for k = 0, n - 1 do
    local x, y, z = string.unpack("<i2i2i2", e, 6 + 6 * k + 1)
    out[k] = { x, y, z }
  end
  return out, n
end

local function polygons(d)
  local quad, textured, lit = false, false, false
  local tex = { 0, 0, 0, 0, 0, 0 }
  local color = { 128, 128, 128 }
  local out = {}
  local p = 0
  while p < #d do
    local c = d:byte(p + 1)
    if c == 0xFF then break end
    local hi, lo = c >> 4, c & 15
    if hi ~= 0 then
      if hi == 8 then quad = lo ~= 0
      elseif hi == 9 then textured = lo ~= 0
      elseif hi == 12 then lit = lo ~= 0 end
      p = p + 1
    elseif lo == 1 then
      tex = { d:byte(p + 2, p + 7) }
      p = p + 7
    elseif lo >= 2 and lo <= 5 then
      if lo == 2 then color = { d:byte(p + 2, p + 4) } end
      p = p + 4
    elseif lo == 0 then
      repeat
        p = p + 1
        local n = quad and 4 or 3
        local poly = { n = n, tex = textured and tex or nil, color = color }
        for k = 1, n do poly[k] = d:byte(p + k) end
        local q = p + (lit and 2 * n or n)
        if textured then
          poly.uv = {}
          for k = 1, n do
            poly.uv[k] = { (d:byte(q + 2 * k - 1) + tex[1]) & 0xFF, (d:byte(q + 2 * k) + tex[3]) & 0xFF }
          end
          q = q + 2 * n
        end
        out[#out + 1] = poly
        p = q
      until p >= #d or d:byte(p + 1) ~= 0
    else
      error(string.format("unknown model command %02x", c))
    end
  end
  return out
end

local function keys(e)
  local tracks = {}
  local list = sprites.read_archive(e)
  for t = 1, 3 do
    local k = {}
    local s = list[t]
    if s then
      for o = 0, #s - 8, 8 do
        local x, y, z, f = string.unpack("<i2i2i2i2", s, o + 1)
        k[#k + 1] = { x, y, z, f }
        if f >= 30000 then break end
      end
    end
    tracks[t] = k
  end
  return tracks
end

-- A model: bones (parent, vertices, polygons, keys), its texture (64x256
-- halfwords) and its motions' frame ranges.
function M.load(data, bone_entry, motions_entry)
  local list = sprites.read_archive(data)
  local b = list[bone_entry + 1]
  local tex_entry, count = u32(b, 0), u32(b, 4)
  local model = { bones = {}, motions = {} }
  for i = 0, count - 1 do
    local parent, mesh_entry, keys_entry = string.unpack("<I4I4I4", b, 8 + 12 * i + 1)
    local mesh = list[mesh_entry + 1]
    local verts = vecs(mesh, 0)
    model.bones[i + 1] = { parent = parent, verts = verts, polys = polygons(entry(mesh, 2)),
      keys = keys(list[keys_entry + 1]) }
  end
  local tims = sprites.read_archive(list[tex_entry + 1])
  local t = tims[1]
  if t:sub(1, 4) == "RLEN" then t = sprites.rlen_unpack(t) end
  local flags = u32(t, 4)
  local p = 8
  if flags & 8 ~= 0 then p = p + u32(t, p) end
  local w, h = bin.u16(t, p + 8), bin.u16(t, p + 10)
  local hw = {}
  for k = 0, w * h - 1 do hw[k] = bin.u16(t, p + 12 + 2 * k) end
  model.tex = { w = w, h = h, hw = hw }
  local motions = sprites.read_archive(list[motions_entry + 1])
  for i, s in ipairs(motions) do
    local ranges = {}
    if s and #s >= 8 and bin.s16(s, 0) == 0 then
      for o = 0, #s - 8, 8 do
        local index, _, f0, f1 = string.unpack("<i2i2i2i2", s, o + 1)
        if index == 0x7FFF then break end
        if f0 >= 0 and f1 > f0 then ranges[#ranges + 1] = { f0, f1 } end
      end
    end
    if #ranges > 0 then model.motions[i - 1] = ranges end
  end
  return model
end

-- The frames of a motion, from its first to its last.
function M.motion_span(model, i)
  local r = assert(model.motions[i], "no motion " .. i)
  return r[1][1], r[#r][2]
end

-- Posing -----------------------------------------------------------------

local function track_at(k, frame, default)
  if #k == 0 then return default end
  local i = 1
  while i < #k do
    if k[i][4] >= frame then break end
    i = i + 1
  end
  local cur = k[i]
  if cur[4] == frame or i == 1 or cur[4] < frame then return { cur[1], cur[2], cur[3] } end
  local prev = k[i - 1]
  local span = cur[4] - prev[4]
  local t = span ~= 0 and ((frame - prev[4]) << 12) // span or 0
  local out = {}
  for c = 1, 3 do
    local dd = ((cur[c] - prev[c] + 0x8000) & 0xFFFF) - 0x8000
    out[c] = prev[c] + ((dd * t) >> 12)
  end
  return out
end

local TAU = 2 * math.pi / 4096

local function bone_matrix(pos, rot, scale)
  local cx, sx = math.cos(rot[1] * TAU), math.sin(rot[1] * TAU)
  local cy, sy = math.cos(rot[2] * TAU), math.sin(rot[2] * TAU)
  local cz, sz = math.cos(rot[3] * TAU), math.sin(rot[3] * TAU)
  local s1, s2, s3 = scale[1] / 4096, scale[2] / 4096, scale[3] / 4096
  return {
    cz * cy * s1, (cz * sy * sx - sz * cx) * s2, (cz * sy * cx + sz * sx) * s3, pos[1],
    sz * cy * s1, (sz * sy * sx + cz * cx) * s2, (sz * sy * cx - cz * sx) * s3, pos[2],
    -sy * s1, cy * sx * s2, cy * cx * s3, pos[3],
  }
end

local function mul(a, b)
  local o = {}
  for r = 0, 2 do
    local a0, a1, a2, a3 = a[4 * r + 1], a[4 * r + 2], a[4 * r + 3], a[4 * r + 4]
    o[4 * r + 1] = a0 * b[1] + a1 * b[5] + a2 * b[9]
    o[4 * r + 2] = a0 * b[2] + a1 * b[6] + a2 * b[10]
    o[4 * r + 3] = a0 * b[3] + a1 * b[7] + a2 * b[11]
    o[4 * r + 4] = a0 * b[4] + a1 * b[8] + a2 * b[12] + a3
  end
  return o
end

local IDENTITY = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }

-- Each bone's world matrix at a frame, and whether it is shown.
function M.pose(model, frame)
  local nodes, shown = { [0] = IDENTITY }, {}
  for i, bone in ipairs(model.bones) do
    local pos = track_at(bone.keys[1], frame, { 0, 0, 0 })
    local rot = track_at(bone.keys[2], frame, { 0, 0, 0 })
    local scale = track_at(bone.keys[3], frame, { 4096, 4096, 4096 })
    shown[i] = (scale[1] | scale[2] | scale[3]) > 48
    nodes[i] = mul(nodes[bone.parent], bone_matrix(pos, rot, scale))
  end
  return nodes, shown
end

-- Drawing ----------------------------------------------------------------

-- Draws the model at `frame`, turned by view.yaw (radians, about the
-- vertical) and tilted by view.pitch, view.scale pixels per model unit,
-- view.ss times supersampled; view.ambient is the light of faces turned
-- away, view.light a direction the light comes from (x right, y down, z
-- away from the viewer; default: the viewer), view.cull (1 or -1) the
-- screen winding of faces not drawn.
-- Returns { w, h, px = {[y * w + x] = 0xRRGGBB}, ox, oy = where the
-- model's origin lands }.
function M.draw(model, frame, view)
  local mats, shown = M.pose(model, frame)
  local ss = view.ss or 2
  local ambient = view.ambient or 0.45
  local light = view.light
  if light then
    local l = math.sqrt(light[1] ^ 2 + light[2] ^ 2 + light[3] ^ 2)
    light = { light[1] / l, light[2] / l, light[3] / l }
  end
  local k = view.scale * ss
  local cy_, sy_ = math.cos(view.yaw), math.sin(view.yaw)
  local cp, sp = math.cos(view.pitch), math.sin(view.pitch)
  local tris = {}
  local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
  for i, bone in ipairs(model.bones) do
    if shown[i] then
      local m = mats[i]
      local pts = {}
      for vi, v in pairs(bone.verts) do
        local x = m[1] * v[1] + m[2] * v[2] + m[3] * v[3] + m[4]
        local y = m[5] * v[1] + m[6] * v[2] + m[7] * v[3] + m[8]
        local z = m[9] * v[1] + m[10] * v[2] + m[11] * v[3] + m[12]
        x, z = x * cy_ - z * sy_, x * sy_ + z * cy_
        y, z = y * cp - z * sp, y * sp + z * cp
        pts[vi] = { x * k, y * k, z }
      end
      for _, p in ipairs(bone.polys) do
        local ok = true
        for c = 1, p.n do if not pts[p[c]] then ok = false end end
        if ok then
          local order = p.n == 4 and { { 1, 2, 3 }, { 2, 4, 3 } } or { { 1, 2, 3 } }
          for _, o in ipairs(order) do
            local a, b, c = pts[p[o[1]]], pts[p[o[2]]], pts[p[o[3]]]
            tris[#tris + 1] = { a, b, c, p.uv and { p.uv[o[1]], p.uv[o[2]], p.uv[o[3]] }, p.tex, p.color }
            for _, q in ipairs({ a, b, c }) do
              if q[1] < minx then minx = q[1] end
              if q[1] > maxx then maxx = q[1] end
              if q[2] < miny then miny = q[2] end
              if q[2] > maxy then maxy = q[2] end
            end
          end
        end
      end
    end
  end
  -- the big picture, aligned so `ss` of its pixels make one of the result's
  local x0 = (math.floor(minx / ss) - 1) * ss
  local y0 = (math.floor(miny / ss) - 1) * ss
  local W = (math.floor(maxx / ss) + 2) * ss - x0
  local H = (math.floor(maxy / ss) + 2) * ss - y0
  local col, zb = {}, {}
  local tex = model.tex
  local hw, tw = tex.hw, tex.w
  local floor = math.floor
  local cull = view.cull
  for _, t in ipairs(tris) do
    local a, b, c = t[1], t[2], t[3]
    local ax, ay, bx, by, cx, cy = a[1] - x0, a[2] - y0, b[1] - x0, b[2] - y0, c[1] - x0, c[2] - y0
    local area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
    if (area > 1e-9 or area < -1e-9) and not (cull and area * cull < 0) then
      -- the face's normal in view space, for a light at the camera
      local ux, uy, uz = b[1] - a[1], b[2] - a[2], (b[3] - a[3]) * k
      local vx, vy, vz = c[1] - a[1], c[2] - a[2], (c[3] - a[3]) * k
      local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
      local ln = math.sqrt(nx * nx + ny * ny + nz * nz)
      local shade = 1
      if ln > 0 then
        if light then
          if nz > 0 then nx, ny, nz = -nx, -ny, -nz end
          local d = (nx * light[1] + ny * light[2] + nz * light[3]) / ln
          shade = ambient + (1 - ambient) * (d > 0 and d or 0)
        else
          shade = ambient + (1 - ambient) * math.abs(nz / ln)
        end
      end
      local uv, tx, flat = t[4], t[5], t[6]
      local u0, u1, u2, v0, v1, v2, depth, base
      if uv and tx then
        u0, u1, u2, v0, v1, v2 = uv[1][1], uv[2][1], uv[3][1], uv[1][2], uv[2][2], uv[3][2]
        depth, base = tx[6] & 3, tx[5] * tw + tx[4]
      end
      local fr, fg, fb = floor(flat[1] * shade), floor(flat[2] * shade), floor(flat[3] * shade)
      local za, zbb, zc = a[3], b[3], c[3]
      local px0 = math.max(0, floor(math.min(ax, bx, cx)))
      local px1 = math.min(W - 1, floor(math.max(ax, bx, cx)))
      local py0 = math.max(0, floor(math.min(ay, by, cy)))
      local py1 = math.min(H - 1, floor(math.max(ay, by, cy)))
      local inv = 1 / area
      -- edge functions, stepped by one pixel in x
      local d0x, d1x = -(cy - by) * inv, -(ay - cy) * inv
      for y = py0, py1 do
        local fy = y + 0.5
        local fx = px0 + 0.5
        local w0 = ((bx - fx) * (cy - fy) - (cx - fx) * (by - fy)) * inv
        local w1 = ((cx - fx) * (ay - fy) - (ax - fx) * (cy - fy)) * inv
        local row = y * W
        for x = px0, px1 do
          local w2 = 1 - w0 - w1
          if w0 >= 0 and w1 >= 0 and w2 >= 0 then
            local z = w0 * za + w1 * zbb + w2 * zc
            local o = row + x
            local zo = zb[o]
            if not zo or z < zo then
              if base then
                local u = floor(w0 * u0 + w1 * u1 + w2 * u2)
                local v = floor(w0 * v0 + w1 * v1 + w2 * v2)
                local idx
                if depth == 0 then
                  idx = ((hw[v * tw + (u >> 2)] or 0) >> ((u & 3) * 4)) & 15
                else
                  idx = ((hw[v * tw + (u >> 1)] or 0) >> ((u & 1) * 8)) & 255
                end
                local cc = hw[base + idx] or 0
                if cc ~= 0 then
                  zb[o] = z
                  local r, g, bl = floor(((cc & 31) << 3) * shade), floor((((cc >> 5) & 31) << 3) * shade),
                    floor((((cc >> 10) & 31) << 3) * shade)
                  col[o] = ((r > 255 and 255 or r) << 16) | ((g > 255 and 255 or g) << 8) | (bl > 255 and 255 or bl)
                end
              else
                zb[o] = z
                col[o] = ((fr > 255 and 255 or fr) << 16) | ((fg > 255 and 255 or fg) << 8) | (fb > 255 and 255 or fb)
              end
            end
          end
          w0, w1 = w0 + d0x, w1 + d1x
        end
      end
    end
  end
  -- down to one pixel per ss x ss: the mean of the covered ones, where at
  -- least half are
  local w, h = W // ss, H // ss
  local px = {}
  local need = (ss * ss + 1) // 2
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local n, r, g, bl = 0, 0, 0, 0
      for yy = 0, ss - 1 do
        local row = (y * ss + yy) * W + x * ss
        for xx = 0, ss - 1 do
          local c = col[row + xx]
          if c then
            n = n + 1
            r, g, bl = r + (c >> 16), g + ((c >> 8) & 255), bl + (c & 255)
          end
        end
      end
      if n >= need then px[y * w + x] = ((r // n) << 16) | ((g // n) << 8) | (bl // n) end
    end
  end
  return { w = w, h = h, px = px, ox = -x0 / ss, oy = -y0 / ss }
end

-- Trims a picture to its covered pixels; returns it with x, y of the cut.
function M.trim(img)
  local x0, y0, x1, y1 = img.w, img.h, -1, -1
  for o in pairs(img.px) do
    local x, y = o % img.w, o // img.w
    if x < x0 then x0 = x end
    if x > x1 then x1 = x end
    if y < y0 then y0 = y end
    if y > y1 then y1 = y end
  end
  if x1 < 0 then return { w = 0, h = 0, px = {}, ox = img.ox, oy = img.oy } end
  local w, h = x1 - x0 + 1, y1 - y0 + 1
  local px = {}
  for o, c in pairs(img.px) do
    px[(o // img.w - y0) * w + (o % img.w - x0)] = c
  end
  return { w = w, h = h, px = px, ox = img.ox - x0, oy = img.oy - y0 }
end

return M
