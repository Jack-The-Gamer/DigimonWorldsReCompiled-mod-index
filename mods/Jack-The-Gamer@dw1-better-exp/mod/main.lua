-- DW1 Better EXP: twice the stat gains from gym training, three times the
-- stat gains from battles.
--
-- Both put a Digimon's stat gains in the same six-number list (HP, MP,
-- Offense, Defense, Speed, Brains) and then show the window that adds them
-- to the Digimon. The mod multiplies the list in between, so the window
-- shows (and adds) the bigger numbers.
--
-- * Battles: one function in the main program fills the list after a win.
--   The mod hooks the instruction right after it returns.
-- * Training: each exercise, in both gym code files (overlays loaded when
--   you train), stores its six gains one after another and then calls the
--   window. The mod hooks that call.
--
-- Both are found by their machine code rather than by fixed addresses, and
-- the list's address is read from the game's own code, so other releases of
-- the game should work too.

local TRAINING = tonumber(dwrc.options.training) or 2
local BATTLE = tonumber(dwrc.options.battle) or 3

-- Main program: `jal <battle gains>` followed by the window's setup.
local BATTLE_CALL = "0c?????? 27a40024 2402ffb2 a7a20028 24020036 a7a2002a"
-- Training: six `lui at, hi` / `sh rX, lo(at)` pairs, then `jal <window>`.
local TRAINING_STORES = "3c01???? a4?????? 3c01???? a4?????? 3c01???? a4?????? " ..
                        "3c01???? a4?????? 3c01???? a4?????? 3c01???? a4?????? 0c??????"

local CODE_FROM, CODE_TO = 0x80080000, 0x80140000
local CHECK_EVERY = 20 -- frames

local buf = nil        -- the gains list, read from the battle code
local battle_hooked = false
local training_hooked = {}

local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

-- Multiplies the six gains in place (only gains: nothing goes negative).
local function multiply(ctx, list, k)
  for i = 0, 5 do
    local g = ctx:read_s16(list + i * 2)
    if g > 0 then ctx:write16(list + i * 2, math.min(g * k, 9999)) end
  end
end

-- The battle gains function starts by clearing the list:
-- `lui v0, hi` / `addiu v0, v0, lo` at +0x2c.
local function find_battle(ctx)
  local at = ctx:find(BATTLE_CALL, 0x80090000, CODE_TO)
  if not at then return end
  local call = ctx:read32(at)
  local fn = 0x80000000 | ((call & 0x03FFFFFF) << 2)
  local lui, add = ctx:read32(fn + 0x2c), ctx:read32(fn + 0x30)
  if (lui >> 16) ~= 0x3c02 or (add >> 16) ~= 0x2442 then
    dwrc.log("DW1 Better EXP: battle code looks different here; battle gains unchanged")
    battle_hooked = true
    return
  end
  buf = ((lui & 0xFFFF) << 16) + s16(add & 0xFFFF)
  local after = at + 8 -- just after the call and its delay slot
  local word = ctx:read32(after)
  battle_hooked = true
  dwrc.on_exec(after, function(c)
    if c:read32(after) ~= word or c:read32(at) ~= call then return false end
    multiply(c, buf, BATTLE)
    return false
  end)
end

-- A match is one of the training stores if the six stores go to six
-- neighbouring numbers in the gains list.
local function training_list(ctx, at)
  local hi = ctx:read32(at) & 0xFFFF
  local first = ctx:read32(at + 4)
  for k = 0, 5 do
    local lui, sh = ctx:read32(at + k * 8), ctx:read32(at + k * 8 + 4)
    if (lui & 0xFFFF) ~= hi or (sh >> 21) & 31 ~= 1 then return nil end
    if (sh & 0xFFFF) ~= ((first & 0xFFFF) + k * 2) & 0xFFFF then return nil end
  end
  local list = (hi << 16) + s16(first & 0xFFFF)
  return list == buf and list or nil
end

local function find_training(ctx)
  local at = ctx:find(TRAINING_STORES, CODE_FROM, CODE_TO)
  while at do
    local stores = at -- `at` moves on; the hook needs this match's address
    local call = stores + 12 * 4
    if not training_hooked[call] and training_list(ctx, stores) then
      training_hooked[call] = true
      dwrc.on_exec(call, function(c)
        -- Another overlay may have been loaded here since: check first.
        if (c:read32(call) >> 26) ~= 3 or training_list(c, stores) == nil then return false end
        multiply(c, buf, TRAINING)
        return false
      end)
    end
    at = ctx:find(TRAINING_STORES, at + 4, CODE_TO)
  end
end

dwrc.on_frame(function(ctx)
  if ctx:frame() % CHECK_EVERY ~= 0 then return end
  if not battle_hooked then find_battle(ctx) end
  if buf then find_training(ctx) end
end)

dwrc.log(string.format("DW1 Better EXP ready: training gains x%d, battle gains x%d", TRAINING, BATTLE))
