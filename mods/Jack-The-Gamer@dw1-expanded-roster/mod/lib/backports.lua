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
    attribute = 3, specialties = { 0, 1, 255 }, radius = 140,
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from Fire from Agumon's mouth (its jaw 4), the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true, points = { [0] = { 4, 4, 34, 0 } } },
    -- Techniques: Agumon's; its finisher (59 Pepper Breath, a fireball, on
    -- Agumon's animation) becomes Guilmon's own Pyro Sphere with the same
    -- stats (lib/tables.lua: new finishers from 0x71).
    finisher = { name = "Pyro Sphere", from = 59 },
    -- Stats gained on evolving into it {HP, MP, Off, Def, Speed, Brains}.
    gains = { 900, 450, 110, 40, 70, 40 },
    -- Becoming it (EvoRequirements): a Koromon (2) whose highest stat is
    -- Offense or Speed (1 = "this one is highest", -1 = don't care) at
    -- weight 25 +- 5, any care mistakes. Agumon and Biyomon (also from
    -- Koromon, lib/tree.lua) want weight 15 +- 5; ties keep the earlier of
    -- Koromon's evolutions.
    requirements = { digimon = 2, hp = -1, mp = -1, offense = 1, defense = -1, speed = 1, brain = -1,
      care = 0, weight = 25, discipline = -1, happiness = -1, battles = -1, techs = -1, flags = 0 },
    -- Its chart icon (lib/icon.lua): the head (DW1 bones 3, 4) at its own
    -- size, so both ears show as two points, and the first frame's head
    -- taken from the second frame (it reads better there).
    icon_head = { 3, 4 }, icon_head_scale = 1.0, icon_head_from_second = true,
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
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Greymon's gains (Agumon's Champion line)
    gains = { 2000, 1500, 200, 200, 200, 200 },
    -- Its finisher (63 Mega Flame) as Exhaust Flame
    finisher = { name = "Exhaust Flame", from = 63 },
    -- Becoming it (a Champion: every stat it names, then care/weight/...):
    -- Offense and Speed 100, at most 3 care mistakes (flags 0x10: "care" is
    -- a maximum), weight 30 +- 5, 30 techniques. Looser on care and
    -- discipline than Greymon (100 in all four stats, 1 mistake, discipline
    -- 90), which Guilmon can also become.
    requirements = { digimon = -1, hp = -1, mp = -1, offense = 100, defense = -1, speed = 100, brain = -1,
      care = 3, weight = 30, discipline = -1, happiness = -1, battles = -1, techs = 30, flags = 0x10 },
    icon_head = { 4, 5 }, -- Greymon's head and jaw
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
    attribute = 3, specialties = { 0, 1, 5 }, radius = 280, -- Virus; Fire, Battle, Mech
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from Fire from its chest (Atomic Blaster's), the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true, points = { [0] = { 2, 95, -15, 0 } } },
    -- MetalGreymon's gains
    gains = { 5000, 5000, 500, 500, 500, 500 },
    -- Becoming it (Ultimate; as MetalGreymon's, with Offense and Speed
    -- first): HP 400, MP 300, Off 500, Def 300, Speed 500, Brains 300, at
    -- most 10 care mistakes (flags 0x10), weight 65, discipline 80, 30
    -- battles, 30 techniques.
    requirements = { digimon = -1, hp = 400, mp = 300, offense = 500, defense = 300, speed = 500, brain = 300,
      care = 10, weight = 65, discipline = 80, happiness = -1, battles = 30, techs = 30, flags = 0x10 },
    -- Its finisher (79 Giga Scissor Claw: stats
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
    attribute = 2, specialties = { 1, 255, 255 }, -- Vaccine; Battle
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (Gabumon's 99 Blue Blaster's stats) as V-Headbutt: a real
    -- Buster Dive, Tyrannomon's (TYRA.MMD animation 0x34: it crouches and
    -- dives head first about 400 forward), retargeted onto Gabumon's skeleton
    -- (`motion.file`: another Digimon's motion; `from` its bone for each of
    -- Gabumon's: chest, head, jaw, arms and legs, its tail and fingers left
    -- out; the dive's travel kept, `travel`), with Buster Dive's effect (0x2F)
    -- where the foe stands (bone 0, 100 up, 550 forward).
    finisher = { name = "V-Headbutt", from = 99, effect = 0x2F, origin = { 0, 0, -100, -550 },
      motion = { file = "TYRA.MMD", type = 8, anim = 0x34, travel = 1,
        from = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [6] = 5, [7] = 6, [8] = 7, [10] = 11, [11] = 12, [12] = 13,
          [13] = 17, [15] = 21, [16] = 22, [17] = 23, [19] = 24, [20] = 25, [21] = 26 } } },
    gains = { 800, 500, 100, 70, 80, 50 },
    -- Becoming it: a Tsunomon (16) whose highest stat is Offense or Brains, at
    -- weight 20 +- 5, any care mistakes (Elecmon, before it, wants HP, Offense
    -- or Speed at weight 15).
    requirements = { digimon = 16, hp = -1, mp = -1, offense = 1, defense = -1, speed = -1, brain = 1,
      care = 0, weight = 20, discipline = -1, happiness = -1, battles = -1, techs = -1, flags = 0 },
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
    attribute = 2, specialties = { 1, 2, 255 }, -- Battle, Air
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (91 Fist of the Beast King) as V-Laser
    -- with Howling Blaster's effect (0x40) from the chest (bone 0: 290 up,
    -- 70 forward)
    finisher = { name = "V-Laser", from = 91, effect = 0x40, origin = { 0, 0, -290, -70 } },
    gains = { 1500, 1500, 250, 150, 200, 200 },
    -- Offense and Speed 100, at most 3 care mistakes (flags 0x10), weight 25,
    -- 10 battles, 30 techniques
    requirements = { digimon = -1, hp = -1, mp = -1, offense = 100, defense = -1, speed = 100, brain = -1,
      care = 3, weight = 25, discipline = -1, happiness = -1, battles = 10, techs = 30, flags = 0x10 },
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
    attribute = 2, specialties = { 0, 1, 255 }, -- Fire, Battle
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (63 Mega Flame) as V-Nova Blast with
    -- Howling Blaster's effect (0x40) from the mouth (Greymon's jaw, bone 5,
    -- where Mega Flame starts)
    finisher = { name = "V-Nova Blast", from = 63, effect = 0x40, origin = { 5, 40, -30, 0 } },
    gains = { 2000, 1500, 200, 200, 200, 200 },
    -- Offense and Defense 100, Brains 80, at most 3 care mistakes, weight 30,
    -- discipline 70, 30 techniques
    requirements = { digimon = -1, hp = -1, mp = -1, offense = 100, defense = 100, speed = -1, brain = 80,
      care = 3, weight = 30, discipline = 70, happiness = -1, battles = -1, techs = 30, flags = 0x10 },
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
    attribute = 2, specialties = { 1, 5, 255 }, -- Battle, Mech
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (102 Spiral Sword) as Death Parade
    -- Blaster with Giga Scissor Claw's effect (0x4F), set up as for
    -- MetalGreymon (bone 0, no offset)
    finisher = { name = "Death Parade Blaster", from = 102, effect = 0x4F, origin = { 0, 0, 0, 0 } },
    gains = { 4500, 5000, 500, 450, 550, 500 },
    -- HP 300, MP 200, Offense 400, Defense 300, Speed 400, Brains 300, at most
    -- 8 care mistakes, weight 50, discipline 90, 30 battles, 35 techniques
    requirements = { digimon = -1, hp = 300, mp = 200, offense = 400, defense = 300, speed = 400, brain = 300,
      care = 8, weight = 50, discipline = 90, happiness = -1, battles = 30, techs = 35, flags = 0x10 },
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
    attribute = 2, specialties = { 1, 2, 0 }, -- Battle, Air, Fire
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (79 Giga Scissor Claw) as Dragon
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
    attribute = 1, specialties = { 2, 1, 255 }, radius = 140, -- Data; Air, Battle
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (93 Electro Shocker: animation,
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
    attribute = 2, specialties = { 2, 1, 255 }, radius = 280, -- Vaccine; Air, Battle
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (93 Electro Shocker) as
    -- Horn Buster at an Ultimate's power
    finisher = { name = "Horn Buster", from = 93, power = 225 },
    gains = { 5000, 4000, 500, 600, 400, 400 },
    -- HP 500, Offense 400, Defense 500, Speed 300, at most 5 care mistakes,
    -- weight 55, 30 battles, 35 techniques (Okuwamon: Offense and Speed)
    requirements = { digimon = -1, hp = 500, mp = -1, offense = 400, defense = 500, speed = 300, brain = -1,
      care = 5, weight = 55, discipline = -1, happiness = -1, battles = 30, techs = 35, flags = 0x10 },
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
    attribute = 3, specialties = { 1, 2, 255 }, radius = 280, -- Virus; Battle, Air
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Centarumon's skeleton and motions (four legs and two arms, like it).
    -- Its finisher (in place of Centarumon's 0x56 Solar Ray) as Double Scissor
    -- Claw: HerculesKabuterimon's Electro Shocker's stats (93) at an
    -- Ultimate's power, playing Kuwagamon's own Scissor Claw (KUWA.MMD
    -- animation 0x38: it rears back and lunges ~400 forward, head and pincers
    -- first, at frames 14..20) retargeted onto Centarumon's skeleton
    -- (`motion.file`; `from`: Centarumon's bone <- Kuwagamon's: horse body and
    -- hind body <- abdomen 23, torso <- upper body 2, head (Okuwamon's head and
    -- pincers) <- head 3, arms <- its first arms 7-9 / 10-11, front legs <- its
    -- legs 24-26 / 27-29; the hind legs keep their rest; its travel kept), and
    -- Kuwagamon's Scissor Claw effect (0x64) striking where Kuwagamon's does
    -- (bone 0, 140 up, 425 forward)
    finisher = { name = "Double Scissor Claw", from = 0x56, stats = 93, power = 230, effect = 0x64, origin = { 0, 0, -140, -425 },
      motion = { file = "KUWA.MMD", type = 51, anim = 0x38, travel = 1,
        from = { [1] = 1, [2] = 23, [16] = 23, [3] = 2, [4] = 3, [5] = 7, [6] = 8, [7] = 9, [8] = 10, [9] = 11,
          [10] = 24, [11] = 25, [12] = 26, [13] = 27, [14] = 28, [15] = 29 } } },
    gains = { 4500, 4500, 600, 400, 600, 400 },
    -- HP 400, MP 300, Offense 500, Defense 300, Speed 500, at most 10 care
    -- mistakes, weight 45, 30 battles, 30 techniques
    requirements = { digimon = -1, hp = 400, mp = 300, offense = 500, defense = 300, speed = 500, brain = -1,
      care = 10, weight = 45, discipline = -1, happiness = -1, battles = 30, techs = 30, flags = 0x10 },
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
    -- Its finisher (102 Spiral Sword: stats, motion) as
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
  -- --- Deltamon, Kimeramon (DW2003) and Machinedramon (DW1's own) -----------------
  {
    type = 192, name = "Deltamon", file = "DELT", level = 4, height = 420,
    attribute = 3, specialties = { 1, 0, 4 }, radius = 230, -- Virus; Battle, Fire, Ice
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from Fire and Ice from its middle mouth, the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true, points = { [0] = { 3, 126, -48, 0 }, [4] = { 3, 126, -48, 0 } } },
    -- Its finisher (58 Blaze Blast: stats, motion) as
    -- Triplex Force with Meramon's Fireball (0x3D), whose three start points
    -- (Meramon's body and hands) are its three mouths: the head's (bone 3) and
    -- the hand heads' (on the hand, bone 7, and the forearm, bone 12), the
    -- front of each snout at rest, in bone space
    finisher = { name = "Triplex Force", from = 58, effect = 0x3D,
      origin = { { 3, 126, -48, 0 }, { 7, 124, 35, -59 }, { 12, 206, -1, -8 } } },
    gains = { 1800, 1200, 250, 200, 150, 150 },
    -- HP, Offense and Defense 100, at most 10 care mistakes (flags 0x10),
    -- weight 35, 15 battles or 28 techniques
    requirements = { digimon = -1, hp = 100, mp = -1, offense = 100, defense = 100, speed = -1, brain = -1,
      care = 10, weight = 35, discipline = -1, happiness = -1, battles = 15, techs = 28, flags = 0x10 },
    icon_head = { 3, 4 },      -- Tyrannomon's head and jaw
    source = { ["SLES-03936"] = { file = 662, bones = 54, motions = 0 } }, -- M138DELT (enemy fighter 0x8A)
    donor = 8, donor_file = "TYRA.MMD", -- Tyrannomon (its fingers and left hand stay empty)
    -- hybrid: arms keep their own stance (each ends in a head: on a finger,
    -- the hand heads' jaws gaped as Tyrannomon's fingers curl, so they ride
    -- the hand); its two tail halves ride the first tail bone
    mapping = {
      [1] = { 2, "core" },                                                                       -- chest
      [9] = { 3, "core" }, [10] = { 3, "follow" }, [11] = { 4, "core" },                         -- neck + head, jaw
      [2] = { 5, "core" }, [3] = { 6, "core" }, [4] = { 7, "core" }, [5] = { 7, "follow" },      -- arm (+x): hand head and its jaw
      [6] = { 11, "core" }, [7] = { 12, "core" }, [8] = { 12, "follow" },                        -- arm (-x): forearm head and its jaw
      [12] = { 17, "core" },                                                                     -- pelvis
      [21] = { 18, "core" }, [22] = { 18, "follow" }, [23] = { 18, "follow" },                   -- tail half (-x)
      [24] = { 18, "core" }, [25] = { 18, "follow" }, [26] = { 18, "follow" },                   -- tail half (+x)
      [17] = { 21, "limb", 18, 22, true }, [18] = { 22, "leaf" }, [19] = { 22, "follow" }, [20] = { 23, "core" }, -- leg (+x)
      [13] = { 24, "limb", 14, 25, true }, [14] = { 25, "leaf" }, [15] = { 25, "follow" }, [16] = { 26, "core" }, -- leg (-x)
    },
  },
  {
    type = 193, name = "Kimeramon", file = "KIME", level = 5, height = 480,
    attribute = 1, specialties = { 1, 0, 2 }, radius = 280, -- Data; Battle, Fire, Air
    -- Techniques of its specialties (lib/techniques.lua: the donor's own of
    -- those kinds first, each other on the donor's closest motion; effects
    -- that don't list the donor start from the nearest-sized
    -- Digimon's place or in front of it)
    techniques = { auto = true },
    -- Its finisher (79 Giga Scissor Claw: stats,
    -- motion) as Heat Viper with Phoenixmon's Crimson Flare (0x6D), whose four
    -- start points (Phoenixmon's wings and feet) are its four hands: the
    -- raised ones (riding the chest, bone 2), then the claws (bones 9, 13),
    -- each hand's centre at rest, in bone space
    finisher = { name = "Heat Viper", from = 79, effect = 0x6D,
      origin = { { 2, 277, -45, -188 }, { 2, 277, -47, 188 }, { 9, 43, -7, 13 }, { 13, 46, -54, -40 } } },
    gains = { 5000, 4500, 550, 450, 500, 450 },
    -- HP 400, MP 400, Offense 450, Defense 400, Speed 400, Brains 400, at most
    -- 15 care mistakes, weight 55, 50 battles or 40 techniques
    requirements = { digimon = -1, hp = 400, mp = 400, offense = 450, defense = 400, speed = 400, brain = 400,
      care = 15, weight = 55, discipline = -1, happiness = -1, battles = 50, techs = 40, flags = 0x10 },
    icon_head = { 4, 5 },      -- MetalGreymon's head and jaw
    -- The Digimon page: MetalGreymon's model position (-30, 390, -780; the
    -- page's camera is at (1300, 0, -3280) looking at the origin) at the same
    -- distance, ~9 px lower and ~6 px left on screen so its horn clears the
    -- panel's title
    view = { -63, 440, -793 },
    source = { ["SLES-03936"] = { file = 1055, bones = 66, motions = 0 } }, -- M237CHMR (enemy fighter 0xED)
    donor = 12, donor_file = "MTGR.MMD", -- MetalGreymon
    -- 18 palettes, merged to 16 (lib/convert.lua). Its forward (Kabuterimon)
    -- claws ride MetalGreymon's arms, the raised (Devimon) arms the chest (on
    -- the arms they flailed as it walked), both wing pairs the wing bones.
    mapping = {
      [9] = { 2, "core" }, [13] = { 2, "follow" }, [14] = { 2, "follow" }, [15] = { 2, "follow" }, [16] = { 2, "follow" }, [17] = { 2, "follow" }, [18] = { 2, "follow" }, -- chest, raised arms
      [10] = { 3, "core" }, [11] = { 4, "core" }, [12] = { 5, "core" },                          -- neck, head, jaw
      [19] = { 7, "core" }, [20] = { 8, "core" }, [21] = { 9, "core" },                          -- claw arm (+x)
      [22] = { 11, "core" }, [23] = { 12, "core" }, [24] = { 13, "core" },                       -- claw arm (-x)
      [25] = { 15, "core" }, [27] = { 15, "core" }, [26] = { 17, "core" }, [28] = { 17, "core" }, -- wings (+x, -x)
      [1] = { 18, "core" },                                                                      -- pelvis -> hips
      [6] = { 19, "limb", 7, 20 }, [7] = { 20, "limb", 8, 21 }, [8] = { 21, "leaf" },            -- tail
      [2] = { 23, "limb", 3, 24, true }, [3] = { 24, "leaf" }, [4] = { 24, "follow" }, [5] = { 25, "core" },      -- leg (+x)
      [29] = { 27, "limb", 30, 28, true }, [30] = { 28, "leaf" }, [31] = { 28, "follow" }, [32] = { 29, "core" }, -- leg (-x)
    },
  },
  {
    -- Digimon World's own Machinedramon (type 115, the last boss: its model has
    -- battle motions only) on MetalGreymon's skeleton (the same build: its back
    -- cannons ride the wing bones), at its own size. A Mega.
    type = 194, name = "Machinedramon", file = "MCDR", level = 5, height = 600, model_height = 650, game = "dw1",
    chart_stage = 6,
    attribute = 3, specialties = { 5, 0, 1 }, radius = 320, -- Virus; Mech, Fire, Battle
    -- Its finisher (in place of 79 Giga Scissor
    -- Claw) its own Infinity Cannon (0x6A: stats and effect) at a Mega's power
    -- (the boss's is 777), playing its own Infinity Cannon motion (its
    -- animation 0x34, retargeted by lib/convert.lua: the cannons swing
    -- forward over its shoulders, it leans in and fires): MetalGreymon's torso
    -- moves with its chest (3), the cannons with their middle segments (9,
    -- 12), the body root with its root. The effect starts in front of it and
    -- at the two cannon ends (its bones 10 and 13 at 220 along x: on
    -- MetalGreymon's wing bones 15 and 17).
    finisher = { name = "Infinity Cannon", from = 79, stats = 0x6A, power = 280, effect = 0x6A,
      motion = { anim = 0x34, from = { [1] = 1, [2] = 3, [15] = 9, [17] = 12 } },
      origin = { { 0, 0, 0, 0 }, { 15, 162, 178, -349 }, { 17, 162, 177, 349 } } },
    gains = { 8000, 6000, 800, 900, 500, 600 },
    -- HP 800, MP 500, Offense 700, Defense 800, Speed 400, Brains 600, at most
    -- 10 care mistakes, weight 80, 80 battles or 45 techniques
    requirements = { digimon = -1, hp = 800, mp = 500, offense = 700, defense = 800, speed = 400, brain = 600,
      care = 10, weight = 80, discipline = -1, happiness = -1, battles = 80, techs = 45, flags = 0x10 },
    icon_head = { 4, 5 },      -- MetalGreymon's head and jaw
    -- The Digimon page: 650 tall, it can't fit at MetalGreymon's distance, so
    -- it stands farther back (by its height over MetalGreymon's) at the same
    -- place on screen
    view = { -709, 590, 500 },
    source = { ["SLUS-01032"] = { type = 115, file = "MUGE.MMD" } },
    donor = 12, donor_file = "MTGR.MMD", -- MetalGreymon
    -- DW1 bone -> MetalGreymon bone (bone 1, the root, has no mesh)
    mapping = {
      [1] = { 2, "core" }, [2] = { 2, "follow" }, [3] = { 2, "follow" },                         -- root, waist, chest
      [4] = { 3, "core" }, [5] = { 3, "follow" }, [6] = { 4, "core" }, [7] = { 5, "core" },      -- neck, head, jaw
      [8] = { 15, "core" }, [9] = { 15, "follow" }, [10] = { 15, "follow" },                     -- cannon (+x)
      [11] = { 17, "core" }, [12] = { 17, "follow" }, [13] = { 17, "follow" },                   -- cannon (-x)
      [14] = { 7, "core" }, [15] = { 8, "core" }, [16] = { 9, "core" },                          -- arm (+x)
      [17] = { 11, "core" }, [18] = { 12, "core" }, [19] = { 13, "core" }, [20] = { 13, "core" }, [21] = { 13, "core" }, -- arm (-x), claws
      [22] = { 18, "core" },                                                                     -- pelvis
      [23] = { 19, "limb", 24, 20 }, [24] = { 20, "limb", 25, 21 }, [25] = { 21, "leaf" },       -- tail
      [26] = { 23, "limb", 27, 24, true }, [27] = { 24, "leaf" }, [28] = { 25, "core" },         -- leg (+x)
      [29] = { 27, "limb", 30, 28, true }, [30] = { 28, "leaf" }, [31] = { 29, "core" },         -- leg (-x)
    },
  },
  -- --- the Sukamon line --------------------------------------------------------------
  {
    -- Digimon World's own PlatinumSukamon (type 73, an enemy: battle motions
    -- only) on Sukamon (39): the very same skeleton and mesh in another
    -- texture, so no mapping (every bone on itself, lib/convert.lua same_rig)
    -- and Sukamon's motions, face changes included, at its own size
    -- (`scale = 1`). A Champion, as the enemy.
    type = 195, name = "PlatinumSukamon", file = "PLSK", level = 4, height = 290, scale = 1, game = "dw1",
    attribute = 2, specialties = { 6, 5, 255 }, radius = 175, -- Vaccine (as the enemy); Filth, Mech
    -- Filth and Mech techniques (`techniques.moves`, technique by slot, each
    -- slot playing Sukamon's slot `motions[k]`): Sukamon's eight and its
    -- finisher (slots 0..8 as Sukamon's), then seven of the eight Mech ones
    -- (16 slots in all: DG Dimension, an Ultimate's, is left out): Power
    -- Crane thrown like Poop Spd Toss, All Range Beam and Full Potential on
    -- Ult Poop Hell's raised arms, Metal Sprinter on Poop Rnd Toss, Pulse
    -- Laser out of the mouth on Odor Spray, Delete Program on Rnd Spd Toss,
    -- Reverse Prog on Big Rnd Toss. The Mech effects don't list Sukamon:
    -- they start where MetalGreymon's do (`from`), its hand 9 on Sukamon's
    -- throwing hand 12 (where Poop Spd Toss starts); DG-less lists naming
    -- neither from that hand too (`fallback`).
    techniques = { from = 12,
      moves = { 0x37, 0x31, 0x32, 0x33, 0x35, 0x36, 0x34, 0x38, 0x41, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1E, 0x1F },
      motions = { 0, 1, 2, 3, 4, 5, 6, 7, 3, 2, 7, 4, 1, 5, 7, 6 },
      bones = { [9] = { 12, 35, -20, 0 } }, fallback = { 12, 35, -20, 0 } },
    -- Its finisher (in place of Sukamon's 0x41 Party Time: stats) as Rare Metal
    -- Poop at a Champion's power: Big Poop Toss's throw (slot 3's motion,
    -- above) and effect (0x33: from the body, as Sukamon's)
    finisher = { name = "Rare Metal Poop", from = 0x41, power = 170, effect = 0x33 },
    gains = { 2000, 1500, 150, 300, 150, 200 },
    -- MP 100, Defense 100, Brains 100, at most 10 care mistakes, weight 20, 28
    -- techniques. In the tree it comes from Gotsumon, not in the mod yet;
    -- until then from Tanemon's other Rookies (`interim_from`)
    requirements = { digimon = -1, hp = -1, mp = 100, offense = -1, defense = 100, speed = -1, brain = 100,
      care = 10, weight = 20, discipline = -1, happiness = -1, battles = -1, techs = 28, flags = 0x10 },
    interim_from = { "Palmon", "Kunemon", "Tentomon" },
    icon_head = { 2, 3, 4 }, icon_head_scale = 1.0, -- all of it is its head
    source = { ["SLUS-01032"] = { type = 73, file = "PCSC.MMD" } },
    donor = 39, donor_file = "SCUM.MMD", -- Sukamon
  },
  {
    -- Digimon World's own KingSukamon (type 120, "King of Sukamon", the NPC
    -- ruling Trash Mountain: a few idle motions) on Sukamon: the same
    -- skeleton 2.75 times as big, a crown on its head, and its arm raised by
    -- its pose (its rest pose takes Sukamon's rotations: lib/dw1source.lua).
    -- An Ultimate, 1.4 times Sukamon's size (`model_height`).
    type = 196, name = "KingSukamon", file = "KSUK", level = 5, height = 400, model_height = 430, game = "dw1",
    attribute = 3, specialties = { 6, 1, 255 }, radius = 240, -- Virus (as the NPC); Filth, Combat
    -- Filth and Combat techniques: Sukamon's (but Horizontal Kick) and its
    -- finisher, then all eight Combat ones: Tremar on Big Poop Toss's slam,
    -- Muscle Charge on Ult Poop Hell's raised arms, War Cry on Odor Spray's
    -- open mouth, Sonic Jab on Poop Spd Toss's swing, Dynamite Kick and
    -- Buster Dive on Horizontal Kick, Counter on Rnd Spd Toss, Megaton Punch
    -- on Big Rnd Toss. The Combat effects start where Etemon's do (`from`):
    -- its head 4 (Buster Dive) at the foe, its hand 9 (Muscle Charge) on
    -- Sukamon's hand 12.
    techniques = { from = 42,
      moves = { 0x31, 0x32, 0x33, 0x35, 0x36, 0x34, 0x38, 0x41, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F },
      motions = { 1, 2, 3, 4, 5, 6, 7, 0, 3, 7, 1, 2, 0, 5, 6, 0 },
      bones = { [4] = { 0, 0, -100, -550 }, [9] = { 12, 35, -20, 0 } }, fallback = { 12, 35, -20, 0 } },
    -- Its finisher (in place of Party Time) as King Stamp at an Ultimate's
    -- power: it jumps high onto the foe and lands with Buster Dive's impact
    -- there (0x2F at bone 0, 100 up, 550 forward). Horizontal Kick's flip,
    -- its own jump (frames 7..25) three times as high and its own forward
    -- travel 1.6 times as far, about 500 (`leap`; an added dash, `lunge`,
    -- would be overridden by the flip's own root keys from frame 10)
    finisher = { name = "King Stamp", from = 0x41, power = 225, effect = 0x2F, origin = { 0, 0, -100, -550 },
      leap = { from = 7, to = 26, up = 3, forward = 1.6 } },
    gains = { 6000, 4000, 550, 650, 400, 400 },
    -- HP 400, Offense 300, Defense 400, at most 15 care mistakes, weight 30,
    -- 30 battles or 35 techniques (Etemon, from Sukamon too, wants none)
    requirements = { digimon = -1, hp = 400, mp = -1, offense = 300, defense = 400, speed = -1, brain = -1,
      care = 15, weight = 30, discipline = -1, happiness = -1, battles = 30, techs = 35, flags = 0x10 },
    icon_head = { 2, 3, 4 }, icon_head_scale = 1.0,
    -- The Digimon page: at Sukamon's distance its crown is cut off, so it
    -- stands farther back by its height over Sukamon's, at the same place
    view = { -87, 361, -700 },
    source = { ["SLUS-01032"] = { type = 120, file = "SCUD.MMD" } },
    donor = 39, donor_file = "SCUM.MMD", -- Sukamon
  },
  -- --- Raremon (DW2003) ----------------------------------------------------------
  {
    -- A Rookie that meets no evolution's requirements becomes Raremon instead
    -- of Numemon a quarter of the time (lib/special.lua); in the tree it
    -- comes from DemiDevimon and Hagurumon, not in the mod yet.
    type = 197, name = "Raremon", file = "RARE", level = 4, height = 330,
    attribute = 3, specialties = { 6, 5, 255 }, radius = 230, -- Virus; Filth, Mech (as PlatinumSukamon)
    -- Filth and Mech techniques (lib/techniques.lua); none list Shellmon,
    -- so they start from its mouth (the nearest-sized Digimon's place)
    techniques = { auto = true, points = { [6] = { 4, 116, -56, -2 }, [5] = { 4, 116, -56, -2 } } },
    -- Its finisher (Shellmon's 0x57 Hydro Pressure: stats, the spray from its
    -- mouth) as Sludge with Vegiemon's Sweet Breath (0x48) from its mouth:
    -- Shellmon's head bone 4, between its upper teeth and its jaw
    finisher = { name = "Sludge", from = 0x57, effect = 0x48, origin = { 4, 116, -56, -2 } },
    gains = { 2000, 1500, 200, 200, 100, 150 },
    -- HP 100, Defense 100, at most 15 care mistakes, weight 30, 25 techniques
    requirements = { digimon = -1, hp = 100, mp = -1, offense = -1, defense = 100, speed = -1, brain = -1,
      care = 15, weight = 30, discipline = -1, happiness = -1, battles = -1, techs = 25, flags = 0x10 },
    icon_head = { 4, 5 },      -- Shellmon's head and jaw
    source = { ["SLES-03936"] = { file = 666, bones = 30, motions = 0 } }, -- M139RARE (enemy fighter 0x8B)
    donor = 35, donor_file = "SHEL.MMD", -- Shellmon: both sit on the ground propped on two clawed arms
    -- its slime base and front lip on the shell, its upper body on Shellmon's
    -- body, head and jaw on head and jaw, its arms on Shellmon's arms in
    -- their own stance; Shellmon's neck (3) stays empty
    mapping = {
      [1] = { 14, "core" }, [2] = { 14, "follow" }, [3] = { 14, "follow" },             -- root (a speck), slime base, front lip
      [4] = { 2, "core" },                                                               -- upper body
      [13] = { 4, "core" }, [14] = { 5, "core" },                                        -- head (eye, upper teeth), jaw
      [5] = { 7, "core" }, [6] = { 8, "core" }, [7] = { 9, "core" }, [8] = { 9, "follow" },    -- arm (+x)
      [9] = { 11, "core" }, [10] = { 12, "core" }, [11] = { 13, "core" }, [12] = { 13, "follow" }, -- arm (-x)
    },
  },
  -- --- the Renamon line (DW2003 partners) -------------------------------------------
  {
    type = 198, name = "Renamon", file = "RENA", level = 3, height = 340, model_height = 360, -- tall for a Rookie, ears included
    attribute = 1, specialties = { 1, 4, 255 }, radius = 150, -- Data; Battle, Ice
    -- Battle and Ice techniques (lib/techniques.lua); the Ice ones (none list
    -- Leomon) start from its right hand
    techniques = { auto = true, points = { [4] = { 7, 15, 8, 8 } } },
    -- Its finisher (Leomon's 91 Fist of the Beast King: stats, the punch) as
    -- Diamond Storm with Seadramon's Ice Blast (0x58) shards from its right
    -- hand, at a Rookie's power (Leomon's is a Champion's 170)
    finisher = { name = "Diamond Storm", from = 91, power = 95, effect = 0x58, origin = { 7, 15, 8, 8 } },
    gains = { 600, 700, 70, 60, 110, 90 },
    -- a Tsunomon (16) whose highest stat is Speed or Brains, at weight 30 +- 5
    -- (Tsunomon's other Rookies want weight 10 to 20)
    requirements = { digimon = 16, hp = -1, mp = -1, offense = -1, defense = -1, speed = 1, brain = 1,
      care = 0, weight = 30, discipline = -1, happiness = -1, battles = -1, techs = -1, flags = 0 },
    raise_from = 17,             -- a Rookie's care (Gabumon, also from Tsunomon)
    view = { 200, 330, -1320 },  -- the donor's camera (Leomon's; Gabumon's came with raise_from)
    icon_head = { 3 },           -- Leomon's head (its jaw stays empty)
    source = { ["SLES-03936"] = { file = 511, bones = 45, motions = 0 } }, -- M373RENA (partner)
    donor = 48, donor_file = "LEOM.MMD", -- Leomon: a tail, four-bone legs
    -- hybrid; its tail keeps its own sideways sweep on Leomon's three tail
    -- bones (the last two segments on the last); Leomon's jaw (4) stays empty
    mapping = {
      [14] = { 2, "core" }, [15] = { 3, "core" },                                              -- chest, head (ears)
      [19] = { 5, "core" }, [20] = { 6, "core" }, [21] = { 7, "core" },                        -- arm (+x)
      [16] = { 8, "core" }, [17] = { 9, "core" }, [18] = { 10, "core" },                       -- arm (-x)
      [1] = { 11, "core" },                                                                    -- hips
      [10] = { 12, "core" }, [11] = { 13, "core" }, [12] = { 14, "core" }, [13] = { 14, "follow" }, -- tail
      [2] = { 15, "limb", 3, 16, true }, [3] = { 16, "leaf" }, [4] = { 17, "core" }, [5] = { 18, "core" }, -- leg (+x)
      [6] = { 19, "limb", 7, 20, true }, [7] = { 20, "leaf" }, [8] = { 21, "core" }, [9] = { 22, "core" }, -- leg (-x)
    },
  },
  {
    type = 199, name = "Kyubimon", file = "KYBI", level = 4, height = 330, model_height = 400,
    attribute = 1, specialties = { 1, 0, 255 }, radius = 230, -- Data; Battle, Fire
    -- Battle and Fire techniques; the Fire ones (Garurumon's list none) from its mouth
    techniques = { auto = true, points = { [0] = { 4, 80, -2, 24 } } },
    -- Its finisher (Garurumon's 0x40 Howling Blaster: stats, motion) as Fox
    -- Tail Inferno with Birdramon's Meteor Wing (0x5E) fireballs from four of
    -- its tail tips (all on Garurumon's tail bone 15)
    finisher = { name = "Fox Tail Inferno", from = 0x40, effect = 0x5E,
      origin = { { 15, 263, -140, -20 }, { 15, 291, 12, -45 }, { 15, 256, 152, -1 }, { 15, 222, 107, 171 } } },
    gains = { 1500, 2000, 150, 150, 200, 250 },
    -- MP and Brains 100, at most 5 care mistakes, weight 25, 30 techniques
    requirements = { digimon = -1, hp = -1, mp = 100, offense = -1, defense = -1, speed = -1, brain = 100,
      care = 5, weight = 25, discipline = -1, happiness = -1, battles = -1, techs = 30, flags = 0x10 },
    icon_head = { 4 },           -- Garurumon's head (its jaw stays empty)
    -- The Digimon page: 400 tall with its tails, it can't fit at Garurumon's
    -- distance (its tails spilled out), so it stands back by its height over
    -- Garurumon's (290) at the same place on screen
    view = { -231, 400, -411 },
    source = { ["SLES-03936"] = { file = 927, bones = 90, motions = 0 } }, -- M374KYBI (partner)
    donor = 22, donor_file = "GARU.MMD", -- Garurumon: four legs
    -- Garurumon's technique motions its list doesn't use go, for room: with
    -- them it only fit slimmed, and lost its ears, its neck rope, then its tails
    prune = true,
    -- its ruff and bead tassels on the neck, the nine tails (a base and seven
    -- more) one fan on Garurumon's first tail bone; its fox fires (16-33,
    -- hidden at rest) left out; Garurumon's jaw and last tail bones stay empty
    mapping = {
      [1] = { 2, "core" },                                                                       -- chest
      [8] = { 3, "core" }, [9] = { 3, "follow" }, [10] = { 3, "follow" }, [11] = { 4, "core" },  -- ruff, tassels, head
      [5] = { 7, "limb", 6, 8, true }, [6] = { 8, "leaf" }, [7] = { 9, "core" },                 -- front leg (+x)
      [2] = { 11, "limb", 3, 12, true }, [3] = { 12, "leaf" }, [4] = { 13, "core" },             -- front leg (-x)
      [12] = { 14, "core" },                                                                     -- hind body
      [13] = { 19, "limb", 14, 20, true }, [14] = { 20, "leaf" }, [15] = { 21, "core" },         -- hind leg (+x)
      [34] = { 23, "limb", 35, 24, true }, [35] = { 24, "leaf" }, [36] = { 25, "core" },         -- hind leg (-x)
      [37] = { 15, "core" }, [38] = { 15, "follow" }, [39] = { 15, "follow" }, [40] = { 15, "follow" }, -- tails
      [41] = { 15, "follow" }, [42] = { 15, "follow" }, [43] = { 15, "follow" }, [44] = { 15, "follow" },
    },
  },
  {
    type = 200, name = "Taomon", file = "TAOM", level = 5, height = 450, model_height = 480,
    attribute = 1, specialties = { 1, 2, 255 }, radius = 230, -- Data; Battle, Air
    -- Battle and Air techniques; the Air ones not Andromon's from its right sleeve
    techniques = { auto = true, points = { [2] = { 7, 35, 17, 19 } } },
    -- Its finisher (Andromon's 102 Spiral Sword: stats, the swing) as
    -- Thousand Spells with Ninjamon's Iga School Knife Throw (0x59), its
    -- talismans flung from the right sleeve
    finisher = { name = "Thousand Spells", from = 102, effect = 0x59, origin = { 7, 35, 17, 19 } },
    gains = { 4000, 5500, 400, 400, 450, 550 },
    -- HP 300, MP 400, Speed 300, Brains 400, at most 5 care mistakes, weight
    -- 30, discipline 80, 35 techniques
    requirements = { digimon = -1, hp = 300, mp = 400, offense = -1, defense = -1, speed = 300, brain = 400,
      care = 5, weight = 30, discipline = 80, happiness = -1, battles = -1, techs = 35, flags = 0x10 },
    icon_head = { 3 },           -- Andromon has no jaw
    -- The Digimon page: 480 tall, its hat and feet were cut off at Andromon's
    -- distance; it stands back by its height over Andromon's (400)
    view = { 52, 432, -1024 },
    source = { ["SLES-03936"] = { file = 1112, bones = 1, motions = 0 } }, -- M375TAOM (partner)
    donor = 40, donor_file = "ANDR.MMD", -- Andromon: upright, arms hanging at its sides
    -- shoulder pads and upper sleeves on the upper arms; its brush tail and
    -- robe flaps on the hips; its brush (28, hidden at rest) left out
    mapping = {
      [18] = { 2, "core" }, [23] = { 3, "core" },                                                -- chest, head
      [19] = { 5, "core" }, [20] = { 5, "follow" }, [21] = { 6, "core" }, [22] = { 7, "core" },  -- arm (+x)
      [24] = { 9, "core" }, [25] = { 9, "follow" }, [26] = { 10, "core" }, [27] = { 11, "core" }, -- arm (-x)
      [1] = { 12, "core" }, [6] = { 12, "follow" }, [7] = { 12, "follow" }, [8] = { 12, "follow" }, [9] = { 12, "follow" }, -- hips, tail
      [14] = { 12, "follow" }, [15] = { 12, "follow" }, [16] = { 12, "follow" }, [17] = { 12, "follow" },                   -- robe flaps
      [2] = { 14, "limb", 3, 15, true }, [3] = { 15, "leaf" }, [4] = { 16, "core" }, [5] = { 16, "follow" },     -- leg (+x)
      [10] = { 18, "limb", 11, 19, true }, [11] = { 19, "leaf" }, [12] = { 20, "core" }, [13] = { 20, "follow" }, -- leg (-x)
    },
  },
  {
    type = 201, name = "Sakuyamon", file = "SKYA", level = 5, height = 470, model_height = 620,
    chart_stage = 6,
    attribute = 1, specialties = { 1, 2, 3 }, radius = 250, -- Data; Battle, Air, Earth
    -- Battle, Air and Earth techniques; the others from the head of its staff
    techniques = { auto = true, points = { [2] = { 9, -259, 87, -101 }, [3] = { 9, -259, 87, -101 } } },
    -- Its finisher (Angemon's 0x52 Hand of Fate: stats, motion, effect) as
    -- Spirit Strike, the light from the head of its staff, at a Mega's power
    finisher = { name = "Spirit Strike", from = 0x52, power = 280, origin = { 9, -259, 87, -101 } },
    gains = { 7000, 8000, 600, 500, 700, 800 },
    -- HP 600, MP 700, Offense 500, Defense 500, Speed 600, Brains 700, at most
    -- 5 care mistakes, weight 35, discipline 90, 45 techniques
    requirements = { digimon = -1, hp = 600, mp = 700, offense = 500, defense = 500, speed = 600, brain = 700,
      care = 5, weight = 35, discipline = 90, happiness = -1, battles = -1, techs = 45, flags = 0x10 },
    raise_from = 59,             -- a Mega's care (Phoenixmon; Angemon is a Champion)
    -- The Digimon page: 620 tall with its staff, whose ring was cut off at
    -- Angemon's distance; it stands back by its height over Angemon's (400)
    view = { -638, 542, 208 },
    icon_head = { 3 },           -- Angemon's head
    source = { ["SLES-03936"] = { file = 1091, bones = 54, motions = 0 } }, -- M376SKYA (partner)
    donor = 20, donor_file = "ANGE.MMD", -- Angemon: a staff in the left hand
    -- the slimming leaves its staff alone (its thin shaft collapsed to a line)
    keep = { 22, 23, 24, 25, 26 },
    -- hair on the head, the staff on the left hand; Angemon's wings (10-17)
    -- and loincloth (25) stay empty
    mapping = {
      [10] = { 2, "core" }, [14] = { 3, "core" }, [15] = { 3, "follow" }, [16] = { 3, "follow" }, [17] = { 3, "follow" }, [18] = { 3, "follow" }, -- chest, head, hair
      [11] = { 4, "core" }, [12] = { 5, "core" }, [13] = { 6, "core" },                          -- arm (+x)
      [19] = { 7, "core" }, [20] = { 8, "core" }, [21] = { 9, "core" },                          -- arm (-x)
      [22] = { 9, "follow" }, [23] = { 9, "follow" }, [24] = { 9, "follow" }, [25] = { 9, "follow" }, [26] = { 9, "follow" }, -- staff
      [1] = { 18, "core" },                                                                      -- hips
      [2] = { 19, "limb", 3, 20, true }, [3] = { 20, "leaf" }, [4] = { 21, "core" }, [5] = { 21, "follow" }, -- leg (+x)
      [6] = { 22, "limb", 7, 23, true }, [7] = { 23, "leaf" }, [8] = { 24, "core" }, [9] = { 24, "follow" }, -- leg (-x)
    },
  },
}

-- The game's own Digimon that change (their evolution lists come from
-- lib/tree.lua). `requirements` replaces only the fields given.
--
-- HerculesKabuterimon and Phoenixmon become Megas (the chart's sixth section;
-- DIGIMON_DATA keeps level 5, which so much of the game reads that a level 6
-- isn't safe) with Mega requirements and gains, once a Digimon they come from
-- in the tree is built (`needs`); until then they stay Ultimates. An Ultimate
-- becomes a Mega like a Champion becomes an Ultimate (lib/evolution.lua:
-- M.MEGA_HOURS). Whamon is an Ultimate in the tree: level 5 (a Champion's
-- evolution into it adds an Ultimate's lifetime) with an Ultimate's
-- requirements and gains.
M.changes = {
  {
    type = 60, name = "HerculesKabuterimon", chart_stage = 6, needs = { 189 }, -- MegaKabuterimon
    -- HP 700, MP 400, Offense 600, Defense 700, Speed 500, at most 5 care
    -- mistakes, weight 60, 50 battles, 45 techniques
    requirements = { digimon = -1, hp = 700, mp = 400, offense = 600, defense = 700, speed = 500, brain = -1,
      care = 5, weight = 60, discipline = -1, happiness = -1, battles = 50, techs = 45, flags = 0x10 },
    gains = { 7000, 6000, 700, 800, 600, 500 },
  },
  {
    type = 59, name = "Phoenixmon", chart_stage = 6, needs = { 191 }, -- Garudamon
    -- HP 600, MP 700, Offense 500, Defense 500, Speed 700, Brains 700, at most
    -- 3 care mistakes, weight 35, discipline 100, 45 techniques
    requirements = { digimon = -1, hp = 600, mp = 700, offense = 500, defense = 500, speed = 700, brain = 700,
      care = 3, weight = 35, discipline = 100, happiness = -1, battles = -1, techs = 45, flags = 0x10 },
    gains = { 7000, 8000, 600, 500, 800, 800 },
  },
  {
    type = 24, name = "Whamon", level = 5, chart_stage = 5,
    -- HP 400, Defense 400, Brains 400, at most 10 care mistakes, weight 50,
    -- discipline 70 or 30 techniques (as a Champion: HP and Brains 100)
    requirements = { digimon = -1, hp = 400, mp = -1, offense = -1, defense = 400, speed = -1, brain = 400,
      care = 10, weight = 50, discipline = 70, happiness = -1, battles = -1, techs = 30, flags = 0x10 },
    gains = { 5000, 3000, 400, 550, 300, 500 },
  },
  -- Vademon comes from Nanimon in the tree; the game has no requirements for
  -- it (it only comes from an event): MP 400, Brains 500, at most 15 care
  -- mistakes, weight 20, 35 techniques
  { type = 28, name = "Vademon",
    requirements = { digimon = -1, hp = -1, mp = 400, offense = -1, defense = -1, speed = -1, brain = 500,
      care = 15, weight = 20, discipline = -1, happiness = -1, battles = -1, techs = 35, flags = 0x10 } },
  -- The Rookies' new In-Training (the tree): `digimon` names it. Kunemon
  -- (no requirements in the game: it came from an event) wants HP or Defense
  -- highest at weight 10 (Palmon, before it, MP, Speed or Brains at 15);
  -- Elecmon now wants weight 10 (Veemon, before it, takes Offense at 15..25).
  { type = 32, name = "Kunemon",
    requirements = { digimon = 44, hp = 1, mp = -1, offense = -1, defense = 1, speed = -1, brain = -1,
      care = 0, weight = 10, discipline = -1, happiness = -1, battles = -2, techs = 0, flags = 0 } },
  { type = 18, name = "Elecmon", requirements = { weight = 10 } },
  { type = 45, name = "Biyomon", requirements = { digimon = 2 } },     -- Koromon
  { type = 4, name = "Betamon", requirements = { digimon = 16 } },     -- Tsunomon
  { type = 17, name = "Gabumon", requirements = { digimon = 16 } },    -- Tsunomon
  { type = 57, name = "Penguinmon", requirements = { digimon = 30 } }, -- Tokomon
}

return M
