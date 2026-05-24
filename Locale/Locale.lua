-------------------------------------------------------------------------------
-- Wardrobe localisation framework  (v1.23+).
--
-- Pattern:
--   local L = Wardrobe_L
--   button:SetText(L["Settings"])
--   Print(L["Last scan: %dm ago"]:format(mins))
--
-- L is a table with a __index metatable that falls back to the key itself
-- when no translation exists. Missing locales (or untranslated strings) just
-- show the original English text -- never an error or a missing-key marker.
--
-- To translate, set keys on Wardrobe_L from inside a Locale-XX.lua file:
--   if GetLocale() ~= "deDE" then return end
--   local L = Wardrobe_L
--   L["Settings"]    = "Einstellungen"
--   L["Apply"]       = "Anwenden"
--   ...
--
-- The enUS defaults below double as the canonical key list AND the enUS
-- translation (since key == value). When adding new user-visible strings to
-- the addon, add the enUS entry here so other locale files have a key to
-- override. Pure colour-code wrappers / format-only strings are not wrapped
-- (they're not text a translator would change).
-------------------------------------------------------------------------------

Wardrobe_L = setmetatable({}, { __index = function(t, k) return k end })
local L = Wardrobe_L

-- =========================================================================
-- Window chrome
-- =========================================================================
L["Wardrobe"]                            = "Wardrobe"
L["Wardrobe Settings"]                   = "Wardrobe Settings"
L["Project Ebonhold transmog browser"]   = "Project Ebonhold transmog browser"
L["Search"]                              = "Search"
L["Settings"]                            = "Settings"

-- =========================================================================
-- Filter row
-- =========================================================================
L["Quality: All"]                        = "Quality: All"
L["Quality: %s+"]                        = "Quality: %s+"
L["Sort: %s"]                            = "Sort: %s"
L["Collection: All"]                     = "Collection: All"
L["Collection: Owned"]                   = "Collection: Owned"
L["Collection: Missing"]                 = "Collection: Missing"
L["Hide %s"]                             = "Hide %s"
L["Hide Slot"]                           = "Hide Slot"

-- Sort orders (also used by the dropdown menu rows)
L["Favourites + Quality"]                = "Favourites + Quality"
L["Quality (high to low)"]               = "Quality (high to low)"
L["Quality (low to high)"]               = "Quality (low to high)"
L["Name (A to Z)"]                       = "Name (A to Z)"
L["Name (Z to A)"]                       = "Name (Z to A)"
L["Recently scanned"]                    = "Recently scanned"

-- Quality names (3.3.5a item qualities 0..6)
L["Poor"]                                = "Poor"
L["Common"]                              = "Common"
L["Uncommon"]                            = "Uncommon"
L["Rare"]                                = "Rare"
L["Epic"]                                = "Epic"
L["Legendary"]                           = "Legendary"
L["Artifact"]                            = "Artifact"
L["Enchant"]                             = "Enchant"
L["Enchant (hidden)"]                    = "Enchant (hidden)"
L[" (hidden)"]                           = " (hidden)"
L[" (uncollected)"]                      = " (uncollected)"

-- =========================================================================
-- Doll column
-- =========================================================================
L["Reset"]                               = "Reset"
L["Reset view"]                          = "Reset view"
L["Outfits (v)"]                         = "Outfits (v)"
L["Save as Outfit"]                      = "Save as Outfit"
L["Delete Outfit"]                       = "Delete Outfit"
L["Apply Preview"]                       = "Apply Preview"
L["Reset Preview"]                       = "Reset Preview"
L["Server Sets (v)"]                     = "Server Sets (v)"
L["Save Server Set"]                     = "Save Server Set"
L["Delete Server Set"]                   = "Delete Server Set"
L["Background art"]                      = "Background art"
L["Hide applied items"]                  = "Hide applied items"
L["Show hidden items"]                   = "Show hidden items"

-- =========================================================================
-- Bottom bar
-- =========================================================================
L["Save Pending"]                        = "Save Pending"
L["Cancel Pending"]                      = "Cancel Pending"
L["Restore Original"]                    = "Restore Original"
L["Server Menu"]                         = "Server Menu"
L["Rescan"]                              = "Rescan"

-- =========================================================================
-- Status stamps
-- =========================================================================
L["No scan yet"]                         = "No scan yet"
L["Last scan: %dm ago  |  %d items in %s"] = "Last scan: %dm ago  |  %d items in %s"
L["Missing list empty -- populate Data/ItemsBySlot.lua to see uncollected items"] =
    "Missing list empty -- populate Data/ItemsBySlot.lua to see uncollected items"
L["Warming %d/%d"]                       = "Warming %d/%d"

-- =========================================================================
-- Row context menu (right-click on an item)
-- =========================================================================
L["Apply"]                               = "Apply"
L["Try On (preview)"]                    = "Try On (preview)"
L["Favourite"]                           = "Favourite"
L["Unfavourite"]                         = "Unfavourite"
L["Hide from List"]                      = "Hide from List"
L["Unhide (restore to list)"]            = "Unhide (restore to list)"
L["Cancel"]                              = "Cancel"
L["This appearance isn't in your collection yet -- Try On only."] =
    "This appearance isn't in your collection yet -- Try On only."

-- =========================================================================
-- Outfit / share popups
-- =========================================================================
L["Load"]                                = "Load"
L["Share"]                               = "Share"
L["Delete"]                              = "Delete"
L["Save"]                                = "Save"
L["Import"]                              = "Import"
L["Outfit name?"]                        = "Outfit name?"
L["Server set name?"]                    = "Server set name?"
L["Delete outfit '%s'?"]                 = "Delete outfit '%s'?"
L["Delete server set '%s'?"]             = "Delete server set '%s'?"
L["Delete this outfit?"]                 = "Delete this outfit?"
L["Delete this server set?"]             = "Delete this server set?"
L["(no outfits saved)"]                  = "(no outfits saved)"
L["(no server sets -- Save one first)"]  = "(no server sets -- Save one first)"

-- =========================================================================
-- Settings panel (v1.22)
-- =========================================================================
L["Filters & sort"]                      = "Filters & sort"
L["Visibility"]                          = "Visibility"
L["Behaviour"]                           = "Behaviour"
L["Recognised NPC names"]                = "Recognised NPC names"
L["Debug"]                               = "Debug"
L["Hide minimap button"]                 = "Hide minimap button"
L["Share favourites across all my characters"] = "Share favourites across all my characters"
L["Scan step delay (seconds)"]           = "Scan step delay (seconds)"
L["Verbose chat logging"]                = "Verbose chat logging"
L["Add"]                                 = "Add"
L["Remove"]                              = "Remove"

-- =========================================================================
-- Chat messages
-- =========================================================================
L["v%s by %s loaded. Talk to a Warpweaver to begin."] =
    "v%s by %s loaded. Talk to a Warpweaver to begin."
L["Talk to the Warpweaver first."]       = "Talk to the Warpweaver first."
L["Talk to the Warpweaver, then /wb rescan."] = "Talk to the Warpweaver, then /wb rescan."
L["All data reset. Reload with /reload."] = "All data reset. Reload with /reload."
L["Debug ON"]                            = "Debug ON"
L["Debug OFF"]                           = "Debug OFF"
L["Type /wb to return to Wardrobe (or just close gossip)."] =
    "Type /wb to return to Wardrobe (or just close gossip)."
L["Select an outfit from the dropdown first."] =
    "Select an outfit from the dropdown first."
L["Pick a set from the Server Sets dropdown first."] =
    "Pick a set from the Server Sets dropdown first."
L["Wardrobe scan complete -- %d appearances cached."] =
    "Wardrobe scan complete -- %d appearances cached."
L["Scanning %d slots..."]                = "Scanning %d slots..."
L["Scan aborted: %s"]                    = "Scan aborted: %s"

return L
