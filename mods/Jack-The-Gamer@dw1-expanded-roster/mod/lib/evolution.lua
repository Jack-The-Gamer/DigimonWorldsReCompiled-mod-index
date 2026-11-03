-- The game's evolution pickers, ported to Lua so that targets can be any
-- type (SLUS-01032). The game keeps targets as signed bytes (-1 = none) all
-- through getInTrainingEvolutionTarget, getRookieEvolutionTarget,
-- getChampionEvolutionTarget and calculateRequirementScore, so types past
-- 127 can't be picked. These ports follow the dw_decomp decompilation's C
-- (src/main/evolution.c, MIT licence, (c) the dw_decomp contributors) step
-- by step, quirks included, with unsigned targets (EVOLUTION_PATHS' 0xFF =
-- none); for the game's own Digimon they give the same answers (checked
-- against the original functions on the same state: see M.compare).

local tables = require("lib.tables")

local M = {}

M.IN_TRAINING = 0x800E2598 -- getInTrainingEvolutionTarget(type) -> int16
M.ROOKIE = 0x800E2BB4      -- getRookieEvolutionTarget(type)
M.CHAMPION = 0x800E2F08    -- getChampionEvolutionTarget(type)

local PARTNER_ENTITY = 0x801557A8
local BASE = PARTNER_ENTITY + 0x38    -- BaseStats {off, def, speed, brain, movesPrio[4], moves[4], hp, mp}
local LEARNED = PARTNER_ENTITY + 0x58 -- learnedMoves[2]
local PARA = 0x80138460               -- PartnerPara
local TRIGGER_BASE_PTR = 0x80134FB8   -- [gp - 27508]: getTriggerOffset's base

local function s16(v) v = v & 0xFFFF; return v >= 0x8000 and v - 0x10000 or v end
local function s8(v) v = v & 0xFF; return v >= 0x80 and v - 0x100 or v end
-- C's division (truncates toward zero); R3000 results for a zero divisor.
local function cdiv(a, b)
  if b == 0 then return a >= 0 and -1 or 1 end
  local q = math.abs(a) // math.abs(b)
  if (a < 0) ~= (b < 0) then q = -q end
  return q
end

local function hp10(ctx) return cdiv(ctx:read_s16(BASE + 0x10), 10) end
local function mp10(ctx) return cdiv(ctx:read_s16(BASE + 0x12), 10) end

-- hasDigimonRaised(type) = isTriggerSet(0x200 + type); new types never are.
local function raised(ctx, t)
  t = t & 0xFFFF
  if t >= 180 then return 0 end
  local trig = t + 0x200
  local byte = ctx:read8(ctx:read32(TRIGGER_BASE_PTR) + 245 + (trig >> 3))
  return (byte & (1 << (trig & 7))) ~= 0 and 1 or 0
end

local function mastered_moves(ctx)
  local n = 0
  for i = 0, 1 do
    local w = ctx:read32(LEARNED + 4 * i)
    for j = 0, 31 do if w & (1 << j) ~= 0 then n = n + 1 end end
  end
  return n
end

-- EvoRequirements {digimon, hp, mp, offense, defense, speed, brain, care,
-- weight, discipline, happiness, battles, techs (int16), flags (int8)}
local function reqs(ctx, target)
  local a = tables.entry("EVOLUTION_REQS", target)
  local r = {}
  for i, k in ipairs({ "digimon", "hp", "mp", "offense", "defense", "speed", "brain", "care", "weight", "discipline", "happiness", "battles", "techs" }) do
    r[k] = ctx:read_s16(a + 2 * (i - 1))
  end
  r.flags = s8(ctx:read8(a + 26))
  return r
end

