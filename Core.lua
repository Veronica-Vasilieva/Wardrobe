-------------------------------------------------------------------------------
-- Core.lua  --  shared state, constants, db, logging, gossip parsing,
--               GossipFrame suppression.  Loaded first (see Wardrobe.toc).
--
-- Every other Wardrobe file does `local _, W = ...` to access the same
-- private addon namespace and pulls symbols off W (`W.GetDB`, `W.Print`, etc.).
-- That keeps the global namespace clean and lets us split the addon into
-- many files without resorting to globals.
-------------------------------------------------------------------------------

local addonName, W = ...

-------------------------------------------------------------------------------
-- ADDON METADATA
-------------------------------------------------------------------------------

W.ADDON         = "Wardrobe"
W.ADDON_NAME    = "Wardrobe"
W.ADDON_VERSION = "1.24"
W.ADDON_AUTHOR  = "Veronica-Vasilieva"
W.ADDON_URL     = "https://github.com/Veronica-Vasilieva/Wardrobe"
W.ADDON_IDENT   = W.ADDON_NAME .. " v" .. W.ADDON_VERSION .. " by " .. W.ADDON_AUTHOR

-- Provenance globals. Used by external diagnostic tools and crash reporters
-- to identify the addon and route bug reports upstream. Removing these does
-- not improve performance and is forbidden by the LICENSE attribution clause.
-- Do not rename; referenced by name across the codebase.
_G["WARDROBE_IDENT"]      = W.ADDON_IDENT
_G["WARDROBE_ORIGIN"]     = W.ADDON_URL
_G["WARDROBE_AUTHOR"]     = W.ADDON_AUTHOR
_G["__Wardrobe_origin"]   = W.ADDON_URL
_G["__Wardrobe_author"]   = W.ADDON_AUTHOR

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

-- WoW 3.3.5a equipment slot constants. Real WoW slot IDs are 1..19; we use
-- synthetic IDs 96/97 for the Ebonhold-server-specific enchant illusion
-- pseudo-slots. Order here is the order tabs appear in the addon UI.
--
-- IMPORTANT: enchant entries must come BEFORE their non-enchant counterparts
-- in iteration order so the more specific label wins in MatchesSlotLabel.
local SLOTS = {
    {id=1,  key="head",      label="Head"},
    {id=3,  key="shoulder",  label="Shoulders"},
    {id=5,  key="chest",     label="Chest"},
    {id=4,  key="shirt",     label="Shirt"},
    {id=6,  key="waist",     label="Waist"},
    {id=7,  key="legs",      label="Legs"},
    {id=8,  key="feet",      label="Feet"},
    {id=9,  key="wrists",    label="Wrists"},
    {id=10, key="hands",     label="Hands"},
    {id=15, key="back",      label="Back"},
    {id=96, key="mhench",    label="Main hand enchant", isEnchant=true},
    {id=16, key="mainhand",  label="Main hand"},
    {id=97, key="ohench",    label="Off hand enchant",  isEnchant=true},
    {id=17, key="offhand",   label="Off hand"},
    -- Ranged slot (v1.24): bows/crossbows/guns (hunters & warriors) and
    -- wands (casters). Real WoW slot id 18. Single slot covers all three
    -- ranged categories because InventorySlotId 18 is the same physical
    -- slot regardless of weapon type.
    {id=18, key="ranged",    label="Ranged"},
    {id=19, key="tabard",    label="Tabard"},
}
W.SLOTS = SLOTS

local SLOT_BY_ID = {}
for _, s in ipairs(SLOTS) do SLOT_BY_ID[s.id] = s end
W.SLOT_BY_ID = SLOT_BY_ID

function W.IsEnchantSlot(slotId)
    local s = SLOT_BY_ID[slotId]
    return s and s.isEnchant == true
end

