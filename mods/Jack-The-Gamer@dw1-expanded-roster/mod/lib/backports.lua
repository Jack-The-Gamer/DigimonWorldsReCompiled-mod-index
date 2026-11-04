-- The Digimon brought over from Digimon World 2003, built while the mod loads
-- from the player's own disc of it (nothing of either game ships with the
-- mod). Each one: its new type number and name, where its battle model is on
-- the DW2003 disc, the DW1 Digimon whose skeleton and animations it uses
-- (the donor), how the bones map (see lib/convert.lua), and its height.
--
-- Only the European DW2003 (SLES-03936) is known so far: the model's file
-- number and its bone/motion entries differ on the American and Japanese
-- discs (find them through the fighter table, SMDLDATA.PRO).

local M = {}

-- Digimon World 2003 (Europe): the executable's file table (first sector,
-- sector count of each file by number).
M.DW3 = {
  ["SLES-03936"] = { exe = "SLES_039.36", load = 0x80010000, sectors = 0x80044F6C, counts = 0x800474A4, files = 2382 },
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
}

return M