local function score(ctx, current, target, max_cm, max_battles, best)
  local r = reqs(ctx, target)
  local points = 0
  local cm = ctx:read_s16(PARA + 0x52)
  if max_cm == 0 then
    if cm >= r.care then points = points + 1 end
  elseif cm <= r.care then
    points = points + 1
  end
  local weight = ctx:read_s16(PARA + 0x42)
  if r.weight - 5 <= weight and weight <= r.weight + 5 then points = points + 1 end
  local stats = { hp10(ctx), mp10(ctx), ctx:read_s16(BASE), ctx:read_s16(BASE + 2), ctx:read_s16(BASE + 4), ctx:read_s16(BASE + 6) }
  if ctx:read8(tables.entry("DIGIMON_DATA", target) + 29) == 3 then -- DigimonPara.level: a Rookie
    local want = { r.hp, r.mp, r.offense, r.defense, r.speed, r.brain }
    local highest
    for i = 1, 6 do
      local top = true
      for j = 1, 6 do if stats[i] < stats[j] then top = false end end
      if top then highest = i end -- ties: the last one
    end
    if want[highest] == 1 then points = points + 1 end
  elseif stats[1] >= r.hp and stats[2] >= r.mp and stats[3] >= r.offense and stats[4] >= r.defense and stats[5] >= r.speed and stats[6] >= r.brain then
    points = points + 1
  end
  local bonus = 0
  if r.digimon ~= -1 and current == r.digimon then bonus = 1 end
  if r.discipline ~= -1 and ctx:read_s16(PARA + 0x28) >= r.discipline then bonus = 1 end
  if r.happiness ~= -1 and ctx:read_s16(PARA + 0x2A) >= r.happiness then bonus = 1 end
  if r.battles ~= -1 then
    local b = ctx:read_s16(PARA + 0x54)
    if max_battles == 0 then
      if b >= r.battles then bonus = 1 end
    elseif b <= r.battles then
      bonus = 1
    end
  end
  if r.techs ~= -1 and mastered_moves(ctx) >= r.techs then bonus = 1 end
  points = points + bonus
  if points >= 3 and best ~= -1 then
    local gains = function(t) return ctx:read_s16(tables.entry("EVOLUTION_STATS_GAINS", t) + 12) end
    local t_raised, b_raised = raised(ctx, gains(target)), raised(ctx, gains(best))
    if t_raised == 1 and b_raised == 0 then points = 0 end
    if t_raised == 0 and b_raised == 1 then points = points + 1 end
  end
  return points
end

-- Targets past a Digimon's six slots (type -> {types}), tried after them in
-- this order: the game's EvolutionPath has room for six.
M.extra = {}

