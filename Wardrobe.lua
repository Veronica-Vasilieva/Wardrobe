-------------------------------------------------------------------------------
-- Wardrobe  v1.4
-- Copyright (c) 2026 Veronica-Vasilieva and the Wardrobe contributors.
-- Released under the Wardrobe Source-Available License — see LICENSE.
-- Project home: https://github.com/Veronica-Vasilieva/Wardrobe
--
-- Interactive transmog browser for Project Ebonhold's Warpweaver NPC.
-- Replaces the gossip-menu paging UI with a searchable per-slot wardrobe.
--
-- v0.1 scope:
--   * Detect Warpweaver gossip
--   * Async scan: walk each equipment slot's gossip submenu and cache the
--     player's appearance collection (entry, name, quality, icon) per slot
--   * Per-character cache keyed by name-realm; account-wide SavedVariables
--   * Searchable list per slot with quality filter
--   * Single-click apply via gossip driver (cost popup passed through)
--   * /wardrobe slash command, /wb alias
--
-- Slash commands: /wardrobe  /wb  /wb rescan  /wb reset  /wb debug
-------------------------------------------------------------------------------

local ADDON         = "Wardrobe"
local ADDON_NAME    = "Wardrobe"
local ADDON_VERSION = "1.4"
local ADDON_AUTHOR  = "Veronica-Vasilieva"
local ADDON_URL     = "https://github.com/Veronica-Vasilieva/Wardrobe"
local ADDON_IDENT   = ADDON_NAME .. " v" .. ADDON_VERSION .. " by " .. ADDON_AUTHOR

-- Provenance globals. Used by external diagnostic tools and crash reporters
-- to identify the addon and route bug reports upstream. Removing these does
-- not improve performance and is forbidden by the LICENSE attribution clause.
-- Do not rename; referenced by name across the codebase.
_G["WARDROBE_IDENT"]      = ADDON_IDENT
_G["WARDROBE_ORIGIN"]     = ADDON_URL
_G["WARDROBE_AUTHOR"]     = ADDON_AUTHOR
_G["__Wardrobe_origin"]   = ADDON_URL
_G["__Wardrobe_author"]   = ADDON_AUTHOR

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

-- WoW 3.3.5a equipment slot constants. Real WoW slot IDs are 1..19; we use
-- synthetic IDs 96/97 for the Ebonhold-server-specific enchant illusion
-- pseudo-slots. Order here is the order tabs appear in the addon UI.
--
-- IMPORTANT: enchant entries must come BEFORE their non-enchant counterparts
-- in iteration order so the more specific label wins in MatchesSlotLabel.
-- (We've also relaxed the old "exclude rows containing 'enchant'" rule —
-- the strict " [" suffix requirement already prevents "Main hand enchant"
-- from matching the "Main hand" label.)
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
    {id=19, key="tabard",    label="Tabard"},
}
local SLOT_BY_ID = {}
for _, s in ipairs(SLOTS) do SLOT_BY_ID[s.id] = s end

local function IsEnchantSlot(slotId)
    local s = SLOT_BY_ID[slotId]
    return s and s.isEnchant == true
end

-- Quality colours (3.3.5a — array indexed, NOT .r/.g/.b)
local QUALITY_COLOR = {
    [0]={0.62,0.62,0.62}, [1]={1,1,1}, [2]={0.12,1,0.12},
    [3]={0,0.44,1}, [4]={0.78,0.40,1}, [5]={1,0.50,0}, [6]={0.90,0.80,0.50},
}
local QUALITY_NAME = {
    [0]="Poor",[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact",
}

local NPC_NAMES = { ["Warpweaver"] = true }  -- extensible via /wb npcname

-- Forward declarations for locals defined further down the file but
-- referenced by closures earlier in the file. Without these, the references
-- fall through to globals (which are nil) and silently error at call time.
local BuildWarmQueue
local WarmingActive
local WarmTick

local SCAN_TTL          = 30 * 60   -- rescan if older than 30 min
local SCAN_STEP_DELAY   = 0.10      -- seconds between gossip clicks
local SCAN_TIMEOUT      = 3.0       -- abort scan if no GOSSIP_SHOW arrives in this window
local SCAN_MAX_PAGES    = 200       -- safety cap per slot
local UI_WIDTH          = 1000
local UI_HEIGHT         = 680
local DOLL_WIDTH        = 280
local TAB_COL_WIDTH     = 150

-------------------------------------------------------------------------------
-- SAVED VARIABLES
-------------------------------------------------------------------------------

local DB_DEFAULTS = {
    npcNames     = { ["Warpweaver"] = true },
    chars        = {},       -- ["Name-Realm"] = { lastScan, slotMenuMap, extras, collection }
    ui           = { qualityFilter = 0 },
    debug        = false,
}

local function PlayerKey()
    local realm = GetRealmName() or "Realm"
    local name  = UnitName("player") or "Unknown"
    return name .. "-" .. realm
end

local function GetDB()
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
    -- Stamp the SavedVariables with provenance metadata so the origin of a
    -- save file is identifiable even if the LICENSE/README are stripped from
    -- a redistributed copy.
    WardrobeDB.__author = ADDON_AUTHOR
    WardrobeDB.__origin = ADDON_URL
    WardrobeDB.__ident  = ADDON_IDENT
    return WardrobeDB
end

local function GetCharDB()
    local db = GetDB()
    local key = PlayerKey()
    if not db.chars[key] then
        db.chars[key] = {
            lastScan    = 0,
            slotMenuMap = {},   -- [slotId] = gossipOptionIndex (1-based)
            extras      = {},   -- {savePending=idx, cancelPending=idx, restore=idx, removeAll=idx, back=idx, update=idx, manageSets=idx}
            collection  = {},   -- [slotId] = { {entry, name, icon, quality, link}, ... }
            outfits     = {},   -- array of { name, slots = {[slotId]=entry} }
            serverSets  = {},   -- array of { name }, scanned from server-side Manage sets
        }
    end
    -- Backfill for chars saved before outfits/serverSets existed.
    if not db.chars[key].outfits    then db.chars[key].outfits    = {} end
    if not db.chars[key].serverSets then db.chars[key].serverSets = {} end
    return db.chars[key]
end

-------------------------------------------------------------------------------
-- LOGGING
-------------------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9b59ffWardrobe:|r " .. tostring(msg))
end

local function Dbg(msg)
    if GetDB().debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7f7f7f[wb] " .. tostring(msg) .. "|r")
    end
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

local function StripFormatting(text)
    if not text then return "" end
    text = text:gsub("|T.-|t", "")    -- textures
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- Returns (entry, name) for a gossip option that wraps an item OR an enchant
-- illusion hyperlink. Enchant illusion slots on the customized server may
-- emit |Henchant:N|h..|h instead of |Hitem:N:|h..|h; we try both. Anything
-- else returns nil so callers know it's a nav/action option, not an entry.
local function ParseItemOption(text)
    if not text then return nil end
    local entry = text:match("|Hitem:(%d+):")
    if not entry then
        entry = text:match("|Henchant:(%d+)")
    end
    if not entry then return nil end
    local name = text:match("|h%[(.-)%]|h") or "?"
    return tonumber(entry), name
end

local function MatchesSlotLabel(text, label)
    local plain   = StripFormatting(text)
    local lcPlain = plain:lower()
    local lcLabel = label:lower()
    if lcPlain == lcLabel then return true end
    -- "Slot Name [tag]" — require the " [" tag bracket so "Main hand"
    -- doesn't accidentally match "Main hand enchant" (the SLOTS table is
    -- ordered with enchant entries before their non-enchant counterparts,
    -- so the more specific label wins on a first-match-and-break iteration).
    return lcPlain:sub(1, #lcLabel + 2) == lcLabel .. " ["
end

-- Read the entire current gossip menu as a list of plain-text options.
-- Returns: array of { index, text, plain }
local function ReadGossipOptions()
    local opts = { GetGossipOptions() }   -- pairs: (text, type, text, type, ...)
    local out = {}
    local idx = 0
    for i = 1, #opts, 2 do
        idx = idx + 1
        local text = opts[i] or ""
        table.insert(out, { index = idx, text = text, plain = StripFormatting(text) })
    end
    return out
end

-------------------------------------------------------------------------------
-- NPC DETECTION
-------------------------------------------------------------------------------

local function IsTransmogNPC()
    local name = UnitName("npc") or ""
    if name == "" then return false end
    return GetDB().npcNames[name] == true
end

-------------------------------------------------------------------------------
-- SCAN ENGINE — async state machine driven by GOSSIP_SHOW events
--
-- States:
--   idle              — not scanning
--   reading_main      — captured main menu, planning scan
--   scanning_slot     — clicked into a slot submenu, waiting for GOSSIP_SHOW
--   returning_main    — clicked Back, waiting for main menu to reappear
--   done              — scan finished, UI ready
--
-- The default GossipFrame is suppressed while scanning. We never call
-- CloseGossip during a scan because that ends the gossip session server-side.
-------------------------------------------------------------------------------

local scanState = {
    active        = false,
    phase         = "idle",
    queue         = {},        -- list of slot ids left to scan
    currentSlot   = nil,
    pageCount     = 0,         -- how many pages we've captured for currentSlot
    seenEntries   = nil,       -- set of entry ids already captured for currentSlot
    scannedSets   = false,     -- have we done the server-sets pass yet?
    timeoutAt     = 0,
}

local function ResetScan()
    scanState.active      = false
    scanState.phase       = "idle"
    scanState.queue       = {}
    scanState.currentSlot = nil
    scanState.pageCount   = 0
    scanState.seenEntries = nil
    scanState.scannedSets = false
    scanState.timeoutAt   = 0
end

-- Identify special menu entries by their plain text.
local EXTRA_PATTERNS = {
    savePending   = {"save pending"},
    cancelPending = {"cancel pending"},
    restore       = {"restore original"},
    removeAll     = {"remove all transmog"},
    update        = {"update menu"},
    back          = {"back"},
    info          = {"how transmog", "how transmogrification"},
    manageSets    = {"manage sets"},
}

local function ClassifyMainMenu()
    local char  = GetCharDB()
    local opts  = ReadGossipOptions()
    char.slotMenuMap = {}
    char.extras      = {}
    for _, opt in ipairs(opts) do
        local lc = opt.plain:lower()
        -- slot row?
        local matched = false
        for _, s in ipairs(SLOTS) do
            if MatchesSlotLabel(opt.text, s.label) then
                char.slotMenuMap[s.id] = opt.index
                matched = true
                break
            end
        end
        if not matched then
            for key, patterns in pairs(EXTRA_PATTERNS) do
                for _, pat in ipairs(patterns) do
                    if lc:find(pat, 1, true) then
                        char.extras[key] = opt.index
                        break
                    end
                end
            end
        end
    end
    Dbg("main menu: " .. #opts .. " options, " .. (function()
        local n=0 for _ in pairs(char.slotMenuMap) do n=n+1 end return n
    end)() .. " slot rows matched")
