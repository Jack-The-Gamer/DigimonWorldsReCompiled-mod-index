-- A Digimon World Digimon's own model as a source for lib/convert.lua, for an
-- NPC-only Digimon whose MMD lacks a partner's animations (Tentomon, type
-- 111: no eating, sleeping or training motions), so it moves onto a partner
-- donor's skeleton like a DW2/DW2003 model. Presented like lib/dw2model.lua:
-- DW1 bone b is source bone b (parent 0 = the root), each with its object's
-- vertices, normals and polygons in bone space; the pose is animation 0's
-- start. A port of research/tools/dw1source.py (the same numbers).
--
-- The texture is the type's ALLTIM entry: 256 x 128 texels (64 halfwords a
-- row) with its 16 CLUTs added as rows 128..143, so a polygon's CLUT is at
-- (0, 128 + row) as convert.lua reads CLUTs from inside a texture.
-- Polygons: 0x34/0x36 (gouraud textured triangles, 0x36 semi-transparent)
-- and 0x3C/0x3E (quads): u0 v0 cba, u1 v1 tsb, u2 v2, [u3 v3], then normal |
-- vertex << 16 per corner (cba = 0x7A00 + CLUT row << 6); flat ones
-- 0x24/0x26/0x2C/0x2E (ToyAgumon's blocks, Hagurumon) have one normal, put on
-- every corner. A semi-transparent
-- one keeps its blend mode (tsb bits 5-6) as `blend` (lib/dw3model.lua's `abr` is another thing).

local convert = require("lib.convert")

local M = {}

-- skel: {[bone] = {object, parent}} (0-based bones, as main.lua reads them);
-- mmd: the Digimon's MMD; tim_entry: its 0x4800-byte ALLTIM entry;
-- same_rig: it uses its donor's very skeleton (the Sukamon family on
-- Sukamon: see M.pose and lib/convert.lua).
function M.read(mmd, skel, tim_entry, same_rig)
  local t = string.unpack("<I4", mmd, 1)
  local nobj = string.unpack("<I4", mmd, t + 8 + 1)
  local top = t + 12
  local objs = {}
  for i = 0, nobj - 1 do
    local vt, vn, nt, nn, pt, pn = string.unpack("<I4I4I4I4I4I4", mmd, top + 28 * i + 1)
    local o = { verts = {}, normals = {}, polys = {} }
    for k = 0, vn - 1 do o.verts[k + 1] = { string.unpack("<i2i2i2", mmd, top + vt + 8 * k + 1) }; o.verts[k + 1][4] = nil end
    for k = 0, nn - 1 do o.normals[k + 1] = { string.unpack("<i2i2i2", mmd, top + nt + 8 * k + 1) }; o.normals[k + 1][4] = nil end
    local p = top + pt
    for _ = 1, pn do
      local ilen, mode = mmd:byte(p + 2), mmd:byte(p + 4)
      local w = {}
      for k = 1, ilen do w[k] = string.unpack("<I4", mmd, p + 4 + 4 * (k - 1) + 1) end
      if mode & 0xE5 ~= 0x24 then -- textured polygons: 0x24/0x26/0x2C/0x2E flat, 0x34/0x36/0x3C/0x3E gouraud
        error(string.format("object %d: polygon mode %02X isn't supported", i, mode))
      end
      local n = (mode & 8 ~= 0) and 4 or 3
      local uv, idx, nrm = {}, {}, {}
      for k = 1, n do uv[k] = { w[k] & 0xFF, (w[k] >> 8) & 0xFF } end
      local first = n + 1
      if mode & 0x10 ~= 0 then
        for k = 1, n do
          local c = w[first + k - 1]
          idx[k], nrm[k] = c >> 16, c & 0xFFFF
        end
      else
        -- flat: normal | v0 << 16, v1 | v2 << 16[, v3]; its one normal on every corner
        local a, b = w[first], w[first + 1]
        idx = { a >> 16, b & 0xFFFF, b >> 16 }
        if n == 4 then idx[4] = w[first + 2] & 0xFFFF end
        for k = 1, n do nrm[k] = a & 0xFFFF end
      end
      local row = ((w[1] >> 16) >> 6) - 488
      local poly = { quad = n == 4, textured = true, lit = true, gouraud = true, idx = idx, nrm = nrm, uv = uv, tex = { 0, 0, 0, 0, 128 + row, 0 } }
      if mode & 2 ~= 0 then poly.blend = (w[2] >> 21) & 3 end
      o.polys[#o.polys + 1] = poly
      p = p + 4 + 4 * ilen
    end
    objs[i] = o
  end
  -- its own MMD and skeleton too: lib/convert.lua can retarget its animations
  local m = { bones = {}, mmd = mmd, skel = skel, same_rig = same_rig or false }
  for b = 1, #skel do
    local o = skel[b][1]
    local src = o >= 0 and objs[o] or { verts = {}, normals = {}, polys = {} }
    m.bones[b] = { parent = skel[b][2], verts = src.verts, normals = src.normals, polys = src.polys }
  end
  -- the entry's own header: most have 16 CLUTs and 128 rows, Hagurumon's
  -- (122) 6 CLUTs and 104 rows (the rest zero, as in VRAM unused)
  local clen, cn = string.unpack("<I4", tim_entry, 9), string.unpack("<I2", tim_entry, 19)
  local ph = string.unpack("<I2", tim_entry, 8 + clen + 10 + 1)
  local rows = { tim_entry:sub(8 + clen + 12 + 1, 8 + clen + 12 + 64 * ph * 2), string.rep("\0", 64 * (128 - ph) * 2) }
  for r = 0, 15 do
    rows[#rows + 1] = (r < cn and tim_entry:sub(20 + 32 * r + 1, 20 + 32 * r + 32) or string.rep("\0", 32)) .. string.rep("\0", 96)
  end
  m.tims = { { w = 64, h = 144, px = table.concat(rows) } }
  return m
end

-- The bones' model-space matrices ({{r, r, r, t} x 3}, 1-based, unit rotation)
-- at animation 0's start pose; with the donor's MMD (rest_from, the same
-- skeleton), its rotations and this model's bone locations, so each bone's
-- mesh lands on the same donor bone as it is (KingSukamon's raised arm is a
-- pose, not its mesh). `rest_anim`: another animation's start instead
-- (Goburimon's walk carries its club forward; its idle holds it overhead);
-- `rest_rot`: {[bone] = {rx, ry, rz}} replacing those rest rotations
-- (WaruMonzaemon's idle stands turned 39 degrees, its head turned back).
function M.pose(mmd, skel, rest_from, rest_anim, rest_rot)
  local w = convert.dw1_pose(mmd, skel, rest_anim or 0, rest_from, rest_rot)
  local out = {}
  for b = 1, #skel do
    local m, t = w[b][1], w[b][2]
    out[b] = {}
    for r = 1, 3 do out[b][r] = { m[r][1] / 4096, m[r][2] / 4096, m[r][3] / 4096, t[r] } end
  end
  return out
end

return M
