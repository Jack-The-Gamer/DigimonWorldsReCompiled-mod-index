-- Digimon World 2 (USA, SLUS-01193) models, read the way the game reads them
-- (Wyrelade's DW2 decompilation: Gfx_AttachModel, Gfx_DrawTexModel,
-- Gfx_CalcModelBoneMatrices, Anim_StepModelAnim), presented like
-- lib/dw3model.lua's so lib/convert.lua builds a Digimon World model from
-- either. A port of research/tools/dw2model.py (the same numbers).
--
-- Model file: +0 texture offset, +4 a flag, +8 bone count n, then four n-long
-- tables: vertex lists, normal lists, polygon lists (offsets from the file's
-- start) and bone depths (a bone's parent is the last bone before it one
-- level up; depth 0 hangs from the root).
-- A vertex or normal list: s16 count, 4 unused bytes, count x {s16 x, y, z}.
-- A polygon list: two quad sections, then two triangle sections, each {s32
-- n, n records} (the first of each pair semi-transparent): a quad {u8 v[4],
-- u8 normal[4], u8 uv[8], u16 clut, u16 tpage}, a triangle {v[3], normal[3],
-- uv[6], clut, tpage}. The clut is (row << 6) | (x / 16) inside the texture.
-- The texture: a 0x40-byte header, then 32 halfwords x 256 rows (4-bit
-- texels, 128 wide; the 16-colour CLUTs among the bottom rows).
-- Animation file: +0 a flag, +4 n offsets of per-bone pose tables (24-byte
-- {s16 m[3][3] (4096 = 1), s16 t[3]}, relative to the parent), then the
-- animations' offsets (ending with 1): per frame n key indices, one a bone.

local M = {}

local function s16(d, o) return (string.unpack("<i2", d, o + 1)) end
local function s32(d, o) return (string.unpack("<i4", d, o + 1)) end

local function read_list(d, o)
  local out = {}
  for k = 0, s16(d, o) - 1 do out[#out + 1] = { string.unpack("<i2i2i2", d, o + 6 + 6 * k + 1) } end
  for _, v in ipairs(out) do v[4] = nil end
  return out
end

-- The model, with every bone's {parent (1-based, 0 = root), verts, normals,
-- polys}; polys as lib/dw3model.lua gives them (tex[4], tex[5] = the CLUT's
-- halfword x and row); tims[1] = the texture (w = 32 halfwords a row).
function M.read(d)
  local tim, n = s32(d, 0), s32(d, 8)
  local function tab(t, j) return s32(d, 12 + 4 * n * t + 4 * j) end
  local m = { bones = {} }
  local last = {}
  for j = 0, n - 1 do
    local depth = tab(3, j)
    local parent = 0
    if depth > 0 then parent = last[depth - 1] + 1 end
    last[depth] = j
    local polys = {}
    local o = tab(2, j)
    for sec = 0, 3 do
      local quad = sec < 2
      local k, size = quad and 4 or 3, quad and 20 or 16
      local cnt = s32(d, o); o = o + 4
      for _ = 1, cnt do
        local idx, nrm, uv = {}, {}, {}
        for c = 1, k do
          idx[c] = d:byte(o + c)
          nrm[c] = d:byte(o + k + c)
          uv[c] = { d:byte(o + 2 * k + 2 * c - 1), d:byte(o + 2 * k + 2 * c) }
        end
        local clut = string.unpack("<I2", d, o + 4 * k + 1)
        polys[#polys + 1] = { quad = quad, textured = true, lit = true, gouraud = true, idx = idx, nrm = nrm, uv = uv,
          tex = { 0, 0, 0, (clut & 63) * 16, clut >> 6, 0 } }
        o = o + size
      end
    end
    m.bones[j + 1] = { parent = parent, verts = read_list(d, tab(0, j)), normals = read_list(d, tab(1, j)), polys = polys }
  end
  m.tims = { { w = 32, h = 256, px = d:sub(tim + 0x40 + 1, tim + 0x40 + 0x4000) } }
  return m
end

-- The bones' model-space matrices ({{r, r, r, t} x 3}, 1-based; [0] the
-- root) at animation `index`'s frame `frame` of the animation file `a`.
function M.pose(m, a, index, frame)
  local n = #m.bones
  local o = 4 + 4 * n
  local anims = {}
  while s32(a, o) ~= 1 do anims[#anims + 1] = s32(a, o); o = o + 4 end
  local f = anims[index + 1] + frame * n
  local nodes = { [0] = { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 } } }
  for b = 1, n do
    local key = a:byte(f + b)
    local v = { string.unpack("<i2i2i2i2i2i2i2i2i2i2i2i2", a, s32(a, 4 + 4 * (b - 1)) + 24 * key + 1) }
    local p = nodes[m.bones[b].parent]
    local out = {}
    for i = 1, 3 do
      local row = {}
      for j = 1, 3 do row[j] = p[i][1] * (v[j] / 4096) + p[i][2] * (v[3 + j] / 4096) + p[i][3] * (v[6 + j] / 4096) end
      row[4] = p[i][1] * v[10] + p[i][2] * v[11] + p[i][3] * v[12] + p[i][4]
      out[i] = row
    end
    nodes[b] = out
  end
  return nodes
end

return M
