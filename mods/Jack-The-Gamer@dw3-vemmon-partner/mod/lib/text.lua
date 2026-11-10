-- The game's text: font codes, text files, and new strings in every
-- language of the European release.
--
-- A string is bytes up to a 0: 0x04-0xE9 are glyphs (0-9, A-Z, a-z, kana,
-- and a few signs), 01 n an icon of the font (the spaces, punctuation and
-- accented letters, and the button and element icons), 02 c ... a control
-- code: 02 01 a new line, 02 02 b wait for a button, 02 03 a new page,
-- 02 08 n the player's name. A text file is a u32 count, a u32 offset per
-- string, then the strings.
--
-- Write text in UTF-8 with {nl}, {wait N}, {page}, {name N} and {iNN}/{gNN}
-- (an icon or glyph by number) for what has no letter.

local bin = require("lib.bin")
local disc = require("lib.disc")
local eu = require("lib.eu")

local M = {}

local CODES = {}
for i = 0, 9 do CODES[48 + i] = string.char(4 + i) end
for i = 0, 25 do
  CODES[65 + i] = string.char(0x0E + i)
  CODES[97 + i] = string.char(0x28 + i)
end
CODES[utf8.codepoint("?")] = "\xE6"
CODES[utf8.codepoint("!")] = "\xE7"
CODES[utf8.codepoint("=")] = "\xE8"
CODES[utf8.codepoint("~")] = "\xE9"
local ICONS = {
  [" "] = 0x01, [","] = 0x04, ["."] = 0x05, [":"] = 0x07, [";"] = 0x08, ["-"] = 0x1A, ["–"] = 0x0C,
  ["/"] = 0x0F, ["("] = 0x15, [")"] = 0x16, ["'"] = 0x13, ['"'] = 0x14, ["…"] = 0x12, ["+"] = 0x19,
  ["<"] = 0x1D, [">"] = 0x1E, ["%"] = 0x2A, ["&"] = 0x2B, ["¡"] = 0x3B, ["¿"] = 0x3F,
  ["Ã"] = 0x40, ["Ä"] = 0x41, ["Å"] = 0x42, ["Æ"] = 0x43, ["Ç"] = 0x44, ["Ñ"] = 0x45, ["Õ"] = 0x46,
  ["Ö"] = 0x47, ["Ø"] = 0x48, ["Ü"] = 0x49, ["ß"] = 0x4A, ["à"] = 0x4B, ["â"] = 0x4C, ["ã"] = 0x4D,
  ["ä"] = 0x4E, ["ç"] = 0x4F, ["è"] = 0x50, ["é"] = 0x51, ["ê"] = 0x52, ["ë"] = 0x53, ["ì"] = 0x54,
  ["î"] = 0x55, ["ï"] = 0x56, ["ñ"] = 0x57, ["ò"] = 0x58, ["ô"] = 0x59, ["õ"] = 0x5A, ["ö"] = 0x5B,
  ["ù"] = 0x5C, ["û"] = 0x5D, ["ü"] = 0x5E, ["á"] = 0x5F, ["í"] = 0x60, ["ó"] = 0x61, ["ú"] = 0x62,
  ["Â"] = 0x63, ["Ê"] = 0x64, ["Ô"] = 0x65, ["Ë"] = 0x66, ["Ÿ"] = 0x67, ["Á"] = 0x68, ["É"] = 0x69,
  ["Í"] = 0x6A, ["Ó"] = 0x6B, ["Ú"] = 0x6C, ["À"] = 0x6D, ["È"] = 0x6E, ["Ì"] = 0x6F, ["Ò"] = 0x70,
  ["Ù"] = 0x71,
}
for ch, n in pairs(ICONS) do CODES[utf8.codepoint(ch)] = "\1" .. string.char(n) end

