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
-- the list's address is read from the game's own code. The Europe and Japan
-- executables were compiled with less optimisation: their battle code sets
-- the call's argument before the call instead of in its delay slot, and one
-- of their exercises (MP) loads a value between two of the stores. Checked
-- on all three: the list is at 0x8013D468 (USA, SLUS-01032), 0x80144A30
-- (Europe, SLES-02914), 0x80147754 (Japan, SLPS-01797), with 6 exercises in
-- TRN_REL.BIN and 5 in TRN2_REL.BIN on each.

local TRAINING = tonumber(dwrc.options.training) or 2
local BATTLE = tonumber(dwrc.options.battle) or 3

-- Main program: `jal <battle gains>` followed by the window's setup; `call`
-- is the jal's offset in the pattern.
local BATTLE_CALLS = {
  { pattern = "0c?????? 27a40024 2402ffb2 a7a20028 24020036 a7a2002a", call = 0 },          -- USA
  { pattern = "27a40024 0c?????? 00000000 2402ffb2 a7a20028 24020036 a7a2002a", call = 4 }, -- Europe, Japan
}

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
  local at
  for _, b in ipairs(BATTLE_CALLS) do
    at = ctx:find(b.pattern, 0x80090000, CODE_TO)
    if at then at = at + b.call break end
  end
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
  dwrc.log(string.format("DW1 Better EXP: battle code found at %08x, gains at %08x", at, buf))
  dwrc.on_exec(after, function(c)
    if c:read32(after) ~= word or c:read32(at) ~= call then return false end
    multiply(c, buf, BATTLE)
    return false
  end)
end

-- Training: from `lui at, hi` / `sh rX, lo(at)` storing the first gain,
-- the stores of all six gains (`lui at, hi` / `sh rX, lo(at)`, in any order,
-- with loads, `lh`/`lhu`/`lw`..., or nops between them) up to `jal <window>`.
-- Returns the jal's address, or nil if the code there is anything else.
local function training_call(ctx, at)
  local lui = 0x3c010000 | (((buf + 0x8000) >> 16) & 0xFFFF)
  local seen, at_set = 0, false
  for p = at, at + 23 * 4, 4 do
    local w = ctx:read32(p)
    local op = w >> 26
    if w == lui then
      at_set = true
    elseif op == 0x29 and (w >> 21) & 31 == 1 then -- sh rX, lo(at)
      local k = s16(w & 0xFFFF) - s16(buf & 0xFFFF)
      if not at_set or k < 0 or k > 10 or k % 2 ~= 0 then return nil end
      seen = seen | (1 << (k // 2))
    elseif op == 3 then -- jal
      return seen == 63 and p or nil
    elseif w ~= 0 and not ((op == 0x20 or op == 0x21 or op == 0x23 or op == 0x24 or op == 0x25) and (w >> 16) & 31 ~= 1) then
      return nil
    end
  end
  return nil
end

local function find_training(ctx)
  local first = string.format("3c01%04x a4??%04x", ((buf + 0x8000) >> 16) & 0xFFFF, buf & 0xFFFF)
  local at = ctx:find(first, CODE_FROM, CODE_TO)
  while at do
    local stores = at -- `at` moves on; the hook needs this match's address
    local call = training_call(ctx, stores)
    if call and not training_hooked[call] then
      training_hooked[call] = true
      dwrc.log(string.format("DW1 Better EXP: training code found at %08x", call))
      dwrc.on_exec(call, function(c)
        -- Another overlay may have been loaded here since: check first.
        if training_call(c, stores) ~= call then return false end
        multiply(c, buf, TRAINING)
        return false
      end)
    end
    at = ctx:find(first, at + 4, CODE_TO)
  end
end

dwrc.on_frame(function(ctx)
  if ctx:frame() % CHECK_EVERY ~= 0 then return end
  if not battle_hooked then find_battle(ctx) end
  if buf then find_training(ctx) end
end)

dwrc.log(string.format("DW1 Better EXP ready: training gains x%d, battle gains x%d", TRAINING, BATTLE))
