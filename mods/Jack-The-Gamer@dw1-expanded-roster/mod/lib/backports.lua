-- The Digimon brought over from Digimon World 2003 and Digimon World 2 (and
-- Digimon World's own NPC-only ones, `game = "dw1"`: lib/dw1source.lua),
-- built while the mod loads from the player's own discs (nothing of any of
-- the games ships with the mod). Each one: its new type number and name, its
-- game (`game`, "dw3" if not given) and where its model is on that disc, the
-- DW1 Digimon whose skeleton and animations it uses (the donor), how the
-- bones map (see lib/convert.lua), and its height.
--
-- Only the European DW2003 (SLES-03936) is known so far: the model's file
-- number and its bone/motion entries differ on the American and Japanese
-- discs (find them through the fighter table, SMDLDATA.PRO). Likewise only
-- the American DW2 (SLUS-01193): its Digimon records (data files 0xCB9..
-- 0xCBB, research/tools/dw2disc.py) give the model and animation files.

local M = {}

-- Digimon World 2003 (Europe): the executable's file table (first sector,
-- sector count of each file by number).
M.DW3 = {
  ["SLES-03936"] = { exe = "SLES_039.36", load = 0x80010000, sectors = 0x80044F6C, counts = 0x800474A4, files = 2382 },
}

-- Digimon World 2 (USA): the executable's file table, by offset in the file
-- (Cd_FileLba s32 first sector, Cd_FileSectors u16 count; 0xE5B files).
M.DW2 = {
  ["SLUS-01193"] = { exe = "SLUS_011.93", lba = 0x33F94, sectors = 0x37900 },
}