end

-- Detects pagination/navigation options in a submenu.
--
-- Confirmed structure on the Ebonhold Warpweaver (from in-game screenshots):
--   Page 1:        "<Slot> - Page 1/N", "Next page", "Show main menu",
--                  "Restore original look", "Hide item",
--                  "Remove pending transmogrification", <items>
--   Page 2..N-1:   "<Slot> - Page X/N", "Next page", "Previous page", <items>
--   Last page:     "<Slot> - Page N/N", "Previous page", <items>
--
-- So the only way back to main is "Show main menu" on page 1. We walk
-- Previous until that option appears, then click it.
local function FindNavOptions(opts)
    local nextIdx, prevIdx, showMainIdx
    for _, opt in ipairs(opts) do
        if not ParseItemOption(opt.text) then
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
local function IsMainMenu(opts)
    local slotMatches = 0
    for _, opt in ipairs(opts) do
        for _, s in ipairs(SLOTS) do
            if MatchesSlotLabel(opt.text, s.label) then
                slotMatches = slotMatches + 1
                break
            end
        end
        if slotMatches >= 3 then return true end
    end
    return false
end

-- Capture items on the current page into char.collection[slotId]. Caller passes
-- isFirstPage=true on the first page of a slot so we reset the entry list and
-- the dedup set. Returns nextIdx, prevIdx so the state machine can advance.
local function CaptureSlotItems(slotId, isFirstPage, opts)
    local char = GetCharDB()
    if isFirstPage then
        char.collection[slotId] = {}
        scanState.seenEntries   = {}
        scanState.pageCount     = 0
    end
    local items       = char.collection[slotId]
    local seen        = scanState.seenEntries
    opts = opts or ReadGossipOptions()
    local newOnPage   = 0
    for _, opt in ipairs(opts) do
        local entry, name = ParseItemOption(opt.text)
        if entry and not seen[entry] then
            seen[entry] = true
            local _, link, quality, _, _, _, _, _, _, icon = GetItemInfo(entry)
            table.insert(items, {
                entry    = entry,
                name     = name,
                link     = link,
                quality  = quality or 1,
                icon     = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                resolved = (link ~= nil),
            })
            newOnPage = newOnPage + 1
        end
    end
    scanState.pageCount = scanState.pageCount + 1
    local nextIdx, prevIdx, showMainIdx = FindNavOptions(opts)
    Dbg(string.format("slot %d page %d: +%d items (total %d)%s%s%s",
        slotId, scanState.pageCount, newOnPage, #items,
        nextIdx and " [next]" or "", prevIdx and " [prev]" or "",
        showMainIdx and " [main]" or ""))
    -- Safety: if a page contributed zero new items, treat as end of list even
    -- if a "next" option still exists (prevents infinite loop on a malformed menu).
    if newOnPage == 0 and scanState.pageCount > 1 then
        nextIdx = nil
    end
    if scanState.pageCount >= SCAN_MAX_PAGES then
        nextIdx = nil
    end
    return nextIdx, prevIdx, showMainIdx
end

-- Forward declarations
local SuppressGossipFrame, RestoreGossipFrame, ShowWardrobeUI

local function FinishScan()
    local char = GetCharDB()
    char.lastScan = time()
    local total = 0
    for _, items in pairs(char.collection) do total = total + #items end
    ResetScan()
    Print(string.format("Wardrobe scan complete — %d appearances cached.", total))
    -- ShowWardrobeUI internally invokes BuildWarmQueue, so no separate call
    -- here. (Adding a redundant call also broke previously because the
    -- closure couldn't resolve BuildWarmQueue defined further down.)
    ShowWardrobeUI()
end

local function AbortScan(reason)
    Print("Scan aborted: " .. tostring(reason))
    ResetScan()
    RestoreGossipFrame()
end

-- Driver: schedules the next gossip click after SCAN_STEP_DELAY.
local scanDriver = CreateFrame("Frame")
scanDriver:Hide()
scanDriver:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if scanState.timeoutAt > 0 and GetTime() > scanState.timeoutAt then
        AbortScan("timed out waiting for gossip response")
        self:Hide()
        return
    end
    if self.t < SCAN_STEP_DELAY then return end
    self.t = 0
    if self.pendingAction then
        local action = self.pendingAction
        self.pendingAction = nil
        scanState.timeoutAt = GetTime() + SCAN_TIMEOUT
        action()
    end
end)

local function ScheduleClick(fn)
    scanDriver.t = 0
    scanDriver.pendingAction = fn
    scanDriver:Show()
end

local function ScanNextSlot()
    local char = GetCharDB()
    if #scanState.queue == 0 then
        -- All slots done — detour into Manage sets to scan server-side
        -- set names before finishing.
        if not scanState.scannedSets and char.extras.manageSets then
            scanState.scannedSets = true
            scanState.phase       = "scanning_sets_entering"
            scanState.currentSlot = nil
            local optIdx = char.extras.manageSets
            ScheduleClick(function()
                Dbg("clicking Manage sets (opt " .. optIdx .. ")")
                SelectGossipOption(optIdx)
            end)
            return
        end
        scanDriver:Hide()
        FinishScan()
        return
    end
    local slotId = table.remove(scanState.queue, 1)
    local optIdx = char.slotMenuMap[slotId]
    if not optIdx then
        Dbg("no menu mapping for slot " .. slotId .. " — skipping")
        ScanNextSlot()
        return
    end
    scanState.currentSlot = slotId
    scanState.pageCount   = 0
    scanState.seenEntries = {}
    scanState.phase       = "scanning_slot_first"
    ScheduleClick(function()
        Dbg("clicking into slot " .. slotId .. " (opt " .. optIdx .. ")")
        SelectGossipOption(optIdx)
    end)
end

-- Decide and schedule the next click needed to return to the main menu.
-- Prefer "Show main menu" (only on page 1); fall back to walking Previous
-- one page at a time. Returns true if a click was scheduled, false if we're
-- stuck (caller should save partial progress).
local function ReturnToMainStep(opts)
    local _, prevIdx, showMainIdx = FindNavOptions(opts)
    if showMainIdx then
        ScheduleClick(function()
            Dbg("clicking Show main menu (opt " .. showMainIdx .. ")")
            SelectGossipOption(showMainIdx)
        end)
        return true
    end
    if prevIdx then
        ScheduleClick(function()
            Dbg("walking back via Previous (opt " .. prevIdx .. ")")
            SelectGossipOption(prevIdx)
        end)
        return true
    end
    return false
end

