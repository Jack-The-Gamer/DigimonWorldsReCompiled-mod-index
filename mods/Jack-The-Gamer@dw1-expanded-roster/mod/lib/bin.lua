-- Little-endian reading of binary data kept in Lua strings (offsets from 0,
-- as in the game's own structs), and word arrays for code.

local M = {}

function M.u8(s, o) return (string.unpack("<I1", s, o + 1)) end
function M.u16(s, o) return (string.unpack("<I2", s, o + 1)) end
function M.u32(s, o) return (string.unpack("<I4", s, o + 1)) end
function M.s32(s, o) return (string.unpack("<i4", s, o + 1)) end

-- A string up to its first zero byte, from offset `o`.
function M.cstr(s, o)
  local e = s:find("\0", o + 1, true)
  return s:sub(o + 1, (e or #s + 1) - 1)
end

-- The 32-bit words of `s` (1-based array; #s should be a multiple of 4).
function M.words(s)
  local w, n = {}, #s // 4
  for i = 1, n do w[i] = string.unpack("<I4", s, 4 * i - 3) end
  return w
end

-- `s` with the words in `patches` (word index -> value, 1-based) replaced.
function M.apply_words(s, patches)
  local idx = {}
  for i in pairs(patches) do idx[#idx + 1] = i end
  table.sort(idx)
  local out, pos = {}, 1
  for _, i in ipairs(idx) do
    local o = 4 * i - 3
    out[#out + 1] = s:sub(pos, o - 1)
    out[#out + 1] = string.pack("<I4", patches[i])
    pos = o + 4
  end
  out[#out + 1] = s:sub(pos)
  return table.concat(out), #idx
end

return M
