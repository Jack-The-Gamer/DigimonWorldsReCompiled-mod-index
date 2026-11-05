-- A flattened Digimon's picture. In battle a Digimon hit by a flattening
-- technique (status 4) isn't drawn as its model: renderFlatDigimon draws a
-- 16 x 16 picture from its own texture instead, standing upright as tall as
-- the Digimon (u 0xE0 / 0xF0, v 0x60 / 0x70 of its 256 x 128 texels, with its
-- CLUT 15): frames 0 and 1 while it walks (they alternate every 10 frames), 2
-- when it attacks, 3 when it's hit. The game's own are side views facing
-- left (the Digimon's front, -z, on the left), filling the box from the feet
-- up: white, a dark outline round them and between parts.
--
-- A new Digimon's texture keeps that corner and CLUT 15 free (lib/convert.lua);
-- this draws the picture there from its model at rest (lib/convert.lua's
-- info.faces): the side view, 4 x 4 samples a pixel, a pixel filled when at
-- least 4 of them are; outlined; lines where a part lies well in front of the
-- one beside it. Frame 1 is frame 0 a pixel lower (a step), frame 2 leans
-- forward, frame 3 back. A Digimon World Digimon's own picture (an NPC made
-- raisable) is copied from its texture instead (M.copy).

local M = {}

local N, SS = 16, 4                        -- the picture, samples a pixel
local OUTLINE, FILL = 1, 2                 -- texel values (CLUT 15: 0 transparent)
local CLUT = string.pack("<" .. string.rep("I2", 16), 0x0000, 0x0421, 0x7FFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x8000) -- the game's (Agumon's)
local INNER_EDGE = 0.12                    -- a part this far in front of its neighbour (share of the size) gets a line
local TIM_CLUT, TIM_PIXELS, ROW = 20, 20 + 512 + 12, 128 -- byte offsets in a 0x4800 texture entry

-- One frame: N x N values (row major, 1-based), from the faces' (z, y) with
-- x as depth (seen from +x), sheared by `lean` (pixels at the top, + forward)
-- and moved down `drop` pixels.
local function frame(faces, box, lean, drop)
  local G = N * SS
  local z0, z1, y0, y1 = box[1], box[2], box[3], box[4]
  local size = math.max(z1 - z0, y1 - y0)
  local k = (G - 2 * SS) / size                   -- a pixel of outline on each side
  local oz = (G - (z1 - z0) * k) / 2
  local oy = G - SS - (y1 - y0) * k               -- the feet on the last row but the outline
  local depth, part = {}, {}
  for i = 1, G * G do depth[i] = -math.huge end
  local function to_grid(p)
    local gy = (p[2] - y0) * k + oy + drop * SS
    local up = (G - gy) / G                       -- 0 at the bottom, 1 at the top
    local gz = (p[3] - z0) * k + oz - lean * SS * up
    return gz, gy, p[1]
  end
  for _, f in ipairs(faces) do
    local tris = { { 1, 2, 3 } }
    if #f.pts == 4 then tris[2] = { 2, 4, 3 } end
    for _, t in ipairs(tris) do
      local ax, ay, az = to_grid(f.pts[t[1]])
      local bx, by, bz = to_grid(f.pts[t[2]])
      local cx, cy, cz = to_grid(f.pts[t[3]])
      local den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
      if den ~= 0 then
        local minx, maxx = math.max(0, math.floor(math.min(ax, bx, cx))), math.min(G - 1, math.ceil(math.max(ax, bx, cx)))
        local miny, maxy = math.max(0, math.floor(math.min(ay, by, cy))), math.min(G - 1, math.ceil(math.max(ay, by, cy)))
        for y = miny, maxy do
          for x = minx, maxx do
            local px, py = x + 0.5, y + 0.5
            local l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
            local l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
            local l3 = 1 - l1 - l2
            if l1 >= 0 and l2 >= 0 and l3 >= 0 then
              local d = l1 * az + l2 * bz + l3 * cz
              local i = y * G + x + 1
              if d > depth[i] then depth[i], part[i] = d, f.bone end
            end
          end
        end
      end
    end
  end
  -- each pixel: filled when 4 of its 16 samples are; its part and depth those
  -- of its nearest sample
  local fill, pp, pd = {}, {}, {}
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local n, best = 0, -math.huge
      local bp
      for sy = 0, SS - 1 do
        for sx = 0, SS - 1 do
          local i = (y * SS + sy) * G + x * SS + sx + 1
          if depth[i] > -math.huge then
            n = n + 1
            if depth[i] > best then best, bp = depth[i], part[i] end
          end
        end
      end
      local j = y * N + x + 1
      fill[j], pp[j], pd[j] = n >= 4, bp, best
    end
  end
  local out = {}
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local j = y * N + x + 1
      local v = 0
      if fill[j] then
        v = FILL
        -- a line where the part behind meets one well in front of it
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and nx < N and ny >= 0 and ny < N then
            local n = ny * N + nx + 1
            if fill[n] and pp[n] ~= pp[j] and pd[n] - pd[j] > INNER_EDGE * size then v = OUTLINE end
          end
        end
      else
        for dy = -1, 1 do
          for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            if nx >= 0 and nx < N and ny >= 0 and ny < N and fill[ny * N + nx + 1] then v = OUTLINE end
          end
        end
      end
      out[j] = v
    end
  end
  return out
end

-- The four frames, written into the texture entry `tim` (0x4800 bytes) at
-- the corner, with CLUT 15; returns the new entry.
function M.draw(tim, faces)
  local box = { math.huge, -math.huge, math.huge, -math.huge }
  for _, f in ipairs(faces) do
    for _, p in ipairs(f.pts) do
      box[1], box[2] = math.min(box[1], p[3]), math.max(box[2], p[3])
      box[3], box[4] = math.min(box[3], p[2]), math.max(box[4], p[2])
    end
  end
  local frames = { frame(faces, box, 0, 0), frame(faces, box, 0, 1), frame(faces, box, 2, 0), frame(faces, box, -2, 0) }
  local bytes = {}
  for i = 1, #tim do bytes[i] = tim:byte(i) end
  for f = 0, 3 do
    local u0, v0 = (f % 2 == 0) and 0xE0 or 0xF0, (f < 2) and 0x60 or 0x70
    local px = frames[f + 1]
    for y = 0, N - 1 do
      for x = 0, N - 1, 2 do
        bytes[TIM_PIXELS + (v0 + y) * ROW + (u0 + x) // 2 + 1] = px[y * N + x + 1] | (px[y * N + x + 2] << 4)
      end
    end
  end
  for i = 1, 32 do bytes[TIM_CLUT + 15 * 32 + i] = CLUT:byte(i) end
  local parts = {}
  for i = 1, #bytes, 4096 do parts[#parts + 1] = string.char(table.unpack(bytes, i, math.min(#bytes, i + 4095))) end
  return table.concat(parts)
end

-- A Digimon World Digimon's own picture and CLUT 15, from its texture entry
-- `from` into `tim`.
function M.copy(tim, from)
  local out = tim:sub(1, TIM_CLUT + 15 * 32) .. from:sub(TIM_CLUT + 15 * 32 + 1, TIM_CLUT + 16 * 32)
    .. tim:sub(TIM_CLUT + 16 * 32 + 1, TIM_PIXELS)
  for v = 0x60, 0x7F do
    local at = TIM_PIXELS + v * ROW + 0xE0 // 2
    out = out .. tim:sub(#out + 1, at) .. from:sub(at + 1, at + 16)
  end
  return out .. tim:sub(#out + 1)
end

return M
