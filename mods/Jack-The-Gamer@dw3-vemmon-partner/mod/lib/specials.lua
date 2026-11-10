-- New special conditions and actions (SPECIAL(id) codes) for the game's
-- scripts. The game looks a special up in SPECIAL_CONDITIONS through
-- checkSpecialCondition(id, expected), both for conditions and, with
-- expected 1, for actions; the mod answers that function for its own ids
-- (from 0x1F0 on: the game's go up to 0x95).

local eu = require("lib.eu")

local M = {}

local handlers = {}           -- id -> function(ctx) -> 0 or 1

M.VEMMON_UNLOCKED = 0x1F0     -- a condition: Vemmon is a partner
M.UNLOCK_VEMMON = 0x1F1       -- an action: makes Vemmon a partner

function M.define(id, fn) handlers[id] = fn end

function M.install()
  dwrc.on_exec(eu.checkSpecialCondition, function(ctx)
    local fn = handlers[ctx:reg("a0")]
    if not fn then return false end
    local result = fn(ctx)
    return ctx:ret(result == ctx:reg("a1") and 1 or 0)
  end)
end

return M