local function StartScan()
    if scanState.active then return end
    scanState.active = true
    scanState.phase  = "reading_main"
    ClassifyMainMenu()
    local char = GetCharDB()
    scanState.queue = {}
    for _, s in ipairs(SLOTS) do
        if char.slotMenuMap[s.id] then
            table.insert(scanState.queue, s.id)
        end
    end
    if #scanState.queue == 0 then
        AbortScan("no recognisable slot rows in gossip menu")
        return
    end
    Print("Scanning " .. #scanState.queue .. " slots…")
    SuppressGossipFrame()
    ScanNextSlot()
end

-- Saves whatever we've captured so far and ends the scan without losing
-- progress. Used when we can't navigate back to main (no Previous option) or
-- when gossip closes unexpectedly.
local function FinishPartialScan(reason)
    local char = GetCharDB()
    char.lastScan = time()
    local total, slotsHit = 0, 0
    for _, items in pairs(char.collection) do
        total = total + #items
        if #items > 0 then slotsHit = slotsHit + 1 end
    end
    Print(string.format("Scan ended early (%s) — %d appearances cached across %d slots.",
        reason, total, slotsHit))
    ResetScan()
    ShowWardrobeUI()
end

-- Called from GOSSIP_SHOW handler when a scan is in progress.
local function OnGossipShowDuringScan()
    scanState.timeoutAt = 0
    local opts = ReadGossipOptions()

    -- Verbose dump: with /wb debug on, log every option per page so we can
    -- see exactly what the server is sending.
    if GetDB().debug then
        Dbg(string.format("=== GOSSIP_SHOW phase=%s slot=%s opts=%d ===",
            scanState.phase, tostring(scanState.currentSlot), #opts))
        for _, opt in ipairs(opts) do
            Dbg(string.format("  [%d] %s", opt.index, opt.plain))
        end
    end

    if scanState.phase == "scanning_slot_first" or scanState.phase == "scanning_slot_more" then
        if not scanState.currentSlot then return end
        -- If we accidentally landed at main (click into slot didn't take),
        -- skip this slot and try the next one.
        if IsMainMenu(opts) then
            Dbg("expected submenu but got main — skipping slot " .. scanState.currentSlot)
            ClassifyMainMenu()
            ScanNextSlot()
            return
        end
        local isFirst = scanState.phase == "scanning_slot_first"
        local nextIdx = CaptureSlotItems(scanState.currentSlot, isFirst, opts)
        if nextIdx then
            scanState.phase = "scanning_slot_more"
            ScheduleClick(function()
                Dbg("clicking Next page (opt " .. nextIdx .. ")")
                SelectGossipOption(nextIdx)
            end)
        else
            -- Forward paging done. Return to main (Show main menu if we're
            -- already on page 1, else walk Previous).
            scanState.phase = "walking_back"
            if not ReturnToMainStep(opts) then
                FinishPartialScan("no Previous or Show main menu option found")
            end
        end
    elseif scanState.phase == "walking_back" then
        if IsMainMenu(opts) then
            ClassifyMainMenu()
            ScanNextSlot()
            return
        end
        if not ReturnToMainStep(opts) then
            FinishPartialScan("walked back but no way to reach main menu")
        end
    elseif scanState.phase == "scanning_sets_entering" then
        -- We're now in the Manage sets menu. Parse the set names and walk
        -- back to main.
        local char = GetCharDB()
        char.serverSets = {}
        local backIdx
        for _, opt in ipairs(opts) do
            if not ParseItemOption(opt.text) then
                local lc = opt.plain:lower()
                if lc:find("back", 1, true) then
                    backIdx = opt.index
                elseif lc == "save set" or lc:find("^save set", 1) then
                    -- skip — server's "Save set" option lives here too
                elseif lc:find("how sets work", 1, true) then
                    -- skip the optional info option
                else
                    -- This is a set name
                    table.insert(char.serverSets, { name = opt.plain })
                end
            end
        end
        Dbg("scanned " .. #char.serverSets .. " server sets")
        if backIdx then
            scanState.phase = "scanning_sets_back"
            ScheduleClick(function()
                Dbg("clicking Back from Manage sets (opt " .. backIdx .. ")")
                SelectGossipOption(backIdx)
            end)
        else
            -- No back option found, just finish (we already have the sets)
            scanDriver:Hide()
            FinishScan()
        end
    elseif scanState.phase == "scanning_sets_back" then
        -- Should now be back at main; finish the scan
        scanDriver:Hide()
        FinishScan()
    end
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

local suppressing = false
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
    if suppressing then
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

function SuppressGossipFrame()
    suppressing = true
    ApplySuppressionState()
end

function RestoreGossipFrame()
    suppressing = false
    ApplySuppressionState()
end

local function InstallGossipSuppression()
    if not GossipFrame then return end
    -- Stash anchors before our first interception so we can always restore.
    StashGossipAnchors()
    GossipFrame:HookScript("OnShow", function(self)
        if suppressing then
            self:SetAlpha(0)
            self:EnableMouse(false)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
        end
    end)
end

-------------------------------------------------------------------------------
-- APPLY FLOW — drive gossip clicks to transmog a single item
--
-- 1. Make sure gossip is open with Warpweaver (UI is shown alongside).
-- 2. Click slot's main-menu option → wait for slot submenu.
-- 3. Find the option matching desired entry → click it.
-- 4. Cost popup may appear — let WoW handle it (passes through to user).
-- 5. Server reopens slot menu via Timed event; we silently click Back to
--    return to main and re-show the wardrobe UI.
-------------------------------------------------------------------------------

-- Unified per-slot action driver. Used by both "apply an appearance" and
-- "hide this slot" — the only difference is which option to look for inside
-- the slot submenu, encoded in the findTarget predicate.
--
-- findTarget(opts)  -> gossip option index of the target, or nil if not on
--                      this page. The driver pages forward until it finds
--                      the target, clicks it, then walks back to main.
local applyState = {
    active     = false,
    phase      = "idle",
    slotId     = nil,
    findTarget = nil,
    label      = nil,
    pageCount  = 0,
    onComplete = nil,   -- callback fired when state returns to idle
}

local function ResetApply()
    -- onComplete is the hook used by the outfit-apply queue to chain the
    -- next item once the current ApplyEntry returns to idle. We swap it out
    -- BEFORE clearing state so the callback can start a new action.
    local cb = applyState.onComplete
    applyState.active     = false
    applyState.phase      = "idle"
    applyState.slotId     = nil
    applyState.findTarget = nil
    applyState.label      = nil
    applyState.pageCount  = 0
    applyState.onComplete = nil
    if cb then cb() end
end

local function StartSlotAction(slotId, findTarget, label)
    if applyState.active then
        Print("Already busy — please wait.")
        return
    end
    if scanState.active then
        Print("Scan still running — please wait.")
        return
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not suppressing) then
        Print("Open the Warpweaver first.")
        return
    end
    local char = GetCharDB()
    local optIdx = char.slotMenuMap[slotId]
    if not optIdx then
        Print("No mapping for that slot — try /wb rescan.")
        return
    end
    applyState.active     = true
    applyState.slotId     = slotId
    applyState.findTarget = findTarget
    applyState.label      = label
    applyState.pageCount  = 0
    applyState.phase      = "entering_slot"
    SuppressGossipFrame()
    ScheduleClick(function() SelectGossipOption(optIdx) end)
end

local function ApplyEntry(slotId, entry)
    StartSlotAction(slotId, function(opts)
        for _, opt in ipairs(opts) do
            local e = ParseItemOption(opt.text)
            if e == entry then return opt.index end
        end
    end, "apply " .. entry)
end

-- "Hide item" lives on page 1 of each slot's submenu — page-1 only, so the
-- driver clicks into the slot and the very first page contains the target.
local function HideSlot(slotId)
    StartSlotAction(slotId, function(opts)
        for _, opt in ipairs(opts) do
            if not ParseItemOption(opt.text) then
                local lc = opt.plain:lower()
                -- Match "Hide item" but not item names containing the word
                if lc == "hide item" or lc:find("^hide ", 1) then
                    return opt.index
                end
            end
        end
    end, "hide slot " .. slotId)
end

local function OnGossipShowDuringApply()
    local opts = ReadGossipOptions()

    if GetDB().debug then
        Dbg(string.format("=== ACTION GOSSIP_SHOW phase=%s slot=%s label=%s opts=%d ===",
            applyState.phase, tostring(applyState.slotId), tostring(applyState.label), #opts))
    end

    if applyState.phase == "entering_slot" then
        applyState.pageCount = applyState.pageCount + 1
        local hit = applyState.findTarget and applyState.findTarget(opts) or nil
        if hit then
            applyState.phase = "confirming_item"
            scanState.timeoutAt = 0
            -- For apply, a GOSSIP_CONFIRM cost popup will appear (separate
            -- StaticPopup, not affected by gossip suppression). For hide, no
            -- popup — server processes immediately and reopens the menu.
            ScheduleClick(function() SelectGossipOption(hit) end)
            return
        end
        -- Not on this page — page Next.
        local nextIdx = FindNavOptions(opts)
        if nextIdx and applyState.pageCount < SCAN_MAX_PAGES then
            ScheduleClick(function() SelectGossipOption(nextIdx) end)
        else
            Print("Target not found in this slot (" .. (applyState.label or "?") .. "). Try /wb rescan.")
            applyState.phase = "walking_back"
            if not ReturnToMainStep(opts) then
                ResetApply()
                ShowWardrobeUI()
            end
        end
    elseif applyState.phase == "confirming_item" then
        -- Server reopened a menu after applying/hiding. Could be the slot
        -- submenu or back at main. Detect which.
        if IsMainMenu(opts) then
            ResetApply()
            ShowWardrobeUI()
            return
        end
        applyState.phase = "walking_back"
        if not ReturnToMainStep(opts) then
            ResetApply()
            ShowWardrobeUI()
        end
    elseif applyState.phase == "walking_back" then
        if IsMainMenu(opts) then
            ResetApply()
            ShowWardrobeUI()
            return
        end
        if not ReturnToMainStep(opts) then
            ResetApply()
            ShowWardrobeUI()
        end
    end
end

-------------------------------------------------------------------------------
-- BATCH ACTIONS — Save Pending / Cancel Pending / Restore Original
-------------------------------------------------------------------------------

local function ClickExtra(key, friendly)
    local char = GetCharDB()
    local idx = char.extras[key]
    if not idx then
        Print("'" .. friendly .. "' option not found — try /wb rescan.")
        return
    end
    -- Let cost popup pass through to user
    RestoreGossipFrame()
    SelectGossipOption(idx)
end

-------------------------------------------------------------------------------
-- PREVIEW & OUTFIT APPLICATION
-------------------------------------------------------------------------------

-- Session preview state. previewSlots[slotId] = entry. Cleared on /reload.
-- Driving the DressUpModel: SetUnit("player") then TryOn each preview entry.
local previewSlots = {}

-- Outfit application queue. Filled by ApplyPreview, drained one slot at a
-- time as each ApplyEntry completes its state machine.
local outfitQueue = nil
local outfitFinalize = false   -- after queue drains, click Save Pending

-- Iterate previewSlots and queue an ApplyEntry per slot. As each ApplyEntry's
-- state machine returns to idle (ResetApply fires onComplete), we dispatch
-- the next. When the queue drains, click Save Pending to commit them all.
local function ApplyPreview()
    if applyState.active or scanState.active then
        Print("Already busy — wait for current action to finish.")
        return
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not suppressing) then
        Print("Open the Warpweaver first.")
        return
    end
    local q = {}
    for slotId, entry in pairs(previewSlots) do
        table.insert(q, {slotId = slotId, entry = entry})
    end
    if #q == 0 then
        Print("Nothing to apply — pick at least one appearance first.")
        return
    end
    outfitQueue    = q
    outfitFinalize = true
    Print(string.format("Queuing %d transmog change(s)…", #q))
    -- Kick off the first one. Each completion chains the next via onComplete.
    local function dispatchNext()
        while outfitQueue and #outfitQueue > 0 do
            local item = table.remove(outfitQueue, 1)
            local char = GetCharDB()
            if not char.slotMenuMap[item.slotId] then
                Print(string.format("Skipping slot %d (no menu mapping — try /wb rescan)", item.slotId))
                -- continue loop, try next
            else
                -- Set onComplete BEFORE the action call so the chain is in
                -- place before any state transitions happen.
                applyState.onComplete = dispatchNext
                if item.entry == "HIDE" then
                    HideSlot(item.slotId)
                else
                    ApplyEntry(item.slotId, item.entry)
                end
                if applyState.active then return end
                -- Action early-returned (preconditions failed). Clear the
                -- onComplete and try the next item.
                applyState.onComplete = nil
            end
        end
        outfitQueue = nil
        if outfitFinalize then
            outfitFinalize = false
            Print("All changes queued — committing via Save Pending.")
            ScheduleClick(function() ClickExtra("savePending", "Save pending transmogrifications") end)
        end
    end
    dispatchNext()
end

-- Cancel a queued ApplyPreview run (best-effort — anything already staged
-- on the server stays staged until the user clicks Cancel Pending).
local function CancelPreviewQueue()
    outfitQueue    = nil
    outfitFinalize = false
    applyState.onComplete = nil
end

-------------------------------------------------------------------------------
-- SERVER SETS — drive the Manage Sets gossip menu for Use/Save/Delete
--
-- Use:    free re-apply of a previously-saved set (Rochet2 charges nothing
--         per-Use; the cost was paid at Save time).
-- Save:   costs gold based on currently-pending transmogs. Uses gossip
--         text input via SelectGossipOption(idx, code).
-- Delete: free removal of a saved set.
--
-- Each operation walks a chain of gossip menus. We bypass the server's
-- built-in confirmation popups (binding warnings, cost confirms) because
-- we surface our own confirmations in the addon UI before starting.
-------------------------------------------------------------------------------

local setActionState = {
    active     = false,
    phase      = "idle",
    op         = nil,   -- "use" / "save" / "delete"
    setName    = nil,
    onComplete = nil,
}

local function ResetSetAction()
    local cb = setActionState.onComplete
    setActionState.active     = false
    setActionState.phase      = "idle"
    setActionState.op         = nil
    setActionState.setName    = nil
    setActionState.onComplete = nil
    if cb then cb() end
end

-- Find an option matching a predicate and click it; transition to nextPhase.
-- Returns true if clicked, false if not found.
local function ClickMatchAndAdvance(opts, predicate, nextPhase, code)
    for _, opt in ipairs(opts) do
        if predicate(opt) then
            setActionState.phase = nextPhase
            local idx = opt.index
            ScheduleClick(function()
                if code ~= nil then
                    SelectGossipOption(idx, code)
                else
                    SelectGossipOption(idx)
                end
            end)
            return true
        end
    end
    return false
end

-- Find a non-item "Back.." option and click it; transition to nextPhase.
local function BackFromCurrentMenu(opts, nextPhase)
    return ClickMatchAndAdvance(opts, function(opt)
        return not ParseItemOption(opt.text)
           and opt.plain:lower():find("back", 1, true) ~= nil
    end, nextPhase)
end

local function FailSetAction(reason)
    Print("Set action aborted: " .. reason)
    ResetSetAction()
    -- Try to bail back to main by closing gossip; user can reopen NPC
    if GossipFrame and (GossipFrame:IsShown() or suppressing) then
        CloseGossip()
    end
end

local function OnGossipShowDuringSetAction()
    local opts = ReadGossipOptions()
    if GetDB().debug then
        Dbg(string.format("=== SETACTION GOSSIP_SHOW op=%s phase=%s opts=%d ===",
            tostring(setActionState.op), tostring(setActionState.phase), #opts))
    end

    local op    = setActionState.op
    local phase = setActionState.phase
    local name  = setActionState.setName

    -- =========================================================== USE flow
    if op == "use" then
        if phase == "use_enter_manage" then
            if not ClickMatchAndAdvance(opts, function(opt)
                return not ParseItemOption(opt.text) and opt.plain == name
            end, "use_enter_set") then
                FailSetAction("set '" .. name .. "' not found in Manage sets — try /wb rescan")
            end
        elseif phase == "use_enter_set" then
            if not ClickMatchAndAdvance(opts, function(opt)
                return not ParseItemOption(opt.text)
                   and opt.plain:lower():find("^use set", 1) ~= nil
            end, "use_applied") then
                FailSetAction("'Use set' option not found")
            end
        elseif phase == "use_applied" then
            -- Server reopened the set-view menu. Walk back to manage sets.
            if not BackFromCurrentMenu(opts, "use_back_manage") then
                FailSetAction("no Back option from set view")
            end
        elseif phase == "use_back_manage" then
            -- Back at manage sets. Walk back to main.
            if not BackFromCurrentMenu(opts, "use_done") then
                FailSetAction("no Back option from Manage sets")
            end
        elseif phase == "use_done" then
            Print("Applied set '" .. name .. "'")
            ResetSetAction()
            ShowWardrobeUI()
        end

    -- =========================================================== SAVE flow
    elseif op == "save" then
        if phase == "save_enter_manage" then
            -- Find the "Save set" option and click it with the name as code
            if not ClickMatchAndAdvance(opts, function(opt)
                if ParseItemOption(opt.text) then return false end
                local lc = opt.plain:lower()
                return lc == "save set" or lc:find("^save set", 1) ~= nil
            end, "save_done", name) then
                FailSetAction("'Save set' option not available — make sure you have pending transmogs that cost something to set")
            end
        elseif phase == "save_done" then
            -- Server reopened Manage sets. The new set should be in the list.
            -- Locally append it so the UI sees the change without a rescan.
            local exists = false
            for _, s in ipairs(GetCharDB().serverSets) do
                if s.name == name then exists = true break end
            end
            if not exists then
                table.insert(GetCharDB().serverSets, { name = name })
            end
            Print("Saved set '" .. name .. "'")
            -- Walk back to main
            if not BackFromCurrentMenu(opts, "save_done2") then
                FailSetAction("no Back option from Manage sets after save")
            end
        elseif phase == "save_done2" then
            ResetSetAction()
            ShowWardrobeUI()
        end

    -- =========================================================== DELETE flow
    elseif op == "delete" then
        if phase == "delete_enter_manage" then
            if not ClickMatchAndAdvance(opts, function(opt)
                return not ParseItemOption(opt.text) and opt.plain == name
            end, "delete_enter_set") then
                FailSetAction("set '" .. name .. "' not found in Manage sets")
            end
        elseif phase == "delete_enter_set" then
            if not ClickMatchAndAdvance(opts, function(opt)
                return not ParseItemOption(opt.text)
                   and opt.plain:lower():find("^delete set", 1) ~= nil
            end, "delete_done") then
                FailSetAction("'Delete set' option not found")
            end
        elseif phase == "delete_done" then
            -- Server reopened Manage sets (the set is gone). Remove from cache.
            local sets = GetCharDB().serverSets
            for i, s in ipairs(sets) do
                if s.name == name then table.remove(sets, i) break end
            end
            Print("Deleted set '" .. name .. "'")
            if not BackFromCurrentMenu(opts, "delete_done2") then
                FailSetAction("no Back option from Manage sets after delete")
            end
        elseif phase == "delete_done2" then
            ResetSetAction()
            ShowWardrobeUI()
        end
    end
end

-- Entry points -------------------------------------------------------------

local function StartUseServerSet(setName)
    if applyState.active or scanState.active or setActionState.active then
        Print("Already busy — please wait.")
        return
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not suppressing) then
        Print("Open the Warpweaver first.")
        return
    end
    local char = GetCharDB()
    if not char.extras.manageSets then
        Print("'Manage sets' option not found — try /wb rescan.")
        return
    end
    setActionState.active  = true
    setActionState.op      = "use"
    setActionState.setName = setName
    setActionState.phase   = "use_enter_manage"
    SuppressGossipFrame()
    local idx = char.extras.manageSets
    ScheduleClick(function() SelectGossipOption(idx) end)
end

local function StartSaveServerSet(setName)
    if applyState.active or scanState.active or setActionState.active then
        Print("Already busy — please wait.")
        return
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not suppressing) then
        Print("Open the Warpweaver first.")
        return
    end
    local char = GetCharDB()
    if not char.extras.manageSets then
        Print("'Manage sets' option not found — try /wb rescan.")
        return
    end
    setActionState.active  = true
    setActionState.op      = "save"
    setActionState.setName = setName
    setActionState.phase   = "save_enter_manage"
    SuppressGossipFrame()
    local idx = char.extras.manageSets
    ScheduleClick(function() SelectGossipOption(idx) end)
end

local function StartDeleteServerSet(setName)
    if applyState.active or scanState.active or setActionState.active then
        Print("Already busy — please wait.")
        return
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not suppressing) then
        Print("Open the Warpweaver first.")
        return
    end
    local char = GetCharDB()
    if not char.extras.manageSets then
        Print("'Manage sets' option not found — try /wb rescan.")
        return
    end
    setActionState.active  = true
    setActionState.op      = "delete"
    setActionState.setName = setName
    setActionState.phase   = "delete_enter_manage"
    SuppressGossipFrame()
    local idx = char.extras.manageSets
    ScheduleClick(function() SelectGossipOption(idx) end)
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------

local ui = {}   -- holds frame refs

-------------------------------------------------------------------------------
-- ITEM CACHE WARMING
--
-- In WoW 3.3.5a, GetItemInfo(id) does NOT trigger a server fetch when the
-- item isn't cached — it just returns nil. The cache only warms when the
-- client encounters the item through inventory, loot, or hyperlink display
-- (tooltip, chat). Without help, scanned appearances that the player has
-- never owned show up as "Common" with a question-mark icon.
--
-- Workaround: a hidden GameTooltip; calling :SetHyperlink("item:N") on it
-- causes the client to request the item info from the server, which
-- populates the cache. We throttle ~20 pings/second so we don't flood.
-------------------------------------------------------------------------------

local scannerTip       -- created lazily on first use
local warmQueue   = {} -- list of item entry IDs to ping
local warmIdx     = 1
local warmTotal   = 0

local function GetScannerTip()
    if not scannerTip then
        scannerTip = CreateFrame("GameTooltip", "WardrobeScannerTip", UIParent, "GameTooltipTemplate")
        scannerTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scannerTip
end

function BuildWarmQueue()
    warmQueue = {}
    warmIdx   = 1
    local seen = {}
    local char = GetCharDB()
    for _, items in pairs(char.collection or {}) do
        for _, it in ipairs(items) do
            if not it.resolved and it.entry and not seen[it.entry] then
                seen[it.entry] = true
                table.insert(warmQueue, it.entry)
            end
        end
    end
    warmTotal = #warmQueue
    if warmTotal > 0 then
        Dbg("warming cache for " .. warmTotal .. " items")
    end
end

function WarmingActive()
    return warmIdx <= #warmQueue
end

-- Ping the next unresolved item via the scanner tooltip. Returns true if it
-- did some work, false when the queue is drained.
function WarmTick()
    while warmIdx <= #warmQueue do
        local entry = warmQueue[warmIdx]
        warmIdx = warmIdx + 1
        if not GetItemInfo(entry) then
            -- Trigger the server fetch
            local tip = GetScannerTip()
            tip:SetOwner(UIParent, "ANCHOR_NONE")
            tip:SetHyperlink("item:" .. entry)
            tip:Hide()
            return true
        end
        -- already cached, skip and keep looking
    end
    return false
end

local function MakeBackdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile   = bg or "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = border or "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left=4,right=4,top=4,bottom=4},
    })
end

local function CreateMainFrame()
    if ui.frame then return ui.frame end
    local f = CreateFrame("Frame", "WardrobeMainFrame", UIParent)
    f:SetSize(UI_WIDTH, UI_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    MakeBackdrop(f, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    f:SetBackdropBorderColor(0.40, 0.25, 0.70)

    -- Custom background texture (purple/gold transmog scene). Rendered on
    -- the BACKGROUND layer so child frames (tabs, doll, list, buttons) sit
    -- on top. Anchored just inside the border so the dark backdrop forms
    -- a visible edge frame. If the texture file is missing, the dark
    -- backdrop above is the fallback and the window still renders cleanly.
    local bgTex = f:CreateTexture(nil, "BACKGROUND")
    bgTex:SetPoint("TOPLEFT",     f, "TOPLEFT",      5,  -5)
    bgTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5,   5)
    bgTex:SetTexture("Interface\\AddOns\\Wardrobe\\Media\\Background")
    -- Dim slightly so foreground text and buttons stay readable
    bgTex:SetVertexColor(0.65, 0.65, 0.70, 1)
    ui.bgTex = bgTex

    -- Title bar
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffd4af37Wardrobe|r")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOP", 0, -32)
    subtitle:SetText("Project Ebonhold transmog browser  |  v" ..
        ADDON_VERSION .. " by |cffd4af37" .. ADDON_AUTHOR .. "|r")
    subtitle:SetTextColor(0.7, 0.7, 0.75)
    ui.subtitle = subtitle

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- "?" info badge next to the close button. Hover -> addon info, slash
    -- command list, license, and project URL. Mirrors the AutoLoot pattern.
    local infoBadge = CreateFrame("Frame", nil, f)
    infoBadge:SetSize(20, 20)
    infoBadge:SetPoint("TOPRIGHT", -32, -10)
    infoBadge:EnableMouse(true)
    local ibBg = infoBadge:CreateTexture(nil, "BACKGROUND")
    ibBg:SetAllPoints()
    ibBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    ibBg:SetVertexColor(0.18, 0.10, 0.30, 0.85)
    local ibTxt = infoBadge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ibTxt:SetPoint("CENTER", 0, 0)
    ibTxt:SetText("|cffffd700?|r")
    infoBadge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffd4af37" .. ADDON_NAME .. "|r v" .. ADDON_VERSION)
        GameTooltip:AddLine("|cff888866by " .. ADDON_AUTHOR .. "|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700About:|r")
        GameTooltip:AddLine("|cffaaaaaaInteractive transmog browser for Project Ebonhold's Warpweaver NPC. Replaces the gossip-menu paging UI with a searchable per-slot wardrobe, 3D paper-doll preview, outfits, and Manage Sets integration.|r", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700Slash commands:|r")
        GameTooltip:AddLine("|cffaaaaaa/wb|r |cff888866 or |r|cffaaaaaa/wardrobe|r   |cff666666open/close|r")
        GameTooltip:AddLine("|cffaaaaaa/wb rescan|r   |cff666666rescan collection + server sets|r")
        GameTooltip:AddLine("|cffaaaaaa/wb reset|r   |cff666666wipe all saved data|r")
        GameTooltip:AddLine("|cffaaaaaa/wb debug|r   |cff666666toggle verbose chat logging|r")
        GameTooltip:AddLine("|cffaaaaaa/wb npcname <Name>|r   |cff666666register a custom NPC name|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700In-window controls:|r")
        GameTooltip:AddLine("|cffaaaaaaLeft-click item|r   |cff666666stage on the doll|r")
        GameTooltip:AddLine("|cffaaaaaaRight-click item|r   |cff666666apply immediately|r")
        GameTooltip:AddLine("|cffaaaaaaLeft-drag doll|r   |cff666666rotate model|r")
        GameTooltip:AddLine("|cffaaaaaaRight-drag doll|r   |cff666666pan vertically|r")
        GameTooltip:AddLine("|cffaaaaaaMouse wheel on doll|r   |cff666666zoom in/out|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700License:|r")
        GameTooltip:AddLine("|cffaaaaaaSource-available. Attribution required. See LICENSE for full terms.|r", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888866" .. ADDON_URL .. "|r")
        GameTooltip:Show()
    end)
    infoBadge:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Closing the wardrobe ends the gossip session cleanly. Calling
    -- CloseGossip() fires GOSSIP_CLOSED which restores GossipFrame visibility.
    -- The Server Menu button sets ui.skipCloseGossip = true so it can hand
    -- control back to the native gossip frame without ending the session.
    f:SetScript("OnHide", function()
        if ui.skipCloseGossip then return end
        if GossipFrame and (GossipFrame:IsShown() or suppressing) then
            CloseGossip()
        end
    end)

    -- Dual ticker:
    --   * Cache warming  — pings the scanner tooltip ~20×/sec to fetch
    --     item info from the server for entries the client hasn't seen.
    --   * Display refresh — every ~0.4s, re-resolve unresolved items in
    --     the current slot via GetItemInfo (now likely cached) and update
    --     the list when any new ones come through.
    f.warmAccum    = 0
    f.refreshAccum = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.warmAccum    = self.warmAccum    + elapsed
        self.refreshAccum = self.refreshAccum + elapsed

        if self.warmAccum >= 0.05 and WarmingActive() then
            self.warmAccum = 0
            WarmTick()
        end

        if self.refreshAccum >= 0.4 then
            self.refreshAccum = 0
            if ui.currentSlot and ui.RefreshList then
                local items = GetCharDB().collection[ui.currentSlot]
                if items then
                    local anyNew = false
                    for _, it in ipairs(items) do
                        if not it.resolved and it.entry then
                            local _, link, quality, _, _, _, _, _, _, icon = GetItemInfo(it.entry)
                            if link then
                                it.link     = link
                                it.quality  = quality or it.quality
                                it.icon     = icon or it.icon
                                it.resolved = true
                                anyNew = true
                            end
                        end
                    end
                    if anyNew then ui.RefreshList() end
                end
            end
        end
    end)

    -- Gold divider under header
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.83, 0.69, 0.22, 0.95)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 10, -50)
    divider:SetPoint("TOPRIGHT", -10, -50)

    -- Slot tab column on left
    local tabCol = CreateFrame("Frame", nil, f)
    tabCol:SetPoint("TOPLEFT", 10, -60)
    tabCol:SetPoint("BOTTOMLEFT", 10, 60)
    tabCol:SetWidth(TAB_COL_WIDTH)
    ui.tabCol = tabCol

    -- Paper doll column (middle): DressUpModel + outfit controls
    local dollCol = CreateFrame("Frame", nil, f)
    dollCol:SetPoint("TOPLEFT", tabCol, "TOPRIGHT", 8, 0)
    dollCol:SetPoint("BOTTOMLEFT", tabCol, "BOTTOMRIGHT", 8, 0)
    dollCol:SetWidth(DOLL_WIDTH)
    ui.dollCol = dollCol

    -- Right pane: search + list
    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", dollCol, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -10, 60)
    ui.right = right

    -- Search box (narrowed in v0.8 to make room for Hide button without overflow)
    local search = CreateFrame("EditBox", "WardrobeSearchBox", right, "InputBoxTemplate")
    search:SetSize(240, 22)
    search:SetPoint("TOPLEFT", 8, -4)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(self) ui.RefreshList() end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    ui.search = search

    local searchLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", -2, 2)
    searchLabel:SetText("Search")

    -- Quality filter dropdown (simple cycle button — avoids UIDropDownMenu cruft)
    local qf = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    qf:SetSize(120, 22)
    qf:SetPoint("LEFT", search, "RIGHT", 12, 0)
    qf:SetScript("OnClick", function()
        local db = GetDB()
        db.ui.qualityFilter = (db.ui.qualityFilter + 1) % 6   -- 0..5
        ui.UpdateQualityButton()
        ui.RefreshList()
    end)
    ui.qualityBtn = qf

    -- Hide Slot button — stages a "hide this slot" preview. Committed by
    -- Apply Preview alongside any other staged appearance changes.
    local hide = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    hide:SetSize(130, 22)
    hide:SetPoint("LEFT", qf, "RIGHT", 8, 0)
    hide:SetScript("OnClick", function()
        if not ui.currentSlot then return end
        previewSlots[ui.currentSlot] = "HIDE"
        ui.RefreshDoll()
        ui.UpdatePreviewLabel()
    end)
    hide:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Stage 'Hide item' on this slot")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Marks this slot to be hidden by the Warpweaver. Nothing is sent to the server until you click |cffffd200Apply Preview|r.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Note: once committed, the slot stays hidden until you transmog something else onto it or use |cffffd200Cancel Pending|r to revert.", 0.95, 0.65, 0.30, true)
        GameTooltip:Show()
    end)
    hide:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.hideBtn = hide

    -- List frame
    local listBg = CreateFrame("Frame", nil, right)
    listBg:SetPoint("TOPLEFT", 4, -32)
    listBg:SetPoint("BOTTOMRIGHT", -4, 4)
    MakeBackdrop(listBg, "Interface\\ChatFrame\\ChatFrameBackground")
    listBg:SetBackdropColor(0.05, 0.04, 0.08, 0.85)
    listBg:SetBackdropBorderColor(0.3, 0.25, 0.4)

    local scroll = CreateFrame("ScrollFrame", "WardrobeListScroll", listBg, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 22, ui.RefreshList)
    end)
    ui.listScroll = scroll
    ui.listBg = listBg

    -- Row pool: 22 rows × 22px = 484px, fits inside the ~512px scroll area
    -- (taller frame in v0.7). Rows anchor TOPLEFT/TOPRIGHT to the scroll
    -- frame so they auto-fit width regardless of scrollbar.
    ui.rows = {}
    for i = 1, 22 do
        local row = CreateFrame("Button", nil, scroll)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT",  scroll, "TOPLEFT",  4, -(i-1)*22)
        row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -4, -(i-1)*22)

        local hi = row:CreateTexture(nil, "BACKGROUND")
        hi:SetAllPoints()
        hi:SetTexture("Interface\\Buttons\\WHITE8X8")
        hi:SetVertexColor(0.8, 0.7, 0.3, 0)
        row.hi = hi
        row:SetScript("OnEnter", function(self)
            self.hi:SetVertexColor(0.8, 0.7, 0.3, 0.18)
            if self.itemData and self.itemData.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemData.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hi:SetVertexColor(0.8, 0.7, 0.3, 0)
            GameTooltip:Hide()
        end)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", 4, 0)
        row.icon = icon

        local qualFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qualFs:SetPoint("RIGHT", -8, 0)
        qualFs:SetJustifyH("RIGHT")
        qualFs:SetWidth(80)
        row.qualFs = qualFs

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFs:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        nameFs:SetPoint("RIGHT", qualFs, "LEFT", -8, 0)
        nameFs:SetJustifyH("LEFT")
        row.nameFs = nameFs

        row:SetScript("OnClick", function(self, button)
            if not (self.itemData and ui.currentSlot) then return end
            if button == "RightButton" then
                -- Right-click: apply immediately, skip preview
                ApplyEntry(ui.currentSlot, self.itemData.entry)
            else
                -- Left-click: preview only (TryOn on doll, stage for batch Apply Preview)
                if ui.PreviewItem then
                    ui.PreviewItem(ui.currentSlot, self.itemData)
                end
            end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        ui.rows[i] = row
    end

    local function MakeBtn(label, width, parent, onclick)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width, 24)
        b:SetText(label)
        b:SetScript("OnClick", onclick)
        return b
    end

    -- ===== Doll column content =====
    local dollBg = CreateFrame("Frame", nil, dollCol)
    dollBg:SetPoint("TOPLEFT", 0, 0)
    dollBg:SetPoint("TOPRIGHT", 0, 0)
    dollBg:SetHeight(380)
    MakeBackdrop(dollBg, "Interface\\ChatFrame\\ChatFrameBackground")
    dollBg:SetBackdropColor(0.05, 0.04, 0.08, 0.85)
    dollBg:SetBackdropBorderColor(0.3, 0.25, 0.4)

    local doll = CreateFrame("DressUpModel", "WardrobeDoll", dollBg)
    doll:SetPoint("TOPLEFT", 6, -6)
    doll:SetPoint("BOTTOMRIGHT", -6, 6)
    doll:SetUnit("player")
    ui.doll = doll

    -- 3D view controls — left-drag rotates, right-drag pans (vertical), mouse
    -- wheel zooms. Mirrors the standard CharacterModelFrame / DressUpFrame
    -- behaviour in WoW 3.3.5a.
    doll:EnableMouse(true)
    doll:EnableMouseWheel(true)
    doll:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.rotating    = true
            self.rotateStart = GetCursorPosition()
        elseif button == "RightButton" then
            self.panning   = true
            self.panStart  = select(2, GetCursorPosition())
        end
    end)
    doll:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then self.rotating = false
        elseif button == "RightButton" then self.panning = false end
    end)
    doll:SetScript("OnUpdate", function(self)
        if self.rotating then
            local x = GetCursorPosition()
            if x ~= self.rotateStart then
                local dx = (x - self.rotateStart) * 0.01
                self:SetFacing((self:GetFacing() or 0) + dx)
                self.rotateStart = x
            end
        end
        if self.panning then
            local _, y = GetCursorPosition()
            if y ~= self.panStart then
                local dy = (y - self.panStart) * 0.004
                local px, py, pz = self:GetPosition()
                -- z is vertical (camera-space "up"); positive moves the model up
                self:SetPosition(px, py, (pz or 0) + dy)
                self.panStart = y
            end
        end
    end)
    doll:SetScript("OnMouseWheel", function(self, delta)
        local px, py, pz = self:GetPosition()
        -- x is camera-space "forward"; positive zooms in toward the model
        self:SetPosition((px or 0) + delta * 0.4, py, pz)
    end)

    -- Snapshot the initial camera so the Reset View button can restore it
    -- after the user has rotated/panned/zoomed.
    local initialFacing = doll:GetFacing() or 0
    local ipx, ipy, ipz = doll:GetPosition()
    doll.resetView = function()
        doll:SetFacing(initialFacing)
        doll:SetPosition(ipx or 0, ipy or 0, ipz or 0)
    end

    -- Small Reset View button overlaid in the bottom-right corner of the
    -- doll panel. Useful if the user accidentally drags the model offscreen.
    local resetView = CreateFrame("Button", nil, dollBg, "UIPanelButtonTemplate")
    resetView:SetSize(56, 18)
    resetView:SetPoint("BOTTOMRIGHT", -8, 8)
    resetView:SetText("Reset")
    resetView:SetFrameLevel(doll:GetFrameLevel() + 1)
    resetView:SetScript("OnClick", function() doll.resetView() end)
    resetView:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset view")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Restores the default camera. Drag the model with left-click to rotate, right-click to pan vertically, and use the mouse wheel to zoom.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetView:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Tiny label below the doll showing how many slots are previewed.
    -- Constrained to the doll column width so longer messages wrap rather
    -- than overflowing into the right pane.
    local previewLbl = dollCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLbl:SetPoint("TOP", dollBg, "BOTTOM", 0, -4)
    previewLbl:SetWidth(DOLL_WIDTH)
    previewLbl:SetJustifyH("CENTER")
    previewLbl:SetTextColor(0.85, 0.78, 0.45)
    ui.previewLbl = previewLbl

    -- Outfit dropdown (custom button — UIDropDownMenu is heavy and finicky)
    local outfitBtn = CreateFrame("Button", nil, dollCol, "UIPanelButtonTemplate")
    outfitBtn:SetSize(DOLL_WIDTH, 22)
    outfitBtn:SetPoint("TOP", previewLbl, "BOTTOM", 0, -8)
    outfitBtn:SetText("Outfits (v)")
    ui.outfitBtn = outfitBtn

    -- Outfit menu (popup list under the button)
    local outfitMenu = CreateFrame("Frame", nil, dollCol)
    outfitMenu:SetSize(DOLL_WIDTH, 4)   -- height adjusts when shown
    outfitMenu:SetPoint("TOPLEFT", outfitBtn, "BOTTOMLEFT", 0, -2)
    outfitMenu:SetFrameStrata("DIALOG")
    MakeBackdrop(outfitMenu, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    outfitMenu:SetBackdropBorderColor(0.5, 0.4, 0.7)
    outfitMenu:Hide()
    outfitMenu.rows = {}
    ui.outfitMenu = outfitMenu

    outfitBtn:SetScript("OnClick", function()
        if outfitMenu:IsShown() then outfitMenu:Hide()
        else ui.RebuildOutfitMenu(); outfitMenu:Show() end
    end)

    -- Save / Apply / Reset / Delete buttons in a small grid
    local saveBtn = MakeBtn("Save as Outfit", (DOLL_WIDTH - 4) / 2, dollCol, function()
        StaticPopup_Show("WARDROBE_NAME_OUTFIT")
    end)
    saveBtn:SetPoint("TOPLEFT", outfitBtn, "BOTTOMLEFT", 0, -6)
    saveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Save the current preview as an outfit")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Snapshots whatever you've staged on the doll into a named outfit.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Wardrobe outfits are stored locally per character (addon SavedVariables) and are |cffff8c40separate from the server's Manage sets|r.", 0.9, 0.7, 0.4, true)
        GameTooltip:Show()
    end)
    saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.saveBtn = saveBtn

    local delBtn = MakeBtn("Delete Outfit", (DOLL_WIDTH - 4) / 2, dollCol, function()
        local idx = ui.selectedOutfitIdx
        local outfits = GetCharDB().outfits
        if not (idx and outfits[idx]) then
            Print("Select an outfit from the dropdown first.")
            return
        end
        StaticPopupDialogs["WARDROBE_DELETE_OUTFIT"].text =
            "Delete outfit '" .. outfits[idx].name .. "'?"
        StaticPopup_Show("WARDROBE_DELETE_OUTFIT")
    end)
    delBtn:SetPoint("TOPRIGHT", outfitBtn, "BOTTOMRIGHT", 0, -6)
    ui.delBtn = delBtn

    local applyPrevBtn = MakeBtn("Apply Preview", (DOLL_WIDTH - 4) / 2, dollCol, function()
        ApplyPreview()
    end)
    applyPrevBtn:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -4)
    ui.applyPrevBtn = applyPrevBtn

    local resetPrevBtn = MakeBtn("Reset Preview", (DOLL_WIDTH - 4) / 2, dollCol, function()
        wipe(previewSlots)
        ui.RefreshDoll()
        ui.UpdatePreviewLabel()
    end)
    resetPrevBtn:SetPoint("TOPRIGHT", delBtn, "BOTTOMRIGHT", 0, -4)
    ui.resetPrevBtn = resetPrevBtn

    -- ===== Server Sets section (below the addon outfit controls) =====
    local serverSetsBtn = CreateFrame("Button", nil, dollCol, "UIPanelButtonTemplate")
    serverSetsBtn:SetSize(DOLL_WIDTH, 22)
    serverSetsBtn:SetPoint("TOPLEFT", applyPrevBtn, "BOTTOMLEFT", 0, -10)
    serverSetsBtn:SetText("Server Sets (v)")
    ui.serverSetsBtn = serverSetsBtn

    local serverSetsMenu = CreateFrame("Frame", nil, dollCol)
    serverSetsMenu:SetSize(DOLL_WIDTH, 4)
    serverSetsMenu:SetPoint("TOPLEFT", serverSetsBtn, "BOTTOMLEFT", 0, -2)
    serverSetsMenu:SetFrameStrata("DIALOG")
    MakeBackdrop(serverSetsMenu, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    serverSetsMenu:SetBackdropBorderColor(0.65, 0.50, 0.30)
    serverSetsMenu:Hide()
    serverSetsMenu.rows = {}
    ui.serverSetsMenu = serverSetsMenu

    serverSetsBtn:SetScript("OnClick", function()
        if serverSetsMenu:IsShown() then serverSetsMenu:Hide()
        else ui.RebuildServerSetsMenu(); serverSetsMenu:Show() end
    end)
    serverSetsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Server-side sets")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click a set name to re-apply it for |cff00ff00free|r — the server only charges when you Save a set, not when you Use it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    serverSetsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local serverSaveBtn = MakeBtn("Save Server Set", (DOLL_WIDTH - 4) / 2, dollCol, function()
        StaticPopup_Show("WARDROBE_NAME_SERVER_SET")
    end)
    serverSaveBtn:SetPoint("TOPLEFT", serverSetsBtn, "BOTTOMLEFT", 0, -4)
    serverSaveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Save current transmogs as a server set")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Captures your currently-applied transmogs into a named server set you can re-Use later for free.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffff8c40Costs gold|r based on the set contents (server-side fee). The cost is taken when you click Save in the popup.", 0.9, 0.7, 0.4, true)
        GameTooltip:Show()
    end)
    serverSaveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.serverSaveBtn = serverSaveBtn

    local serverDelBtn = MakeBtn("Delete Server Set", (DOLL_WIDTH - 4) / 2, dollCol, function()
        local idx = ui.selectedServerSetIdx
        local sets = GetCharDB().serverSets
        if not (idx and sets[idx]) then
            Print("Pick a set from the Server Sets dropdown first.")
            return
        end
        StaticPopupDialogs["WARDROBE_DELETE_SERVER_SET"].text =
            "Delete server set '" .. sets[idx].name .. "'?"
        StaticPopup_Show("WARDROBE_DELETE_SERVER_SET")
    end)
    serverDelBtn:SetPoint("TOPRIGHT", serverSetsBtn, "BOTTOMRIGHT", 0, -4)
    ui.serverDelBtn = serverDelBtn

    -- ===== Bottom action bar =====
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT", 10, 10)
    bar:SetPoint("BOTTOMRIGHT", -10, 10)
    bar:SetHeight(44)
    MakeBackdrop(bar, "Interface\\DialogFrame\\UI-DialogBox-Background")
    bar:SetBackdropColor(0.1, 0.08, 0.14, 0.85)
    bar:SetBackdropBorderColor(0.4, 0.3, 0.55)

    local applyAll = MakeBtn("Apply All (Save Pending)", 170, bar, function()
        ClickExtra("savePending", "Save pending transmogrifications")
    end)
    applyAll:SetPoint("LEFT", 8, 0)

    local cancelAll = MakeBtn("Cancel Pending", 120, bar, function()
        ClickExtra("cancelPending", "Cancel pending transmogrifications")
    end)
    cancelAll:SetPoint("LEFT", applyAll, "RIGHT", 6, 0)

    local restore = MakeBtn("Restore Original", 130, bar, function()
        ClickExtra("restore", "Restore original look")
    end)
    restore:SetPoint("LEFT", cancelAll, "RIGHT", 6, 0)

    -- Server Menu — hands the user back to the native gossip frame so they
    -- can use server-side features (Manage Sets, How transmogrification
    -- works, etc.) that Wardrobe doesn't surface directly. We skip the
    -- usual CloseGossip on hide so the session stays alive.
    local serverMenu = MakeBtn("Server Menu", 110, bar, function()
        if not GossipFrame then return end
        ui.userInServerMenu = true
        ui.skipCloseGossip  = true
        ui.frame:Hide()
        ui.skipCloseGossip  = false
        RestoreGossipFrame()
        Print("Type |cffffd200/wb|r to return to Wardrobe (or just close gossip).")
    end)
    serverMenu:SetPoint("LEFT", restore, "RIGHT", 6, 0)
    serverMenu:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Show the native gossip menu")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hides Wardrobe and reveals the underlying Warpweaver gossip frame. Use this to reach |cffffd200Manage sets|r, |cffffd200How transmogrification works|r, and other server-side options.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Note: Wardrobe's saved outfits are separate from the server's Manage sets — they live in your addon SavedVariables, not the server's preset table.", 0.7, 0.7, 0.75, true)
        GameTooltip:Show()
    end)
    serverMenu:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rescan = MakeBtn("Rescan", 80, bar, function()
        if not GossipFrame:IsShown() and not suppressing then
            Print("Talk to the Warpweaver first.")
            return
        end
        StartScan()
    end)
    rescan:SetPoint("RIGHT", -8, 0)

    local stamp = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stamp:SetPoint("RIGHT", rescan, "LEFT", -8, 0)
    stamp:SetJustifyH("RIGHT")
    stamp:SetTextColor(0.7, 0.7, 0.75)
    ui.stamp = stamp

    ui.frame = f
    return f
