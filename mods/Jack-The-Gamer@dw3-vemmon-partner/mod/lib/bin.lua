-- Little-endian reading and writing of binary data kept in Lua strings
-- (offsets from 0, as in the game's own structs).

local M = {}

function M.u8(s, o) return (string.unpack("<I1", s, o + 1)) end
function M.u16(s, o) return (string.unpack("<I2", s, o + 1)) end
function M.u32(s, o) return (string.unpack("<I4", s, o + 1)) end
function M.s8(s, o) return (string.unpack("<i1", s, o + 1)) end
function M.s16(s, o) return (string.unpack("<i2", s, o + 1)) end
function M.s32(s, o) return (string.unpack("<i4", s, o + 1)) end

-- `s` with `data` written over it at `o` (the string grows when needed).
function M.put(s, o, data)
  if #s < o then s = s .. string.rep("\0", o - #s) end
  return s:sub(1, o) .. data .. s:sub(o + #data + 1)
end

function M.put8(s, o, v) return M.put(s, o, string.pack("<I1", v & 0xff)) end
function M.put16(s, o, v) return M.put(s, o, string.pack("<I2", v & 0xffff)) end
function M.put32(s, o, v) return M.put(s, o, string.pack("<I4", v & 0xffffffff)) end

-- `s` padded with zeros to a multiple of `n` bytes.
function M.pad(s, n)
  local r = #s % n
  if r == 0 then return s end
  return s .. string.rep("\0", n - r)
end

-- A string from a list of byte values.
function M.bytes(list)
  local t = {}
  for i, b in ipairs(list) do t[i] = string.char(b & 0xff) end
  return table.concat(t)
end

-- Base64 (the mod's binary assets are stored as base64 text in .lua files).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end

function M.unbase64(text)
  local out, n, acc, bits = {}, 0, 0, 0
  for i = 1, #text do
    local v = DEC[text:byte(i)]
    if v then
      acc = (acc << 6) | v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        n = n + 1
        out[n] = string.char((acc >> bits) & 0xff)
      end
    end
  end
  return table.concat(out)
end

return M
