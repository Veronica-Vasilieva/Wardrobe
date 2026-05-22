-------------------------------------------------------------------------------
-- Data/ItemsBySlot.lua  --  master "all transmoggable items" reference set.
--
-- Used by the v1.21 missing-collections filter to know which items EXIST in
-- the game's item pool, beyond what the player has personally collected via
-- the Warpweaver. Without a master list, "Missing" can't be computed -- the
-- gossip scan only tells us what the player owns.
--
-- This file is loaded BEFORE Scan.lua / UI_Main.lua, so the global is always
-- available. Shipped empty -- populate by regenerating with the tool:
--
--     python tools/build_items_list.py --source path/to/items.csv
--
-- Format:
--     WardrobeItemsBySlot[slotId] = { itemId, itemId, itemId, ... }
--
-- Slot IDs match Wardrobe's internal slot table (see Core.lua SLOTS):
--   1=Head 3=Shoulders 4=Shirt 5=Chest 6=Waist 7=Legs 8=Feet 9=Wrists
--   10=Hands 15=Back 16=MainHand 17=OffHand 19=Tabard
--
-- Enchant slots (96/97) are intentionally not in this file -- enchants are
-- discovered server-side and have no master list outside the scan.
--
-- The list does NOT need to be exhaustive; partial coverage is better than
-- nothing. Items that exist in this list but not the player's collection
-- show up as "missing" (dimmed) rows the player can Try On but not Apply.
-------------------------------------------------------------------------------

WardrobeItemsBySlot = {
    [1]  = {},   -- Head
    [3]  = {},   -- Shoulders
    [4]  = {},   -- Shirt
    [5]  = {},   -- Chest
    [6]  = {},   -- Waist
    [7]  = {},   -- Legs
    [8]  = {},   -- Feet
    [9]  = {},   -- Wrists
    [10] = {},   -- Hands
    [15] = {},   -- Back
    [16] = {},   -- Main hand
    [17] = {},   -- Off hand
    [19] = {},   -- Tabard
}

-- Format version. Bump if the structure ever changes (e.g. switching from
-- a flat array of itemIds to {itemId, source, name} tuples). The addon can
-- then warn on load if the data file is incompatible.
WardrobeItemsBySlotVersion = 1