end

local function BuildSlotTabs()
    if ui.slotTabs then return end
    ui.slotTabs = {}
    for i, s in ipairs(SLOTS) do
        local tab = CreateFrame("Button", nil, ui.tabCol)
        tab:SetSize(150, 22)
        tab:SetPoint("TOPLEFT", 0, -(i-1)*24)

        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.15, 0.10, 0.20, 0.6)
        tab.bg = bg

        local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", 8, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(s.label)
        tab.fs = fs

        local count = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetPoint("RIGHT", -8, 0)
        count:SetJustifyH("RIGHT")
        count:SetTextColor(0.6, 0.6, 0.7)
        tab.count = count

        tab:SetScript("OnClick", function() ui.SelectSlot(s.id) end)
        tab.slotId = s.id
        ui.slotTabs[s.id] = tab
    end
end

function ui.UpdateQualityButton()
    local q = GetDB().ui.qualityFilter
    if q == 0 then
        ui.qualityBtn:SetText("Quality: All")
    else
        local c = QUALITY_COLOR[q] or {1,1,1}
        ui.qualityBtn:SetText(string.format("Quality: |cff%02x%02x%02x%s+|r",
            c[1]*255, c[2]*255, c[3]*255, QUALITY_NAME[q] or "?"))
    end
end

