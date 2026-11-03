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
    -- stats (lib/tables.lua: on an unused finisher number).
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
    -- Until WarGrowlmon is built: Greymon's own (MetalGreymon, SkullGreymon).
    evolutions = { 12, 26 },
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
}

return M
