-- Moving a table: every piece of code that reaches it does so with a `lui`
-- (the address's high half) followed by an addiu/ori/load/store carrying the
-- low half, sometimes after an index has been added to the register:
--
--   lui  v1, 0x8013          lui  at, 0x8013
--   addiu v1, v1, -0x314C    addu at, at, v0
--                            lh   v0, -0x3134(at)
--
-- scan() follows each `lui`'s register through the next instructions (the
-- same rules as research/tools/dw1refs.py) and, when the address it builds
-- lies in a moved table, rewrites the high half and every low half for the
-- table's new place. A `lui` that also reaches something that isn't moved is
-- an error (none exists in SLUS-01032: dw1refs.py reports them as SHARED).

local M = {}

local WINDOW = 48
local LOADS_STORES = { [0x20] = true, [0x21] = true, [0x22] = true, [0x23] = true, [0x24] = true, [0x25] = true, [0x26] = true,
  [0x28] = true, [0x29] = true, [0x2A] = true, [0x2B] = true, [0x2E] = true, [0x32] = true, [0x3A] = true }
-- Instructions that write rt (immediates and loads).
local WRITES_RT = { [0x08] = true, [0x09] = true, [0x0A] = true, [0x0B] = true, [0x0C] = true, [0x0D] = true, [0x0E] = true, [0x0F] = true,
  [0x20] = true, [0x21] = true, [0x22] = true, [0x23] = true, [0x24] = true, [0x25] = true, [0x26] = true, [0x32] = true }
-- SPECIAL functions that don't write rd: jr, syscall, break, mthi, mtlo, mult(u), div(u).
local NO_RD = { [0x08] = true, [0x0C] = true, [0x0D] = true, [0x11] = true, [0x13] = true, [0x18] = true, [0x19] = true, [0x1A] = true, [0x1B] = true }

local function sext(x) return x >= 0x8000 and x - 0x10000 or x end

-- words: the code (1-based u32 array), base: the address of words[1],
-- move(addr): the address's new place, or nil when it isn't moved.
-- Returns patches (word index -> new word) and the number of references.
function M.scan(words, base, move, name)
  local patches, refs = {}, 0
  local function put(i, w)
    local old = patches[i]
    if old and old ~= w then error(string.format("%s: two different rewrites of %08X", name, base + 4 * (i - 1))) end
    patches[i] = w
  end
  local n = #words
  for i = 1, n do
    local w = words[i]
    if w >> 26 == 0x0F then
      local hi = (w & 0xFFFF) << 16
      local tracked = { [(w >> 16) & 31] = true }
      local uses = {}
      for j = i + 1, math.min(i + WINDOW - 1, n) do
        local x = words[j]
        local op, rs, rt, rd, fn = x >> 26, (x >> 21) & 31, (x >> 16) & 31, (x >> 11) & 31, x & 0x3F
        if op == 0 and (fn == 0x21 or fn == 0x20) and (tracked[rs] or tracked[rt]) then
          tracked[rd] = true -- an index added to the high half
        else
          if (op == 0x09 or op == 0x0D or LOADS_STORES[op]) and tracked[rs] then
            local imm = x & 0xFFFF
            uses[#uses + 1] = { j = j, op = op, addr = op == 0x0D and (hi | imm) or ((hi + sext(imm)) & 0xFFFFFFFF) }
          end
          if op == 0 then
            if not NO_RD[fn] then tracked[rd] = nil end
          elseif WRITES_RT[op] then
            tracked[rt] = nil
          elseif op == 0x03 then
            tracked[31] = nil
          end
        end
        if next(tracked) == nil then break end
      end
      local moved = 0
      for _, u in ipairs(uses) do
        u.new = move(u.addr)
        if u.new then moved = moved + 1 end
      end
      if moved > 0 then
        if moved ~= #uses then
          error(string.format("%s: the lui at %08X reaches a moved table and other data too", name, base + 4 * (i - 1)))
        end
        local first = uses[1]
        local nhi = first.op == 0x0D and (first.new >> 16) or (((first.new + 0x8000) >> 16) & 0xFFFF)
        put(i, (w & 0xFFFF0000) | nhi)
        for _, u in ipairs(uses) do
          local lo = u.new - (nhi << 16)
          if (u.op == 0x0D and (lo < 0 or lo > 0xFFFF)) or (u.op ~= 0x0D and (lo < -0x8000 or lo > 0x7FFF)) then
            error(string.format("%s: %08X can't reach %08X from the lui at %08X", name, base + 4 * (u.j - 1), u.new, base + 4 * (i - 1)))
          end
          put(u.j, (words[u.j] & 0xFFFF0000) | (lo & 0xFFFF))
          refs = refs + 1
        end
      end
    end
  end
  return patches, refs
end

return M