-- UTF-8 text with {tokens} -> the game's bytes (without the final 0).
function M.encode(s)
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "{" then
      local j = assert(s:find("}", i, true), "unclosed { in " .. s)
      local tok = {}
      for w in s:sub(i + 1, j - 1):gmatch("%S+") do tok[#tok + 1] = w end
      local t = tok[1]
      if t == "nl" then out[#out + 1] = "\2\1"
      elseif t == "wait" then out[#out + 1] = "\2\2" .. string.char(tonumber(tok[2]))
      elseif t == "page" then out[#out + 1] = "\2\3"
      elseif t == "name" then out[#out + 1] = "\2\8" .. string.char(tonumber(tok[2]))
      elseif t:match("^c%d+$") then
        -- a control code by number and its argument bytes ({c7} brackets a speaker's name)
        local s = "\2" .. string.char(tonumber(t:sub(2)))
        for k = 2, #tok do s = s .. string.char(tonumber(tok[k], 16)) end
        out[#out + 1] = s
      elseif t:sub(1, 1) == "i" then out[#out + 1] = "\1" .. string.char(tonumber(t:sub(2), 16))
      elseif t:sub(1, 1) == "g" then out[#out + 1] = string.char(tonumber(t:sub(2), 16))
      else error("unknown text token {" .. t .. "}") end
      i = j + 1
    else
      local cp = utf8.codepoint(s, i)
      local code = CODES[cp]
      if not code then error(string.format("no glyph for %q in %q", utf8.char(cp), s)) end
      out[#out + 1] = code
      i = i + #utf8.char(cp)
    end
  end
  return table.concat(out)
end

-- The length of each control code 02 c, the 02 included (FONT_CODE_LENGTHS).
local CODE_LEN = { [0] = 1, 2, 3, 2, 5, 3, 3, 2, 3, 2, 0 }

-- Where the string at byte `o` (from 0) ends: its 0, skipping the
-- arguments of icons and control codes (which may be 0).
local function string_end(data, o)
  while true do
    local c = data:byte(o + 1)
    if c == nil or c == 0 then return o end
    if c == 1 or c == 3 then
      o = o + 2
    elseif c == 2 then
      local ln = CODE_LEN[data:byte(o + 2)] or 2
      o = o + (ln > 0 and ln or 2)
    else
      o = o + 1
    end
  end
end
M.string_end = string_end

-- A text file -> its strings (raw bytes, without the 0s).
function M.read(data)
  local n = bin.u32(data, 0)
  local list = {}
  for k = 0, n - 1 do
    local o = bin.u32(data, 4 + 4 * k)
    list[k] = data:sub(o + 1, string_end(data, o))
  end
  return list, n
end

-- Strings (0 .. n-1) -> a text file.
function M.write(list, n)
  local head = 4 + 4 * n
  local offs, body, pos = {}, {}, head
  for k = 0, n - 1 do
    local s = list[k] or ""
    offs[#offs + 1] = string.pack("<I4", pos)
    body[#body + 1] = s .. "\0"
    pos = pos + #s + 1
  end
  return string.pack("<I4", n) .. table.concat(offs) .. table.concat(body)
end

local pending = {}      -- file number -> { [index] = raw }

-- Sets string `index` of file `file` (raw bytes).
function M.set(file, index, raw)
  pending[file] = pending[file] or {}
  pending[file][index] = raw
end

-- Sets string `index` of a text in every European language: `base` is the
-- Japanese copy's file number, `by_lang` the text by language (en, fr, it,
-- de, es); the USA copy gets the English one.
function M.set_all(base, index, by_lang)
  for _, lang in ipairs(eu.LANGS) do
    M.set(base + eu.LANG_OFFSET[lang], index, M.encode(assert(by_lang[lang], "missing " .. lang .. " text")))
  end
  M.set(base + eu.LANG_OFFSET.us, index, M.encode(by_lang.en))
end

-- The strings of a text file now (with the changes not yet written).
function M.strings(file)
  local list, n = M.read(disc.read_file(file))
  for k, v in pairs(pending[file] or {}) do
    list[k] = v
    if k >= n then n = k + 1 end
  end
  return list, n
end

-- Writes every changed text file.
function M.commit()
  for file in pairs(pending) do
    local list, n = M.strings(file)
    disc.replace_file(file, M.write(list, n))
  end
  pending = {}
end

return M
