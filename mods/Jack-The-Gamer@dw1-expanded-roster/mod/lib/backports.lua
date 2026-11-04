-- The Digimon brought over from Digimon World 2003 and Digimon World 2,
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
      [1] = { 2, "core" },                                                         -- upper body -> torso
      [2] = { 6, "limb", 3, 7 }, [3] = { 7, "limb", 4, 8 }, [4] = { 8, "leaf" },  -- right arm
      [10] = { 10, "limb", 11, 11 }, [11] = { 11, "limb", 12, 12 }, [12] = { 12, "leaf" }, -- left arm
      [5] = { 3, "core" }, [6] = { 3, "follow" }, [8] = { 3, "follow" }, [9] = { 3, "follow" }, -- neck, head, ears -> head
      [7] = { 4, "core" },                                                         -- jaw -> jaw
      [13] = { 13, "core" }, [22] = { 13, "follow" }, [23] = { 13, "follow" }, [24] = { 13, "follow" }, -- pelvis, tail -> hips
      [14] = { 15, "limb", 15, 16 }, [15] = { 16, "limb", 17, 17 }, [16] = { 16, "follow" }, [17] = { 17, "leaf" }, -- right leg
      [18] = { 19, "limb", 19, 20 }, [19] = { 20, "limb", 21, 21 }, [20] = { 20, "follow" }, [21] = { 21, "leaf" }, -- left leg
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
      [1] = { 2, "core" },                                                         -- upper body -> torso
      [6] = { 3, "core" }, [7] = { 4, "core" }, [8] = { 5, "core" },               -- neck, head, jaw
      [2] = { 7, "limb", 3, 8 }, [3] = { 8, "limb", 5, 9 }, [4] = { 8, "follow" }, [5] = { 9, "leaf" }, -- right arm, elbow blade
      [9] = { 11, "limb", 10, 12 }, [10] = { 12, "limb", 12, 13 }, [11] = { 12, "follow" }, [12] = { 13, "leaf" }, -- left arm
      [13] = { 14, "core" },                                                       -- pelvis
      [14] = { 15, "limb", 15, 16 }, [15] = { 16, "limb", 16, 17 }, [16] = { 17, "leaf" }, -- tail
      [17] = { 23, "limb", 18, 24 }, [18] = { 24, "limb", 20, 25 }, [19] = { 24, "follow" }, [20] = { 25, "leaf" }, -- left leg
      [21] = { 19, "limb", 22, 20 }, [22] = { 20, "limb", 24, 21 }, [23] = { 20, "follow" }, [24] = { 21, "leaf" }, -- right leg
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
    -- (bone 0, as that effect's own users: 100 up, 550 forward, where the foe stands). Buster Dive
    -- hits where the user's own motion carries it, and no Digimon with
    -- Gabumon's skeleton has its dive, so it plays Gabumon's lunging Megaton
    -- Punch (0x2E) instead of Blue Blaster's breath (`anim`).
    finisher = { name = "V-Headbutt", from = 99, anim = 0x2E, effect = 0x2F, origin = { 0, 0, -100, -550 } },
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
      [13] = { 2, "core" }, [20] = { 3, "core" }, [21] = { 4, "core" },                          -- chest, head, jaw
      [14] = { 6, "limb", 15, 7 }, [15] = { 7, "limb", 16, 8 }, [16] = { 8, "leaf" },          -- right arm
      [17] = { 10, "limb", 18, 11 }, [18] = { 11, "limb", 19, 12 }, [19] = { 12, "leaf" },     -- left arm
      [1] = { 13, "core" }, [2] = { 13, "follow" }, [3] = { 13, "follow" }, [4] = { 13, "follow" }, -- pelvis, tail -> hips
      -- feet not turned with the shin (its battle crouch tipped them toes-down)
      [5] = { 15, "limb", 6, 16 }, [6] = { 16, "limb", 8, 17 }, [7] = { 16, "follow" }, [8] = { 17, "core" },     -- right leg
      [9] = { 19, "limb", 10, 20 }, [10] = { 20, "limb", 12, 21 }, [11] = { 20, "follow" }, [12] = { 21, "core" }, -- left leg
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
      [1] = { 2, "core" }, [2] = { 3, "core" }, [3] = { 4, "core" }, [4] = { 5, "core" },       -- chest, neck, head, jaw
      [5] = { 7, "limb", 6, 8 }, [6] = { 8, "limb", 7, 9 }, [7] = { 9, "leaf" },                -- right arm
      [8] = { 11, "limb", 9, 12 }, [9] = { 12, "limb", 10, 13 }, [10] = { 13, "leaf" },         -- left arm
      [11] = { 14, "core" },                                                                    -- pelvis
      [12] = { 15, "limb", 13, 16 }, [13] = { 16, "limb", 14, 17 }, [14] = { 17, "leaf" },      -- tail
      -- feet not turned with the shin (they tipped toes-up)
      [15] = { 19, "limb", 16, 20 }, [16] = { 20, "limb", 17, 21 }, [17] = { 21, "core" },      -- right leg
      [18] = { 23, "limb", 19, 24 }, [19] = { 24, "limb", 20, 25 }, [20] = { 25, "core" },      -- left leg
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
    evolves_from = { 184 }, -- ExVeemon
    icon_head = { 3 },      -- Andromon has no jaw
    source = { ["SLES-03936"] = { file = 601, bones = 54, motions = 0 } }, -- M254PLDR (fighter 0xFE)
    donor = 40, donor_file = "ANDR.MMD", -- Andromon (no tail or jaw)
    -- 948 polygons: slimmed to fit next to Andromon's animations. Its hip
    -- cannons (13, 15) ride the hips; 14 and 16 are folded to a point at rest
    -- (hidden) and left out.
    mapping = {
      [17] = { 2, "core" }, [25] = { 2, "follow" }, [26] = { 2, "follow" }, [27] = { 2, "follow" }, [28] = { 2, "follow" }, -- chest, wings
      [21] = { 3, "core" },                                                                     -- head
      [18] = { 5, "limb", 19, 6 }, [19] = { 6, "limb", 20, 7 }, [20] = { 7, "leaf" },          -- right arm
      [22] = { 9, "limb", 23, 10 }, [23] = { 10, "limb", 24, 11 }, [24] = { 11, "leaf" },      -- left arm
      [1] = { 12, "core" }, [10] = { 12, "follow" }, [11] = { 12, "follow" }, [12] = { 12, "follow" }, [13] = { 12, "follow" }, [15] = { 12, "follow" }, -- hips, tail, cannons
      [2] = { 14, "limb", 3, 15 }, [3] = { 15, "limb", 5, 16 }, [4] = { 15, "follow" }, [5] = { 16, "leaf" },      -- right leg
      [6] = { 18, "limb", 7, 19 }, [7] = { 19, "limb", 9, 20 }, [8] = { 19, "follow" }, [9] = { 20, "leaf" },      -- left leg
    },
  },
  {
    type = 187, name = "AeroVeedramon", file = "AVDR", level = 5, height = 470, game = "dw2",
    attribute = 2,
    -- MetalGreymon's techniques; its finisher (79 Giga Scissor Claw) as Dragon
    -- Impulse with Crimson Flare's effect (0x6D) from the chest (the torso,
    -- bone 2, as WarGrowlmon's Atomic Blaster)
    finisher = { name = "Dragon Impulse", from = 79, effect = 0x6D, origin = { 2, 95, -15, 0 } },
    gains = { 5000, 5000, 500, 500, 500, 500 },
    -- HP 400, MP 300, Offense 500, Defense 400, Speed 400, Brains 300, at most
    -- 10 care mistakes, weight 60, discipline 90, 30 battles, 30 techniques
    requirements = { digimon = -1, hp = 400, mp = 300, offense = 500, defense = 400, speed = 400, brain = 300,
      care = 10, weight = 60, discipline = 90, happiness = -1, battles = 30, techs = 30, flags = 0x10 },
    evolves_from = { 185, 184 }, -- Veedramon, ExVeemon
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
}

return M
