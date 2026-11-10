-- Vemmon in the places that go through the eight partners one by one.
--
-- The Lab's "Switch Digimon" screen (STGDGLAB_updatePartyScreen) lists the
-- unlocked partners outside the party (LabPartyScreen.partners[8], count);
-- with nine partners and at least one in the party, eight still fit. Its
-- loop over the eight records ends at 0x8008C1B0 (`lw a0, 80(s2)`, s2 = the
-- screen), which becomes a jal to a stub where Vemmon is added.
--
-- The menus that draw a partner's little animation (the Lab, the field
-- menu, the gyms, the battle report, the save screens) look it up in a
-- table of eight rows of frame ids. Each table is copied to the end of its
-- overlay with 18 rows (17 = Vemmon, whose frames sprites.lua adds to that
-- menu's sprite sheet), and the code or data that points at it is changed.
--
-- In the field, the party's partners are characters 3 + partner
-- (FIELDSTG's three createActor calls for them), which would make Vemmon
-- character 20 (someone else). The game's characters for Vemmon's field
-- sprite (118, 272-279) belong to its story scenes, whose events look for
-- them (with one of them following the party, Asuka City's event with
-- Vemmon waits forever), so partner 17 becomes a character of its own,
-- 406, the first after the game's 0-405: FIELDSTG_fileEntries (file << 16 | entry of
-- the sprite's set table) and FIELDSTG_actorWidths, read only by
-- getFileEntry and getActorWidth, are copied with it added (file 995's set
-- table, entry 50, 32 pixels wide like the others). That sprite has stand (1) and walk
-- (4) sets; the partners' also have sets 5 and 6 (run) and 0x40, which the
-- field would otherwise draw with the stand set: they get walk, walk and
-- stand.

local disc = require("lib.disc")
local eu = require("lib.eu")
local ext = require("lib.ext")
local files = require("lib.files")
local forms = require("lib.forms")
local mips = require("lib.mips")
local sprites = require("lib.sprites")
local tables = require("lib.tables")

local M = {}

local PARTY_LIST_END = 0x8008C1B0      -- lw a0, 80(s2)
local PARTY_LIST_NEXT = 0x8008C1B8     -- after its load delay slot
local PARTY_SCREEN_PARTNERS = 0xE4     -- s32 partners[8]
local PARTY_SCREEN_COUNT = 0x104
local PARTY_SCREEN_LAB = 0x50

-- The Lab's Digivolve Chart: STGDGLAB_data.recipes[8] (16 LabRecipes a
-- partner) and STGDGLAB_tableItems[8] (the partner's Digimon id, for its
-- icon), by partner. Its four `lw x, 8(base + partner * 4)` (base =
-- STGDGLAB_data) read 18-entry copies instead (17 = Vemmon: Guilmon's
-- recipes, as evolutions.lua's list), and the lui/addiu of tableItems moves.
local LAB_DATA = 0x8008FD68
local RECIPE_LOADS = { { 0x8008339C, 0x8C840008 }, { 0x80083454, 0x8C630008 }, { 0x800834D4, 0x8C820008 }, { 0x80084528, 0x8C830008 } }
local TABLE_ITEMS = 0x8008F470
local TABLE_ITEMS_PAIR = { { 0x80083FB8, 0x3C028009, 0x80083FC0, 0x2442F470 } }
local LAB_ENTRIES = 0x8008F628        -- STGDGLAB_entries: {s16 id, sprite, b}, id 0 ends
local LAB_ENTRIES_USES = {            -- getItemSprite, getItemB: lui v1 / lh v0, lo(v1) / addiu v1, v1, lo
  { 0x8008F3D8, 0x3C038009 }, { 0x8008F3DC, 0x8462F628 }, { 0x8008F3E8, 0x2463F628 },
  { 0x8008F424, 0x3C038009 }, { 0x8008F428, 0x8462F628 }, { 0x8008F434, 0x2463F628 },
}
local GUILMON = 5

-- Functions that take a partner and have data for partners 0-7 only treat
-- Vemmon as Guilmon: equipment (an item's partners mask has a bit for each
-- of partners 0-7: STSTATUS_canEquip, STITSHOP_canEquip). Each function's
-- first two words become a jump to a routine that turns partner 17 into 5,
-- does those two words and jumps back. (The gyms do the same, and read
-- Vemmon's own image set: gym.lua.)
local AS_GUILMON = {
  { file = eu.FILE_STSTATUS, at = 0x8009A344, words = { 0x27BDFFE0, 0xAFB00010 } },   -- canEquip: addiu sp, sp, -32; sw s0, 16(sp)
  { file = eu.FILE_STITSHOP, at = 0x8008C4CC, words = { 0x27BDFFE8, 0xAFB00010 } },   -- canEquip: addiu sp, sp, -24; sw s0, 16(sp)
}
-- The battle gauges: clearBattleGauges (exe) empties gauges[0-7].
local clearBattleGauges = 0x80013534
local VEMMON_GAUGE = 0x80042B96        -- BATTLE_SETUP.gauges[17]

local createActor = 0x8009116C                                -- FIELDSTG_createActor(character, kind, image, entry)
local FOLLOWER_CALLS = { 0x8008AFD4, 0x8008B014, 0x8008B054 }    -- jal createActor, a0 = getPartyPartner(i) + 3
local VEMMON_CHARACTER = 406
local FILE_STGMCARD = 494                                       -- the save screens
local SUMMARY_CHAIN = 0x80086498                                -- STGMCARD_fillSave: v1 = member * 0x3DC (sll v1, v0, 5; subu v1, v1, v0; ...)

local FILE_ENTRIES = 0x80099E00                                -- s32[406]
local FILE_ENTRIES_PAIR = { { 0x800920DC, 0x3C02800A, 0x800920E0, 0x24429E00 } }
local ACTOR_WIDTHS = 0x8009A458                                 -- u8[408]
local ACTOR_WIDTHS_PAIR = { { 0x800920F8, 0x3C02800A, 0x800920FC, 0x2442A458 } }
local CHARACTER_COUNT = 406
local FIELD_SPRITE_SETS = 50                                    -- entry of file 995: rows {set, anim by direction 0-4}

-- The menus' animation tables. sheet/tex: sprites.add's spec (sheet and
-- texture files, where the menu loads the texture and sets it for the
-- sheet); table: its address, row size, and what points at it (a data
-- word, or lui/addiu pairs with their words); like: the frame of the sheet
-- whose place Vemmon's frames take (Agumon's first).
local MENUS = {
  { name = "the Lab", file = eu.FILE_STGDGLAB,
    sheet_file = 709, sheet_entry = 0, tex_file = 710, tex_entry = 0, load_x = 0x280, load_y = 0x100, tex_x = 0x280, tex_y = 0x100,
    table = 0x8008F4C4, row = 28, pointer = 0x8008FD68 },                       -- STGDGLAB_partnerAnims, STGDGLAB_data.anim
  { name = "the field menu", file = eu.FILE_STSTATUS,
    sheet_file = 1028, sheet_entry = 0, tex_file = 1029, tex_entry = 0, load_x = 0x280, load_y = 0x100, tex_x = 0x280, tex_y = 0x100,
    table = 0x8009A9C0, row = 28, pointer = 0x8009AF68 },                       -- STSTATUS_partnerAnims, STSTATUS_data.partnerAnims
  { name = "the gyms", file = eu.FILE_STGTRAIN,
    sheet_file = 652, sheet_entry = 3, tex_file = 653, tex_entry = 0, load_x = 0x240, load_y = 0x100, tex_x = 0x240, tex_y = 0x100,
    table = 0x8008C224, row = 28, pairs = {                                     -- STGTRAIN_waitAnims
      { 0x80084888, 0x3C028009, 0x8008488C, 0x2454C224 }, { 0x800849A8, 0x3C038009, 0x800849AC, 0x2463C224 },
      { 0x80084A74, 0x3C038009, 0x80084A78, 0x2463C224 }, { 0x80084CA0, 0x3C028009, 0x80084CA4, 0x2456C224 } } },
  { name = "the battle report", file = eu.FILE_STFGTREP,
    sheet_file = 1951, sheet_entry = 0, tex_file = 1952, tex_entry = 0, load_x = 0x280, load_y = 0, tex_x = 0x280, tex_y = 0,
    table = 0x8008905C, row = 28, pairs = {                                     -- STFGTREP_animations
      { 0x80083BC4, 0x3C038009, 0x80083BC8, 0x2463905C }, { 0x80083C14, 0x3C038009, 0x80083C18, 0x2463905C } } },
  { name = "the save screens", file = 494,
    sheet_file = 669, sheet_entry = 0, tex_file = 670, tex_entry = 0, load_x = 0x280, load_y = 0, tex_x = 0x280, tex_y = 0,
    table = 0x80088204, row = 28, pairs = {                                     -- STGMCARD_partnerAnims
      { 0x800839A0, 0x3C038009, 0x800839A4, 0x24688204 }, { 0x80083A40, 0x3C028009, 0x80083A44, 0x24558204 } },
    icons = { table = 0x800882E4, pairs = {                                     -- STGMCARD_partnerIcons
      { 0x8008490C, 0x3C028009, 0x80084910, 0x245582E4 } } } },
  -- the renaming screen (STDGNAME, file 354): the party's partners in its
  -- menu (STDGNAME_menuAnims, sheet 648 / texture 649, full: Vemmon's frames
  -- go in an image of their own, which loads at 0x2C0, 0, a column the
  -- screen doesn't draw from) and the one being renamed by the keyboard
  -- (STDGNAME_nameAnims, the keyboard's sheet 1904 / texture 1905). Without
  -- a row for partner 17 the menu stops opening.
  { name = "the renaming menu", file = 354,
    sheet_file = 648, sheet_entry = 0, tex_file = 649, tex_entry = 0, load_x = 0x280, load_y = 0, tex_x = 0x280, tex_y = 0,
    extra_image = { 32, 32 },
    table = 0x80087E58, row = 28, pairs = {                                     -- STDGNAME_menuAnims
      { 0x80085804, 0x3C028008, 0x80085808, 0x24577E58 } } },
  { name = "the renaming keyboard", file = 354,
    sheet_file = 1904, sheet_entry = 0, tex_file = 1905, tex_entry = 0, load_x = 0x280, load_y = 0x100, tex_x = 0x280, tex_y = 0x100,
    table = 0x80087A90, row = 28, pairs = {                                     -- STDGNAME_nameAnims
      { 0x80083DB0, 0x3C038008, 0x80083DB8, 0x24637A90 }, { 0x80083E00, 0x3C038008, 0x80083E04, 0x24637A90 } } },
}

-- The table's 8 rows, then rows 8-16 (copies of row 0, never read) and
-- Vemmon's, at the end of the overlay; returns the copy's address.
local function extend(ovl, addr, row, vemmon_row)
  local rows = ovl:read(addr, 8 * row)
  ovl.ext:align(4)
  local at = ovl.ext:addr()
  ovl.ext:raw(rows)
  for _ = 8, 16 do ovl.ext:raw(rows:sub(1, row)) end
  ovl.ext:raw(vemmon_row)
  return at
end

local function repoint(file, pairs, old, new)
  for _, p in ipairs(pairs) do
    local lui_at, lui, use_at, use = p[1], p[2], p[3], p[4]
    assert(((lui & 0xFFFF) << 16) + ((use & 0xFFFF) ~ 0x8000) - 0x8000 == old, string.format("%08x doesn't address %08x", use_at, old))
    files.patch32(file, lui_at, lui, (lui & 0xFFFF0000) | mips.hi(new))
    files.patch32(file, use_at, use, (use & 0xFFFF0000) | mips.lo(new))
  end
end

-- Vemmon's field sprite gets sets 5, 6 (walk) and 0x40 (stand).
local function field_sets()
  local list = sprites.read_archive(disc.read_file(sprites.FIELD_SPRITE_FILE))
  local t = list[FIELD_SPRITE_SETS + 1]
  local rows, by_set = {}, {}
  for o = 0, #t - 12, 12 do
    local row = { string.unpack("<HHHHHH", t, o + 1) }
    if row[1] == 0 then break end
    rows[#rows + 1] = row
    by_set[row[1]] = row
  end
  assert(by_set[1] and by_set[4], "Vemmon's field sprite has no stand or walk set")
  for _, add in ipairs({ { 5, 4 }, { 6, 4 }, { 0x40, 1 } }) do
    if not by_set[add[1]] then
      local from = by_set[add[2]]
      rows[#rows + 1] = { add[1], from[2], from[3], from[4], from[5], from[6] }
    end
  end
  local out = {}
  for _, r in ipairs(rows) do out[#out + 1] = string.pack("<HHHHHH", table.unpack(r, 1, 6)) end
  out[#out + 1] = string.rep("\0", 12)
  list[FIELD_SPRITE_SETS + 1] = table.concat(out)
  disc.replace_file(sprites.FIELD_SPRITE_FILE, sprites.build_archive(list))
end

function M.build()
  -- the field: partner 17 is character 406
  local field = files.overlay(eu.FILE_FIELDSTG)
  field.ext:align(4)
  local entries_at = field.ext:addr()
  field.ext:raw(field:read(FILE_ENTRIES, 4 * CHARACTER_COUNT))
  field.ext:u32((sprites.FIELD_SPRITE_FILE << 16) | FIELD_SPRITE_SETS)
  local widths_at = field.ext:addr()
  field.ext:raw(field:read(ACTOR_WIDTHS, CHARACTER_COUNT))
  field.ext:u8(32)
  repoint(eu.FILE_FIELDSTG, FILE_ENTRIES_PAIR, FILE_ENTRIES, entries_at)
  repoint(eu.FILE_FIELDSTG, ACTOR_WIDTHS_PAIR, ACTOR_WIDTHS, widths_at)
  local R = mips.R
  local follower = tables.routine("vemmon_follower", {
    mips.addiu(R.at, R.zero, ext.VEMMON_ID + 3),
    mips.bne_to(R.a0, R.at, "go"),
    mips.NOP,
    mips.addiu(R.a0, R.zero, VEMMON_CHARACTER),
    "go",
    mips.j(createActor),
    mips.NOP,
  })
  for _, at in ipairs(FOLLOWER_CALLS) do
    files.patch32(eu.FILE_FIELDSTG, at, mips.jal(createActor), mips.jal(follower))
  end
  field_sets()

  -- equipment: Vemmon as Guilmon
  for i, c in ipairs(AS_GUILMON) do
    local wrapper = tables.routine("vemmon_as_guilmon_" .. i, {
      mips.addiu(R.at, R.zero, ext.VEMMON_ID),
      mips.bne_to(R.a0, R.at, "skip"),
      mips.NOP,
      mips.addiu(R.a0, R.zero, GUILMON),
      "skip",
      c.words[1],
      c.words[2],
      mips.j(c.at + 8),
      mips.NOP,
    })
    files.patch32(c.file, c.at, c.words[1], mips.j(wrapper))
    files.patch32(c.file, c.at + 4, c.words[2], mips.NOP)
  end

  -- the gyms: Vemmon's own exercise animations, drawn from its battle
  -- model (gym.lua; its createActor takes partner 17 as Guilmon's set)
  local gym = require("lib.gym")
  local t0 = os.clock()
  gym.install(gym.build())
  print(string.format("DW3 Vemmon Partner: Vemmon's gym animations drawn in %.1f s", os.clock() - t0))

  -- the save's summary (STGMCARD_fillSave): each party member's level and
  -- number come from the save buffer, a copy of GAME, at member * 0x3DC
  -- (a chain with a load inside, so not in sites_partner.lua); Vemmon's
  -- record isn't in that copy, so for partner 17 the offset points at
  -- ext.VEMMON (garbage there sent the save list into an endless loop)
  local summary = tables.routine("vemmon_save_summary", {
    mips.addiu(R.at, R.zero, ext.VEMMON_ID),
    mips.bne_to(R.v0, R.at, "game"),
    mips.sll(R.v1, R.v0, 5),
    mips.lw(R.v1, 16, R.s4),                         -- dataBuf
    mips.lui(R.at, mips.hi(ext.VEMMON - (ext.GAME_PARTNERS - eu.GAME))),
    mips.addiu(R.at, R.at, mips.lo(ext.VEMMON - (ext.GAME_PARTNERS - eu.GAME))),
    mips.subu(R.v1, R.at, R.v1),
    mips.lw(R.v0, 16, R.s4),
    mips.j(SUMMARY_CHAIN + 0x18),                    -- addu v0, v0, v1 (past the sll 2)
    mips.NOP,
    "game",
    mips.subu(R.v1, R.v1, R.v0),
    mips.sll(R.v1, R.v1, 3),
    mips.subu(R.v1, R.v1, R.v0),
    mips.j(SUMMARY_CHAIN + 0x10),                    -- lw v0, 16(s4); sll v1, v1, 2
    mips.NOP,
  })
  files.patch32(FILE_STGMCARD, SUMMARY_CHAIN, 0x00021940, mips.j(summary))
  files.patch32(FILE_STGMCARD, SUMMARY_CHAIN + 4, 0x00621823, mips.NOP)

  -- the Lab's Digivolve Chart
  local lab = files.overlay(eu.FILE_STGDGLAB)
  local recipes = {}
  for p = 0, 7 do recipes[p] = lab:read32(LAB_DATA + 8 + 4 * p) end
  lab.ext:align(4)
  local rtable = lab.ext:addr()
  for p = 0, 17 do lab.ext:u32(p < 8 and recipes[p] or (p == 17 and recipes[GUILMON] or recipes[0])) end
  for _, s in ipairs(RECIPE_LOADS) do
    local off = rtable - LAB_DATA
    assert(off < 0x8000)
    files.patch32(eu.FILE_STGDGLAB, s[1], s[2], (s[2] & 0xFFFF0000) | off)
  end
  local items = extend(lab, TABLE_ITEMS, 4, string.pack("<i4", forms.ID[forms.VEMMON]))
  repoint(eu.FILE_STGDGLAB, TABLE_ITEMS_PAIR, TABLE_ITEMS, items)

  -- the chart's first icon: STGDGLAB_entries ({s16 id, sprite, b}, id 0
  -- ends) has no Vemmon, so its chart showed sprite 0 (another Digimon's);
  -- a copy of the list with Vemmon's own icon (sprites.add_chart_icon)
  local icon = sprites.add_chart_icon({ sheet_file = 709, sheet_entry = 1, tex_file = 710, tex_entry = 2,
    load_x = 0x140, load_y = 0x100, tex_x = 0x140, tex_y = 0x100, clut_x = 0x280, clut_y = 0 })
  local rows = {}
  for at = LAB_ENTRIES, LAB_ENTRIES + 0x1000, 6 do
    local row = lab:read(at, 6)
    if string.unpack("<h", row) == 0 then break end
    rows[#rows + 1] = row
  end
  lab.ext:align(4)
  local entries = lab.ext:addr()
  lab.ext:raw(table.concat(rows) .. string.pack("<hhh", forms.ID[forms.VEMMON], icon, 0) .. string.pack("<hhh", 0, 0, 0))
  for _, s in ipairs(LAB_ENTRIES_USES) do
    local at, word = s[1], s[2]
    local new = (word & 0xFFFF0000) | ((word >> 16 & 0xFFFF) == 0x3C03 and mips.hi(entries) or mips.lo(entries))
    files.patch32(eu.FILE_STGDGLAB, at, word, new)
  end

  M.party_stub = tables.stub("lab_party_list")
  files.patch32(eu.FILE_STGDGLAB, PARTY_LIST_END, mips.lw(mips.R.a0, PARTY_SCREEN_LAB, mips.R.s2), mips.jal(M.party_stub))

  for _, m in ipairs(MENUS) do
    local ovl = files.overlay(m.file)
    m.like = ovl:read32(m.table + 3 * m.row)          -- Agumon's first frame
    local ids = sprites.add(m)
    local anim = string.pack("<i4i4i4i4i4i4i4", ids[1], ids[2], ids[3], ids[2], -1, -1, -1)
    local new = extend(ovl, m.table, m.row, anim:sub(1, m.row))
    if m.pointer then
      files.patch32(m.file, m.pointer, m.table, new)
    else
      repoint(m.file, m.pairs, m.table, new)
    end
    if m.icons then
      -- the save list's card: Agumon's (frame 41) made Vemmon's (sprites.add_icon)
      local card = sprites.add_icon({ sheet_file = m.sheet_file, sheet_entry = m.sheet_entry, tex_file = m.tex_file,
        tex_entry = m.tex_entry, load_x = m.load_x, load_y = m.load_y, tex_x = m.tex_x, tex_y = m.tex_y, base = 41 })
      local icons = extend(ovl, m.icons.table, 4, string.pack("<i4", card))
      repoint(m.file, m.icons.pairs, m.icons.table, icons)
    end
  end
end

local function in_party(ctx, p)
  for i = 0, 2 do
    if ctx:read_s32(eu.GAME_PARTY + 4 * i) == p then return true end
  end
  return false
end

function M.install()
  dwrc.on_exec(clearBattleGauges, function(ctx)
    ctx:write16(VEMMON_GAUGE, 0)
    return false
  end)

  dwrc.on_exec(M.party_stub, function(ctx)
    local screen = ctx:reg("s2")
    if ext.vemmon_unlocked(ctx) and not in_party(ctx, ext.VEMMON_ID) then
      local count = ctx:read32(screen + PARTY_SCREEN_COUNT)
      if count < 8 then
        ctx:write32(screen + PARTY_SCREEN_PARTNERS + 4 * count, ext.VEMMON_ID)
        ctx:write32(screen + PARTY_SCREEN_COUNT, count + 1)
      end
    end
    ctx:set_reg("a0", ctx:read32(screen + PARTY_SCREEN_LAB))
    ctx:set_pc(PARTY_LIST_NEXT)
    return true
  end)
end

return M