M.list = {
  {
    type = 180, name = "Guilmon", file = "GIRU", level = 3, height = 270,
    -- Its entries start as the donor's; these replace them (DW1 values:
    -- attribute 1 Data, 2 Vaccine, 3 Virus; specialties 0 Fire, 1 Battle,
    -- 2 Air, 3 Earth, 4 Ice, 5 Mech, 6 Filth, 255 none).
    attribute = 3, specialties = { 0, 255, 1 }, radius = 140,
    -- Techniques: Agumon's; its finisher (59 Pepper Breath, a fireball, on
    -- Agumon's animation) becomes Guilmon's own Pyro Sphere with the same
    -- stats (lib/tables.lua: new finishers from 0x71).
    finisher = { name = "Pyro Sphere", from = 59 },
    -- Stats gained on evolving into it {HP, MP, Off, Def, Speed, Brains}.
    gains = { 900, 450, 110, 40, 70, 40 },
    -- Becoming it (EvoRequirements): a Koromon (2) whose highest stat is
    -- Offense or Speed (1 = "this one is highest", -1 = don't care) at
    -- weight 25 +- 5, any care mistakes. Agumon and Gabumon (also from
    -- Koromon) want weight 15 +- 5; ties keep the earlier of Koromon's
    -- evolutions, and Guilmon comes after them.
    requirements = { digimon = 2, hp = -1, mp = -1, offense = 1, defense = -1, speed = 1, brain = -1,
      care = 0, weight = 25, discipline = -1, happiness = -1, battles = -1, techs = -1, flags = 0 },
    evolves_from = { 2 }, -- Koromon
    -- Its chart icon (lib/icon.lua): the head (DW1 bones 3, 4) at its own
    -- size, so both ears show as two points, and the first frame's head
    -- taken from the second frame (it reads better there).
    icon_head = { 3, 4 }, icon_head_scale = 1.0, icon_head_from_second = true,
    -- Its own evolutions: Growlmon (only from Guilmon, not Agumon), Greymon,
    -- Tyrannomon, Airdramon. Ties keep the earlier one.
    evolutions = { 181, 5, 8, 7 },
    -- The Digimon page's camera stays the donor's (RAISE_DATA viewX/Y/Z:
    -- Agumon's 550, 230, -1870 frames it whole; a more negative z comes
    -- closer and moves it left, a larger y moves it down). `view = {x, y, z}`
    -- sets another.
    source = { ["SLES-03936"] = { file = 356, bones = 24, motions = 50 } }, -- M366GIRU
    donor = 3, donor_file = "AGUM.MMD", -- Agumon
    -- DW3 bone (1-based) -> { DW1 bone, kind [, DW3 child, DW1 child] }
    mapping = {
      -- hybrid (as WarGrowlmon): arms keep their own stance; thighs turned to the
      -- donor's keeping their roll, so its walk swings them the right way; shins
      -- keep their bend to the thigh; feet flat
      [1] = { 2, "core" },                                                         -- upper body -> torso
      [2] = { 6, "core" }, [3] = { 7, "core" }, [4] = { 8, "core" },  -- right arm
      [10] = { 10, "core" }, [11] = { 11, "core" }, [12] = { 12, "core" }, -- left arm
      [5] = { 3, "core" }, [6] = { 3, "follow" }, [8] = { 3, "follow" }, [9] = { 3, "follow" }, -- neck, head, ears -> head
      [7] = { 4, "core" },                                                         -- jaw -> jaw
      [13] = { 13, "core" }, [22] = { 13, "follow" }, [23] = { 13, "follow" }, [24] = { 13, "follow" }, -- pelvis, tail -> hips
      [14] = { 15, "limb", 15, 16, true }, [15] = { 16, "leaf" }, [16] = { 16, "follow" }, [17] = { 17, "core" }, -- right leg
      [18] = { 19, "limb", 19, 20, true }, [19] = { 20, "leaf" }, [20] = { 20, "follow" }, [21] = { 21, "core" }, -- left leg
    },
  },
  {
    type = 181, name = "Growlmon", file = "GRAW", level = 4, height = 410,
    attribute = 3, specialties = { 0, 1, 255 }, radius = 230, -- Virus; Fire, Battle
    -- Greymon's gains (Agumon's Champion line)
    gains = { 2000, 1500, 200, 200, 200, 200 },
    -- Greymon's techniques; its finisher (63 Mega Flame) as Exhaust Flame
    finisher = { name = "Exhaust Flame", from = 63 },
    -- Becoming it (a Champion: every stat it names, then care/weight/...):
    -- Offense and Speed 100, at most 3 care mistakes (flags 0x10: "care" is
    -- a maximum), weight 30 +- 5, 30 techniques. Looser on care and
    -- discipline than Greymon (100 in all four stats, 1 mistake, discipline
    -- 90), which Guilmon can also become.
    requirements = { digimon = -1, hp = -1, mp = -1, offense = 100, defense = -1, speed = 100, brain = -1,
      care = 3, weight = 30, discipline = -1, happiness = -1, battles = -1, techs = 30, flags = 0x10 },
    evolves_from = { 180 }, -- Guilmon
    icon_head = { 4, 5 }, -- Greymon's head and jaw
    -- WarGrowlmon, SkullGreymon (Greymon's other Ultimate) or Megadramon
    -- (SkullGreymon's own source list is full, so its chart page doesn't
    -- name Growlmon; Megadramon's has room)
    evolutions = { 182, 26, 54 },
    source = { ["SLES-03936"] = { file = 625, bones = 50, motions = 0 } }, -- M367GRAW
    donor = 5, donor_file = "GREY.MMD", -- Greymon
    -- Its model is bigger than Greymon's: lib/convert.lua slims it to fit
    -- the partner buffer (shortest edges first).
    mapping = {
      -- hybrid (as WarGrowlmon): arms keep their own stance; thighs turned to the
      -- donor's keeping their roll, so its walk swings them the right way; shins
      -- keep their bend to the thigh; feet flat
      [1] = { 2, "core" },                                                         -- upper body -> torso
      [6] = { 3, "core" }, [7] = { 4, "core" }, [8] = { 5, "core" },               -- neck, head, jaw
      [2] = { 7, "core" }, [3] = { 8, "core" }, [4] = { 8, "follow" }, [5] = { 9, "core" }, -- right arm, elbow blade
      [9] = { 11, "core" }, [10] = { 12, "core" }, [11] = { 12, "follow" }, [12] = { 13, "core" }, -- left arm
      [13] = { 14, "core" },                                                       -- pelvis
      [14] = { 15, "limb", 15, 16 }, [15] = { 16, "limb", 16, 17 }, [16] = { 17, "leaf" }, -- tail
      [17] = { 23, "limb", 18, 24, true }, [18] = { 24, "leaf" }, [19] = { 24, "follow" }, [20] = { 25, "core" }, -- left leg
      [21] = { 19, "limb", 22, 20, true }, [22] = { 20, "leaf" }, [23] = { 20, "follow" }, [24] = { 21, "core" }, -- right leg
    },
  },
  {
    type = 182, name = "WarGrowlmon", file = "WGRW", level = 5, height = 460,
    attribute = 3, specialties = { 0, 5, 1 }, radius = 280, -- Virus; Fire, Mech, Battle
    -- MetalGreymon's gains
    gains = { 5000, 5000, 500, 500, 500, 500 },
    -- Becoming it (Ultimate; as MetalGreymon's, with Offense and Speed
    -- first): HP 400, MP 300, Off 500, Def 300, Speed 500, Brains 300, at
    -- most 10 care mistakes (flags 0x10), weight 65, discipline 80, 30
    -- battles, 30 techniques.
    requirements = { digimon = -1, hp = 400, mp = 300, offense = 500, defense = 300, speed = 500, brain = 300,
      care = 10, weight = 65, discipline = 80, happiness = -1, battles = 30, techs = 30, flags = 0x10 },
    evolves_from = { 181, 5, 8 }, -- Growlmon, Greymon, Tyrannomon
    -- MetalGreymon's techniques; its finisher (79 Giga Scissor Claw: stats
    -- and animation) as WarGrowlmon's Atomic Blaster, with the effect of
    -- Vademon's Abduction Beam (0x43) fired from the chest: the torso (bone
    -- 2), in its own space 95 forward of the pivot.
    finisher = { name = "Atomic Blaster", from = 79, effect = 0x43, origin = { 2, 95, -15, 0 } },
    icon_head = { 4, 5 }, -- MetalGreymon's head and jaw
    source = { ["SLES-03936"] = { file = 1103, bones = 54, motions = 0 } }, -- M368MGRW
    donor = 12, donor_file = "MTGR.MMD", -- MetalGreymon (its small parts 15 and 17 stay empty)
    -- 980 polygons: slimmed to fit next to MetalGreymon's animations
    mapping = {
      [13] = { 2, "core" }, [14] = { 2, "follow" }, [15] = { 2, "follow" }, [16] = { 2, "follow" }, [17] = { 2, "follow" }, -- upper body, the strands on its back
      [18] = { 3, "core" }, [19] = { 4, "core" }, [20] = { 5, "core" },               -- neck, head, jaw
      -- Arms keep WarGrowlmon's own stance (cannons down at the sides):
      -- turned to MetalGreymon's forward claws, the forearm blades stuck out
      -- across the body. Thighs are turned to MetalGreymon's (legs swing up
      -- to 98 degrees walking) keeping their roll (5th field: the smallest
      -- turn crossed the legs); shins and feet keep their angle to the thigh
      -- (MetalGreymon's shins slant inward and put the feet together).
      [21] = { 7, "core" }, [22] = { 8, "core" }, [23] = { 9, "core" },               -- right arm, forearm blade
      [24] = { 11, "core" }, [25] = { 12, "core" }, [26] = { 13, "core" },            -- left arm
      [1] = { 18, "core" },                                                           -- pelvis -> hips
      [2] = { 19, "limb", 3, 20 }, [3] = { 20, "limb", 4, 21 }, [4] = { 21, "leaf" },  -- tail
      -- feet: not turned with the thigh, so they stay flat on the ground
      [5] = { 23, "limb", 6, 24, true }, [6] = { 24, "leaf" }, [7] = { 24, "follow" }, [8] = { 25, "core" }, -- right leg
      [9] = { 27, "limb", 10, 28, true }, [10] = { 28, "leaf" }, [11] = { 28, "follow" }, [12] = { 29, "core" }, -- left leg
    },
  },
  -- --- the Veemon line (DW2003) and the Veedramon line (DW2) ----------------------
  {
    type = 183, name = "Veemon", file = "VMON", level = 3, height = 260,
    attribute = 2, -- Vaccine
    -- Gabumon's techniques; its finisher (99 Blue Blaster's stats) as
    -- V-Headbutt with Buster Dive's effect (0x2F), placed in front of it
    -- (bone 0, as that effect's own users: 100 up, 550 forward, where the foe
    -- stands). No Digimon with Gabumon's skeleton has Buster Dive's dive, so
    -- it plays Gabumon's Megaton Punch (0x2E, `anim`) with the dive's travel
    -- added (`lunge`: the whole Digimon moves 450 forward over frames 4..10,
    -- the punch, as MetalGreymon's Buster Dive moves it ~630).
    finisher = { name = "V-Headbutt", from = 99, anim = 0x2E, lunge = { frame = 4, frames = 6, distance = 450 },
      effect = 0x2F, origin = { 0, 0, -100, -550 } },
    gains = { 800, 500, 100, 70, 80, 50 },
    -- Becoming it: a Tsunomon (16) whose highest stat is Offense or Brains, at
    -- weight 20 +- 5, any care mistakes (Elecmon, before it, wants HP, Offense
    -- or Speed at weight 15).
    requirements = { digimon = 16, hp = -1, mp = -1, offense = 1, defense = -1, speed = -1, brain = 1,
      care = 0, weight = 20, discipline = -1, happiness = -1, battles = -1, techs = -1, flags = 0 },
    evolves_from = { 16 }, -- Tsunomon
    evolutions = { 185, 184, 10 }, -- Veedramon, ExVeemon, Seadramon
    source = { ["SLES-03936"] = { file = 526, bones = 44, motions = 0 } }, -- M145VMON (fighter 0x91)
    donor = 17, donor_file = "GABU.MMD", -- Gabumon (Agumon's skeleton)
    mapping = {
      -- hybrid (as WarGrowlmon): arms keep their own stance; thighs turned to the
      -- donor's keeping their roll, so its walk swings them the right way; shins
      -- keep their bend to the thigh; feet flat
      [13] = { 2, "core" }, [20] = { 3, "core" }, [21] = { 4, "core" },                          -- chest, head, jaw
      [14] = { 6, "core" }, [15] = { 7, "core" }, [16] = { 8, "core" },          -- right arm
      [17] = { 10, "core" }, [18] = { 11, "core" }, [19] = { 12, "core" },     -- left arm
      [1] = { 13, "core" }, [2] = { 13, "follow" }, [3] = { 13, "follow" }, [4] = { 13, "follow" }, -- pelvis, tail -> hips
      [5] = { 15, "limb", 6, 16, true }, [6] = { 16, "leaf" }, [7] = { 16, "follow" }, [8] = { 17, "core" },     -- right leg
      [9] = { 19, "limb", 10, 20, true }, [10] = { 20, "leaf" }, [11] = { 20, "follow" }, [12] = { 21, "core" }, -- left leg
    },
  },
  {
    type = 184, name = "ExVeemon", file = "EXVM", level = 4, height = 420,
    attribute = 2,
    -- Leomon's techniques; its finisher (91 Fist of the Beast King) as V-Laser
    -- with Howling Blaster's effect (0x40) from the chest (bone 0: 290 up,
    -- 70 forward)
    finisher = { name = "V-Laser", from = 91, effect = 0x40, origin = { 0, 0, -290, -70 } },
    gains = { 1500, 1500, 250, 150, 200, 200 },
    -- Offense and Speed 100, at most 3 care mistakes (flags 0x10), weight 25,
    -- 10 battles, 30 techniques
    requirements = { digimon = -1, hp = -1, mp = -1, offense = 100, defense = -1, speed = 100, brain = -1,
      care = 3, weight = 25, discipline = -1, happiness = -1, battles = 10, techs = 30, flags = 0x10 },
    evolves_from = { 183 }, -- Veemon
    evolutions = { 186, 187, 13 }, -- Paildramon, AeroVeedramon, Mamemon
    source = { ["SLES-03936"] = { file = 575, bones = 54, motions = 0 } }, -- M259EXVM (fighter 0x103)
    donor = 48, donor_file = "LEOM.MMD", -- Leomon (a tail, 4-bone legs)
    mapping = {
      [13] = { 2, "core" }, [20] = { 2, "follow" }, [21] = { 2, "follow" }, [25] = { 2, "follow" }, [26] = { 2, "follow" }, -- chest, wings
      [17] = { 3, "core" }, [18] = { 3, "follow" }, [19] = { 4, "core" },                        -- neck + head, jaw
      -- arms and legs keep ExVeemon's own wide stance (turned onto Leomon's
      -- straight column legs and close arms, it looked squashed)
      [14] = { 5, "core" }, [15] = { 6, "core" }, [16] = { 7, "core" },                         -- right arm
      [22] = { 8, "core" }, [23] = { 9, "core" }, [24] = { 10, "core" },                        -- left arm
      [1] = { 11, "core" },                                                                     -- pelvis -> hips
      [10] = { 12, "limb", 11, 13 }, [11] = { 13, "limb", 12, 14 }, [12] = { 14, "leaf" },      -- tail
      [2] = { 15, "core" }, [3] = { 16, "core" }, [4] = { 17, "core" }, [5] = { 18, "core" },  -- right leg
      [6] = { 19, "core" }, [7] = { 20, "core" }, [8] = { 21, "core" }, [9] = { 22, "core" },  -- left leg
    },
  },
  {
    type = 185, name = "Veedramon", file = "VDRA", level = 4, height = 400, game = "dw2",
    attribute = 2,
    -- Greymon's techniques; its finisher (63 Mega Flame) as V-Nova Blast with
    -- Howling Blaster's effect (0x40) from the mouth (Greymon's jaw, bone 5,
    -- where Mega Flame starts)
    finisher = { name = "V-Nova Blast", from = 63, effect = 0x40, origin = { 5, 40, -30, 0 } },
    gains = { 2000, 1500, 200, 200, 200, 200 },
    -- Offense and Defense 100, Brains 80, at most 3 care mistakes, weight 30,
    -- discipline 70, 30 techniques
    requirements = { digimon = -1, hp = -1, mp = -1, offense = 100, defense = 100, speed = -1, brain = 80,
      care = 3, weight = 30, discipline = 70, happiness = -1, battles = -1, techs = 30, flags = 0x10 },
    evolves_from = { 183 }, -- Veemon
    evolutions = { 12, 187 }, -- MetalGreymon, AeroVeedramon
    icon_head = { 4, 5 },     -- Greymon's head and jaw
    source = { ["SLUS-01193"] = { model = 135, anim = 26 } }, -- DW2 Digimon 128 (its first animation file)
    donor = 5, donor_file = "GREY.MMD", -- Greymon
    mapping = {
      -- hybrid (as WarGrowlmon): arms keep their own stance; thighs turned to the
      -- donor's keeping their roll, so its walk swings them the right way; shins
      -- keep their bend to the thigh; feet flat
      [1] = { 2, "core" }, [2] = { 3, "core" }, [3] = { 4, "core" }, [4] = { 5, "core" },       -- chest, neck, head, jaw
      [5] = { 7, "core" }, [6] = { 8, "core" }, [7] = { 9, "core" },                -- right arm
      [8] = { 11, "core" }, [9] = { 12, "core" }, [10] = { 13, "core" },         -- left arm
      [11] = { 14, "core" },                                                                    -- pelvis
      [12] = { 15, "limb", 13, 16 }, [13] = { 16, "limb", 14, 17 }, [14] = { 17, "leaf" },      -- tail
      [15] = { 19, "limb", 16, 20, true }, [16] = { 20, "leaf" }, [17] = { 21, "core" },      -- right leg
      [18] = { 23, "limb", 19, 24, true }, [19] = { 24, "leaf" }, [20] = { 25, "core" },      -- left leg
    },
  },
  {
    type = 186, name = "Paildramon", file = "PLDR", level = 5, height = 470,
    attribute = 2,
    -- Andromon's techniques; its finisher (102 Spiral Sword) as Death Parade
    -- Blaster with Giga Scissor Claw's effect (0x4F), set up as for
    -- MetalGreymon (bone 0, no offset)
    finisher = { name = "Death Parade Blaster", from = 102, effect = 0x4F, origin = { 0, 0, 0, 0 } },
    gains = { 4500, 5000, 500, 450, 550, 500 },
    -- HP 300, MP 200, Offense 400, Defense 300, Speed 400, Brains 300, at most
    -- 8 care mistakes, weight 50, discipline 90, 30 battles, 35 techniques
    requirements = { digimon = -1, hp = 300, mp = 200, offense = 400, defense = 300, speed = 400, brain = 300,
      care = 8, weight = 50, discipline = 90, happiness = -1, battles = 30, techs = 35, flags = 0x10 },
    evolves_from = { 184, 19, 7 }, -- ExVeemon, Kabuterimon, Airdramon
    icon_head = { 3 },      -- Andromon has no jaw
    source = { ["SLES-03936"] = { file = 601, bones = 54, motions = 0 } }, -- M254PLDR (fighter 0xFE)
    donor = 40, donor_file = "ANDR.MMD", -- Andromon (no tail or jaw)
    -- 948 polygons: slimmed to fit next to Andromon's animations. Its hip
    -- cannons (13, 15) ride the hips; 14 and 16 are folded to a point at rest
    -- (hidden) and left out.
    mapping = {
      -- hybrid (as WarGrowlmon): arms keep their own stance; thighs turned to the
      -- donor's keeping their roll, so its walk swings them the right way; shins
      -- keep their bend to the thigh; feet flat
      [17] = { 2, "core" }, [25] = { 2, "follow" }, [26] = { 2, "follow" }, [27] = { 2, "follow" }, [28] = { 2, "follow" }, -- chest, wings
      [21] = { 3, "core" },                                                                     -- head
      [18] = { 5, "core" }, [19] = { 6, "core" }, [20] = { 7, "core" },          -- right arm
      [22] = { 9, "core" }, [23] = { 10, "core" }, [24] = { 11, "core" },      -- left arm
      [1] = { 12, "core" }, [10] = { 12, "follow" }, [11] = { 12, "follow" }, [12] = { 12, "follow" }, [13] = { 12, "follow" }, [15] = { 12, "follow" }, -- hips, tail, cannons
      [2] = { 14, "limb", 3, 15, true }, [3] = { 15, "leaf" }, [4] = { 15, "follow" }, [5] = { 16, "core" },      -- right leg
      [6] = { 18, "limb", 7, 19, true }, [7] = { 19, "leaf" }, [8] = { 19, "follow" }, [9] = { 20, "core" },      -- left leg
    },
  },
  {
    type = 187, name = "AeroVeedramon", file = "AVDR", level = 5, height = 470, game = "dw2",
    attribute = 2,
    -- MetalGreymon's techniques; its finisher (79 Giga Scissor Claw) as Dragon
    -- Impulse with Crimson Flare's effect (0x6D), whose four start points
    -- (Phoenixmon's wings and feet) are its wings (torso, bone 2) and hands
    -- (bones 9, 13): the centres of those parts at rest, in bone space.
    finisher = { name = "Dragon Impulse", from = 79, effect = 0x6D,
      origin = { { 2, 89, 236, -192 }, { 2, 89, 236, 192 }, { 9, 54, 1, 8 }, { 13, 37, -38, -12 } } },
    gains = { 5000, 5000, 500, 500, 500, 500 },
    -- HP 400, MP 300, Offense 500, Defense 400, Speed 400, Brains 300, at most
    -- 10 care mistakes, weight 60, discipline 90, 30 battles, 30 techniques
    requirements = { digimon = -1, hp = 400, mp = 300, offense = 500, defense = 400, speed = 400, brain = 300,
      care = 10, weight = 60, discipline = 90, happiness = -1, battles = 30, techs = 30, flags = 0x10 },
    evolves_from = { 185, 184, 5, 7, 8 }, -- Veedramon, ExVeemon, Greymon, Airdramon, Tyrannomon
    icon_head = { 4, 5 },   -- MetalGreymon's head and jaw
    source = { ["SLUS-01193"] = { model = 114, anim = 27 } }, -- DW2 Digimon 180
    donor = 12, donor_file = "MTGR.MMD", -- MetalGreymon (as WarGrowlmon: arms keep their own stance, feet flat)
    mapping = {
      [1] = { 2, "core" }, [8] = { 2, "follow" }, [9] = { 2, "follow" },                         -- chest, wings
      [2] = { 3, "core" }, [3] = { 4, "core" }, [4] = { 5, "core" },                             -- neck, head, jaw
      [5] = { 7, "core" }, [6] = { 8, "core" }, [7] = { 9, "core" },                             -- right arm
      [10] = { 11, "core" }, [11] = { 12, "core" }, [12] = { 13, "core" },                       -- left arm
      [13] = { 18, "core" },                                                                     -- pelvis -> hips
      [20] = { 19, "limb", 21, 20 }, [21] = { 20, "limb", 22, 21 }, [22] = { 21, "leaf" },       -- tail
      [17] = { 23, "limb", 18, 24, true }, [18] = { 24, "leaf" }, [19] = { 25, "core" },         -- right leg
      [14] = { 27, "limb", 15, 28, true }, [15] = { 28, "leaf" }, [16] = { 29, "core" },         -- left leg
    },
  },
  -- --- the Kabuterimon and Birdramon lines --------------------------------------------
  {
    -- Digimon World's own Tentomon (type 111, an NPC: its model has no eating,
    -- sleeping or training motions) on Kabuterimon's skeleton (the same
    -- four-armed beetle rig), at its own size (`model_height`: the mesh's
    -- height at rest, antennae included; `height` is DIGIMON_DATA's, as the NPC's).
    type = 188, name = "Tentomon", file = "TNTO", level = 3, height = 220, model_height = 277, game = "dw1",
    attribute = 1, specialties = { 3, 255, 255 }, radius = 140, -- Data; Earth (as the NPC)
    -- Kabuterimon's techniques; its finisher (93 Electro Shocker: animation,
    -- effect) as Super Shocker at a Rookie's power (Kunemon's Electric
    -- Thread is 94, Electro Shocker 170). Electro Shocker gathers in front
    -- (bone 0: 200 up, 340 forward for Kabuterimon) from the four hands
    -- (Kabuterimon's hand bones 7, 13, 10, 16 stay empty here): Tentomon's
    -- in front of its claws, then its four claw tips (bones 6, 12, 9, 15, in
    -- bone space), in that order.
    finisher = { name = "Super Shocker", from = 93, power = 95,
      origin = { { 0, 0, -80, -220 }, { 6, 30, 64, -20 }, { 12, 98, -36, 119 }, { 9, 26, 54, 43 }, { 15, 98, -36, -119 } } },
    gains = { 800, 700, 100, 60, 50, 50 },
    -- A Tanemon (44) whose highest stat is Offense, at weight 20 +- 5 (Palmon
    -- and Betamon, before it, want MP/Speed/Brains or HP/MP/Defense at 15).
    requirements = { digimon = 44, hp = -1, mp = -1, offense = 1, defense = -1, speed = -1, brain = -1,
      care = 0, weight = 20, discipline = -1, happiness = -1, battles = -1, techs = -1, flags = 0 },
    evolves_from = { 44 },     -- Tanemon
    evolutions = { 19, 51 },   -- Kabuterimon, Kuwagamon
    -- A Rookie's care (meals, sleep, weight, food, training, Digimon page
    -- camera) from Kunemon (32), not Kabuterimon's
    raise_from = 32,
    icon_head = { 3 },         -- Kabuterimon's head bone
    source = { ["SLUS-01032"] = { type = 111, file = "TENT.MMD" } },
    donor = 19, donor_file = "KABU.MMD", -- Kabuterimon
    -- DW1 bone -> Kabuterimon bone: shell and body on its body (its walk
    -- nods the head bone hard: on it, the shell rocked), the head on its
    -- head; 2-bone arms and legs on its 3-bone ones (hands, pelvis, wings
    -- and feet bones stay empty)
    mapping = {
      [1] = { 2, "core" }, [2] = { 2, "follow" }, [3] = { 2, "follow" }, [4] = { 2, "follow" }, [5] = { 2, "follow" }, [6] = { 2, "follow" }, [7] = { 2, "follow" }, -- shell, body
      [8] = { 3, "core" }, [9] = { 3, "follow" }, [10] = { 3, "follow" },                         -- head, mandibles
      [11] = { 3, "follow" }, [12] = { 3, "follow" }, [13] = { 3, "follow" }, [14] = { 3, "follow" }, -- antennae
      [15] = { 11, "core" }, [16] = { 12, "core" }, [17] = { 14, "core" }, [18] = { 15, "core" }, -- upper arms (claws forward)
      [19] = { 5, "core" }, [20] = { 6, "core" }, [21] = { 8, "core" }, [22] = { 9, "core" },      -- lower arms
      [23] = { 22, "limb", 24, 23, true }, [24] = { 23, "core" },                                 -- right leg (+x): thigh, foot
      [25] = { 25, "limb", 26, 26, true }, [26] = { 26, "core" },                                 -- left leg
    },
  },
  {
    type = 189, name = "MegaKabuterimon", file = "MKAB", level = 5, height = 460, game = "dw2",
    attribute = 2, specialties = { 3, 1, 255 }, radius = 280, -- Vaccine; Earth, Battle
    -- HerculesKabuterimon's techniques; its finisher (93 Electro Shocker) as
    -- Horn Buster at an Ultimate's power
    finisher = { name = "Horn Buster", from = 93, power = 225 },
    gains = { 5000, 4000, 500, 600, 400, 400 },
    -- HP 500, Offense 400, Defense 500, Speed 300, at most 5 care mistakes,
    -- weight 55, 30 battles, 35 techniques (Okuwamon: Offense and Speed)
    requirements = { digimon = -1, hp = 500, mp = -1, offense = 400, defense = 500, speed = 300, brain = -1,
      care = 5, weight = 55, discipline = -1, happiness = -1, battles = 30, techs = 35, flags = 0x10 },
    evolves_from = { 19, 51 },  -- Kabuterimon, Kuwagamon
    evolutions = { 60 },        -- HerculesKabuterimon (a Mega)
    icon_head = { 3, 4 },
    source = { ["SLUS-01193"] = { model = 115, anim = 28 } }, -- DW2 Digimon 181
    donor = 60, donor_file = "HKAB.MMD", -- HerculesKabuterimon (its wing bones stay empty)
    mapping = {
      [8] = { 2, "core" },                                                                       -- body
      [21] = { 3, "core" }, [22] = { 4, "core" },                                                -- head, horn
      [12] = { 9, "core" }, [13] = { 10, "core" }, [14] = { 11, "core" },                        -- upper arm (+x)
      [9] = { 12, "core" }, [10] = { 13, "core" }, [11] = { 14, "core" },                        -- upper arm (-x)
      [18] = { 5, "core" }, [19] = { 6, "core" }, [20] = { 6, "follow" },                        -- lower arm (+x)
      [15] = { 7, "core" }, [16] = { 8, "core" }, [17] = { 8, "follow" },                        -- lower arm (-x)
      [1] = { 19, "core" },                                                                      -- hips
      [2] = { 20, "limb", 3, 21, true }, [3] = { 21, "leaf" }, [4] = { 22, "core" },             -- leg (+x)
      [5] = { 23, "limb", 6, 24, true }, [6] = { 24, "leaf" }, [7] = { 25, "core" },             -- leg (-x)
    },
  },
  {
    type = 190, name = "Okuwamon", file = "OKWA", level = 5, height = 430,
    attribute = 3, specialties = { 3, 1, 2 }, radius = 280, -- Virus; Earth, Battle, Air
    -- Centarumon's skeleton and motions (four legs and two arms, like it) with
    -- HerculesKabuterimon's techniques (`techniques`): each plays one of
    -- Centarumon's technique motions (`motions`: HerculesKabuterimon's slot k
    -- -> Centarumon's slot, a list from slot 0: Prominence Beam and Red
    -- Inferno on their own, Megaton Punch, Buster Dive and the claws on Dynamite
    -- Kick and Counter, Green Trap on Magma Bomb, the powders from the mouth on
    -- Spit Fire and Fire Tower, Bug on Heat Laser, Charm Perfume on Meltdown,
    -- Mass Morph and Muscle Charge on Muscle Charge). Where an effect starts
    -- from HerculesKabuterimon's bones and doesn't list Centarumon, its start
    -- point moves to the matching part (`bones`: its bone -> {bone, x, y, z},
    -- the part's place in bone space at rest; lib/limits.lua: borrow).
    techniques = { from = 60, motions = { 3, 5, 7, 8, 7, 9, 8, 7, 2, 0, 4, 6, 1, 9, 8 },
      bones = { [2] = { 3, 66, -1, 72 }, [3] = { 4, -41, 1, -230 }, [4] = { 4, -41, 1, -230 },
        [6] = { 7, 92, -51, -130 }, [11] = { 7, 92, -51, -130 }, [8] = { 9, 142, 0, -296 }, [14] = { 9, 142, 0, -296 } } },
    -- Its finisher as Double Scissor Claw: Electro Shocker's stats at an
    -- Ultimate's power, Counter's strike with a dash (`lunge`: 450 forward over
    -- frames 4..11; Counter's root keys move nothing, so the dash isn't
    -- overridden) and Kuwagamon's Scissor Claw (0x64) striking where Kuwagamon's
    -- does (bone 0, 140 up, 425 forward)
    finisher = { name = "Double Scissor Claw", from = 93, power = 230, lunge = { frame = 4, frames = 7, distance = 450 },
      effect = 0x64, origin = { 0, 0, -140, -425 } },
    gains = { 4500, 4500, 600, 400, 600, 400 },
    -- HP 400, MP 300, Offense 500, Defense 300, Speed 500, at most 10 care
    -- mistakes, weight 45, 30 battles, 30 techniques
    requirements = { digimon = -1, hp = 400, mp = 300, offense = 500, defense = 300, speed = 500, brain = -1,
      care = 10, weight = 45, discipline = -1, happiness = -1, battles = 30, techs = 30, flags = 0x10 },
    evolves_from = { 19, 51 },  -- Kabuterimon, Kuwagamon
    evolutions = { 60 },        -- HerculesKabuterimon (a Mega)
    raise_from = 60,            -- an Ultimate's care (Centarumon is a Champion)
    icon_head = { 4 },
    source = { ["SLES-03936"] = { file = 832, bones = 58, motions = 0 } }, -- M226OKWA (enemy fighter 0xE2)
    donor = 36, donor_file = "CENT.MMD", -- Centarumon
    -- abdomen on the horse body (the front legs' parent), chest on the human
    -- torso; legs and arms keep Okuwamon's own stance (turned to Centarumon's
    -- narrow legs, its splayed legs became one column)
    mapping = {
      [1] = { 2, "core" },                                                                       -- abdomen
      [14] = { 3, "core" }, [21] = { 3, "follow" }, [22] = { 3, "follow" }, [27] = { 3, "follow" }, [28] = { 3, "follow" }, -- chest, wings
      [23] = { 4, "core" }, [24] = { 4, "follow" }, [25] = { 4, "follow" }, [26] = { 4, "follow" }, -- head, mouth, pincers
      [15] = { 5, "core" }, [16] = { 6, "core" }, [17] = { 7, "core" },                          -- arm (+x)
      [18] = { 8, "core" }, [19] = { 9, "core" }, [20] = { 9, "follow" },                        -- arm (-x; Centarumon's has 2 bones)
      [11] = { 10, "core" }, [12] = { 11, "core" }, [13] = { 12, "core" },                       -- front leg (+x)
      [2] = { 13, "core" }, [3] = { 14, "core" }, [4] = { 15, "core" },                          -- front leg (-x)
      [8] = { 19, "core" }, [9] = { 20, "core" }, [10] = { 22, "core" },                         -- back leg (+x; 4 bones there)
      [5] = { 23, "core" }, [6] = { 24, "core" }, [7] = { 26, "core" },                          -- back leg (-x)
    },
  },
  {
    type = 191, name = "Garudamon", file = "GRDA", level = 5, height = 470, game = "dw2",
    attribute = 2, specialties = { 0, 2, 1 }, radius = 260, -- Vaccine; Fire, Air, Battle
    -- Andromon's techniques; its finisher (102 Spiral Sword: stats, motion) as
    -- Wing Blade with Birdramon's Meteor Wing (0x5E), whose four start points
    -- (Birdramon's wings) are its wing tips (on the chest, bone 2) and hands
    -- (7, 11): those parts' centres at rest, in bone space
    finisher = { name = "Wing Blade", from = 102, effect = 0x5E,
      origin = { { 2, 134, -65, -216 }, { 2, 164, -6, 183 }, { 7, -25, -31, -6 }, { 11, 2, -40, 1 } } },
    gains = { 5000, 5000, 500, 450, 550, 500 },
    -- HP 400, MP 300, Offense 400, Defense 300, Speed 400, Brains 300, at most
    -- 5 care mistakes, weight 40, discipline 90, 35 techniques
    requirements = { digimon = -1, hp = 400, mp = 300, offense = 400, defense = 300, speed = 400, brain = 300,
      care = 5, weight = 40, discipline = 90, happiness = -1, battles = -1, techs = 35, flags = 0x10 },
    evolves_from = { 21, 20, 50 }, -- Birdramon, Angemon, Kokatorimon
    evolutions = { 59 },           -- Phoenixmon (a Mega)
    icon_head = { 3 },             -- Andromon has no jaw
    source = { ["SLUS-01193"] = { model = 226, anim = 225 } }, -- DW2 Digimon 187
    donor = 40, donor_file = "ANDR.MMD", -- Andromon (as Paildramon)
    mapping = {
      [1] = { 2, "core" }, [2] = { 2, "follow" }, [3] = { 2, "follow" }, [13] = { 2, "follow" }, [14] = { 2, "follow" }, -- chest, wings
      [4] = { 3, "core" }, [5] = { 3, "follow" }, [6] = { 3, "follow" }, [7] = { 3, "follow" }, [8] = { 3, "follow" }, [9] = { 3, "follow" }, -- head
      [15] = { 5, "core" }, [16] = { 6, "core" }, [17] = { 7, "core" },                          -- arm (+x)
      [10] = { 9, "core" }, [11] = { 10, "core" }, [12] = { 11, "core" },                        -- arm (-x)
      [18] = { 12, "core" }, [23] = { 12, "follow" },                                            -- hips, tail feathers
      [19] = { 14, "limb", 20, 15, true }, [20] = { 15, "leaf" }, [21] = { 15, "follow" }, [22] = { 16, "core" }, -- leg (+x)
      [24] = { 18, "limb", 25, 19, true }, [25] = { 19, "leaf" }, [26] = { 19, "follow" }, [27] = { 20, "core" }, -- leg (-x)
    },
  },
}

-- The game's own Digimon that change: HerculesKabuterimon and Phoenixmon become
-- Megas (the chart's sixth section; DIGIMON_DATA keeps level 5, which so much
-- of the game reads that a level 6 isn't safe). Each is taken off every other
-- Digimon's targets (Kabuterimon, Kuwagamon, Shellmon; Birdramon, Angemon,
-- Airdramon, Kokatorimon, Unimon), comes from `evolves_from` only, has no
-- targets (Phoenixmon's sixth slot holds a stray 0), and gets Mega
-- requirements and gains. An Ultimate becomes a Mega like a Champion becomes
-- an Ultimate (lib/evolution.lua: M.MEGA_HOURS).
M.changes = {
  {
    type = 60, name = "HerculesKabuterimon", chart_stage = 6,
    evolves_from = { 189, 190 }, -- MegaKabuterimon, Okuwamon
    -- HP 700, MP 400, Offense 600, Defense 700, Speed 500, at most 5 care
    -- mistakes, weight 60, 50 battles, 45 techniques
    requirements = { digimon = -1, hp = 700, mp = 400, offense = 600, defense = 700, speed = 500, brain = -1,
      care = 5, weight = 60, discipline = -1, happiness = -1, battles = 50, techs = 45, flags = 0x10 },
    gains = { 7000, 6000, 700, 800, 600, 500 },
  },
  {
    type = 59, name = "Phoenixmon", chart_stage = 6,
    evolves_from = { 191, 55 }, -- Garudamon, Piximon
    -- HP 600, MP 700, Offense 500, Defense 500, Speed 700, Brains 700, at most
    -- 3 care mistakes, weight 35, discipline 100, 45 techniques
    requirements = { digimon = -1, hp = 600, mp = 700, offense = 500, defense = 500, speed = 700, brain = 700,
      care = 3, weight = 35, discipline = 100, happiness = -1, battles = -1, techs = 45, flags = 0x10 },
    gains = { 7000, 8000, 600, 500, 800, 800 },
  },
}

return M