-- The targets of `current`: its six slots (type - 1 row; 0xFF = none), then
-- any extra ones.
local function targets(ctx, current)
  local a = tables.entry("EVOLUTION_PATHS", current) + 5 -- {from[5], to[6]}
  local out = {}
  for i = 0, 5 do out[#out + 1] = ctx:read8(a + i) end
  for _, t in ipairs(M.extra[current] or {}) do out[#out + 1] = t end
  return out
end

local function flags_of(ctx, t)
  local f = ctx:read8(tables.entry("EVOLUTION_REQS", t) + 26)
  return (f & 0x10) >> 4, f & 1
end

function M.in_training(ctx, current)
  local best, best_score = -1, 0
  for _, t in ipairs(targets(ctx, current)) do
    if t ~= 0xFF then
      local cm, b = flags_of(ctx, t)
      local s = score(ctx, current, t, cm, b, best)
      if best_score < s and s >= 3 then best, best_score = t, s end
    end
  end
  return best
end

-- Rookies and Champions: of the targets scoring 3+, the one whose required
-- stats average highest. As in the game, the running total and count are
-- only reset when a target wins, so a losing target's average carries into
-- the next one's sum.
local function by_stats(ctx, current)
  local best, best_score, total, count = -1, 0, 0, 0
  for _, t in ipairs(targets(ctx, current)) do
    if t ~= 0xFF then
      local cm, b = flags_of(ctx, t)
      if score(ctx, current, t, cm, b, best) >= 3 then
        local r = reqs(ctx, t)
        if r.hp ~= -1 then total = total + hp10(ctx); count = count + 1 end
        if r.mp ~= -1 then total = total + mp10(ctx); count = count + 1 end
        if r.offense ~= -1 then total = total + ctx:read_s16(BASE); count = count + 1 end
        if r.defense ~= -1 then total = total + ctx:read_s16(BASE + 2); count = count + 1 end
        if r.speed ~= -1 then total = total + ctx:read_s16(BASE + 4); count = count + 1 end
        if r.brain ~= -1 then total = total + ctx:read_s16(BASE + 6); count = count + 1 end
        total = s16(cdiv(s16(total), s16(count)))
        if best_score < total then
          best, best_score = t, total
          total, count = 0, 0
        end
      end
    end
  end
  return best
end

function M.rookie(ctx, current)
  local best = by_stats(ctx, current)
  if best == -1 and ctx:read_s16(PARA + 0x56) >= 96 then best = 11 end -- evoTimer: Numemon
  return best
end

function M.champion(ctx, current)
  return by_stats(ctx, current)
end

local PICKERS = { [M.IN_TRAINING] = M.in_training, [M.ROOKIE] = M.rookie, [M.CHAMPION] = M.champion }

-- The game's pickers answer from the ports.
function M.install()
  for addr, fn in pairs(PICKERS) do
    dwrc.on_exec(addr, function(ctx)
      ctx:ret(fn(ctx, ctx:reg("a0")) & 0xFFFFFFFF)
      return true
    end)
  end
end

-- Developer check: from a hook at `at` (a function's first instruction,
-- reached every frame), call the game's original pickers for every partner
-- type, `rounds` times with random partner stats and care values, and
-- compare each answer with the port's. The partner's data is put back
-- afterwards. Install this instead of M.install.
function M.compare(at, rounds)
  local PICKER_OF_LEVEL = { [2] = M.IN_TRAINING, [3] = M.ROOKIE, [4] = M.CHAMPION }
  local saved_regs, saved_data, queue, round, checked, mismatches = nil, nil, nil, 0, 0, 0
  local function randomize(ctx)
    for i = 0, 3 do ctx:write16(BASE + 2 * i, math.random(0, 999)) end
    ctx:write16(BASE + 0x10, math.random(1, 9999)); ctx:write16(BASE + 0x12, math.random(1, 9999))
    ctx:write16(PARA + 0x28, math.random(0, 100)); ctx:write16(PARA + 0x2A, math.random(0, 100))
    ctx:write16(PARA + 0x42, math.random(1, 99)); ctx:write16(PARA + 0x52, math.random(0, 40))
    ctx:write16(PARA + 0x54, math.random(0, 120)); ctx:write16(PARA + 0x56, math.random(0, 200))
    ctx:write32(LEARNED, math.random(0, 0xFFFFFFFF)); ctx:write32(LEARNED + 4, math.random(0, 0xFFFFFFFF))
  end
  local function build(ctx)
    queue = {}
    for t = 1, 65 do
      local p = PICKER_OF_LEVEL[ctx:read8(tables.entry("DIGIMON_DATA", t) + 29)]
      if p and t <= 62 then queue[#queue + 1] = { p, t } end
    end
  end
  local pending
  dwrc.on_exec(at, function(ctx)
    if round >= rounds and not saved_regs then return false end
    if not saved_regs then
      saved_regs = {}
      for r = 1, 31 do saved_regs[r] = ctx:reg(r) end
      saved_data = { ctx:read_bytes(PARTNER_ENTITY, 0x80), ctx:read_bytes(PARA, 0x84) }
      round = round + 1
      randomize(ctx)
      build(ctx)
    end
    if pending then -- the original just returned here
      local got, want = s16(ctx:reg("v0")), pending.port
      checked = checked + 1
      if got ~= want then
        mismatches = mismatches + 1
        if mismatches <= 20 then dwrc.log(string.format("picker %08X type %d: game %d, port %d", pending.fn, pending.type, got, want)) end
      end
      pending = nil
    end
    local q = table.remove(queue)
    if q then
      pending = { fn = q[1], type = q[2], port = PICKERS[q[1]](ctx, q[2]) }
      ctx:set_reg("a0", q[2])
      ctx:set_reg("ra", at)
      ctx:set_pc(q[1])
      return true
    end
    ctx:write_bytes(PARTNER_ENTITY, saved_data[1]); ctx:write_bytes(PARA, saved_data[2])
    for r = 1, 31 do ctx:set_reg(r, saved_regs[r]) end
    saved_regs = nil
    if round % 10 == 0 or round >= rounds then
      dwrc.log(string.format("evolution pickers: %d rounds, %d answers compared, %d mismatches", round, checked, mismatches))
    end
    return false
  end)
end

return M