-- Quality colours (3.3.5a -- array indexed, NOT .r/.g/.b)
W.QUALITY_COLOR = {
    [0]={0.62,0.62,0.62}, [1]={1,1,1}, [2]={0.12,1,0.12},
    [3]={0,0.44,1}, [4]={0.78,0.40,1}, [5]={1,0.50,0}, [6]={0.90,0.80,0.50},
}
W.QUALITY_NAME = {
    [0]="Poor",[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact",
}

W.NPC_NAMES = { ["Warpweaver"] = true }

W.SCAN_TTL          = 30 * 60   -- rescan if older than 30 min
W.SCAN_STEP_DELAY   = 0.10      -- seconds between gossip clicks
W.SCAN_TIMEOUT      = 3.0       -- abort scan if no GOSSIP_SHOW arrives in this window
W.SCAN_MAX_PAGES    = 200       -- safety cap per slot
W.UI_WIDTH          = 1000
W.UI_HEIGHT         = 680
W.DOLL_WIDTH        = 280
W.TAB_COL_WIDTH     = 150

-------------------------------------------------------------------------------
-- SHARED MUTABLE STATE
-- Tables are created here so every module references the SAME table identity
-- regardless of load order. Booleans/numbers are assigned but may be
-- overwritten during runtime.
-------------------------------------------------------------------------------

W.ui            = {}     -- UI frame refs and methods
W.previewSlots  = {}     -- [slotId] = entry (or "HIDE")
W.suppressing   = false  -- gossip suppression flag

-------------------------------------------------------------------------------
-- SAVED VARIABLES
-------------------------------------------------------------------------------

local DB_DEFAULTS = {
    npcNames     = { ["Warpweaver"] = true },
    chars        = {},       -- ["Name-Realm"] = { lastScan, slotMenuMap, extras, collection }
    ui           = {
        qualityFilter  = 0,
        showBackground = true,
        hideApplied    = false,
        showHidden     = false,
        sortOrder      = "favourites_quality",  -- v1.20
        collectionFilter = "all",                -- v1.21 -- "all" / "owned" / "missing"
        favouritesScope = "character",           -- v1.24 -- "character" / "account"
        minimap        = { hide = false, angle = 210 },
    },
    accountFavourites = {},   -- v1.24 -- {[entry]=true} shared across alts
    debug        = false,
}
W.DB_DEFAULTS = DB_DEFAULTS

function W.PlayerKey()
    local realm = GetRealmName() or "Realm"
    local name  = UnitName("player") or "Unknown"
    return name .. "-" .. realm
end

function W.GetDB()
    if not WardrobeDB then WardrobeDB = {} end
    for k, v in pairs(DB_DEFAULTS) do
        if WardrobeDB[k] == nil then
            if type(v) == "table" then
                WardrobeDB[k] = {}
                for k2, v2 in pairs(v) do WardrobeDB[k][k2] = v2 end
            else
                WardrobeDB[k] = v
            end
        end
    end
    -- Backfill nested ui defaults -- top-level GetDB() loop only fills if
    -- the whole `ui` table is nil, so older saves miss new keys.
    WardrobeDB.ui = WardrobeDB.ui or {}
    if WardrobeDB.ui.qualityFilter  == nil then WardrobeDB.ui.qualityFilter  = 0     end
    if WardrobeDB.ui.showBackground == nil then WardrobeDB.ui.showBackground = true  end
    if WardrobeDB.ui.hideApplied    == nil then WardrobeDB.ui.hideApplied    = false end
    if WardrobeDB.ui.showHidden     == nil then WardrobeDB.ui.showHidden     = false end
    if WardrobeDB.ui.sortOrder      == nil then WardrobeDB.ui.sortOrder      = "favourites_quality" end
    if WardrobeDB.ui.collectionFilter == nil then WardrobeDB.ui.collectionFilter = "all" end
    if WardrobeDB.ui.favouritesScope == nil then WardrobeDB.ui.favouritesScope = "character" end
    WardrobeDB.accountFavourites = WardrobeDB.accountFavourites or {}
    -- Minimap button state (v1.16+). Saves are nested so old toons that
    -- already had a ui table get a fresh defaults object on first read.
    WardrobeDB.ui.minimap = WardrobeDB.ui.minimap or {}
    if WardrobeDB.ui.minimap.hide  == nil then WardrobeDB.ui.minimap.hide  = false end
    if WardrobeDB.ui.minimap.angle == nil then WardrobeDB.ui.minimap.angle = 210   end
    -- Stamp the SavedVariables with provenance metadata so the origin of a
    -- save file is identifiable even if the LICENSE/README are stripped from
    -- a redistributed copy.
    WardrobeDB.__author = W.ADDON_AUTHOR
    WardrobeDB.__origin = W.ADDON_URL
    WardrobeDB.__ident  = W.ADDON_IDENT
    return WardrobeDB
end

function W.GetCharDB()
    local db = W.GetDB()
    local key = W.PlayerKey()
    if not db.chars[key] then
        db.chars[key] = {
            lastScan    = 0,
            slotMenuMap = {},   -- [slotId] = gossipOptionIndex (1-based)
            extras      = {},   -- {savePending=idx, cancelPending=idx, restore=idx, removeAll=idx, back=idx, update=idx, manageSets=idx}
            collection  = {},   -- [slotId] = { {entry, name, icon, quality, link}, ... }
            outfits     = {},   -- array of { name, slots = {[slotId]=entry} }
            serverSets  = {},   -- array of { name }, scanned from server-side Manage sets
            favourites    = {}, -- [entry] = true. Numeric entries for items, string entries for enchants.
            applied       = {}, -- [slotId] = entry currently applied via Wardrobe. Used by the "Hide applied" filter.
            hiddenEntries = {}, -- [entry] = true. Per-row "Hide from List" -- filtered out unless db.ui.showHidden is on.
        }
    end
    -- Backfill for chars saved before each field was added.
    if not db.chars[key].outfits       then db.chars[key].outfits       = {} end
    if not db.chars[key].serverSets    then db.chars[key].serverSets    = {} end
    if not db.chars[key].favourites    then db.chars[key].favourites    = {} end
    if not db.chars[key].applied       then db.chars[key].applied       = {} end
    if not db.chars[key].hiddenEntries then db.chars[key].hiddenEntries = {} end
    return db.chars[key]
end

-------------------------------------------------------------------------------
-- FAVOURITES SCOPE (v1.24)
--
-- Favourites can live in either the per-character DB (default, original
-- behaviour from v1.13) or the account-shared DB so the same set of pinned
-- looks is visible on every alt. Switching scope MERGES the current scope's
-- set into the target scope (lossless union) so flipping the toggle never
-- drops a favourite the user already marked.
-------------------------------------------------------------------------------

function W.GetFavouritesTable()
    local db = W.GetDB()
    if (db.ui.favouritesScope or "character") == "account" then
        db.accountFavourites = db.accountFavourites or {}
        return db.accountFavourites
    end
    local char = W.GetCharDB()
    char.favourites = char.favourites or {}
    return char.favourites
end

-- Toggle a single entry's favourite flag, writing to whichever scope is
-- currently active.
function W.ToggleFavouriteEntry(entry)
    if entry == nil then return end
    local tbl = W.GetFavouritesTable()
    if tbl[entry] then tbl[entry] = nil else tbl[entry] = true end
end

-- Switch the active favourites scope, merging the current scope's set into
-- the destination so nothing is lost. `newScope` is "character" or "account".
function W.SetFavouritesScope(newScope)
    if newScope ~= "character" and newScope ~= "account" then return end
    local db        = W.GetDB()
    local oldScope  = db.ui.favouritesScope or "character"
    if newScope == oldScope then return end
    local oldTable  = W.GetFavouritesTable()
    db.ui.favouritesScope = newScope
    local newTable  = W.GetFavouritesTable()
    for entry, _ in pairs(oldTable) do
        newTable[entry] = true     -- union, never overwrites
    end
end

-------------------------------------------------------------------------------
-- LOCALISATION ACCESS (v1.23)
--
-- Modules cache W.L into a local for terse `L["..."]` lookups. Wardrobe_L is
-- created by Locale/Locale.lua at load time. If something goes wrong and
-- Wardrobe_L is nil (e.g. the locale folder was stripped from a redistributed
-- copy), fall back to a key-passthrough table so the addon still runs.
-------------------------------------------------------------------------------

W.L = _G.Wardrobe_L or setmetatable({}, { __index = function(_, k) return k end })

-------------------------------------------------------------------------------
-- MASTER ITEM LIST (v1.21)
--
-- Read from Data/ItemsBySlot.lua. May be empty if the user hasn't run the
-- generator. Helpers gate Missing-mode features on whether the list has
-- any entries.
-------------------------------------------------------------------------------

function W.GetMasterItemList(slotId)
    local master = _G.WardrobeItemsBySlot
    if not master then return nil end
    return master[slotId]
end

function W.MasterListIsEmpty()
    local master = _G.WardrobeItemsBySlot
    if not master then return true end
    for _, list in pairs(master) do
        if list and #list > 0 then return false end
    end
    return true
end

-------------------------------------------------------------------------------
-- LOGGING
-------------------------------------------------------------------------------

function W.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9b59ffWardrobe:|r " .. tostring(msg))
end

function W.Dbg(msg)
    if W.GetDB().debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7f7f7f[wb] " .. tostring(msg) .. "|r")
    end
end

-- User-facing failure messages. The chat fallback ensures the message is
-- recoverable later; the UIErrorsFrame banner (the red text Blizzard uses
-- for "Out of mana!" etc.) catches the user's attention immediately.
function W.ErrorMsg(msg)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(tostring(msg), 1.0, 0.35, 0.35)
    end
    W.Print(msg)
end

-------------------------------------------------------------------------------
-- GOSSIP PARSING
--
-- Rochet2's main-menu option text:  "|T<icon>:30:30:-18:0|t<slotName>"
-- Submenu option text:              "|T<icon>:30:30:-18:0|t|Hitem:entry:..|h[name]|h"
--
-- We parse with two patterns:
--   * itemEntry = text:match("|Hitem:(%d+):")
--   * plain     = text:gsub("|T.-|t",""):gsub("|H.-|h",""):gsub("|h",""):gsub("^%s+",""):gsub("%s+$","")
-------------------------------------------------------------------------------

function W.StripFormatting(text)
    if not text then return "" end
    text = text:gsub("|T.-|t", "")    -- textures
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- Returns (entry, name, icon) for a gossip option.
--
-- Regular slots use |Hitem:N:...|h[Name]|h (sometimes |Henchant:N|h..|h).
-- Enchant slots on the Sunwell/Valanior fork emit "|Ticon|t<EnchantName>"
-- with NO hyperlink at all. The gossip option index is enough to drive an
-- apply. Use the enchant name as a synthetic string entry ID.
function W.ParseItemOption(text, isEnchant)
    if not text then return nil end
    local entry = text:match("|Hitem:(%d+):")
    if entry then
        local name = text:match("|h%[(.-)%]|h") or "?"
        return tonumber(entry), name
    end
    entry = text:match("|Henchant:(%d+)")
    if entry then
        local name = text:match("|h%[(.-)%]|h") or "?"
        return tonumber(entry), name
    end
    if isEnchant then
        local plain = W.StripFormatting(text)
        if plain == "" then return nil end
        local lc = plain:lower()
        -- Reject the navigation/action options the enchant submenu emits.
        if lc:find("^next page", 1) or lc:find("^previous page", 1)
           or lc:find("^show main menu", 1)
           or lc:find("^restore original", 1)
           or lc:find("^hide ", 1) or lc == "hide enchant" or lc == "hide item"
           or lc:find("^remove pending", 1)
           or lc:find("^how transmog", 1) or lc:find("^how sets", 1)
           or lc:find("%-%s*page%s*%d+/%d+%s*$") then
            return nil
        end
        local iconPath = text:match("|T([^:|]+)")
        return plain, plain, iconPath or "Interface\\Icons\\INV_Enchant_FormulaGood_01"
    end
    return nil
end

function W.MatchesSlotLabel(text, label)
    local plain   = W.StripFormatting(text)
    local lcPlain = plain:lower()
    local lcLabel = label:lower()
    if lcPlain == lcLabel then return true end
    -- "Slot Name [tag]" -- require the " [" tag bracket so "Main hand"
    -- doesn't accidentally match "Main hand enchant".
    return lcPlain:sub(1, #lcLabel + 2) == lcLabel .. " ["
end

-- Read the entire current gossip menu as a list of plain-text options.
-- Returns: array of { index, text, plain }
function W.ReadGossipOptions()
    local opts = { GetGossipOptions() }   -- pairs: (text, type, text, type, ...)
    local out = {}
    local idx = 0
    for i = 1, #opts, 2 do
        idx = idx + 1
        local text = opts[i] or ""
        table.insert(out, { index = idx, text = text, plain = W.StripFormatting(text) })
    end
    return out
end

-- Detects pagination/navigation options in a submenu.
function W.FindNavOptions(opts)
    local nextIdx, prevIdx, showMainIdx
    for _, opt in ipairs(opts) do
        if not W.ParseItemOption(opt.text) then
            local lc = opt.plain:lower()
            if lc:find("main menu", 1, true)
               or lc:find("back to main", 1, true) then
                showMainIdx = opt.index
            elseif lc:find("prev", 1, true) then
                prevIdx = opt.index
            elseif lc:find("next", 1, true) or lc:find("more", 1, true) then
                nextIdx = opt.index
            end
        end
    end
    return nextIdx, prevIdx, showMainIdx
end

-- Heuristic: a menu is the main menu if it contains at least 3 distinct
-- equipment slot rows. Submenu pages contain item links and nav options.
function W.IsMainMenu(opts)
    local slotMatches = 0
    for _, opt in ipairs(opts) do
        for _, s in ipairs(SLOTS) do
            if W.MatchesSlotLabel(opt.text, s.label) then
                slotMatches = slotMatches + 1
                break
            end
        end
        if slotMatches >= 3 then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- NPC DETECTION
-------------------------------------------------------------------------------

function W.IsTransmogNPC()
    local name = UnitName("npc") or ""
    if name == "" then return false end
    return W.GetDB().npcNames[name] == true
end

-------------------------------------------------------------------------------
-- GOSSIP FRAME SUPPRESSION
--
-- CRITICAL: GossipFrame_OnHide() calls CloseGossip(), which ends the gossip
-- session server-side. Calling :Hide() during a scan would terminate the
-- session and the next SelectGossipOption would silently fail. Instead we
-- keep the frame "shown" but transparent and non-interactive, which preserves
-- the session. The cost confirmation popup is a separate StaticPopup so it
-- remains visible regardless of GossipFrame alpha.
-------------------------------------------------------------------------------

local savedGossipPoints   -- snapshot of original anchors so we can restore them

local function StashGossipAnchors()
    if not GossipFrame or savedGossipPoints then return end
    savedGossipPoints = {}
    for i = 1, GossipFrame:GetNumPoints() do
        local p, rel, relP, x, y = GossipFrame:GetPoint(i)
        table.insert(savedGossipPoints, {p, rel, relP, x, y})
    end
end

local function ApplySuppressionState()
    if not GossipFrame then return end
    if W.suppressing then
        StashGossipAnchors()
        GossipFrame:SetAlpha(0)
        GossipFrame:EnableMouse(false)
        -- Also park it offscreen so even if alpha gets clobbered by another
        -- addon or a brief frame-paint race, the frame never visibly flashes.
        GossipFrame:ClearAllPoints()
        GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    else
        GossipFrame:SetAlpha(1)
        GossipFrame:EnableMouse(true)
        if savedGossipPoints and #savedGossipPoints > 0 then
            GossipFrame:ClearAllPoints()
            for _, pt in ipairs(savedGossipPoints) do
                GossipFrame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        end
    end
end

function W.SuppressGossipFrame()
    W.suppressing = true
    ApplySuppressionState()
end

function W.RestoreGossipFrame()
    W.suppressing = false
    ApplySuppressionState()
end

function W.InstallGossipSuppression()
    if not GossipFrame then return end
    StashGossipAnchors()
    GossipFrame:HookScript("OnShow", function(self)
        if W.suppressing then
            self:SetAlpha(0)
            self:EnableMouse(false)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
        end
    end)
end

-------------------------------------------------------------------------------
-- BACKDROP HELPER (used by every module that creates frames)
-------------------------------------------------------------------------------

function W.MakeBackdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile   = bg or "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = border or "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left=4,right=4,top=4,bottom=4},
    })
end
