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
}

return M
