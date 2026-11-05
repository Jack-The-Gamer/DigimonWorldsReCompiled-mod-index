-- A new Digimon's technique list from its specialties (backports.lua
-- `techniques = { auto = true, ... }`): the user asked that a Digimon with
-- given specialties also know techniques of those kinds. A port of
-- research/tools/dw1convert.py's auto_techniques (the same lists, so the
-- same models).
--
-- Up to 15 techniques of those kinds (0x00..0x38, but the second Dynamite
-- Kick 0x30 and Horizontal Kick 0x39, twins of 0x2C and 0x37): a kind's 8,
-- two kinds 8 + 7, three 5 + 5 + 5 (each takes the room left over the kinds
-- left, rounded up), the donor's own first (in its slot order), then by
-- number; listed by kind and number, the finisher last (16 slots in all).
-- Each plays the donor's own motion for it, else the donor technique motion
-- of the same kind and range (else the same kind and range class: close,
-- distant, on itself; else that class; else kind; else any), the least used
-- so far, then the lowest slot; the finisher the slot of fin_anim (or its
-- own).

local M = {}

local MOVE_DATA = 0x8012623C            -- the game's, 16 bytes a technique: range +8, kind +9
local TWIN = { [0x30] = 0x2C, [0x39] = 0x37 }
local RCLASS = { [0] = 0, [1] = 1, [2] = 2, [3] = 2, [4] = 4 }

-- u8(addr): a byte of the executable; donor_moves: the donor's 16
-- DigimonPara.moves; kinds: specialties in order. Returns moves (technique
-- by slot) and motions (the donor slot each plays), both 1-based lists.
function M.build(u8, donor_moves, kinds, fin_from, fin_anim)
  local function kind(t) return u8(MOVE_DATA + 16 * t + 9) end
  local function rng(t) return u8(MOVE_DATA + 16 * t + 8) end
  local dm = donor_moves
  local own = {}
  for k = 0, 15 do
    local t = dm[k + 1]
    if t < 0x3A then
      local c = TWIN[t] or t
      if own[c] == nil then own[c] = k end
    end
  end
  local left, chosen = 15, {}
  for i, K in ipairs(kinds) do
    local pool = {}
    for t = 0, 0x38 do if not TWIN[t] and kind(t) == K then pool[#pool + 1] = t end end
    local rest = #kinds - i + 1
    local q = math.min(#pool, (left + rest - 1) // rest)
    local mine, others = {}, {}
    for _, t in ipairs(pool) do
      if own[t] then mine[#mine + 1] = t else others[#others + 1] = t end
    end
    table.sort(mine, function(a, b) return own[a] < own[b] end)
    local take = {}
    for _, t in ipairs(mine) do if #take < q then take[#take + 1] = t end end
    for _, t in ipairs(others) do if #take < q then take[#take + 1] = t end end
    table.sort(take)
    for _, t in ipairs(take) do chosen[#chosen + 1] = t end
    left = left - q
  end
  local used = {}
  for k = 0, 15 do used[k] = 0 end
  local moves, motions = {}, {}
  for _, t in ipairs(chosen) do
    local m = own[t]
    if m == nil then
      local best
      for k = 0, 15 do
        local u = dm[k + 1]
        if u < 0x3A then
          local key = {
            (kind(u) == kind(t) and rng(u) == rng(t)) and 0 or 1,
            (kind(u) == kind(t) and RCLASS[rng(u)] == RCLASS[rng(t)]) and 0 or 1,
            RCLASS[rng(u)] == RCLASS[rng(t)] and 0 or 1,
            kind(u) == kind(t) and 0 or 1,
            used[k], k }
          local better = not best
          if best then
            for j = 1, #key do
              if key[j] ~= best[j] then better = key[j] < best[j]; break end
            end
          end
          if better then best = key end
        end
      end
      m = best[6]
    end
    used[m] = used[m] + 1
    moves[#moves + 1] = t
    motions[#motions + 1] = m
  end
  moves[#moves + 1] = fin_from
  local want = fin_anim or fin_from
  for k = 0, 15 do
    if dm[k + 1] == want then motions[#motions + 1] = k; break end
  end
  return moves, motions
end

return M
