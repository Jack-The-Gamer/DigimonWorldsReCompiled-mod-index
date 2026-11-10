-- The (code, value) condition and action codes of the game's scripts
-- (game_state.h): FLAGS_00.checkConditions tests them, applyActions applies
-- them; lists end with CODES_END.

local M = {}

function M.FLAG(group, id) return (group << 8) | id end
function M.PROGRESS(n) return 0x6000 | n end
function M.SPECIAL(id) return 0x7000 | id end
function M.ITEM(kind, id) return 0x8000 | (kind << 9) | id end
function M.START_EVENT(i) return 0x9000 | i end
M.END = 0xFFFF

-- Specials of the game used here (story.h).
M.SPECIAL_STORY_SINCE_GENJI_BEATEN = M.SPECIAL(9)
M.SPECIAL_SHOW_ITEM_GET_ICON = M.SPECIAL(0x13)

-- The story points of the sixteen auctions in Asuka City's Cargo Tower: the
-- crowd stands there for the whole story point.
M.AUCTION_PROGRESS = { 0x05, 0x08, 0x0C, 0x0E, 0x10, 0x16, 0x18, 0x1A, 0x1C, 0x1E, 0x1F, 0x22, 0x24, 0x25, 0x26, 0x27 }

return M
