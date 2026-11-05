-- A Digimon World model (an MMD and an ALLTIM texture entry) built from a
-- Digimon World 2003 battle model on a DW1 donor's skeleton and animations.
-- A port of research/tools/dw1convert.py (and the DW1 maths of dw1model.py),
-- kept step for step the same so both build identical files.
--
-- Every DW3 bone is given a DW1 bone. An *anchor* starts a rigid group; a
-- *limb* anchor is turned so its direction to a named child matches the DW1
-- bone's direction to its child (the battle stance becomes the donor's
-- standing pose); a *leaf* keeps its parent group's turn; *core* parts
-- aren't turned; a *follow* bone moves with its parent's group. Parts stay
-- joined as on the DW3 model, scaled to a target height with the feet at
-- y 0. The donor's bones then get the DW3 model's proportions: each mapped
-- bone's location, in every animation's start pose, is rewritten so its
-- pivot lands on the joint (only the root bone ever moves its location, so
-- the donor's motions play unchanged). Each vertex goes into its DW1 bone's
-- local space at that rest pose.
--
-- DW1 TMDs as the game uses them: lit gouraud textured triangles (0x34) and
-- quads (0x3C); per corner normal index (low half) | vertex index (high
-- half); cba = 0x7A00 + CLUT row << 6; UVs in 256 x 128; the faces' winding
-- as in DW2003. The texture: 4-bit 256 x 128 with 16 CLUT rows.

local M = {}

-- Python's round() (halves to even), so both versions agree to the bit.
local function round(x)
  local f = math.floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 end
  if d < 0.5 then return f end
  return (f % 2 == 0) and f or f + 1
end

local function clamp16(x) return math.max(-32768, math.min(32767, math.tointeger(round(x)))) end

-- --- DW1: PsyQ fixed-point matrices (4096 = 1.0); RotMatrix is X*Y*Z -------
local function rsin(a) return round(math.sin(a * 2 * math.pi / 4096) * 4096) end
local function rcos(a) return round(math.cos(a * 2 * math.pi / 4096) * 4096) end

local function mul(a, b)
  local out = {}
  for i = 1, 3 do
    out[i] = {}
    for j = 1, 3 do out[i][j] = (a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]) / 4096 end
  end
  return out
end

local function rot_matrix(r)
  local rx, ry, rz = r[1], r[2], r[3]
  local X = { { 4096, 0, 0 }, { 0, rcos(rx), -rsin(rx) }, { 0, rsin(rx), rcos(rx) } }
  local Y = { { rcos(ry), 0, rsin(ry) }, { 0, 4096, 0 }, { -rsin(ry), 0, rcos(ry) } }
  local Z = { { rcos(rz), -rsin(rz), 0 }, { rsin(rz), rcos(rz), 0 }, { 0, 0, 4096 } }
  return mul(mul(X, Y), Z)
end

local function local_matrix(sc, rot, loc)
  local m = rot_matrix(rot)
  local out = {}
  for i = 1, 3 do out[i] = { m[i][1] * sc[1] / 4096, m[i][2] * sc[2] / 4096, m[i][3] * sc[3] / 4096 } end
  return out, { loc[1], loc[2], loc[3] }
end

local function chain(pm, pt, m, t)
  local tt = {}
  for r = 1, 3 do tt[r] = pt[r] + (pm[r][1] * t[1] + pm[r][2] * t[2] + pm[r][3] * t[3]) / 4096 end
  return mul(pm, m), tt
end

local IDENT4096 = { { 4096, 0, 0 }, { 0, 4096, 0 }, { 0, 0, 4096 } }

-- The donor's MMD: {u32 tmd, u32 animations}, the TMD's object count, the
-- animation table's offsets, and an animation's start pose.
local function donor_info(mmd)
  local t, a = string.unpack("<I4I4", mmd)
  local nobj = string.unpack("<I4", mmd, t + 8 + 1)
  local n = string.unpack("<I4", mmd, a + 1) // 4
  local anims = {}
  for i = 0, n - 1 do anims[i] = string.unpack("<I4", mmd, a + 4 * i + 1) end
  return { anim_base = a, anims = anims, nobj = nobj }
end

local function start_pose(mmd, info, anim, bones)
  local p = info.anim_base + info.anims[anim]
  local fc = string.unpack("<I2", mmd, p + 1)
  p = p + 2
  local out = { [0] = { { 4096, 4096, 4096 }, { 0, 0, 0 }, { 0, 0, 0 } } }
  for i = 1, bones - 1 do
    local sc = { 4096, 4096, 4096 }
    if fc & 0x8000 ~= 0 then sc = { string.unpack("<i2i2i2", mmd, p + 1) }; sc[4] = nil; p = p + 6 end
    local rot = { string.unpack("<i2i2i2", mmd, p + 1) }; rot[4] = nil; p = p + 6
    local loc = { string.unpack("<i2i2i2", mmd, p + 1) }; loc[4] = nil; p = p + 6
    out[i] = { sc, rot, loc }
  end
  return out
end

-- --- float helpers (as dw1convert.py) -------------------------------------------
local function norm(v)
  local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if l == 0 then l = 1.0 end
  return { v[1] / l, v[2] / l, v[3] / l }
end

local function mv(m, v)
  return { m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3], m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3], m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3] }
end

local I3 = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

