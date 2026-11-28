-- Text in the European release's style: full-width Shift-JIS, two bytes a
-- letter (dw_decomp: en_eu is the en_us text in full width; drawString
-- reads halfwords and drawGlyph gives letters, digits and a few signs 8
-- pixels, everything else 12, a space 8).

local M = {}

local SIGNS = { [" "] = 0x8140, ["-"] = 0x817C, ["."] = 0x8144, [","] = 0x8143, ["!"] = 0x8149, ["?"] = 0x8148,
  ["'"] = 0x8166, [":"] = 0x8146, ["/"] = 0x815E, ["("] = 0x8169, [")"] = 0x816A }
local BACK = {}
for c, w in pairs(SIGNS) do BACK[w] = c end
BACK[0x8142] = "."

-- The full-width code of an ASCII character (nil for one it has none for).
function M.code(c)
  local b = c:byte()
  if b >= 65 and b <= 90 then return 0x8260 + b - 65 end
  if b >= 97 and b <= 122 then return 0x8281 + b - 97 end
  if b >= 48 and b <= 57 then return 0x824F + b - 48 end
  return SIGNS[c]
end

-- ASCII text in full width (characters it has no code for are dropped).
function M.fullwidth(s)
  local out = {}
  for c in s:gmatch(".") do
    local w = M.code(c)
    if w then out[#out + 1] = string.char(w >> 8, w & 0xFF) end
  end
  return table.concat(out)
end

-- Full-width text (up to a zero byte) back to ASCII; other codes as "?".
function M.ascii(s)
  local out, i = {}, 1
  while i < #s do
    local w = (s:byte(i) << 8) | s:byte(i + 1)
    if s:byte(i) == 0 then break end
    if w >= 0x8260 and w <= 0x8279 then out[#out + 1] = string.char(65 + w - 0x8260)
    elseif w >= 0x8281 and w <= 0x829A then out[#out + 1] = string.char(97 + w - 0x8281)
    elseif w >= 0x824F and w <= 0x8258 then out[#out + 1] = string.char(48 + w - 0x824F)
    else out[#out + 1] = BACK[w] or "?" end
    i = i + 2
  end
  return table.concat(out)
end

-- drawGlyph's width for a code (European font).
function M.width(w)
  if w == 0x8140 then return 8 end
  if (w >= 0x8260 and w < 0x829B) or (w >= 0x824F and w < 0x8259) or (w >= 0x8341 and w < 0x8395)
    or w == 0x8148 or w == 0x8149 or w == 0x8166 or w == 0x8143 or w == 0x8144 or w == 0x8146
    or w == 0x817C or w == 0x815E or w == 0x8169 or w == 0x816A then
    return 8
  end
  return 12
end

return M