function ui.RefreshTabs()
    local char = GetCharDB()
    for _, tab in pairs(ui.slotTabs) do
        local list = char.collection[tab.slotId]
        tab.count:SetText(list and tostring(#list) or "-")
        if tab.slotId == ui.currentSlot then
            tab.bg:SetVertexColor(0.45, 0.30, 0.65, 0.85)
            tab.fs:SetTextColor(1, 0.95, 0.6)
        else
            tab.bg:SetVertexColor(0.15, 0.10, 0.20, 0.6)
            tab.fs:SetTextColor(0.92, 0.92, 0.95)
        end
    end
end

function ui.RefreshList()
    local char  = GetCharDB()
    local items = (char.collection[ui.currentSlot] or {})
    local filter = (ui.search:GetText() or ""):lower()
    local qf     = GetDB().ui.qualityFilter
    local filtered = {}
    for _, it in ipairs(items) do
        -- Lazy refresh: client may not have had item data cached at scan time.
        if not it.resolved and it.entry then
            local _, link, quality, _, _, _, _, _, _, icon = GetItemInfo(it.entry)
            if link then
                it.link     = link
                it.quality  = quality or it.quality
                it.icon     = icon or it.icon
                it.resolved = true
            end
        end
        if (qf == 0 or (it.quality or 1) >= qf)
           and (filter == "" or (it.name or ""):lower():find(filter, 1, true)) then
            table.insert(filtered, it)
        end
    end
    table.sort(filtered, function(a, b)
        if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) > (b.quality or 1) end
        return (a.name or "") < (b.name or "")
    end)

    FauxScrollFrame_Update(ui.listScroll, #filtered, #ui.rows, 22)
    -- Clamp the offset to the new filtered range. Without this, switching
    -- from a large slot (e.g. Head, 256 items) to a small one (Tabard, 9)
    -- or narrowing a search leaves the scrollbar parked past the end of the
    -- new list and every row reads past `filtered` — the list LOOKS empty
    -- even though we have items.
    local maxOffset = math.max(0, #filtered - #ui.rows)
    local offset    = FauxScrollFrame_GetOffset(ui.listScroll)
    if offset > maxOffset then
        offset = maxOffset
        ui.listScroll:SetVerticalScroll(maxOffset * 22)
    end
    for i = 1, #ui.rows do
        local row = ui.rows[i]
        local it = filtered[i + offset]
        if it then
            row.icon:SetTexture(it.icon)
            local c = QUALITY_COLOR[it.quality or 1] or {1,1,1}
            row.nameFs:SetText(it.name or "?")
            row.nameFs:SetTextColor(c[1], c[2], c[3])
            row.qualFs:SetText(QUALITY_NAME[it.quality or 1] or "")
            row.qualFs:SetTextColor(c[1]*0.8, c[2]*0.8, c[3]*0.8)
            row.itemData = it
            row:Show()
        else
            row.itemData = nil
            row:Hide()
        end
    end

    -- Stamp (with warming progress when active)
    local base
    if char.lastScan and char.lastScan > 0 then
        local age  = time() - char.lastScan
        local mins = math.floor(age / 60)
        base = string.format("Last scan: %dm ago  |  %d items in %s",
            mins, #filtered, SLOT_BY_ID[ui.currentSlot] and SLOT_BY_ID[ui.currentSlot].label or "?")
    else
        base = "No scan yet"
    end
    if WarmingActive() then
        ui.stamp:SetText(string.format("|cffffd200Warming %d/%d|r  |  %s",
            warmIdx - 1, warmTotal, base))
    else
        ui.stamp:SetText(base)
    end
end

function ui.UpdateHideButton()
    if not ui.hideBtn then return end
    local s = SLOT_BY_ID[ui.currentSlot]
    ui.hideBtn:SetText("Hide " .. (s and s.label or "Slot"))
    -- Enchant pseudo-slots have no "Hide item" option in their gossip
    -- submenu, so the button would just error out. Disable visually.
    if s and s.isEnchant then
        ui.hideBtn:Disable()
    else
        ui.hideBtn:Enable()
    end
end

-------------------------------------------------------------------------------
-- PREVIEW / DOLL / OUTFITS
-------------------------------------------------------------------------------

function ui.UpdatePreviewLabel()
    if not ui.previewLbl then return end
    local nTransmog, nHide = 0, 0
    for _, v in pairs(previewSlots) do
        if v == "HIDE" then nHide = nHide + 1 else nTransmog = nTransmog + 1 end
    end
    if nTransmog == 0 and nHide == 0 then
        ui.previewLbl:SetText("Previewing current look\nLeft-click to stage, right-click to apply")
        ui.previewLbl:SetTextColor(0.6, 0.6, 0.65)
    else
        local parts = {}
        if nTransmog > 0 then table.insert(parts, nTransmog .. " transmog" .. (nTransmog > 1 and "s" or "")) end
        if nHide     > 0 then table.insert(parts, nHide     .. " hide"     .. (nHide     > 1 and "s" or "")) end
        ui.previewLbl:SetText(table.concat(parts, " + ") .. " staged\nApply Preview to commit")
        ui.previewLbl:SetTextColor(0.95, 0.85, 0.45)
    end
end

-- Walk previewSlots and TryOn each item's link. Reset to the player's
-- current equipped+transmogged look first via SetUnit("player"). A preview
-- value of "HIDE" tries to undress that slot (best-effort: 3.3.5a may not
-- have UndressSlot, in which case the doll still shows the current item but
-- the preview label still records the pending hide). Enchant pseudo-slots
-- (synthetic IDs 96/97) are skipped — DressUpModel can't render enchant
-- illusions, but the preview label still tracks them so the user knows
-- what's staged.
function ui.RefreshDoll()
    if not ui.doll then return end
    -- Preserve user-adjusted camera across the SetUnit reset, otherwise each
    -- preview click snaps the model back to default facing/zoom.
    local facing = ui.doll:GetFacing() or 0
    local px, py, pz = ui.doll:GetPosition()
    ui.doll:SetUnit("player")
    ui.doll:SetFacing(facing)
    if px and py and pz then ui.doll:SetPosition(px, py, pz) end
    local char = GetCharDB()
    for slotId, entry in pairs(previewSlots) do
        if IsEnchantSlot(slotId) then
            -- Enchant illusion — no doll preview, just stays staged.
        elseif entry == "HIDE" then
            -- Try the API that exists on later WoW versions; ignore errors
            -- in 3.3.5a where it isn't defined.
            pcall(function() ui.doll:UndressSlot(slotId) end)
        else
            -- Find the cached link for this entry so we can TryOn with a
            -- proper item link. Falls back to "item:entry" if not cached.
            local link
            local items = char.collection[slotId]
            if items then
                for _, it in ipairs(items) do
                    if it.entry == entry then link = it.link; break end
                end
            end
            ui.doll:TryOn(link or ("item:" .. entry))
        end
    end
end

function ui.PreviewItem(slotId, itemData)
    if not (slotId and itemData and itemData.entry) then return end
    previewSlots[slotId] = itemData.entry
    ui.RefreshDoll()
    ui.UpdatePreviewLabel()
end

function ui.RebuildOutfitMenu()
    local menu = ui.outfitMenu
    if not menu then return end
    -- Hide old rows
    for _, row in ipairs(menu.rows) do row:Hide() end
    local outfits = GetCharDB().outfits or {}
    if #outfits == 0 then
        menu:SetHeight(28)
        if not menu.empty then
            menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            menu.empty:SetPoint("CENTER")
            menu.empty:SetText("(no outfits saved)")
            menu.empty:SetTextColor(0.6, 0.6, 0.7)
        end
        menu.empty:Show()
        return
    end
    if menu.empty then menu.empty:Hide() end
    -- Build / reuse rows
    for i, outfit in ipairs(outfits) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, -4 - (i-1)*20)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i-1)*20)
            local hi = row:CreateTexture(nil, "BACKGROUND")
            hi:SetAllPoints()
            hi:SetTexture("Interface\\Buttons\\WHITE8X8")
            hi:SetVertexColor(0.8, 0.7, 0.3, 0)
            row.hi = hi
            row:SetScript("OnEnter", function(self) self.hi:SetVertexColor(0.8, 0.7, 0.3, 0.18) end)
            row:SetScript("OnLeave", function(self) self.hi:SetVertexColor(0.8, 0.7, 0.3, 0) end)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("LEFT", 8, 0)
            fs:SetJustifyH("LEFT")
            row.fs = fs
            menu.rows[i] = row
        end
        row.fs:SetText(outfit.name)
        local idx = i
        row:SetScript("OnClick", function()
            ui.SelectOutfit(idx)
            menu:Hide()
        end)
        row:Show()
    end
    menu:SetHeight(8 + #outfits * 20)
end

function ui.RebuildServerSetsMenu()
    local menu = ui.serverSetsMenu
    if not menu then return end
    for _, row in ipairs(menu.rows) do row:Hide() end
    local sets = GetCharDB().serverSets or {}
    if #sets == 0 then
        menu:SetHeight(28)
        if not menu.empty then
            menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            menu.empty:SetPoint("CENTER")
            menu.empty:SetText("(no server sets — Save one first)")
            menu.empty:SetTextColor(0.6, 0.6, 0.7)
        end
        menu.empty:Show()
        return
    end
    if menu.empty then menu.empty:Hide() end
    for i, set in ipairs(sets) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, -4 - (i-1)*20)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i-1)*20)
            local hi = row:CreateTexture(nil, "BACKGROUND")
            hi:SetAllPoints()
            hi:SetTexture("Interface\\Buttons\\WHITE8X8")
            hi:SetVertexColor(0.95, 0.75, 0.30, 0)
            row.hi = hi
            row:SetScript("OnEnter", function(self) self.hi:SetVertexColor(0.95, 0.75, 0.30, 0.18) end)
            row:SetScript("OnLeave", function(self) self.hi:SetVertexColor(0.95, 0.75, 0.30, 0) end)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("LEFT", 8, 0)
            fs:SetJustifyH("LEFT")
            row.fs = fs
            menu.rows[i] = row
        end
        row.fs:SetText(set.name)
        local idx = i
        local setName = set.name
        row:SetScript("OnClick", function()
            ui.selectedServerSetIdx = idx
            if ui.serverSetsBtn then ui.serverSetsBtn:SetText("Set: " .. setName .. " (v)") end
            menu:Hide()
            StartUseServerSet(setName)
        end)
        row:Show()
    end
    menu:SetHeight(8 + #sets * 20)
end

function ui.SelectOutfit(idx)
    local outfits = GetCharDB().outfits
    local outfit = outfits and outfits[idx]
    if not outfit then return end
    ui.selectedOutfitIdx = idx
    wipe(previewSlots)
    for slotId, entry in pairs(outfit.slots) do
        previewSlots[slotId] = entry
    end
    ui.RefreshDoll()
    ui.UpdatePreviewLabel()
    if ui.outfitBtn then ui.outfitBtn:SetText("Outfit: " .. outfit.name .. " (v)") end
    Print("Loaded outfit '" .. outfit.name .. "' — click Apply Preview to commit.")
end

function ui.SaveCurrentPreviewAsOutfit(name)
    local n = 0; for _ in pairs(previewSlots) do n = n + 1 end
    if n == 0 then
        Print("Nothing to save — preview some items first.")
        return
    end
    local char = GetCharDB()
    local outfit = { name = name, slots = {} }
    for slotId, entry in pairs(previewSlots) do outfit.slots[slotId] = entry end
    table.insert(char.outfits, outfit)
    ui.selectedOutfitIdx = #char.outfits
    if ui.outfitBtn then ui.outfitBtn:SetText("Outfit: " .. name .. " (v)") end
    Print("Saved outfit '" .. name .. "' (" .. n .. " slots).")
end

function ui.DeleteSelectedOutfit()
    local idx = ui.selectedOutfitIdx
    local outfits = GetCharDB().outfits
    if not (idx and outfits[idx]) then return end
    local name = outfits[idx].name
    table.remove(outfits, idx)
    ui.selectedOutfitIdx = nil
    if ui.outfitBtn then ui.outfitBtn:SetText("Outfits (v)") end
    Print("Deleted outfit '" .. name .. "'.")
end

-- StaticPopup dialogs registered once.
--
-- IMPORTANT: WoW 3.3.5a's StaticPopup_Show does NOT set `dialog.editBox` as
-- a field — it only creates the named child frame "<DialogName>EditBox".
-- Accessing self.editBox returns nil and any :GetText() call errors silently.
-- We have to fetch the edit box via the global lookup. The `self.editBox or`
-- guard keeps the addon forward-compatible with later clients that DO set
-- the field.
local function PopupEditBox(dialog)
    if not dialog then return nil end
    return dialog.editBox or _G[dialog:GetName() .. "EditBox"]
end

StaticPopupDialogs["WARDROBE_NAME_OUTFIT"] = {
    text          = "Name this outfit:",
    button1       = "Save",
    button2       = "Cancel",
    hasEditBox    = true,
    maxLetters    = 32,
    timeout       = 0,
    whileDead     = true,
    hideOnEscape  = true,
    OnAccept = function(self)
        local eb = PopupEditBox(self)
        if not eb then return end
        local name = (eb:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
        if name ~= "" then ui.SaveCurrentPreviewAsOutfit(name) end
    end,
    OnShow = function(self)
        local eb = PopupEditBox(self)
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    EditBoxOnEnterPressed = function(self)
        -- StaticPopup_EditBoxOnEnterPressed calls us with self = the editbox.
        local name = (self:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
        if name ~= "" then ui.SaveCurrentPreviewAsOutfit(name) end
        local parent = self:GetParent()
        if parent then parent:Hide() end
    end,
    EditBoxOnEscapePressed = function(self)
        local parent = self:GetParent()
        if parent then parent:Hide() end
    end,
}

StaticPopupDialogs["WARDROBE_DELETE_OUTFIT"] = {
    text         = "Delete this outfit?",   -- overwritten before Show
    button1      = "Delete",
    button2      = "Cancel",
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function() ui.DeleteSelectedOutfit() end,
}

-- Server-set popups (separate so we can branch on Save vs Delete cleanly)
StaticPopupDialogs["WARDROBE_NAME_SERVER_SET"] = {
    text          = "Name the server set (costs gold per the server's fee):",
    button1       = "Save",
    button2       = "Cancel",
    hasEditBox    = true,
    maxLetters    = 32,
    timeout       = 0,
    whileDead     = true,
    hideOnEscape  = true,
    OnAccept = function(self)
        local eb = PopupEditBox(self)
        if not eb then return end
        local name = (eb:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
        if name ~= "" then StartSaveServerSet(name) end
    end,
    OnShow = function(self)
        local eb = PopupEditBox(self)
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    EditBoxOnEnterPressed = function(self)
        local name = (self:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
        if name ~= "" then StartSaveServerSet(name) end
        local parent = self:GetParent()
        if parent then parent:Hide() end
    end,
    EditBoxOnEscapePressed = function(self)
        local parent = self:GetParent()
        if parent then parent:Hide() end
    end,
}

StaticPopupDialogs["WARDROBE_DELETE_SERVER_SET"] = {
    text         = "Delete this server set?",   -- overwritten before Show
    button1      = "Delete",
    button2      = "Cancel",
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept = function()
        local idx = ui.selectedServerSetIdx
        local sets = GetCharDB().serverSets
        if idx and sets[idx] then StartDeleteServerSet(sets[idx].name) end
    end,
}

function ui.SelectSlot(slotId)
    ui.currentSlot = slotId
    ui.RefreshTabs()
    ui.UpdateHideButton()
    ui.RefreshList()
end

function ShowWardrobeUI()
    CreateMainFrame()
    BuildSlotTabs()
    ui.UpdateQualityButton()
    if not ui.currentSlot then ui.currentSlot = SLOTS[1].id end
    ui.RefreshTabs()
    ui.UpdateHideButton()
    ui.UpdatePreviewLabel()
    ui.RefreshDoll()
    ui.RefreshList()
    -- Pre-warm any unresolved item cache entries — without this, items the
    -- player has never owned appear as "Common ?" until manually hovered.
    BuildWarmQueue()
    ui.frame:Show()
end

-------------------------------------------------------------------------------
-- EVENT DISPATCH
-------------------------------------------------------------------------------

local function NeedsScan()
    local char = GetCharDB()
    return (time() - (char.lastScan or 0)) > SCAN_TTL
end

local function OnGossipShow()
    -- Driver phases first
    if scanState.active then
        OnGossipShowDuringScan()
        return
    end
    if applyState.active then
        OnGossipShowDuringApply()
        return
    end
    if setActionState.active then
        OnGossipShowDuringSetAction()
        return
    end
    -- If the user clicked "Server Menu" they want to interact with the native
    -- gossip frame directly — don't re-suppress on every option click.
    if ui.userInServerMenu then
        Dbg("user in server menu — letting native gossip render")
        return
    end
    -- Fresh open
    if not IsTransmogNPC() then return end
    Dbg("Warpweaver gossip detected")
    if NeedsScan() then
        StartScan()
    else
        SuppressGossipFrame()
        ClassifyMainMenu()
        ShowWardrobeUI()
    end
end

local function OnGossipClosed()
    if scanState.active then
        -- Save partial progress rather than losing it.
        local char = GetCharDB()
        char.lastScan = time()
        local total, slotsHit = 0, 0
        for _, items in pairs(char.collection) do
            total = total + #items
            if #items > 0 then slotsHit = slotsHit + 1 end
        end
        Print(string.format("Gossip closed mid-scan — saved %d appearances across %d slots. Reopen Warpweaver and /wb rescan to continue.",
            total, slotsHit))
        ResetScan()
    end
    if applyState.active or outfitQueue then
        -- Clear queue first so the chained onComplete doesn't try to start
        -- a new ApplyEntry against a closed gossip session.
        outfitQueue           = nil
        outfitFinalize        = false
        applyState.onComplete = nil
        ResetApply()
    end
    if setActionState.active then
        ResetSetAction()
    end
    -- Closing gossip ends any Server Menu detour
    ui.userInServerMenu = false
    RestoreGossipFrame()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        GetDB()
    elseif event == "PLAYER_LOGIN" then
        GetCharDB()
        InstallGossipSuppression()
    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "GOSSIP_CLOSED" then
        OnGossipClosed()
    end
end)

-------------------------------------------------------------------------------
-- SLASH COMMANDS
-------------------------------------------------------------------------------

SLASH_WARDROBE1 = "/wardrobe"
SLASH_WARDROBE2 = "/wb"
SlashCmdList["WARDROBE"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    if msg == "rescan" then
        if GossipFrame and GossipFrame:IsShown() or suppressing then
            StartScan()
        else
            Print("Talk to the Warpweaver, then /wb rescan.")
        end
    elseif msg == "reset" then
        WardrobeDB = nil
        Print("All data reset. Reload with /reload.")
    elseif msg == "debug" then
        local db = GetDB()
        db.debug = not db.debug
        Print("Debug " .. (db.debug and "ON" or "OFF"))
    elseif msg:sub(1,8) == "npcname " then
        local n = msg:sub(9):gsub("^%s+",""):gsub("%s+$","")
        if n ~= "" then
            -- preserve original casing of typed name
            GetDB().npcNames[n:gsub("^%l", string.upper)] = true
            Print("Registered NPC name: " .. n)
        end
    elseif msg == "" or msg == "show" then
        if ui.frame and ui.frame:IsShown() then ui.frame:Hide() else ShowWardrobeUI() end
    else
        Print("|cffd4af37" .. ADDON_NAME .. "|r v" .. ADDON_VERSION ..
              " by " .. ADDON_AUTHOR .. "  -  " .. ADDON_URL)
        Print("Commands: /wb (toggle), /wb rescan, /wb reset, /wb debug, /wb npcname <Name>")
    end
end

Print("v" .. ADDON_VERSION .. " by |cffd4af37" .. ADDON_AUTHOR ..
      "|r loaded. Talk to a Warpweaver to begin.")
