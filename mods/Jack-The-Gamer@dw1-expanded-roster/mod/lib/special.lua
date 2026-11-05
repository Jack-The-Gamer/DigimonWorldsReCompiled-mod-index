-- The special evolutions around Sukamon and Numemon (SLUS-01032), as the
-- user asked:
-- * the virus bar's evolution into Sukamon gives PlatinumSukamon a quarter of
--   the time (and neither of them catches it again);
-- * a Rookie that met no evolution's requirements becomes Raremon instead of
--   Numemon a quarter of the time (lib/evolution.lua asks M.numemon);
-- * a Sukamon or PlatinumSukamon that has eaten 20 piles of poop becomes
--   KingSukamon at once; PlatinumSukamon eats poop as Sukamon and Numemon do.
--   The count is kept in the save (PartnerPara's unused5, +88, which nothing
--   reads or writes) and starts over at every evolution, as care mistakes
--   and battles do.
-- Addresses from the dw_decomp decompilation (src/main/partner_impl.c,
-- config/us/symbols.txt); each hooked instruction is checked first (M.check).

local M = {}

local PARTNER_ENTITY = 0x801557A8   -- its type (u32) first
local PARA = 0x80138460             -- PartnerPara
local POOP_EATEN = PARA + 88        -- s16, PartnerPara.unused5
local EVOLUTION_TARGET = 0x80134E50 -- s16, -1 = none
local PARTNER_STATE = 0x80134C5B    -- u8, 1 = idle in the field

local SUKAMON, NUMEMON = 39, 11
M.POOPS = 20                        -- piles for KingSukamon
M.CHANCE = 4                        -- one in four

-- tickConditions (0x800A8F38): once the virus bar reaches 16 and the partner
-- isn't Sukamon (0x800A92A4), 0x800A92AC sets EVOLUTION_TARGET = 39, keeps the
-- partner's type and stats for its return, and empties the bar; both paths
-- meet at 0x800A9328, which starts any evolution set (state 13).
local VIRUS_SUKAMON = 0x800A92AC
local CONDITIONS_TAIL = 0x800A9328
-- tickPoopDetection (0x800A7ED0): only Numemon (11) and Sukamon (39) look for
-- a pile beside the tamer (0x800A7EE4: the Sukamon test, else return); the
-- search starts at 0x800A7EF0 and sends the partner to eat it (state 9,
-- partnerTickEatShit), which ends in handleEatingPoop (0x800A8244).
local POOP_SUKAMON_TEST = 0x800A7EE4
local POOP_SEARCH = 0x800A7EF0
local EAT_POOP = 0x800A8244
-- setDigimonRaised (0x800FF7F8): called for the new Digimon at every
-- evolution (EVL, after careMistakes and battles are cleared) and new game.
local SET_DIGIMON_RAISED = 0x800FF7F8

M.CODE = {
  [VIRUS_SUKAMON] = 0x24020027,     -- addiu v0, zero, 39
  [CONDITIONS_TAIL] = 0x87829324,   -- lh v0, -27868(gp)
  [POOP_SUKAMON_TEST] = 0x24010027, -- addiu at, zero, 39
  [POOP_SEARCH] = 0x3C018015,       -- lui at, 0x8015
  [EAT_POOP] = 0x9383913C,          -- lbu v1, -28356(gp)
  [SET_DIGIMON_RAISED] = 0x27BDFFE8, -- addiu sp, sp, -24
}

-- word(addr): the executable's instruction there; false if one isn't as expected.
function M.check(word)
  for addr, w in pairs(M.CODE) do
    if word(addr) ~= w then return false, string.format("%08X: %08X, not %08X", addr, word(addr), w) end
  end
  return true
end

local roll = function() return math.random(M.CHANCE) == 1 end

-- The Rookie that met nothing (lib/evolution.lua): Numemon, or Raremon.
function M.numemon()
  if M.raremon and roll() then return M.raremon end
  return NUMEMON
end

-- types: { platinum = 195, king = 196, raremon = 197 } (the ones built)
function M.install(types)
  M.raremon = types.raremon
  local platinum, king = types.platinum, types.king
  local function sukamon(t) return t == SUKAMON or (platinum and t == platinum) end

  local to_platinum = false
  dwrc.on_exec(VIRUS_SUKAMON, function(ctx)
    if platinum and ctx:read32(PARTNER_ENTITY) == platinum then
      ctx:set_pc(CONDITIONS_TAIL) -- PlatinumSukamon is already one of them
      return true
    end
    to_platinum = platinum ~= nil and roll()
    return false
  end)
  dwrc.on_exec(CONDITIONS_TAIL, function(ctx)
    if to_platinum then
      to_platinum = false
      ctx:write16(EVOLUTION_TARGET, platinum)
    end
    -- 20 piles eaten: KingSukamon, once the partner is idle again
    if king and ctx:read16(EVOLUTION_TARGET) == 0xFFFF and ctx:read8(PARTNER_STATE) == 1
      and sukamon(ctx:read32(PARTNER_ENTITY)) and ctx:read_s16(POOP_EATEN) >= M.POOPS then
      ctx:write16(EVOLUTION_TARGET, king)
    end
    return false
  end)

  if platinum then
    dwrc.on_exec(POOP_SUKAMON_TEST, function(ctx)
      if ctx:read32(PARTNER_ENTITY) ~= platinum then return false end
      ctx:set_pc(POOP_SEARCH)
      return true
    end)
  end
  dwrc.on_exec(EAT_POOP, function(ctx)
    if sukamon(ctx:read32(PARTNER_ENTITY)) then
      local n = ctx:read_s16(POOP_EATEN)
      if n < 0x7FFF then ctx:write16(POOP_EATEN, n + 1) end
    end
    return false
  end)
  dwrc.on_exec(SET_DIGIMON_RAISED, function(ctx)
    ctx:write16(POOP_EATEN, 0)
    return false
  end)
end

return M
