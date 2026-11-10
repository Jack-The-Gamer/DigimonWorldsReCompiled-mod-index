-- R3000A instruction encodings, for the mod's code patches and the small
-- routines it puts in its own RAM. Branch offsets are counted from the
-- delay slot, so branches take their own address and the target.

local M = {}

M.R = { zero = 0, at = 1, v0 = 2, v1 = 3, a0 = 4, a1 = 5, a2 = 6, a3 = 7, t0 = 8, t1 = 9, t2 = 10, t3 = 11,
  t4 = 12, t5 = 13, t6 = 14, t7 = 15, s0 = 16, s1 = 17, s2 = 18, s3 = 19, s4 = 20, s5 = 21, s6 = 22, s7 = 23,
  t8 = 24, t9 = 25, k0 = 26, k1 = 27, gp = 28, sp = 29, fp = 30, ra = 31 }

-- The halves of an address for lui + addiu (the low half is signed).
function M.hi(addr) return ((addr + 0x8000) >> 16) & 0xffff end
function M.lo(addr) return addr & 0xffff end

local function i_type(op, rs, rt, imm) return (op << 26) | (rs << 21) | (rt << 16) | (imm & 0xffff) end
local function r_type(rs, rt, rd, sa, fn) return (rs << 21) | (rt << 16) | (rd << 11) | (sa << 6) | fn end

function M.lui(rt, imm) return i_type(0x0F, 0, rt, imm) end
function M.addiu(rt, rs, imm) return i_type(0x09, rs, rt, imm) end
function M.slti(rt, rs, imm) return i_type(0x0A, rs, rt, imm) end
function M.ori(rt, rs, imm) return i_type(0x0D, rs, rt, imm) end
function M.lh(rt, off, base) return i_type(0x21, base, rt, off) end
function M.lhu(rt, off, base) return i_type(0x25, base, rt, off) end
function M.lw(rt, off, base) return i_type(0x23, base, rt, off) end
function M.sh(rt, off, base) return i_type(0x29, base, rt, off) end
function M.sw(rt, off, base) return i_type(0x2B, base, rt, off) end
function M.sll(rd, rt, sa) return r_type(0, rt, rd, sa, 0x00) end
function M.sra(rd, rt, sa) return r_type(0, rt, rd, sa, 0x03) end
function M.jr(rs) return r_type(rs, 0, 0, 0, 0x08) end
function M.addu(rd, rs, rt) return r_type(rs, rt, rd, 0, 0x21) end
function M.subu(rd, rs, rt) return r_type(rs, rt, rd, 0, 0x23) end
function M.j(addr) return 0x08000000 | ((addr >> 2) & 0x3ffffff) end
function M.jal(addr) return 0x0C000000 | ((addr >> 2) & 0x3ffffff) end

local function branch(op, rs, rt, at, target)
  local off = (target - (at + 4)) // 4
  assert(off >= -0x8000 and off < 0x8000, "branch out of range")
  return i_type(op, rs, rt, off)
end
function M.beq(rs, rt, at, target) return branch(0x04, rs, rt, at, target) end
function M.bne(rs, rt, at, target) return branch(0x05, rs, rt, at, target) end

M.NOP = 0

-- Assembles a routine at `base` from a list of words and labels: an entry
-- is a word, a label name (string), or a function(at, labels) returning a
-- word (for branches to labels). Returns the code as a string and the labels.
function M.assemble(base, list)
  local labels, at = {}, base
  for _, e in ipairs(list) do
    if type(e) == "string" then labels[e] = at else at = at + 4 end
  end
  local out = {}
  at = base
  for _, e in ipairs(list) do
    if type(e) ~= "string" then
      local w = type(e) == "function" and e(at, labels) or e
      out[#out + 1] = string.pack("<I4", w & 0xffffffff)
      at = at + 4
    end
  end
  return table.concat(out), labels
end

-- Branch helpers for assemble(): beq/bne to a label.
function M.beq_to(rs, rt, label) return function(at, l) return M.beq(rs, rt, at, assert(l[label], label)) end end
function M.bne_to(rs, rt, label) return function(at, l) return M.bne(rs, rt, at, assert(l[label], label)) end end

return M