local function rot_between(a, b)
  a, b = norm(a), norm(b)
  local v = { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
  local c = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
  if c < -0.9999 then
    local p = norm(math.abs(a[1]) < 0.9 and { 1, 0, 0 } or { 0, 1, 0 })
    local ax = norm({ a[2] * p[3] - a[3] * p[2], a[3] * p[1] - a[1] * p[3], a[1] * p[2] - a[2] * p[1] })
    local r = {}
    for i = 1, 3 do r[i] = {}; for j = 1, 3 do r[i][j] = 2 * ax[i] * ax[j] - (i == j and 1 or 0) end end
    return r
  end
  local k = 1 / (1 + c)
  local vx = { { 0, -v[3], v[2] }, { v[3], 0, -v[1] }, { -v[2], v[1], 0 } }
  local r = {}
  for i = 1, 3 do
    r[i] = {}
    for j = 1, 3 do
      local vx2 = vx[i][1] * vx[1][j] + vx[i][2] * vx[2][j] + vx[i][3] * vx[3][j]
      r[i][j] = (i == j and 1 or 0) + vx[i][j] + vx2 * k
    end
  end
  return r
end

-- The turn taking direction a to b that also keeps a second axis the same
-- way round: of x, y and z, the one least parallel to a and b (first on a
-- tie), made perpendicular to each. A limb turned by it keeps its outer side
-- outward; the smallest turn leaves that roll to chance (it crossed
-- WarGrowlmon's legs). Same float steps as dw1convert.rot_frame.
local function rot_frame(a, b)
  a, b = norm(a), norm(b)
  local refs = { { 1.0, 0.0, 0.0 }, { 0.0, 1.0, 0.0 }, { 0.0, 0.0, 1.0 } }
  local ref, best = refs[1], nil
  for _, r in ipairs(refs) do
    local c = math.max(math.abs(a[1] * r[1] + a[2] * r[2] + a[3] * r[3]), math.abs(b[1] * r[1] + b[2] * r[2] + b[3] * r[3]))
    if best == nil or c < best then ref, best = r, c end
  end
  local function frame(u)
    local d = u[1] * ref[1] + u[2] * ref[2] + u[3] * ref[3]
    local v = norm({ ref[1] - d * u[1], ref[2] - d * u[2], ref[3] - d * u[3] })
    local w = { u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1] }
    return { u, v, w }
  end
  local f3, f1 = frame(a), frame(b)
  local r = {}
  for i = 1, 3 do
    r[i] = {}
    for j = 1, 3 do r[i][j] = f1[1][i] * f3[1][j] + f1[2][i] * f3[2][j] + f1[3][i] * f3[3][j] end
  end
  return r
end

local function point(M3, v)
  local w = {}
  for i = 1, 3 do w[i] = M3[i][1] * v[1] + M3[i][2] * v[2] + M3[i][3] * v[3] + M3[i][4] end
  return w
end

local function sorted_keys(t)
  local k = {}
  for b in pairs(t) do k[#k + 1] = b end
  table.sort(k)
  return k
end

-- mapping: DW3 bone -> { DW1 bone, kind [, DW3 child, DW1 child] }
-- m3: lib.dw3model's model; mats3: its pose; skel: {[bone] = {obj, parent}}
-- (0-based bones); donor_mmd: the donor's MMD; tim_entry: the donor's
-- ALLTIM entry (its TIM headers are reused).
-- --- Slimming a model to fit the partner's buffer (dw1convert.simplify) -----
-- Vertex and normal indices are 0-based, as in the TMD.

local PERIMETER = { [3] = { 0, 1, 2 }, [4] = { 0, 1, 3, 2 } } -- corners in order round the edge

local function prim_bytes(p) return p.n == 4 and 36 or 28 end

local function obj_bytes(o)
  local n = 8 * (#o.verts + #o.normals)
  for _, p in ipairs(o.prims) do n = n + prim_bytes(p) end
  return n
end

local function face_normal(V, idx)
  local a, b, c = V[idx[1] + 1], V[idx[2] + 1], V[idx[3] + 1]
  local u = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
  local w = { c[1] - a[1], c[2] - a[2], c[3] - a[3] }
  return { u[2] * w[3] - u[3] * w[2], u[3] * w[1] - u[1] * w[3], u[1] * w[2] - u[2] * w[1] }
end

-- Facing within 30 degrees (cos^2 >= 3/4), in doubles (the products don't
-- fit an integer), in the prototype's order.
local function flat_enough(na, nb)
  local a1, a2, a3 = na[1] + 0.0, na[2] + 0.0, na[3] + 0.0
  local b1, b2, b3 = nb[1] + 0.0, nb[2] + 0.0, nb[3] + 0.0
  local d = a1 * b1 + a2 * b2 + a3 * b3
  return d > 0 and d * d * 4.0 >= 3.0 * (a1 * a1 + a2 * a2 + a3 * a3) * (b1 * b1 + b2 * b2 + b3 * b3)
end

local function same_uv(a, b) return a[1] == b[1] and a[2] == b[2] end

-- Two triangles sharing an edge (the same texture coordinates and normals
-- on it, the same CLUT, facing within 30 degrees) become one quad: the GPU
-- draws a quad as exactly those two triangles.
local function pair_triangles(V, prims)
  local tris = {}
  for k, p in ipairs(prims) do if p.n == 3 then tris[#tris + 1] = k end end
  local used, merged = {}, {}
  for at, ka in ipairs(tris) do
    if not used[ka] then
      local A = prims[ka]
      for j = at + 1, #tris do
        local kb = tris[j]
        if not used[kb] then
          local B, q = prims[kb], nil
          if B.clut == A.clut and B.blend == A.blend then
            for r = 0, 2 do
              local x, y = (r + 1) % 3, (r + 2) % 3
              for t = 0, 2 do
                local bx, by = (t + 1) % 3, t
                if B.idx[by + 1] == A.idx[y + 1] and B.idx[bx + 1] == A.idx[x + 1] and same_uv(B.uv[bx + 1], A.uv[x + 1]) and same_uv(B.uv[by + 1], A.uv[y + 1])
                    and B.nrm[bx + 1] == A.nrm[x + 1] and B.nrm[by + 1] == A.nrm[y + 1] then
                  if flat_enough(face_normal(V, A.idx), face_normal(V, B.idx)) then
                    local z = (t + 2) % 3
                    q = { n = 4, clut = A.clut, blend = A.blend, uv = { A.uv[r + 1], A.uv[x + 1], A.uv[y + 1], B.uv[z + 1] },
                      idx = { A.idx[r + 1], A.idx[x + 1], A.idx[y + 1], B.idx[z + 1] }, nrm = { A.nrm[r + 1], A.nrm[x + 1], A.nrm[y + 1], B.nrm[z + 1] } }
                  end
                  break
                end
              end
              if q then break end
            end
          end
          if q then
            used[ka], used[kb], merged[ka] = true, true, q
            break
          end
        end
      end
    end
  end
  local out = {}
  for k, p in ipairs(prims) do
    if merged[k] then out[#out + 1] = merged[k] elseif not used[k] then out[#out + 1] = p end
  end
  return out
end

-- The polygons with their corners renumbered: corners that meet are lost (a
-- quad with one gone becomes a triangle, corners in their order round the
-- edge so it faces the same way; anything less is dropped). Every corner
-- keeps its own texture coordinates and normal.
local function remap(prims, vmap, nmap)
  local out = {}
  for _, p in ipairs(prims) do
    local idx, nrm = {}, {}
    for k = 1, p.n do idx[k], nrm[k] = vmap[p.idx[k]], nmap[p.nrm[k]] end
    local keep, seen = {}, {}
    for _, c in ipairs(PERIMETER[p.n]) do
      if not seen[idx[c + 1]] then
        seen[idx[c + 1]] = true
        keep[#keep + 1] = c
      end
    end
    if #keep == 4 then
      out[#out + 1] = { n = 4, uv = p.uv, clut = p.clut, blend = p.blend, idx = idx, nrm = nrm }
    elseif #keep == 3 then
      local uv, i3, n3 = {}, {}, {}
      for k, c in ipairs(keep) do uv[k], i3[k], n3[k] = p.uv[c + 1], idx[c + 1], nrm[c + 1] end
      out[#out + 1] = { n = 3, uv = uv, clut = p.clut, blend = p.blend, idx = i3, nrm = n3 }
    end
  end
  return out
end

local function used_sorted(prims, field)
  local set, list = {}, {}
  for _, p in ipairs(prims) do
    for _, i in ipairs(p[field]) do
      if not set[i] then
        set[i] = true
        list[#list + 1] = i
      end
    end
  end
  table.sort(list)
  return list
end

-- Only the vertices and normals the polygons use, in order; the triangles paired.
local function compact(o)
  local prims = pair_triangles(o.verts, o.prims)
  local vused, nused = used_sorted(prims, "idx"), used_sorted(prims, "nrm")
  if #vused == 0 and #o.verts > 0 then vused = { 0 } end -- an object keeps a vertex
  if #nused == 0 and #o.normals > 0 then nused = { 0 } end
  local vmap, nmap, verts, normals = {}, {}, {}, {}
  for k, i in ipairs(vused) do vmap[i], verts[k] = k - 1, o.verts[i + 1] end
  for k, i in ipairs(nused) do nmap[i], normals[k] = k - 1, o.normals[i + 1] end
  local out = {}
  for k, p in ipairs(prims) do
    local idx, nrm = {}, {}
    for c = 1, p.n do idx[c], nrm[c] = vmap[p.idx[c]], nmap[p.nrm[c]] end
    out[k] = { n = p.n, uv = p.uv, clut = p.clut, blend = p.blend, idx = idx, nrm = nrm }
  end
  return { verts = verts, normals = normals, prims = out }
end

local NORMAL_COS = 16541266 -- cos(10 degrees) * 4096 * 4096, rounded down

-- The objects (0-based) slimmed until their TMD is at most `budget` bytes,
-- and how many edges that took. Free first: normals within 10 degrees
-- shared, vertices at the same place shared, triangle pairs as quads. Then
-- the shortest edge in the model collapses to its middle (an integer point),
-- again and again: detail goes where the mesh is densest. Vertices marked
-- in an object's `keep` (parts that must stay whole: Kyubimon's face,
-- Sakuyamon's staff) never move.
local function simplify(objs, nobj, budget)
  local work = {}
  for oi = 0, nobj - 1 do
    local o = objs[oi]
    local reps, nmap = {}, {}
    for i, n in ipairs(o.normals) do
      local found
      for k, r in ipairs(reps) do
        if r[1] * n[1] + r[2] * n[2] + r[3] * n[3] >= NORMAL_COS then
          found = k - 1
          break
        end
      end
      if not found then
        found = #reps
        reps[#reps + 1] = { n[1], n[2], n[3] }
      end
      nmap[i - 1] = found
    end
    local place, vmap, verts, keep = {}, {}, {}, {}
    for i, v in ipairs(o.verts) do
      local key = v[1] .. "," .. v[2] .. "," .. v[3]
      if not place[key] then
        place[key] = #verts
        verts[#verts + 1] = { v[1], v[2], v[3] }
        keep[#verts] = false
      end
      vmap[i - 1] = place[key]
      if o.keep and o.keep[i] then keep[place[key] + 1] = true end
    end
    work[oi] = { verts = verts, normals = reps, prims = remap(o.prims, vmap, nmap), keep = keep }
  end
  local sizes = {}
  for oi = 0, nobj - 1 do sizes[oi] = obj_bytes(compact(work[oi])) end
  local function total()
    local n = 12 + 28 * nobj
    for oi = 0, nobj - 1 do n = n + sizes[oi] end
    return n
  end
  local collapsed = 0
  while total() > budget do
    local bd, bo, blo, bhi
    for oi = 0, nobj - 1 do
      local V = work[oi].verts
      for _, p in ipairs(work[oi].prims) do
        local ring = PERIMETER[p.n]
        for k = 1, #ring do
          local a, b = p.idx[ring[k] + 1], p.idx[ring[k % #ring + 1] + 1]
          if not (work[oi].keep[a + 1] or work[oi].keep[b + 1]) then
            local lo, hi = math.min(a, b), math.max(a, b)
            local va, vb = V[a + 1], V[b + 1]
            local dx, dy, dz = va[1] - vb[1], va[2] - vb[2], va[3] - vb[3]
            local d = dx * dx + dy * dy + dz * dz
            if not bd or d < bd or (d == bd and (oi < bo or (oi == bo and (lo < blo or (lo == blo and hi < bhi))))) then
              bd, bo, blo, bhi = d, oi, lo, hi
            end
          end
        end
      end
    end
    if not bd then error("the model doesn't fit the partner buffer") end
    local o = work[bo]
    local A, B = o.verts[blo + 1], o.verts[bhi + 1]
    o.verts[blo + 1] = { (A[1] + B[1]) // 2, (A[2] + B[2]) // 2, (A[3] + B[3]) // 2 }
    local vmap, nmap = {}, {}
    for i = 0, #o.verts - 1 do vmap[i] = (i == bhi) and blo or i end
    for i = 0, #o.normals - 1 do nmap[i] = i end
    o.prims = remap(o.prims, vmap, nmap)
    sizes[bo] = obj_bytes(compact(o))
    collapsed = collapsed + 1
  end
  local out = {}
  for oi = 0, nobj - 1 do out[oi] = compact(work[oi]) end
  return out, collapsed
end

-- More palettes than Digimon World's 16 (Kimeramon has 18, some copies of
-- others): merged until 16 are left (as dw1convert.py's merge_cluts). A
-- palette's colours count where its polygons' UV boxes (inclusive) have
-- texels; each round merges the pair (in row order, the first lowest) whose
-- colours differ least there (squared 5-bit channel differences summed;
-- transparent 0x0000 against any other colour counts 1 << 20), the palette
-- with fewer polygons into the other. Rewrites the polygons' rows; returns
-- the list ({x, y}) of those left, in their old order.
local function merge_cluts(objs, nobj, tim, list)
  local w0, src = tim.w, tim.px
  local function texel(u, v)
    return (string.unpack("<I2", src, (v * w0 + (u >> 2)) * 2 + 1) >> ((u & 3) * 4)) & 15
  end
  local function colour(k, i) return string.unpack("<I2", src, (list[k][2] * w0 + list[k][1] + i) * 2 + 1) end
  local used, count, into = {}, {}, {}
  for k = 1, #list do used[k], count[k], into[k] = {}, 0, k end
  for o = 0, nobj - 1 do
    for _, p in ipairs(objs[o].prims) do
      local k = p.clut + 1
      count[k] = count[k] + 1
      local u0, v0, u1, v1 = 255, 255, 0, 0
      for _, uv in ipairs(p.uv) do
        u0, v0 = math.min(u0, uv[1]), math.min(v0, uv[2])
        u1, v1 = math.max(u1, uv[1]), math.max(v1, uv[2])
      end
      for v = v0, v1 do for u = u0, u1 do used[k][texel(u, v)] = true end end
    end
  end
  local function dist(a, b)
    if (a == 0) ~= (b == 0) then return 1 << 20 end
    local d = 0
    for _, s in ipairs({ 0, 5, 10 }) do d = d + (((a >> s) & 31) - ((b >> s) & 31)) ^ 2 end
    return math.tointeger(d)
  end
  local alive = {}
  for k = 1, #list do alive[k] = k end
  while #alive > 16 do
    local best
    for i = 1, #alive do
      for j = i + 1, #alive do
        local a, b = alive[i], alive[j]
        local c = 0
        for n = 0, 15 do if used[a][n] or used[b][n] then c = c + dist(colour(a, n), colour(b, n)) end end
        if not best or c < best[1] then best = { c, a, b } end
      end
    end
    local a, b = best[2], best[3]
    local keep, drop = a, b
    if count[a] < count[b] then keep, drop = b, a end
    for n = 0, 15 do if used[drop][n] then used[keep][n] = true end end
    count[keep] = count[keep] + count[drop]
    for k = 1, #list do if into[k] == drop then into[k] = keep end end
    for i = #alive, 1, -1 do if alive[i] == drop then table.remove(alive, i) end end
  end
  local row, out = {}, {}
  for i, k in ipairs(alive) do row[k] = i - 1; out[i] = list[k] end
  for o = 0, nobj - 1 do
    for _, p in ipairs(objs[o].prims) do p.clut = row[into[p.clut + 1]] end
  end
  return out
end

-- The parts of a source texture the polygons use, packed into Digimon
-- World's 256 x 128 texels (as research/tools/dw1convert.py's pack_texture):
-- every polygon's UV box (inclusive), boxes that overlap merged into islands
-- (in polygon order: a new box takes in every island it touches, again until
-- none), islands placed on shelves tallest first (then widest, then by source
-- v, u), at full size if they fit, else all scaled by k/20 (k from 19 down
-- to 10; nearest texel). Gives each polygon new UVs; returns the 64 x 128
-- halfwords. tim: {w = halfwords a row, px}.
local function pack_texture(objs, nobj, tim)
  local w0, src = tim.w, tim.px
  local function texel(u, v)
    return (string.unpack("<I2", src, (v * w0 + (u >> 2)) * 2 + 1) >> ((u & 3) * 4)) & 15
  end
  local islands = {} -- {u0, v0, u1, v1, prims}
  for o = 0, nobj - 1 do
    for _, p in ipairs(objs[o].prims) do
      local r = { 255, 255, 0, 0, { p } }
      for _, uv in ipairs(p.uv) do
        r[1], r[2] = math.min(r[1], uv[1]), math.min(r[2], uv[2])
        r[3], r[4] = math.max(r[3], uv[1]), math.max(r[4], uv[2])
      end
      while true do
        local hit = {}
        for k, s in ipairs(islands) do
          if s[1] <= r[3] and r[1] <= s[3] and s[2] <= r[4] and r[2] <= s[4] then hit[#hit + 1] = k end
        end
        if #hit == 0 then break end
        for h = #hit, 1, -1 do
          local s = table.remove(islands, hit[h])
          local members = {}
          for _, q in ipairs(s[5]) do members[#members + 1] = q end
          for _, q in ipairs(r[5]) do members[#members + 1] = q end
          r = { math.min(r[1], s[1]), math.min(r[2], s[2]), math.max(r[3], s[3]), math.max(r[4], s[4]), members }
        end
      end
      islands[#islands + 1] = r
    end
  end
  local order = {}
  for k = 1, #islands do order[k] = k end
  table.sort(order, function(a, b)
    local A, B = islands[a], islands[b]
    if A[4] - A[2] ~= B[4] - B[2] then return A[4] - A[2] > B[4] - B[2] end
    if A[3] - A[1] ~= B[3] - B[1] then return A[3] - A[1] > B[3] - B[1] end
    if A[2] ~= B[2] then return A[2] < B[2] end
    return A[1] < B[1]
  end)
  local place, fit
  for k = 20, 10, -1 do
    place = {}
    local x, y, shelf = 0, 0, 0
    for _, i in ipairs(order) do
      local s = islands[i]
      local w, h = math.max(1, (s[3] - s[1] + 1) * k // 20), math.max(1, (s[4] - s[2] + 1) * k // 20)
      if x + w > 256 then x, y, shelf = 0, y + shelf, 0 end
      place[i] = { x, y, w, h }
      x, shelf = x + w, math.max(shelf, h)
    end
    if y + shelf <= 128 then fit = k; break end
  end
  if not fit then error("its texture doesn't fit in 256 x 128 even at half size") end
  local out = {}
  for i = 1, 256 * 128 do out[i] = 0 end
  for i, pl in pairs(place) do
    local x, y, w, h = pl[1], pl[2], pl[3], pl[4]
    local u0, v0, u1, v1 = islands[i][1], islands[i][2], islands[i][3], islands[i][4]
    local sw, sh = u1 - u0 + 1, v1 - v0 + 1
    for yy = 0, h - 1 do
      local sv = v0 + yy * sh // h
      for xx = 0, w - 1 do out[(y + yy) * 256 + x + xx + 1] = texel(u0 + xx * sw // w, sv) end
    end
    for _, p in ipairs(islands[i][5]) do
      local uv = {}
      for c, t in ipairs(p.uv) do uv[c] = { x + (t[1] - u0) * w // sw, y + (t[2] - v0) * h // sh } end
      p.uv = uv
    end
  end
  local rows = {}
  for r = 0, 127 do
    local hw = {}
    for c = 0, 63 do
      local b = r * 256 + 4 * c
      hw[c + 1] = string.pack("<I2", out[b + 1] | out[b + 2] << 4 | out[b + 3] << 8 | out[b + 4] << 12)
    end
    rows[r + 1] = table.concat(hw)
  end
  return table.concat(rows), { islands = #islands, scale = fit }
end

-- A copy of an animation (its bytes from the start) in which the whole
-- Digimon (bone 0, whose location moves the entity: applyRootMomentum) moves
-- `distance` forward (-z) over `frames` frames from `frame`: a bone-0
-- location-z key (0x8040, frames, -distance) in the keyframe group at
-- `frame` and a stop (0x8040, 1, 0) at frame + frames, each in a new group
-- where the animation has none at that frame (as dw1convert.py).
-- anim_steps: an animation's instructions {offset, kind, frame} (from the
-- animation at offset `at` of d; offsets relative to it).
local function anim_steps(d, at, bones)
  local function u16(o) return (string.unpack("<I2", d, at + o + 1)) end
  local fc = u16(0)
  local p = 2 + (bones - 1) * ((fc & 0x8000 ~= 0) and 18 or 12)
  fc = fc & 0x7FFF
  local steps, first = {}, true
  while at + p + 2 <= #d do
    local w = u16(p)
    local kind, f = w & 0xF000, first and 1 or (w & 0xFFF)
    first = false
    steps[#steps + 1] = { p, kind, f }
    if kind == 0 then
      p = p + 2
      while at + p + 2 <= #d and u16(p) & 0x8000 ~= 0 do
        local bits, x = 0, u16(p) & 0x7FC0
        while x ~= 0 do bits = bits + (x & 1); x = x >> 1 end
        p = p + 4 + 2 * bits
      end
    elseif kind == 0x1000 then p = p + 2
    elseif kind == 0x2000 or kind == 0x4000 then p = p + 4
    elseif kind == 0x3000 then p = p + 8
    else break end
    if (kind == 0 or kind == 0x3000 or kind == 0x4000) and f > fc then break end
  end
  return steps
end

local function add_root_motion(d, bones, frame, frames, distance)
  local steps = anim_steps(d, 0, bones)
  local function place(f, value, div)
    local entry = string.pack("<I2i2i2", 0x8040, div, value)
    for _, st in ipairs(steps) do
      if st[2] == 0 and st[3] == f then return st[1] + 2, entry end
      if (st[2] == 0 or st[2] == 0x3000 or st[2] == 0x4000) and st[3] > f then return st[1], string.pack("<I2", f) .. entry end
    end
    error("the animation has no frame " .. f)
  end
  local a1, b1 = place(frame, -distance, frames)
  local a2, b2 = place(frame + frames, 0, 1)
  if a1 > a2 then a1, b1, a2, b2 = a2, b2, a1, b1 end
  return d:sub(1, a1) .. b1 .. d:sub(a1 + 1, a2) .. b2 .. d:sub(a2 + 1)
end

-- A copy of an animation whose own jump and travel grow between frames a and
-- b (leap = {a, b, up, forward}): bone 1's (the body root's) location-y
-- totals (channel 0x80) times `up` (it rises and falls that much higher,
-- ending about where it did) and bone 0's (the entity's) forward location-z
-- totals (channel 0x40, negative) times `forward` (it travels that much
-- farther). Keys at frames a..b-1. As dw1convert.py.
local function scale_leap(d, bones, leap)
  local a, b, up, forward = leap[1], leap[2], leap[3], leap[4]
  local function bits(x) local n = 0; while x ~= 0 do n = n + (x & 1); x = x >> 1 end return n end
  local edits = {}
  for _, st in ipairs(anim_steps(d, 0, bones)) do
    if st[2] == 0 and st[3] >= a and st[3] < b then
      local p = st[1] + 2
      while p + 2 <= #d and string.unpack("<I2", d, p + 1) & 0x8000 ~= 0 do
        local w = string.unpack("<I2", d, p + 1)
        local flags, bone = w & 0x7FC0, w & 0x3F
        for _, c in ipairs({ { 0x80, up, 1 }, { 0x40, forward, 0 } }) do
          local flag, k, which = c[1], c[2], c[3]
          if bone == which and flags & flag ~= 0 then
            local at = p + 4 + 2 * bits(flags & (0x7FC0 & ~(2 * flag - 1)))
            local v = string.unpack("<i2", d, at + 1)
            if flag == 0x80 or v < 0 then edits[at] = string.pack("<i2", clamp16(v * k)) end
          end
        end
        p = p + 4 + 2 * bits(flags)
      end
    end
  end
  local parts, pos = {}, 0
  for _, o in ipairs(sorted_keys(edits)) do
    parts[#parts + 1] = d:sub(pos + 1, o)
    parts[#parts + 1] = edits[o]
    pos = o + 2
  end
  parts[#parts + 1] = d:sub(pos + 1)
  return table.concat(parts)
end

-- --- a DW1 source's own animation on the converted model (dw1convert.py's
-- retarget; Machinedramon's Infinity Cannon) -----------------------------------
local function world(skel, pose, nb)
  local w = { [0] = { IDENT4096, { 0, 0, 0 } } }
  for i = 1, nb - 1 do
    local par = skel[i][2]
    local m, t = local_matrix(pose[i][1], pose[i][2], pose[i][3])
    w[i] = { chain(w[par][1], w[par][2], m, t) }
  end
  return w
end

local function rots(w, nb)
  local out = {}
  for i = 0, nb - 1 do
    local m = w[i][1]
    out[i] = { { m[1][1] / 4096, m[1][2] / 4096, m[1][3] / 4096 }, { m[2][1] / 4096, m[2][2] / 4096, m[2][3] / 4096 }, { m[3][1] / 4096, m[3][2] / 4096, m[3][3] / 4096 } }
  end
  return out
end

local function mm(a, b)
  local out = {}
  for i = 1, 3 do
    out[i] = {}
    for j = 1, 3 do out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
  end
  return out
end

local function mt(a) return { { a[1][1], a[2][1], a[3][1] }, { a[1][2], a[2][2], a[3][2] }, { a[1][3], a[2][3], a[3][3] } } end

-- The angles (4096 a turn) of rotation m = X(rx) Y(ry) Z(rz), RotMatrix's order.
local function euler_xyz(m)
  local ry = math.asin(math.max(-1.0, math.min(1.0, m[1][3])))
  local rx = math.atan(-m[2][3], m[3][3])
  local rz = math.atan(-m[1][2], m[1][1])
  return { rx * 2048 / math.pi, ry * 2048 / math.pi, rz * 2048 / math.pi }
end

-- A bone pose after `frame` ticks of an animation, as tickAnimation plays it
-- (research/tools/dw1anim.py's pose_at): each tick adds every bone's channel
-- velocities (a key's total / frames), then runs the instructions due on
-- that frame. Bone 0 stays put.
local function pose_at(mmd, info, anim, bones, frame)
  local function u16(o) return (string.unpack("<I2", mmd, o + 1)) end
  local pose = start_pose(mmd, info, anim, bones)
  for i = 0, bones - 1 do
    pose[i] = { { pose[i][1][1], pose[i][1][2], pose[i][1][3] }, { pose[i][2][1], pose[i][2][2], pose[i][2][3] }, { pose[i][3][1], pose[i][3][2], pose[i][3][3] } }
  end
  local p = info.anim_base + info.anims[anim]
  local fc = u16(p) & 0x7FFF
  local has_scale = u16(p) & 0x8000 ~= 0
  p = p + 2 + (bones - 1) * (has_scale and 18 or 12)
  local vel = {}
  for b = 0, bones - 1 do vel[b] = { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 } end
  local cur, end_frame, loop_start, loop_count = 1, 1, nil, 0
  for _ = 1, frame do
    for b = 1, bones - 1 do
      for c = 0, 8 do
        local v = vel[b][c + 1]
        if v ~= 0 then pose[b][c // 3 + 1][c % 3 + 1] = pose[b][c // 3 + 1][c % 3 + 1] + v end
      end
    end
    if p + 2 <= #mmd and u16(p) & 0x1000 ~= 0 and u16(p) & 0x2000 == 0 and (u16(p) & 0xF000) == 0x1000 then
      loop_count = u16(p) & 0xFF; p = p + 2; loop_start = p; end_frame = u16(p) & 0xFFF
    end
    local guard = 0
    while cur == end_frame and p + 2 <= #mmd and guard < 64 do
      guard = guard + 1
      local w = u16(p)
      local kind = w & 0xF000
      if kind == 0 then
        p = p + 2
        while p + 2 <= #mmd and u16(p) & 0x8000 ~= 0 do
          local ins, div = u16(p), string.unpack("<i2", mmd, p + 3)
          p = p + 4
          local b, flag = ins & 0x3F, 0x4000
          for c = 1, 9 do
            if ins & flag ~= 0 then
              local v = string.unpack("<i2", mmd, p + 1)
              p = p + 2
              if b < bones then vel[b][c] = div ~= 0 and v / div or 0.0 end
            end
            flag = flag >> 1
          end
        end
      elseif kind == 0x1000 then
        loop_count = w & 0xFF; p = p + 2; loop_start = p
      elseif kind == 0x2000 then
        if loop_count ~= 0xFF then loop_count = loop_count - 1 end
        if loop_count == 0 or not loop_start then p = p + 4 else cur = u16(p + 2); p = loop_start end
      elseif kind == 0x3000 then p = p + 8
      elseif kind == 0x4000 then p = p + 4
      else break end
      if p + 2 <= #mmd then end_frame = u16(p) & 0xFFF end
    end
    if cur < fc then cur = cur + 1 end
  end
  return pose
end

-- One of a DW1 source's own animations (src: lib/dw1source.lua's model, its
-- MMD's animation `anim`) played on the converted model, as a new animation
-- for the donor's skeleton (dw1convert.py's retarget, the same numbers). Each
-- source tick gives each mapped part's turn from its rest (its source bone's
-- world rotation against rest), applied to the donor bone it rides (in its
-- group's frame: r A r^T); the donor bone's local angles follow (XYZ). A
-- donor bone's motion comes from the source bone that set its pivot, or
-- motion_from {[donor bone] = source bone}; bones without one keep their
-- rest angles. Bone 1 (the body root) also takes the source root's location
-- change (times s). Each bone's keys at most `step` ticks apart, closer
-- (halving) where a straight line between them would miss a tick's angle by
-- more than `tol` (4096 a turn): per channel, a velocity reaching the
-- rounded angle exactly at the segment's end, left out while it changes by
-- `slack` or less; the source's sound instructions are kept.
-- travel: src is another DW1 Digimon, not the converted model's source
-- (Veemon's dive from Tyrannomon's Buster Dive): motion_from names every
-- donor bone's bone there, nothing is turned (no groups), s is the two body
-- roots' heights at rest, and its whole-body travel (bone 0's location keys,
-- which move the entity) is kept, times `travel`.
local function retarget(src, anim, motion_from, mapping, group, s, skel, nb, rest_pose, travel)
  local step, slack, tol = 8, 2, 64
  local sinfo = donor_info(src.mmd)
  local snb = #src.skel + 1
  local s_rest = rots(world(src.skel, start_pose(src.mmd, sinfo, 0, snb), snb), snb)
  local t_rest = rots(world(skel, rest_pose, nb), nb)
  local source = {}
  if not travel then
    for _, b in ipairs(sorted_keys(mapping)) do
      if mapping[b][2] ~= "follow" and not source[mapping[b][1]] then source[mapping[b][1]] = b end
    end
  end
  for t, b in pairs(motion_from or {}) do source[t] = b end
  local keyed = {}
  for _, i in ipairs(sorted_keys(source)) do if i >= 1 and i < nb then keyed[#keyed + 1] = i end end
  local base = sinfo.anim_base + sinfo.anims[anim]
  local fc = string.unpack("<I2", src.mmd, base + 1) & 0x7FFF
  local loc_rest = start_pose(src.mmd, sinfo, 0, snb)[1][3]
  if travel then s = rest_pose[1][3][2] / loc_rest[2] end
  local ang, prev = {}, nil
  local I = { { 1.0, 0.0, 0.0 }, { 0.0, 1.0, 0.0 }, { 0.0, 0.0, 1.0 } }
  for t = 1, fc do
    local sp = pose_at(src.mmd, sinfo, anim, snb, t)
    local sw = rots(world(src.skel, sp, snb), snb)
    local W = { [0] = I }
    local cur = {}
    for i = 1, nb - 1 do
      local par = skel[i][2]
      if source[i] then
        local b = source[i]
        local r = travel and I or group[b][3]
        local A = mm(sw[b], mt(s_rest[b]))
        W[i] = mm(mm(mm(r, A), mt(r)), t_rest[i])
        local a = euler_xyz(mm(mt(W[par]), W[i]))
        if prev then
          for c = 1, 3 do a[c] = prev[i][c] + ((a[c] - prev[i][c] + 2048) % 4096 - 2048) end
        end
        if i == 1 then
          for k = 1, 3 do a[3 + k] = rest_pose[1][3][k] + s * (sp[1][3][k] - loc_rest[k]) end
        end
        cur[i] = a
      else
        W[i] = mm(W[par], mm(mt(t_rest[par]), t_rest[i]))
      end
    end
    ang[t] = {}
    for i, a in pairs(cur) do
      local r = {}
      for c, x in ipairs(a) do r[c] = math.tointeger(round(x)) end
      ang[t][i] = r
    end
    prev = cur
  end
  local out = { string.pack("<I2", fc) }
  for i = 1, nb - 1 do
    local rot, loc = rest_pose[i][2], rest_pose[i][3]
    local a = ang[1][i]
    if a then
      rot = { a[1], a[2], a[3] }
      if #a > 3 then loc = { a[4], a[5], a[6] } end
    end
    out[#out + 1] = string.pack("<i2i2i2i2i2i2", rot[1], rot[2], rot[3], loc[1], loc[2], loc[3])
  end
  local sounds = {}
  for _, st in ipairs(anim_steps(src.mmd, base, snb)) do
    if st[2] == 0x4000 then sounds[#sounds + 1] = { st[3], (string.unpack("<I2", src.mmd, base + st[1] + 3)) } end
  end
  local moves0 = {} -- frame -> bone 0's location keys (the entity's travel)
  if travel then
    local function bits(x) local n = 0; while x ~= 0 do n = n + (x & 1); x = x >> 1 end return n end
    local d = src.mmd
    for _, st in ipairs(anim_steps(d, base, snb)) do
      if st[2] == 0 then
        local q = base + st[1] + 2
        while q + 2 <= #d and string.unpack("<I2", d, q + 1) & 0x8000 ~= 0 do
          local w = string.unpack("<I2", d, q + 1)
          local fl = w & 0x7FC0
          if w & 0x3F == 0 and fl & 0x1C0 ~= 0 then
            local parts = { string.pack("<I2", 0x8000 | (fl & 0x1C0)), d:sub(q + 3, q + 4) }
            local first = bits(fl & 0x7E00)
            for c = first, bits(fl) - 1 do
              parts[#parts + 1] = string.pack("<i2", clamp16(string.unpack("<i2", d, q + 5 + 2 * c) * travel))
            end
            moves0[st[3]] = (moves0[st[3]] or "") .. table.concat(parts)
          end
          q = q + 4 + 2 * bits(fl)
        end
      end
    end
  end
  local cur, last, due = {}, {}, {}
  for _, i in ipairs(keyed) do
    cur[i], last[i], due[i] = {}, {}, 1
    for c, x in ipairs(ang[1][i]) do cur[i][c] = x end
  end
  local flags = { 0x0800, 0x0400, 0x0200, 0x0100, 0x0080, 0x0040 }
  for g = 1, fc do
    local group_bytes = { moves0[g] }
    for _, i in ipairs(keyed) do
      if due[i] == g and g < fc then
        local n = math.min(step, fc - g)
        local function misses()
          for c = 1, #cur[i] do
            for k = 1, n - 1 do
              if math.abs(cur[i][c] + (ang[g + n][i][c] - cur[i][c]) * k / n - ang[g + k][i][c]) > tol then return true end
            end
          end
          return false
        end
        while n > 1 and misses() do n = n // 2 end
        due[i] = g + n
        local word, vals = 0, {}
        for c = 1, #cur[i] do
          local total = ang[g + n][i][c] - cur[i][c]
          local l = last[i][c]
          if l and l[2] == n and math.abs(total - l[1]) <= slack then
            total = l[1]
          else
            word = word | flags[c]
            vals[#vals + 1] = string.pack("<i2", total)
            last[i][c] = { total, n }
          end
          cur[i][c] = cur[i][c] + total
        end
        if word ~= 0 then group_bytes[#group_bytes + 1] = string.pack("<I2i2", 0x8000 | word | i, n) .. table.concat(vals) end
      end
    end
    if #group_bytes > 0 then out[#out + 1] = string.pack("<I2", g) .. table.concat(group_bytes) end
    for _, snd in ipairs(sounds) do
      if snd[1] == g then out[#out + 1] = string.pack("<I2I2", 0x4000 | g, snd[2]) end
    end
  end
  out[#out + 1] = string.pack("<I2", fc + 1) -- never reached: playback stops at fc
  return table.concat(out)
end

-- anim_alias: {[animation] = other animation}: that entry of the animation
-- table plays the other one (a finisher with another of the donor's motions;
-- technique slot k is animation 0x2E + k); or {animation, frame, frames,
-- distance}: a copy of it with that forward travel (add_root_motion); or
-- {motion = animation, from = {...}}: the source's own animation retargeted
-- (a DW1 source only; it replaces the last animation when nothing else plays
-- that one).
-- A DW1 model's bones at an animation's start pose (lib/dw1source.lua): per
-- bone {matrix (4096 = 1, with scale), location}, chained to the parents.
-- rest_from: another MMD on the same skeleton whose rotations (and scales)
-- to take, keeping this one's bone locations.
function M.dw1_pose(mmd, skel, anim, rest_from)
  local nb = #skel + 1
  local info = donor_info(mmd)
  local pose = start_pose(mmd, info, anim or 0, nb)
  if rest_from then
    local other = start_pose(rest_from, donor_info(rest_from), 0, nb)
    for i = 1, nb - 1 do pose[i] = { other[i][1], other[i][2], pose[i][3] } end
  end
  local w = { [0] = { IDENT4096, { 0, 0, 0 } } }
  for i = 1, nb - 1 do
    local par = skel[i][2]
    local m, t = local_matrix(pose[i][1], pose[i][2], pose[i][3])
    w[i] = { chain(w[par][1], w[par][2], m, t) }
  end
  return w
end

-- The animation block without the motions no table entry plays any more (a
-- donor's technique motions the new list doesn't use): the rest in order,
-- each 4-aligned, the table pointed at their new places. `starts`: the
-- table's entries before the aliases (0-based).
local function prune_anims(anims, count, starts)
  local table_, seen, bounds, used = {}, {}, {}, {}
  for a = 0, count - 1 do table_[a] = string.unpack("<I4", anims, 4 * a + 1) end
  for a = 0, count - 1 do
    for _, o in ipairs({ starts[a] or 0, table_[a] }) do
      if o ~= 0 and not seen[o] then seen[o] = true; bounds[#bounds + 1] = o end
    end
    if table_[a] ~= 0 then used[table_[a]] = true end
  end
  table.sort(bounds)
  bounds[#bounds + 1] = #anims
  local parts, len, moved = { anims:sub(1, 4 * count) }, 4 * count, {}
  for i = 1, #bounds - 1 do
    local a, b = bounds[i], bounds[i + 1]
    if used[a] then
      local pad = (4 - len % 4) % 4
      parts[#parts + 1] = string.rep("\0", pad)
      len = len + pad
      moved[a] = len
      parts[#parts + 1] = anims:sub(a + 1, b)
      len = len + (b - a)
    end
  end
  local out = table.concat(parts)
  local words = {}
  for a = 0, count - 1 do words[#words + 1] = string.pack("<I4", table_[a] ~= 0 and moved[table_[a]] or 0) end
  return table.concat(words) .. out:sub(4 * count + 1)
end

function M.convert(mapping, m3, mats3, skel, donor_mmd, tim_entry, target_height, anim_alias, keep, prune)
  local nb = #skel + 1
  local info = donor_info(donor_mmd)
  local pose1 = start_pose(donor_mmd, info, 0, nb)

  local o3 = {}
  for b = 1, #m3.bones do o3[b] = { mats3[b][1][4], mats3[b][2][4], mats3[b][3][4] } end
  local w1 = { [0] = { IDENT4096, { 0, 0, 0 } } }
  for i = 1, nb - 1 do
    local par = skel[i][2]
    local m, t = local_matrix(pose1[i][1], pose1[i][2], pose1[i][3])
    w1[i] = { chain(w1[par][1], w1[par][2], m, t) }
  end
  local o1 = {}
  for i = 0, nb - 1 do o1[i] = w1[i][2] end
  local order = sorted_keys(mapping)
  -- A DW1 source on the donor's own skeleton (lib/dw1source.lua same_rig:
  -- the Sukamon family on Sukamon): every bone's mesh moves onto the same
  -- bone, placed from its own root and ground (no lift), and the donor's
  -- texture moves (face changes) stay when its texture keeps its layout.
  local same_rig = m3.same_rig

  local function groups(s)
    local group, first = {}, nil
    for _, b in ipairs(order) do
      local e = mapping[b]
      local target, kind = e[1], e[2]
      local parent = m3.bones[b].parent
      if kind == "follow" then
        group[b] = group[parent]
      else
        local r
        if kind == "limb" then
          local c3b, c1b = e[3], e[4]
          local turn = e[5] and rot_frame or rot_between -- 5th field: keep the roll
          r = turn({ o3[c3b][1] - o3[b][1], o3[c3b][2] - o3[b][2], o3[c3b][3] - o3[b][3] },
            { o1[c1b][1] - o1[target][1], o1[c1b][2] - o1[target][2], o1[c1b][3] - o1[target][3] })
        elseif kind == "leaf" then
          r = group[parent][3]
        else
          r = I3
        end
        local p1
        if parent == 0 then
          if not first then
            first = b
            -- a DW1 model on its own skeleton's donor keeps its own place
            if same_rig then p1 = { s * o3[b][1], s * o3[b][2], s * o3[b][3] }
            else p1 = { o1[target][1], o1[target][2], o1[target][3] } end
          else
            local g = group[first]
            p1 = {}
            for k = 1, 3 do p1[k] = g[2][k] + s * (o3[b][k] - o3[first][k]) end
          end
        else
          local g = group[parent]
          local x = mv(g[3], { s * (o3[b][1] - g[1][1]), s * (o3[b][2] - g[1][2]), s * (o3[b][3] - g[1][3]) })
          p1 = { g[2][1] + x[1], g[2][2] + x[2], g[2][3] + x[3] }
        end
        group[b] = { o3[b], p1, r }
      end
    end
    return group
  end

  local function place(g, s, b, v)
    local w = point(mats3[b], v)
    local x = mv(g[3], { w[1] - g[1][1], w[2] - g[1][2], w[3] - g[1][3] })
    return { g[2][1] + s * x[1], g[2][2] + s * x[2], g[2][3] + s * x[3] }
  end

  local function y_range(group, s)
    local lo, hi
    for _, b in ipairs(order) do
      for _, v in ipairs(m3.bones[b].verts) do
        local y = place(group[b], s, b, v)[2]
        if not lo or y < lo then lo = y end
        if not hi or y > hi then hi = y end
      end
    end
    return lo, hi
  end

  -- size: the target height, then the feet on the ground
  local lo, hi = y_range(groups(1.0), 1.0)
  -- {scale = k}: k times the source's own size (PlatinumSukamon: 1, Sukamon's)
  local s = type(target_height) == "table" and target_height.scale or target_height / (hi - lo)
  local group = groups(s)
  lo, hi = y_range(group, s)
  local lift = same_rig and 0 or -hi
  local lifted = {}
  for b, g in pairs(group) do lifted[b] = { g[1], { g[2][1], g[2][2] + lift, g[2][3] }, g[3] } end
  group = lifted

  -- the donor's skeleton with the new pivots
  local pivot = {}
  for _, b in ipairs(order) do
    if mapping[b][2] ~= "follow" and not pivot[mapping[b][1]] then pivot[mapping[b][1]] = group[b][2] end
  end
  local new_loc = {}
  w1 = { [0] = { IDENT4096, { 0, 0, 0 } } }
  for i = 1, nb - 1 do
    local par = skel[i][2]
    local sc, rot, loc = pose1[i][1], pose1[i][2], pose1[i][3]
    local pm, pt = w1[par][1], w1[par][2]
    if pivot[i] and par >= 0 then
      local d = { pivot[i][1] - pt[1], pivot[i][2] - pt[2], pivot[i][3] - pt[3] }
      loc = {}
      for j = 1, 3 do loc[j] = clamp16((pm[1][j] * d[1] + pm[2][j] * d[2] + pm[3][j] * d[3]) / 4096) end
      new_loc[i] = loc
    end
    local m, t = local_matrix(sc, rot, loc)
    w1[i] = { chain(pm, pt, m, t) }
  end

  -- the objects: the donor's object numbers, filled from the mapped bones
  local objs = {}
  for o = 0, info.nobj - 1 do objs[o] = { verts = {}, normals = {}, prims = {}, keep = {} } end
  local clut_rows, clut_list = {}, {}
  local faces = {} -- every polygon at the rest pose, for the chart icon (lib/icon.lua)
  for _, b in ipairs(order) do
    local target = mapping[b][1]
    local o = skel[target][1]
    local bone, M3, g = m3.bones[b], mats3[b], group[b]
    if o < 0 and #bone.verts == 0 and #bone.polys == 0 then goto next_bone end
    if o < 0 then error("DW1 bone " .. target .. " has no object") end
    local m1, t1 = w1[target][1], w1[target][2]
    local out = objs[o]
    local vbase, nbase = #out.verts, #out.normals
    local placed_verts = {}
    for _, v in ipairs(bone.verts) do
      local w = place(g, s, b, v)
      placed_verts[#placed_verts + 1] = w
      local d = { w[1] - t1[1], w[2] - t1[2], w[3] - t1[3] }
      local loc = {}
      for i = 1, 3 do loc[i] = clamp16((m1[1][i] * d[1] + m1[2][i] * d[2] + m1[3][i] * d[3]) / 4096) end
      out.verts[#out.verts + 1] = loc
      out.keep[#out.keep + 1] = (keep and keep[b]) and true or false
    end
    for _, n in ipairs(bone.normals) do
      local w = mv(g[3], { M3[1][1] * n[1] + M3[1][2] * n[2] + M3[1][3] * n[3], M3[2][1] * n[1] + M3[2][2] * n[2] + M3[2][3] * n[3], M3[3][1] * n[1] + M3[3][2] * n[2] + M3[3][3] * n[3] })
      local l = norm({ m1[1][1] * w[1] + m1[2][1] * w[2] + m1[3][1] * w[3], m1[1][2] * w[1] + m1[2][2] * w[2] + m1[3][2] * w[3], m1[1][3] * w[1] + m1[2][3] * w[2] + m1[3][3] * w[3] })
      out.normals[#out.normals + 1] = { clamp16(l[1] * 4096), clamp16(l[2] * 4096), clamp16(l[3] * 4096) }
    end
    for _, p in ipairs(bone.polys) do
      if not p.textured then error("DW3 bone " .. b .. " has a polygon that isn't textured") end
      local key = p.tex[4] .. "," .. p.tex[5]
      if not clut_rows[key] then
        clut_list[#clut_list + 1] = { p.tex[4], p.tex[5] }
        clut_rows[key] = #clut_list - 1
      end
      local n = p.quad and 4 or 3
      local idx, nn = {}, {}
      if p.lit then
        local nrm = p.nrm
        if not p.gouraud then nrm = {}; for k = 1, n do nrm[k] = p.nrm[1] end end
        for k = 1, n do idx[k] = vbase + p.idx[k]; nn[k] = nbase + nrm[k] end
      else
        -- unlit (Kyubimon's flame wisps): lit flat here, by the face's own
        -- normal (outward: (v2 - v0) x (v1 - v0) in DW1's winding)
        local v0, v1, v2 = out.verts[vbase + p.idx[1] + 1], out.verts[vbase + p.idx[2] + 1], out.verts[vbase + p.idx[3] + 1]
        local a = { v2[1] - v0[1], v2[2] - v0[2], v2[3] - v0[3] }
        local c = { v1[1] - v0[1], v1[2] - v0[2], v1[3] - v0[3] }
        local fn = norm({ a[2] * c[3] - a[3] * c[2], a[3] * c[1] - a[1] * c[3], a[1] * c[2] - a[2] * c[1] })
        out.normals[#out.normals + 1] = { clamp16(fn[1] * 4096), clamp16(fn[2] * 4096), clamp16(fn[3] * 4096) }
        for k = 1, n do idx[k] = vbase + p.idx[k]; nn[k] = #out.normals - 1 end
      end
      -- DW3's semi-transparency (0xEn: 0 opaque, else ABR n - 1; Kyubimon's
      -- flames: 2, additive) on the unlit ones only (lit ones never had it)
      local blend = p.blend
      if not p.lit and p.abr and p.abr > 0 then blend = p.abr - 1 end
      out.prims[#out.prims + 1] = { n = n, uv = p.uv, clut = clut_rows[key], blend = blend, idx = idx, nrm = nn }
      local pts = {}
      for k = 1, n do pts[k] = placed_verts[p.idx[k] + 1] end
      faces[#faces + 1] = { pts = pts, uv = p.uv, clut = p.tex[5] * m3.tims[1].w + p.tex[4], bone = target, dw3_bone = b } -- CLUT: halfword index in the texture
    end
    ::next_bone::
  end
  if #clut_list > 16 then clut_list = merge_cluts(objs, info.nobj, m3.tims[1], clut_list) end

  -- texture: 256x128 texels, CLUT rows 0..15 (the source's rows as they are
  -- when it's 256 wide and uses only the first 128, else packed)
  local px, tw = m3.tims[1].px, m3.tims[1].w
  local vmax = 0
  for o = 0, info.nobj - 1 do for _, p in ipairs(objs[o].prims) do for _, uv in ipairs(p.uv) do vmax = math.max(vmax, uv[2]) end end end
  local pixels, packed
  if vmax < 128 and tw == 64 then
    pixels = px:sub(1, 128 * 128)
  else
    pixels, packed = pack_texture(objs, info.nobj, m3.tims[1])
  end
  local clut = {}
  for row = 0, 15 do clut[row + 1] = string.rep("\0", 32) end
  for row, c in ipairs(clut_list) do
    local at = (c[2] * tw + c[1]) * 2
    clut[row] = px:sub(at + 1, at + 32)
  end
  local tim = tim_entry:sub(1, 20) .. table.concat(clut) .. tim_entry:sub(8 + 524 + 1, 8 + 524 + 12) .. pixels
  tim = tim .. string.rep("\0", 0x4800 - #tim)

  -- the donor's animations with the new bone locations in every start pose,
  -- then the aliases (before the TMD: it gets whatever room they leave)
  local anims = donor_mmd:sub(info.anim_base + 1)
  -- a same-rig source's texture has the donor's layout (the Sukamon family's
  -- four eye blocks in the same places): its face changes work as they are
  local keep_moves = same_rig and packed == nil
  local edits = {}
  for a = 0, #info.anims do
    local off = info.anims[a]
    if off and off ~= 0 then
      local fc = string.unpack("<I2", anims, off + 1)
      local step = fc & 0x8000 ~= 0 and 18 or 12
      for i, loc in pairs(new_loc) do edits[off + 2 + (i - 1) * step + step - 6] = string.pack("<i2i2i2", loc[1], loc[2], loc[3]) end
      -- Texture moves (0x3xxx {src, size, dest}: copy a block of the
      -- Digimon's own texture, the donor's eye and face changes) would
      -- copy across another layout: each copies its block onto itself.
      for _, st in ipairs(anim_steps(anims, off, nb)) do
        if st[2] == 0x3000 and not keep_moves then
          local src, size = string.unpack("<I2I2", anims, off + st[1] + 2 + 1)
          edits[off + st[1] + 2] = string.pack("<I2I2I2", src, size, src)
        end
      end
    end
  end
  local parts, pos = {}, 0
  for _, o in ipairs(sorted_keys(edits)) do
    parts[#parts + 1] = anims:sub(pos + 1, o)
    parts[#parts + 1] = edits[o]
    pos = o + 6
  end
  parts[#parts + 1] = anims:sub(pos + 1)
  anims = table.concat(parts)
  -- An alias past the table's end (techniques from another Digimon with more
  -- of them than the donor has slots): the table grows, everything after it
  -- moves down.
  local count, offs = #info.anims + 1, {}
  for a = 0, count - 1 do offs[a] = info.anims[a] end
  local need = count
  for dst in pairs(anim_alias or {}) do need = math.max(need, dst + 1) end
  if need > count then
    local delta, words = 4 * (need - count), {}
    for a = 0, need - 1 do
      local o = offs[a] or 0
      if o ~= 0 then o = o + delta end
      offs[a] = o
      words[#words + 1] = string.pack("<I4", o)
    end
    anims = table.concat(words) .. anims:sub(4 * count + 1)
  end
  -- A retargeted motion replacing the last animation, used nowhere else:
  -- that one goes (its room is the TMD's).
  for _, dst in ipairs(sorted_keys(anim_alias or {})) do
    local src, o = anim_alias[dst], offs[dst]
    if type(src) == "table" and src.motion and o and o ~= 0 then
      local top, uses = 0, 0
      for a = 0, need - 1 do
        local x = offs[a] or 0
        if x > top then top = x end
        if x == o then uses = uses + 1 end
      end
      if o == top and uses == 1 then anims = anims:sub(1, o) end
    end
  end
  for _, dst in ipairs(sorted_keys(anim_alias or {})) do
    local src = anim_alias[dst]
    local off
    if type(src) == "table" and src.motion then
      local rest_pose = {}
      for i = 0, nb - 1 do rest_pose[i] = { pose1[i][1], pose1[i][2], new_loc[i] or pose1[i][3] } end
      local blob = retarget(src.other or m3, src.motion, src.from, mapping, group, s, skel, nb, rest_pose, src.travel)
      anims = anims .. string.rep("\0", (4 - #anims % 4) % 4)
      off = #anims
      anims = anims .. blob
    elseif type(src) == "table" then
      local start, stop = offs[src[1]], #anims
      for a = 0, need - 1 do
        local o = offs[a]
        if o and o > start and o < stop then stop = o end
      end
      local blob = anims:sub(start + 1, stop)
      if src[5] then blob = scale_leap(blob, nb, src[5]) end
      if src[2] then blob = add_root_motion(blob, nb, src[2], src[3], src[4]) end
      anims = anims .. string.rep("\0", (4 - #anims % 4) % 4)
      off = #anims
      anims = anims .. blob
    else
      off = offs[src]
    end
    anims = anims:sub(1, 4 * dst) .. string.pack("<I4", off) .. anims:sub(4 * dst + 5)
  end
  -- The donor's motions nothing plays any more go, when asked (`prune`:
  -- Kyubimon, whose mesh doesn't fit beside all of Garurumon's)
  if prune then anims = prune_anims(anims, need, offs) end


  -- TMD, slimmed when it doesn't fit the partner's buffer (0x18800 bytes)
  -- next to the animations (built first: the TMD gets whatever room they leave)
  -- A donor object nothing maps to (MetalGreymon's small side parts under
  -- WarGrowlmon) still needs a mesh: the game crashes on an empty one. It
  -- gets one vertex at its pivot and a triangle of zero size (draws nothing).
  local budget = 0x18800 - 8 - #anims
  local empty = {}
  for o = 0, info.nobj - 1 do if #objs[o].prims == 0 then empty[#empty + 1] = o end end
  budget = budget - (8 + 8 + 28) * #empty
  local size, collapsed = 12 + 28 * info.nobj, -1
  for o = 0, info.nobj - 1 do size = size + obj_bytes(objs[o]) end
  if size > budget then objs, collapsed = simplify(objs, info.nobj, budget) end
  for _, o in ipairs(empty) do
    objs[o] = { verts = { { 0, 0, 0 } }, normals = { { 0, -4096, 0 } },
      prims = { { n = 3, uv = { { 0, 0 }, { 0, 0 }, { 0, 0 } }, clut = 0, idx = { 0, 0, 0 }, nrm = { 0, 0, 0 } } } }
  end
  local body, tab = {}, {}
  local at = 28 * info.nobj
  for o = 0, info.nobj - 1 do
    local ob = objs[o]
    local vb, nbs, pb = {}, {}, {}
    for _, v in ipairs(ob.verts) do vb[#vb + 1] = string.pack("<i2i2i2i2", v[1], v[2], v[3], 0) end
    for _, n in ipairs(ob.normals) do nbs[#nbs + 1] = string.pack("<i2i2i2i2", n[1], n[2], n[3], 0) end
    for _, p in ipairs(ob.prims) do
      local uv = p.uv
      local cba = 0x7A00 + (p.clut << 6)
      -- a semi-transparent polygon (blend: its blend mode) keeps it: TMD mode
      -- bit 2 and the tsb's bits 5-6 (updateTMDTextureData leaves those)
      local tsb = p.blend and (0x5 | p.blend << 5) or 0x5
      local words = { uv[1][1] | uv[1][2] << 8 | cba << 16, uv[2][1] | uv[2][2] << 8 | tsb << 16, uv[3][1] | uv[3][2] << 8 }
      if p.n == 4 then words[#words + 1] = uv[4][1] | uv[4][2] << 8 end
      for k = 1, p.n do words[#words + 1] = p.nrm[k] | p.idx[k] << 16 end
      local olen, mode = 9, 0x34
      if p.n == 4 then olen, mode = 12, 0x3C end
      if p.blend then mode = mode | 2 end
      pb[#pb + 1] = string.pack("<I1I1I1I1", olen, #words, 0, mode)
      for _, w in ipairs(words) do pb[#pb + 1] = string.pack("<I4", w) end
    end
    vb, nbs, pb = table.concat(vb), table.concat(nbs), table.concat(pb)
    tab[#tab + 1] = string.pack("<I4I4I4I4I4I4I4", at, #ob.verts, at + #vb, #ob.normals, at + #vb + #nbs, #ob.prims, 0)
    body[#body + 1] = vb .. nbs .. pb
    at = at + #vb + #nbs + #pb
  end
  local tmd = string.pack("<I4I4I4", 0x41, 0, info.nobj) .. table.concat(tab) .. table.concat(body)

  local mmd = string.pack("<I4I4", 8, 8 + #tmd) .. tmd .. anims
  local verts, prims = 0, 0
  for o = 0, info.nobj - 1 do verts = verts + #objs[o].verts; prims = prims + #objs[o].prims end
  local pivots = {}
  for i = 0, nb - 1 do pivots[i] = w1[i][2] end
  return mmd, tim, { scale = s, collapsed = collapsed, verts = verts, prims = prims, cluts = #clut_list, bytes = #mmd, faces = faces, texture = px, texture_w = tw, packed = packed, pivots = pivots }
end

return M
