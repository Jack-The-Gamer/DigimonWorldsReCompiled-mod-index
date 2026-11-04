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
          if B.clut == A.clut then
            for r = 0, 2 do
              local x, y = (r + 1) % 3, (r + 2) % 3
              for t = 0, 2 do
                local bx, by = (t + 1) % 3, t
                if B.idx[by + 1] == A.idx[y + 1] and B.idx[bx + 1] == A.idx[x + 1] and same_uv(B.uv[bx + 1], A.uv[x + 1]) and same_uv(B.uv[by + 1], A.uv[y + 1])
                    and B.nrm[bx + 1] == A.nrm[x + 1] and B.nrm[by + 1] == A.nrm[y + 1] then
                  if flat_enough(face_normal(V, A.idx), face_normal(V, B.idx)) then
                    local z = (t + 2) % 3
                    q = { n = 4, clut = A.clut, uv = { A.uv[r + 1], A.uv[x + 1], A.uv[y + 1], B.uv[z + 1] },
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
      out[#out + 1] = { n = 4, uv = p.uv, clut = p.clut, idx = idx, nrm = nrm }
    elseif #keep == 3 then
      local uv, i3, n3 = {}, {}, {}
      for k, c in ipairs(keep) do uv[k], i3[k], n3[k] = p.uv[c + 1], idx[c + 1], nrm[c + 1] end
      out[#out + 1] = { n = 3, uv = uv, clut = p.clut, idx = i3, nrm = n3 }
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
    out[k] = { n = p.n, uv = p.uv, clut = p.clut, idx = idx, nrm = nrm }
  end
  return { verts = verts, normals = normals, prims = out }
end

local NORMAL_COS = 16541266 -- cos(10 degrees) * 4096 * 4096, rounded down

-- The objects (0-based) slimmed until their TMD is at most `budget` bytes,
-- and how many edges that took. Free first: normals within 10 degrees
-- shared, vertices at the same place shared, triangle pairs as quads. Then
-- the shortest edge in the model collapses to its middle (an integer point),
-- again and again: detail goes where the mesh is densest.
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
    local place, vmap, verts = {}, {}, {}
    for i, v in ipairs(o.verts) do
      local key = v[1] .. "," .. v[2] .. "," .. v[3]
      if not place[key] then
        place[key] = #verts
        verts[#verts + 1] = { v[1], v[2], v[3] }
      end
      vmap[i - 1] = place[key]
    end
    work[oi] = { verts = verts, normals = reps, prims = remap(o.prims, vmap, nmap) }
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

function M.convert(mapping, m3, mats3, skel, donor_mmd, tim_entry, target_height)
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
            p1 = { o1[target][1], o1[target][2], o1[target][3] }
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
  local s = target_height / (hi - lo)
  local group = groups(s)
  lo, hi = y_range(group, s)
  local lift = -hi
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
  for o = 0, info.nobj - 1 do objs[o] = { verts = {}, normals = {}, prims = {} } end
  local clut_rows, clut_list = {}, {}
  local faces = {} -- every polygon at the rest pose, for the chart icon (lib/icon.lua)
  for _, b in ipairs(order) do
    local target = mapping[b][1]
    local o = skel[target][1]
    if o < 0 then error("DW1 bone " .. target .. " has no object") end
    local bone, M3, g = m3.bones[b], mats3[b], group[b]
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
    end
    for _, n in ipairs(bone.normals) do
      local w = mv(g[3], { M3[1][1] * n[1] + M3[1][2] * n[2] + M3[1][3] * n[3], M3[2][1] * n[1] + M3[2][2] * n[2] + M3[2][3] * n[3], M3[3][1] * n[1] + M3[3][2] * n[2] + M3[3][3] * n[3] })
      local l = norm({ m1[1][1] * w[1] + m1[2][1] * w[2] + m1[3][1] * w[3], m1[1][2] * w[1] + m1[2][2] * w[2] + m1[3][2] * w[3], m1[1][3] * w[1] + m1[2][3] * w[2] + m1[3][3] * w[3] })
      out.normals[#out.normals + 1] = { clamp16(l[1] * 4096), clamp16(l[2] * 4096), clamp16(l[3] * 4096) }
    end
    for _, p in ipairs(bone.polys) do
      if not (p.textured and p.lit) then error("DW3 bone " .. b .. " has a polygon that isn't textured and lit") end
      local key = p.tex[4] .. "," .. p.tex[5]
      if not clut_rows[key] then
        clut_list[#clut_list + 1] = { p.tex[4], p.tex[5] }
        clut_rows[key] = #clut_list - 1
      end
      local n = p.quad and 4 or 3
      local nrm = p.nrm
      if not p.gouraud then nrm = {}; for k = 1, n do nrm[k] = p.nrm[1] end end
      local idx, nn = {}, {}
      for k = 1, n do idx[k] = vbase + p.idx[k]; nn[k] = nbase + nrm[k] end
      out.prims[#out.prims + 1] = { n = n, uv = p.uv, clut = clut_rows[key], idx = idx, nrm = nn }
      local pts = {}
      for k = 1, n do pts[k] = placed_verts[p.idx[k] + 1] end
      faces[#faces + 1] = { pts = pts, uv = p.uv, clut = p.tex[5] * 64 + p.tex[4], bone = target, dw3_bone = b } -- CLUT: halfword index in the texture
    end
  end
  if #clut_list > 16 then error(#clut_list .. " CLUTs; Digimon World has room for 16") end

  -- texture: 256x128 texels, CLUT rows 0..15
  local px = m3.tims[1].px
  local vmax = 0
  for o = 0, info.nobj - 1 do for _, p in ipairs(objs[o].prims) do for _, uv in ipairs(p.uv) do vmax = math.max(vmax, uv[2]) end end end
  if vmax >= 128 then error("the texture uses rows up to " .. vmax .. ": Digimon World has 128 (repacking not done yet)") end
  local clut = {}
  for row = 0, 15 do clut[row + 1] = string.rep("\0", 32) end
  for row, c in ipairs(clut_list) do
    local at = (c[2] * 64 + c[1]) * 2
    clut[row] = px:sub(at + 1, at + 32)
  end
  local tim = tim_entry:sub(1, 20) .. table.concat(clut) .. tim_entry:sub(8 + 524 + 1, 8 + 524 + 12) .. px:sub(1, 128 * 128)
  tim = tim .. string.rep("\0", 0x4800 - #tim)

  -- TMD, slimmed when it doesn't fit the partner's buffer (0x18800 bytes)
  -- next to the donor's animations
  -- A donor object nothing maps to (MetalGreymon's small side parts under
  -- WarGrowlmon) still needs a mesh: the game crashes on an empty one. It
  -- gets one vertex at its pivot and a triangle of zero size (draws nothing).
  local budget = 0x18800 - 8 - (#donor_mmd - info.anim_base)
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
      local words = { uv[1][1] | uv[1][2] << 8 | cba << 16, uv[2][1] | uv[2][2] << 8 | 0x5 << 16, uv[3][1] | uv[3][2] << 8 }
      if p.n == 4 then words[#words + 1] = uv[4][1] | uv[4][2] << 8 end
      for k = 1, p.n do words[#words + 1] = p.nrm[k] | p.idx[k] << 16 end
      local olen, mode = 9, 0x34
      if p.n == 4 then olen, mode = 12, 0x3C end
      pb[#pb + 1] = string.pack("<I1I1I1I1", olen, #words, 0, mode)
      for _, w in ipairs(words) do pb[#pb + 1] = string.pack("<I4", w) end
    end
    vb, nbs, pb = table.concat(vb), table.concat(nbs), table.concat(pb)
    tab[#tab + 1] = string.pack("<I4I4I4I4I4I4I4", at, #ob.verts, at + #vb, #ob.normals, at + #vb + #nbs, #ob.prims, 0)
    body[#body + 1] = vb .. nbs .. pb
    at = at + #vb + #nbs + #pb
  end
  local tmd = string.pack("<I4I4I4", 0x41, 0, info.nobj) .. table.concat(tab) .. table.concat(body)

  -- the donor's animations with the new bone locations in every start pose
  local anims = donor_mmd:sub(info.anim_base + 1)
  local edits = {}
  for a = 0, #info.anims do
    local off = info.anims[a]
    if off and off ~= 0 then
      local fc = string.unpack("<I2", anims, off + 1)
      local step = fc & 0x8000 ~= 0 and 18 or 12
      for i, loc in pairs(new_loc) do edits[off + 2 + (i - 1) * step + step - 6] = string.pack("<i2i2i2", loc[1], loc[2], loc[3]) end
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

  local mmd = string.pack("<I4I4", 8, 8 + #tmd) .. tmd .. anims
  local verts, prims = 0, 0
  for o = 0, info.nobj - 1 do verts = verts + #objs[o].verts; prims = prims + #objs[o].prims end
  local pivots = {}
  for i = 0, nb - 1 do pivots[i] = w1[i][2] end
  return mmd, tim, { scale = s, collapsed = collapsed, verts = verts, prims = prims, cluts = #clut_list, bytes = #mmd, faces = faces, texture = px, pivots = pivots }
end

return M
