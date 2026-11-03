-- Digimon World 2003 battle models (FIGHT/MODEL/M###XXXX.BIN), read from the
-- player's own disc: bones, meshes, keyframes, the texture, and the bones'
-- pose at a frame. A port of research/tools/dw3model.py and the posing of
-- dw3render.py (themselves after Feerdus95's dw3-model-viewer, MIT), kept
-- step for step the same so both give identical models.
--
-- A model file is an archive (u32 offsets from its start; count = first
-- offset / 4); entries can be archives themselves. The bone list {texture
-- entry, count, (parent, mesh entry, keys entry) * count}; a mesh is an
-- archive [0] vertices, [1] normals (count in the first vector's x), [2]
-- drawing commands; keys an archive of position, rotation and scale tracks
-- (x, y, z, frame; frame >= 30000 ends a track) on one timeline.

local M = {}

local function u8(d, o) return d:byte(o + 1) end
local function u32(d, o) return (string.unpack("<I4", d, o + 1)) end
local function s16(d, o) return (string.unpack("<i2", d, o + 1)) end

-- --- archives ---------------------------------------------------------------
local Archive = {}
Archive.__index = Archive

local function archive(d, base, size)
  return setmetatable({ d = d, base = base or 0, size = size or (#d - (base or 0)) }, Archive)
end

function Archive:count() return self.size < 4 and 0 or u32(self.d, self.base) // 4 end
function Archive:off(i) return u32(self.d, self.base + 4 * i) end

function Archive:entry(i)
  if i < 0 or (i + 1) * 4 > self.size then return nil end
  local o = self:off(i)
  if o < self.size then return self.base + o end
  return nil
end

function Archive:entry_size(i)
  local e = self:entry(i)
  if not e then return 0 end
  local stop, eo = self.size, e - self.base
  for j = 0, self:count() - 1 do
    local o = self:off(j)
    if eo < o and o < stop then stop = o end
  end
  return stop - eo
end

function Archive:sub(i)
  local e = self:entry(i)
  if not e then return nil end
  return archive(self.d, e, self:entry_size(i))
end

-- --- meshes -------------------------------------------------------------------
local function read_vecs(a, i)
  local p = a:entry(i)
  local n = s16(a.d, p)
  local out = {}
  for k = 0, n - 1 do
    out[#out + 1] = { string.unpack("<i2i2i2", a.d, p + 6 + 6 * k + 1) }
    out[#out][4] = nil
  end
  return out
end

-- The drawing commands: 0x8n quad, 0x9n textured, 0xCn lit, 0xDn gouraud,
-- 0xEn semi-transparency; 01 u uhi v cx cy tp: texture; 02-05 + RGB:
-- colours; 00: polygons (indices, normal indices when lit, UVs when
-- textured), more while the next byte is 0; FF: end.
local function read_commands(d, cmd, stop)
  local quad, textured, lit, gouraud, abr, u, v, tex = false, false, false, false, 0, 0, 0, nil
  local polys = {}
  while cmd < stop and u8(d, cmd) ~= 0xFF do
    local c = u8(d, cmd)
    local hi, lo = c >> 4, c & 15
    if hi ~= 0 then
      if hi == 8 then quad = lo ~= 0
      elseif hi == 9 then textured = lo ~= 0
      elseif hi == 12 then lit = lo ~= 0
      elseif hi == 13 then gouraud = lo ~= 0
      elseif hi == 14 then abr = lo end
      cmd = cmd + 1
    elseif lo == 1 then
      u = u8(d, cmd + 1) + (u8(d, cmd + 2) << 8)
      v = u8(d, cmd + 3)
      tex = { u8(d, cmd + 1), u8(d, cmd + 2), u8(d, cmd + 3), u8(d, cmd + 4), u8(d, cmd + 5), u8(d, cmd + 6) }
      cmd = cmd + 7
    elseif lo >= 2 and lo <= 5 then
      cmd = cmd + 4
    elseif lo == 0 then
      while true do
        cmd = cmd + 1
        local n = quad and 4 or 3
        local len = n + (lit and n or 0) + (textured and 2 * n or 0)
        local idx, nrm, uv = {}, nil, nil
        for k = 0, n - 1 do idx[#idx + 1] = u8(d, cmd + k) end
        if lit then
          nrm = {}
          for k = 0, n - 1 do nrm[#nrm + 1] = u8(d, cmd + n + k) end
        end
        local q = cmd + (lit and 2 * n or n)
        if textured then
          uv = {}
          for k = 0, n - 1 do uv[#uv + 1] = { (u8(d, q + 2 * k) + u) & 0xff, (u8(d, q + 2 * k + 1) + v) & 0xff } end
        end
        polys[#polys + 1] = { quad = quad, textured = textured, lit = lit, gouraud = gouraud, abr = abr, idx = idx, nrm = nrm, uv = uv, tex = tex }
        cmd = cmd + len
        if not (cmd < stop and u8(d, cmd) == 0) then break end
      end
    else
      error(string.format("unknown model command %02x at %x", c, cmd))
    end
  end
  return polys
end

-- --- textures (TIMs, maybe RLEN-packed: 0x80|n = n copies of the next byte) --
local function rlen_unpack(d, s, stop)
  local out = {}
  s = s + 8
  while s < stop and u8(d, s) ~= 0 do
    local c = u8(d, s)
    if c & 0x80 ~= 0 then
      out[#out + 1] = string.rep(d:sub(s + 2, s + 2), c & 0x7F)
      s = s + 2
    else
      out[#out + 1] = d:sub(s + 2, s + 1 + c)
      s = s + 1 + c
    end
  end
  return table.concat(out)
end

local function read_tims(a)
  local tims = {}
  for i = 0, a:count() - 1 do
    if a:off(i) == 0 then break end
    local src = a:entry(i)
    if not src then break end
    local stop = a.base + a.size
    local buf
    if a.d:sub(src + 1, src + 4) == "RLEN" then buf = rlen_unpack(a.d, src, stop) else buf = a.d:sub(src + 1, stop) end
    if #buf >= 20 and u32(buf, 0) == 0x10 then
      local flag, at = u32(buf, 4), 8
      if flag & 8 ~= 0 then at = at + u32(buf, 8) end
      local w, h = string.unpack("<I2I2", buf, at + 8 + 1)
      tims[#tims + 1] = { w = w, h = h, px = buf:sub(at + 12 + 1, at + 12 + w * h * 2) } -- px: w*h halfwords
    end
  end
  return tims
end

-- --- the model ------------------------------------------------------------------
function M.read(data, bone_entry, motions_entry)
  local a = archive(data)
  local e = a:entry(bone_entry)
  local m = { tex_entry = u32(data, e), bones = {} }
  for b = 0, u32(data, e + 4) - 1 do
    local parent, mesh, keys = string.unpack("<I4I4I4", data, e + 8 + 12 * b + 1)
    local ma, ka = a:sub(mesh), a:sub(keys)
    local tracks = {}
    for t = 0, 2 do
      local p, stop, ks = ka:entry(t), ka.base + ka.size, {}
      while p and p + 8 <= stop do
        local k = { string.unpack("<i2i2i2i2", data, p + 1) }
        k[5] = nil
        ks[#ks + 1] = k
        p = p + 8
        if k[4] >= 30000 then break end
      end
      tracks[t + 1] = ks
    end
    m.bones[#m.bones + 1] = { parent = parent, verts = read_vecs(ma, 0), normals = read_vecs(ma, 1),
      polys = read_commands(data, ma:entry(2), ma.base + ma.size), keys = tracks }
  end
  m.tims = m.tex_entry ~= 0 and read_tims(a:sub(m.tex_entry)) or {}
  -- the idle frame: motion 0's first step {index, count, frame, endFrame}
  local mo = a:sub(motions_entry)
  m.idle_frame = s16(data, mo:entry(0) + 4)
  return m
end

-- --- posing (FIGHTSTG: each bone Rz*Ry*Rx, columns scaled, under its parent) -----
local function lerp(prev, cur, t)
  local out = {}
  for i = 1, 3 do
    local d = ((cur[i] - prev[i] + 0x8000) & 0xFFFF) - 0x8000
    out[i] = prev[i] + (d * t) // 4096
  end
  return out
end

local function pose_bone(bone, frame)
  local out = {}
  for t = 1, 3 do
    local keys = bone.keys[t]
    if #keys == 0 then
      out[t] = t < 3 and { 0, 0, 0 } or { 4096, 4096, 4096 }
    else
      local k, found = 1, false
      while true do
        if k + 1 > #keys then break end
        if keys[k][4] == frame then found = true; break end
        if keys[k][4] >= frame then break end
        k = k + 1
      end
      local cur = keys[k]
      if found or k == 1 or cur[4] < frame then
        out[t] = { cur[1], cur[2], cur[3] }
      else
        local prev = keys[k - 1]
        local span = cur[4] - prev[4]
        local dp = span ~= 0 and ((frame - prev[4]) << 12) // span or 0
        out[t] = lerp(prev, cur, dp)
      end
    end
  end
  return out
end

local function bone_matrix(pos, rot, scale)
  local k = 2 * math.pi / 4096
  local cx, sx = math.cos(rot[1] * k), math.sin(rot[1] * k)
  local cy, sy = math.cos(rot[2] * k), math.sin(rot[2] * k)
  local cz, sz = math.cos(rot[3] * k), math.sin(rot[3] * k)
  local r = { { cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx },
    { sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx },
    { -sy, cy * sx, cy * cx } }
  local s = { scale[1] / 4096, scale[2] / 4096, scale[3] / 4096 }
  local out = {}
  for i = 1, 3 do out[i] = { r[i][1] * s[1], r[i][2] * s[2], r[i][3] * s[3], pos[i] } end
  return out
end

local function mul(a, b)
  local out = {}
  for i = 1, 3 do
    local row = {}
    for j = 1, 3 do row[j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
    row[4] = a[i][1] * b[1][4] + a[i][2] * b[2][4] + a[i][3] * b[3][4] + a[i][4]
    out[i] = row
  end
  return out
end

-- Model-space 3x4 matrices of every bone (1-based, as m.bones) at `frame`.
function M.pose(m, frame)
  local nodes = { [0] = { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 } } }
  for i, bone in ipairs(m.bones) do
    local p = pose_bone(bone, frame)
    nodes[i] = mul(nodes[bone.parent], bone_matrix(p[1], p[2], p[3]))
  end
  nodes[0] = nil
  return nodes
end

return M
