-- New battle models on a donor's skeleton (Snatchmon on Devimon's,
-- Destromon on Cannondramon's).
--
-- A battle model file is an archive: the motions (entry 0), per bone a mesh
-- entry and a keys entry, the texture, the bone list (texture entry, count,
-- parent / mesh / keys per bone) and the scripts. The mod ships its own
-- meshes and texture (models/*.lua, made by research/tools/partner_model.py)
-- by the entry numbers they replace; at load it reads the donor's file from
-- the disc, puts them in, and adds the result as a new file, so the donor's
-- keys, motions and scripts (game data) are used as they are and the donor
-- itself is unchanged.

local bin = require("lib.bin")
local disc = require("lib.disc")
local sprites = require("lib.sprites")

local M = {}

-- The new model file made from donor file `donor_file` and data module
-- `data` ({ entries = { [n] = base64 } }); returns its file number.
function M.build(donor_file, data)
  local list = sprites.read_archive(disc.read_file(donor_file))
  for n, b64 in pairs(data.entries) do
    assert(n < #list, string.format("the donor file %d has no entry %d", donor_file, n))
    list[n + 1] = bin.unbase64(b64)
  end
  return disc.add_file(sprites.build_archive(list))
end

return M
