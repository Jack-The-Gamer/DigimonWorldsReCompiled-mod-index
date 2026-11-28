-- What differs between the releases the mod runs on: Digimon World (USA,
-- SLUS-01032) and Digimon World (Europe, SLES-02914). Addresses and names
-- from the dw_decomp decompilation (config/us and config/eu symbols; the
-- European executable and overlays were compiled with less optimisation, so
-- hooks in the middle of a function were read in its own code). Every other
-- file reads its release's facts from here; `nil` means the release has no
-- such thing. Returns the table for dwrc.serial, or nil.

local US = {
  serial = "SLUS-01032",
  title = "Digimon World (USA)",
  exe = "SLUS_010.32",
  exe_code = 0x80090800,          -- the executable's first byte after its 2 KiB header
  rel_bin_offsets = 0x8012B96C,   -- the overlays' load addresses (16 words)
  rel_bin_files = 0x8012BA8C,     -- and their names (16 pointers)
  file_offset_table = 0x8011FE1C, -- every file: {sector, size, name*}, up to size 0

  -- DigimonPara: the USA one starts with name[20]
  para = { size = 0x34, name = 0, bones = 20, radius = 24, height = 26, attribute = 28, level = 29, special = 30, moves = 35 },
  -- names: in DigimonPara (USA), or DIGIMON_NAMES' char * (Europe, full-width Shift-JIS)
  names = nil,

  tables = {
    DIGIMON_DATA = 0x8012CEB4, DIGIMON_SKELETONS = 0x8011CE60, PTR_DIGIMON_FILE_NAMES = 0x8011D19C,
    ORIGINAL_DIGIMON_TYPES = 0x8012A84C, TOURNAMENT_SCHEDULE = 0x80130198, DIGIMON_VBALL_SOUND_ID = 0x80127F40,
    RAISE_DATA = 0x801225BC, ITEM_TAKE_DISTANCE = 0x80122D24, DIGIMON_VLALL_SOUND_ID = 0x80127EFC,
    CARD_DATA = 0x8012FFD8, EVOLUTION_REQS = 0x8012ABEC, EVOLUTION_STATS_GAINS = 0x8012B2D0,
    EVOLUTION_PATHS = 0x8012B66C, MOVE_NAMES = 0x80126054, MOVE_DATA = 0x8012623C,
  },
  init_heap3 = 0x80090F24,        -- InitHeap3(start, size), called by initializeHeap()
  heap_start = 0x801BFB70,        -- what initializeHeap() passes (from _end)
  heap_end = 0x801EFF00,          -- where it ends: 64 KiB below the stack top
  stack_top = 0x801FFFF0,

  -- lib/limits.lua: address, the instruction there (slti/sltiu rt, rs, limit)
  type_limits = {
    { 0x800A1F98, 0x2A2100B4 }, -- loadMMD: type < 180
    { 0x800A258C, 0x288100B4 }, -- getEntityModelComponent: type < 180
    { 0x800A2840, 0x2A0100B4 }, -- loadMMDAsync: type < 180 (the evolution's next model)
    { 0x800A2A70, 0x2A2100B4 }, -- applyMMD: type < 180
    { 0x800C64F8, 0x2A010042 }, -- loadPartnerSounds: type < 66, else the default voice 15
    { 0x800E9188, 0x2A010042 }, -- loadVLALL (the evolution's voice): type <= 65, else voice 15
  },
  finisher_checks = {
    { "SLUS_010.32", 0x800A46C8, 0x2CA10071 }, -- initializePartner
    { "SLUS_010.32", 0x800F5E34, 0x28A10071 }, -- VS__tickDigimonSenile
    { "BTL_REL.BIN", 0x80058734, 0x28A10071 }, -- BTL_tickEnemyAI
    { "BTL_REL.BIN", 0x8005A1AC, 0x28810071 }, -- BTL_tickMeleeAttack
    { "BTL_REL.BIN", 0x8005BCA4, 0x28E10071 }, -- BTL_calculateHitChance
    { "BTL_REL.BIN", 0x8005BFC4, 0x2A010071 }, -- BTL_calculateDamage
    { "BTL_REL.BIN", 0x8005C10C, 0x2A010071 }, -- BTL_calculateDamage
    { "BTL_REL.BIN", 0x8005D3D8, 0x28410071 }, -- BTL_isMoveUsable
    { "BTL_REL.BIN", 0x8005D824, 0x2A610071 }, -- BTL_startQueuedMove
    { "BTL_REL.BIN", 0x8005DB2C, 0x2A210071 }, -- BTL_setupMoveExecution
    { "BTL_REL.BIN", 0x8005DCC4, 0x2A210071 }, -- BTL_setupMoveExecution
    { "BTL_REL.BIN", 0x8005E050, 0x28410071 }, -- BTL_addFinisherProgress
    { "STD_REL.BIN", 0x8005729C, 0x28410071 }, -- STD_initializeOpponent
    { "STD_REL.BIN", 0x800574BC, 0x2C610071 }, -- STD_initializeOpponent
    { "STD_REL.BIN", 0x800601CC, 0x28A10071 }, -- STD_tickEnemyAI
    { "STD_REL.BIN", 0x80061D74, 0x28810071 }, -- STD_tickMeleeAttack
    { "STD_REL.BIN", 0x80063D6C, 0x28E10071 }, -- STD_applyPartnerStatsToFighter
    { "STD_REL.BIN", 0x80063FAC, 0x2A010071 }, -- STD_calculateDamage
    { "STD_REL.BIN", 0x800640F4, 0x2A010071 }, -- STD_calculateDamage
    { "STD_REL.BIN", 0x8006517C, 0x28410071 }, -- STD_isMoveUsable
    { "STD_REL.BIN", 0x800655C8, 0x2A610071 }, -- STD_startQueuedMove
    { "STD_REL.BIN", 0x800659AC, 0x2A010071 }, -- STD_setupMoveExecution
    { "STD_REL.BIN", 0x80065B44, 0x2A010071 }, -- STD_setupMoveExecution
    { "STD_REL.BIN", 0x80065E84, 0x28410071 }, -- STD_addFinisherProgress
    { "VS_REL.BIN",  0x8005B9F0, 0x28E10071 }, -- VS_applyPartnerStatsToFighter
    { "VS_REL.BIN",  0x8005BC20, 0x28C10071 }, -- VS_rollAttackOutcome
    { "VS_REL.BIN",  0x8005CB84, 0x28410071 }, -- VS_isMoveUsable
    { "VS_REL.BIN",  0x8005CF80, 0x2A610071 }, -- VS_startFighterMove
    { "VS_REL.BIN",  0x8005D364, 0x2A210071 }, -- VS_playMoveEffect
    { "VS_REL.BIN",  0x8005D384, 0x2A210071 }, -- VS_playMoveEffect
    { "VS_REL.BIN",  0x8005D868, 0x28410071 }, -- VS_addFinisherProgress
    { "EVL_REL.BIN", 0x80063A0C, 0x2C810071 }, -- EVL_applyEvolution
  },
  generic_attack = {
    { "BTL_REL.BIN", 0x8005B7B8, 0x24020079 },
    { "STD_REL.BIN", 0x800638AC, 0x24020079 },
    { "VS_REL.BIN",  0x8005B530, 0x24020079 },
    { "BTL_REL.BIN", 0x800596DC, 0x24070079 }, -- BTL_tickFlatState
    { "STD_REL.BIN", 0x8006133C, 0x24070079 }, -- STD_tickFlatState
    { "SLUS_010.32", 0x800F53D0, 0x24070079 }, -- VS__tickDigimonFlat
  },
  name_check = { "SLUS_010.32", 0x8010FC0C, 0x28410079 }, -- drawMoveName
  has_digimon_raised = 0x800FF824,
  set_digimon_raised = 0x800FF7F8,
  new_game_scene = 0x800EF1E0,
  get_original_type = 0x800D9A3C,
  get_efedat_entry = 0x800AEFF4,
  -- initializeDigimonObject: both paths meet here; where the type and the
  -- root PositionData are ({reg} or {stack offset})
  root_scale = { at = 0x800A1094, type = { reg = "s4" }, root = "s1" },
  setup_loaded_efe = { { "BTL_REL.BIN", 0x800650EC }, { "STD_REL.BIN", 0x8006D7D4 }, { "VS_REL.BIN", 0x800638A4 } },
  check_tech = { { "BTL_REL.BIN", 0x8006D8FC }, { "STD_REL.BIN", 0x80075ED8 }, { "VS_REL.BIN", 0x8006BFA8 } },
  evl_set_scratch_top = 0x800601B0,
  efe_data_stack = 0x80134CC8,
  efe_script_context = 0x80134CE8,

  -- lib/files.lua
  lookup_file_table = 0x800A31F8,
  add_file_read_request_path = 0x800E3938,
  add_file_read_request_lookup = 0x800E3BB4,
  -- loadMMD's NPC branch with its path built: the instructions there, the
  -- path's place on the stack, and the return addresses that say the load
  -- comes from a map script ({stack offset, value} each)
  npc_path = { at = 0x800A2188, words = { 0x20420030, 0xA3A20031, 0x0C028CB3, 0x27A40028 }, path = 40, from_script = { { 36, 0x80106A04 } } },

  -- lib/evolution.lua, lib/special.lua
  pickers = { in_training = 0x800E2598, rookie = 0x800E2BB4, champion = 0x800E2F08 },
  partner_tick = 0x800DD7AC,
  -- tickConditions where its level checks meet again: the registers with the level and evoTimer
  ultimate_check = { at = 0x800A9254, level = "s0", timer = "s1" },
  evolution_target = 0x80134E50,
  partner_entity = 0x801557A8,
  partner_para = 0x80138460,
  partner_state = 0x80134C5B,
  trigger_base_ptr = 0x80134FB8,
  special = {
    virus_sukamon = { 0x800A92AC, 0x24020027 },   -- addiu v0, zero, 39
    conditions_tail = { 0x800A9328, 0x87829324 }, -- lh v0, -27868(gp)
    poop_sukamon_test = { 0x800A7EE4, 0x24010027 }, -- addiu at, zero, 39
    poop_search = { 0x800A7EF0, 0x3C018015 },     -- lui at, 0x8015
    eat_poop = { 0x800A8244, 0x9383913C },        -- lbu v1, -28356(gp)
  },

  -- lib/names.lua
  long_names = {
    draw_string = { 0x8010CF24, 0x27BDFFE0 },     -- addiu sp, sp, -32
    glyph_advance = { 0x8010D004, 0x02221021 },   -- addu v0, s1, v0: s1 the glyph's x, v0 its width
    glyph_regs = { x = "s1", w = "v0" },
    draw_string_end = { 0x8010D01C, 0x8FBF001C }, -- lw ra, 28(sp): s2 y
    end_y = { reg = "s2" },
    name_call = { 0x800BB85C, 0x0C0396D4 },       -- jal renderString (the name)
    name_done = { 0x800BB864, 0x3C018014 },       -- lui at, 0x8014
    render_string = { 0x800E5B50, 0x27BDFFC0 },   -- addiu sp, sp, -64
  },

  -- the Digivolution Chart (lib/chart.lua)
  chart = {
    render_chart = 0x800BD940, chart_tick = 0x800B9654, chart_tick_end = 0x800B9B88,
    render_border_box = 0x800BE990, is_key_down = 0x800FC054, play_sound = 0x800C6374,
    is_ui_box_available = 0x800BA1D4, create_animated_ui_box = 0x800C3014, remove_animated_ui_box = 0x800C31FC,
    render_chart_detail = 0x800BA930, load_image = 0x800948A8, draw_sync = 0x800947B0,
    draw_line_3p = 0x800E3D14, draw_line_2p = 0x800E3E7C, draw_chart_strings = 0x800C0718,
    render_string = 0x800E5B50, draw_string = 0x8010CF24, render_inset_box = 0x800BE734,
    menu_sub_state = 0x80134D35, ascii_to_sjis = 0x800F18C8, sjis_to_font = 0x800F1AB0,
    font_codes = 0x801307E0, font_glyphs = 0x80130880,
    evo_chart_detail_colors = 0x80123E6C, chart_to_line_colors = 0x80124A84,
    menu_state = 0x80134D34, player_menu_state = 0x80134D37, chart_selected_digimon = 0x80134D40,
    main_d_80134d46 = 0x80134D46, changed_input = 0x80134EEC, playtime_frames = 0x80134F00,
    evo_chart_boxes = 0x80124544, evo_chart_view_colors = 0x80123E1C,
    gs_out_packet_p = 0x80136FE4, active_ordering_table = 0x80134ED0,
  },

  -- File City's Arena (lib/arena.lua, STD_REL.BIN)
  arena = {
    participant_types = 0x80135150,
    add_bracket = 0x8005DEEC, add_bracket_words = { 0x27BDFFE8, 0x3C018013, 0xAFBF0014 },
    render_tile = 0x8005D5B0, render_words = { [0x8005D578] = 0x90510000, [0x8005D5B0] = 0x0220A021, [0x8005D5FC] = 0x0C024AAF },
    get_clut = 0x80092ABC, from_render = 0x8005D604, load_image = 0x800948A8, draw_sync = 0x800947B0,
  },

  -- Sukamon's hint in File City: section 6 of script 162 in each language's script file
  sukamon_hint = { { file = "DG.SCN", at = 0x740C6 } },
}

local EU = {
  serial = "SLES-02914",
  title = "Digimon World (Europe)",
  exe = "SLES_029.14",
  exe_code = 0x80090800,
  rel_bin_offsets = 0x801357B4,
  rel_bin_files = 0x801358D4,
  file_offset_table = 0x80125F44,

  -- Where each overlay's bss starts in its file (dw_decomp config/eu/*.yaml):
  -- the European files carry leftover bytes there, code-shaped ones too
  -- (MOV_REL.BIN's buffers hold 261 lui/addiu pairs that look like table
  -- references, STD 18, KAR 16, FISH 3), so the scan stops there.
  code_end = {
    ["BTL_REL.BIN"] = 0x29A8C, ["DOO2_REL.BIN"] = 0x27EC, ["DOOA_REL.BIN"] = 0x629C, ["EAB_REL.BIN"] = 0x1E70,
    ["ENDI_REL.BIN"] = 0x12BC, ["EVL_REL.BIN"] = 0x54A4, ["FISH_REL.BIN"] = 0xEB88, ["KAR_REL.BIN"] = 0xA3C0,
    ["MOV_REL.BIN"] = 0xC04, ["MURD_REL.BIN"] = 0x21FC, ["STD_REL.BIN"] = 0x3246C, ["TRN_REL.BIN"] = 0x7CF4,
    ["TRN2_REL.BIN"] = 0x61CC, ["VS_REL.BIN"] = 0x31B88,
  },

  -- DigimonPara without the name (0x20 bytes)
  para = { size = 0x20, bones = 0, radius = 4, height = 6, attribute = 8, level = 9, special = 10, moves = 15 },
  names = 0x8013A1DC,             -- DIGIMON_NAMES: char *[180]

  tables = {
    DIGIMON_DATA = 0x80138B5C, DIGIMON_SKELETONS = 0x80122DD4, PTR_DIGIMON_FILE_NAMES = 0x80123110,
    ORIGINAL_DIGIMON_TYPES = 0x8013AA8C, TOURNAMENT_SCHEDULE = 0x801348BC, DIGIMON_VBALL_SOUND_ID = 0x801313BC,
    RAISE_DATA = 0x80129A2C, ITEM_TAKE_DISTANCE = 0x8012A194, DIGIMON_VLALL_SOUND_ID = 0x80131378,
    CARD_DATA = 0x801346FC, EVOLUTION_REQS = 0x80134A30, EVOLUTION_STATS_GAINS = 0x80135114,
    EVOLUTION_PATHS = 0x801354B0, MOVE_NAMES = 0x8012FAD0, MOVE_DATA = 0x8012FCB8,
    DIGIMON_NAMES = 0x8013A1DC,
  },
  init_heap3 = 0x80091074,
  heap_start = 0x801C8CD0,
  heap_end = 0x801EFF00,
  stack_top = 0x801FFFF0,

  type_limits = {
    { 0x800A1640, 0x2A4100B4 }, -- loadMMD
    { 0x800A1D4C, 0x2A2100B4 }, -- getEntityModelComponent
    { 0x800A20DC, 0x284100B4 }, -- loadMMDAsync
    { 0x800A23C8, 0x2A4100B4 }, -- applyMMD
    { 0x800CE8B0, 0x2A010042 }, -- loadPartnerSounds
    { 0x80105900, 0x2A410042 }, -- loadVLALL
  },
  finisher_checks = {
    { "SLES_029.14", 0x800A52C8, 0x2C410071 }, -- initializePartner
    { "VS_REL.BIN",  0x80065544, 0x28410071 }, -- VS__tickDigimonSenile (in the overlay here)
    { "BTL_REL.BIN", 0x80058EB8, 0x28410071 }, -- BTL_tickEnemyAI
    { "BTL_REL.BIN", 0x8005B014, 0x28410071 }, -- BTL_tickMeleeAttack
    { "BTL_REL.BIN", 0x8005D110, 0x28410071 }, -- BTL_calculateHitChance
    { "BTL_REL.BIN", 0x8005D500, 0x2A410071 }, -- BTL_calculateDamage
    { "BTL_REL.BIN", 0x8005D674, 0x2A410071 }, -- BTL_calculateDamage
    { "BTL_REL.BIN", 0x8005EE28, 0x2A210071 }, -- BTL_isMoveUsable
    { "BTL_REL.BIN", 0x8005F3AC, 0x28410071 }, -- BTL_startQueuedMove
    { "BTL_REL.BIN", 0x8005F764, 0x28410071 }, -- BTL_setupMoveExecution
    { "BTL_REL.BIN", 0x8005F964, 0x28410071 }, -- BTL_setupMoveExecution
    { "BTL_REL.BIN", 0x8005FDF0, 0x2A410071 }, -- BTL_addFinisherProgress
    { "STD_REL.BIN", 0x800573E4, 0x28410071 }, -- STD_initializeOpponent
    { "STD_REL.BIN", 0x800576B8, 0x2C410071 }, -- STD_initializeOpponent
    { "STD_REL.BIN", 0x80062208, 0x28410071 }, -- STD_tickEnemyAI
    { "STD_REL.BIN", 0x80064478, 0x28410071 }, -- STD_tickMeleeAttack
    { "STD_REL.BIN", 0x80066C28, 0x28410071 }, -- STD_applyPartnerStatsToFighter
    { "STD_REL.BIN", 0x80066F10, 0x2A410071 }, -- STD_calculateDamage
    { "STD_REL.BIN", 0x80067084, 0x2A410071 }, -- STD_calculateDamage
    { "STD_REL.BIN", 0x80068510, 0x2A210071 }, -- STD_isMoveUsable
    { "STD_REL.BIN", 0x80068A94, 0x28410071 }, -- STD_startQueuedMove
    { "STD_REL.BIN", 0x80068F5C, 0x28410071 }, -- STD_setupMoveExecution
    { "STD_REL.BIN", 0x8006915C, 0x28410071 }, -- STD_setupMoveExecution
    { "STD_REL.BIN", 0x800695B8, 0x2A410071 }, -- STD_addFinisherProgress
    { "VS_REL.BIN",  0x80067B20, 0x28410071 }, -- VS_applyPartnerStatsToFighter
    { "VS_REL.BIN",  0x80067E08, 0x2A410071 }, -- VS_rollAttackOutcome
    { "VS_REL.BIN",  0x80069140, 0x2A410071 }, -- VS_isMoveUsable
    { "VS_REL.BIN",  0x80069660, 0x28410071 }, -- VS_startFighterMove
    { "VS_REL.BIN",  0x80069B20, 0x2A410071 }, -- VS_playMoveEffect
    { "VS_REL.BIN",  0x80069B40, 0x2A410071 }, -- VS_playMoveEffect
    { "VS_REL.BIN",  0x8006A170, 0x2A410071 }, -- VS_addFinisherProgress
    { "EVL_REL.BIN", 0x80064D98, 0x2C410071 }, -- EVL_applyEvolution
  },
  generic_attack = {
    { "BTL_REL.BIN", 0x8005CC0C, 0x24020079 },
    { "STD_REL.BIN", 0x80066740, 0x24020079 },
    { "VS_REL.BIN",  0x80067638, 0x24020079 },
    { "BTL_REL.BIN", 0x8005A2F4, 0x24070079 }, -- BTL_tickFlatState
    { "STD_REL.BIN", 0x8006380C, 0x24070079 }, -- STD_tickFlatState
    { "VS_REL.BIN",  0x800648A4, 0x24070079 }, -- VS__tickDigimonFlat
  },
  name_check = { "SLES_029.14", 0x80109FE0, 0x2A010079 },
  has_digimon_raised = 0x800FC610,
  set_digimon_raised = 0x800FC5D0,
  new_game_scene = 0x801154EC,
  get_original_type = 0x80118800,
  get_efedat_entry = 0x800B1F20,
  -- the type is a local (sp + 56) here, the root in s0
  root_scale = { at = 0x800A03D8, type = { stack = 56 }, root = "s0" },
  setup_loaded_efe = { { "BTL_REL.BIN", 0x80069020 }, { "STD_REL.BIN", 0x8007361C }, { "VS_REL.BIN", 0x80072B00 } },
  check_tech = { { "BTL_REL.BIN", 0x80074A38 }, { "STD_REL.BIN", 0x8007EE64 }, { "VS_REL.BIN", 0x8007E348 } },
  evl_set_scratch_top = 0x800613AC,
  efe_data_stack = 0x8013BD98,
  efe_script_context = 0x8013BDB8,

  lookup_file_table = 0x800A2E10,
  add_file_read_request_path = 0x800FE1DC,
  add_file_read_request_lookup = 0x800FE4BC,
  -- addiu a0,sp,44; jal lookupFileSize; nop. No tail calls here: loadMMD's
  -- ra is thunkLoadMMD's, whose is loadNPCModel's, whose is scriptLoadModel's.
  npc_path = { at = 0x800A18B8, words = { 0x27A4002C, 0x0C028BC1, 0x00000000 }, path = 44,
    from_script = { { 36, 0x8009FD54 }, { 88 + 16, 0x800BA508 }, { 88 + 24 + 16, 0x800EEB7C } } },

  pickers = { in_training = 0x800FC97C, rookie = 0x800FD144, champion = 0x800FD568 },
  partner_tick = 0x800E6FE4,
  ultimate_check = { at = 0x800AA84C, level = "s1", timer = "s0" },
  evolution_target = 0x8013BFE0,
  partner_entity = 0x8016C7F8,
  partner_para = 0x8013FA28,
  partner_state = 0x8013BD2E,
  trigger_base_ptr = 0x8013BF28,
  special = {
    virus_sukamon = { 0x800AA8B0, 0x24020027 },     -- addiu v0, zero, 39
    conditions_tail = { 0x800AA93C, 0x878293EC },   -- lh v0, -27668(gp)
    poop_sukamon_test = { 0x800A9294, 0x24010027 }, -- addiu at, zero, 39
    poop_search = { 0x800A92A0, 0x00008021 },       -- addu s0, zero, zero
    eat_poop = { 0x800A96C0, 0x27BDFFE0 },          -- addiu sp, sp, -32
  },

  long_names = {
    draw_string = { 0x800A467C, 0x27BDFFE0 },     -- addiu sp, sp, -32
    glyph_advance = { 0x800A46D0, 0x02221021 },   -- addu v0, s1, v0 (x += drawGlyph(...))
    glyph_regs = { x = "s1", w = "v0" },
    draw_string_end = { 0x800A46E8, 0x8FBF001C }, -- lw ra, 28(sp)
    end_y = { stack = 40 },                       -- y kept at sp + 40 here
    name_call = { 0x800C151C, 0x0C0404BE },       -- jal renderString (width = letters * 8)
    name_done = { 0x800C1524, 0x3C018014 },       -- lui at, 0x8014
    render_string = { 0x801012F8, 0x27BDFFD8 },   -- addiu sp, sp, -40
    name_x = -0x6D, name_y = -0x33, box = 116,
  },

  chart = {
    render_chart = 0x800C3AF8, chart_tick = 0x800BE228, chart_tick_end = 0x800BE934,
    render_border_box = 0x800C4CF4, is_key_down = 0x800F7C60, play_sound = 0x800CE688,
    is_ui_box_available = 0x800BF934, create_animated_ui_box = 0x800CAA30, remove_animated_ui_box = 0x800CAB3C,
    render_chart_detail = 0x800C03AC, load_image = 0x80094550, draw_sync = 0x80094458,
    draw_line_3p = 0x800FE640, draw_line_2p = 0x800FE800, draw_chart_strings = 0x800C70F8,
    render_string = 0x801012F8, draw_string = 0x800A467C, render_inset_box = 0x800C4A4C,
    menu_sub_state = 0x8013BE05, -- (no ASCII here: text is full width, lib/text.lua measures it)
    evo_chart_detail_colors = 0x8012BAC8, chart_to_line_colors = 0x8012C6E0,
    menu_state = 0x8013BE06, player_menu_state = 0x8013BE04, chart_selected_digimon = 0x8013BE18,
    main_d_80134d46 = 0x8013BE16, changed_input = 0x8013C0B4, playtime_frames = 0x8013C0D0,
    evo_chart_boxes = 0x8012C100, evo_chart_view_colors = 0x8012BA78,
    gs_out_packet_p = 0x8013DFC4, active_ordering_table = 0x8013C0B0,
    -- the page's text area: the stage names are 48-pixel cells ("Traini",
    -- "Traini", "Rookie" in row 0x18 from u 0x30; "Champi", "Ultima" in row
    -- 0x48), "Chart" in the title's place, names up to 160 pixels
    stage_text = { { 0x30, 0x30, 0x18 }, { 0x30, 0x60, 0x18 }, { 0x30, 0x90, 0x18 }, { 0x30, 0, 0x48 }, { 0x30, 0x30, 0x48 } },
    title_text = { -0x19, 0x30 },
    name_max = 0xA0,
    mega_text = { 0x60, 0x48 },  -- after "Ultima"
    -- drawEvoChartStrings reads its int8 type back from the stack: lb v0,
    -- 40(sp); nop; sll v1, v0, 2 (the DIGIMON_NAMES index)
    name_index = { 0x800C7214, 0x00021880, "v0" },
    first_icon_slot = 4,         -- the chart icons' first row starts past "Mega"
  },

  arena = {
    participant_types = 0x8013C1CC,
    add_bracket = 0x8005F524, add_bracket_words = { 0x27BDFFE8, 0xAFBF0010, 0xAFA40018 },
    -- the tile stays in s1 all through STD_renderBracketDigimon here: hooked
    -- where it is first used (sra t9, s1, 6)
    render_tile = 0x8005E8F0, render_words = { [0x8005E8B0] = 0x305100FF, [0x8005E8F0] = 0x0011C983, [0x8005E958] = 0x0C025541 },
    get_clut = 0x80095504, from_render = 0x8005E960, load_image = 0x80094550, draw_sync = 0x80094458,
  },

  -- one script file per language: English, French, German, Italian, Spanish
  sukamon_hint = { { file = "DG0.SCN", at = 0x740C2 } },
}

local R = ({ ["SLUS-01032"] = US, ["SLES-02914"] = EU })[dwrc.serial]
return R
