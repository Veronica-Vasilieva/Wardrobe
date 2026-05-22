-------------------------------------------------------------------------------
-- Scan.lua  --  Async state machine that walks the Warpweaver gossip menu,
-- captures every appearance per slot, and detours through Manage Sets to
-- mirror server-side set names locally.
--
-- States:
--   idle              -- not scanning
--   reading_main      -- captured main menu, planning scan
--   scanning_slot     -- clicked into a slot submenu, waiting for GOSSIP_SHOW
--   walking_back      -- clicked Back, waiting for main menu to reappear
--   scanning_sets_*   -- detour through Manage sets to mirror set names
--
-- The default GossipFrame is suppressed while scanning. We never call
-- CloseGossip during a scan because that ends the gossip session server-side.
-------------------------------------------------------------------------------

local addonName, W = ...

-- Locally cache shared symbols that are settled by Core.lua at this point.
local SLOTS               = W.SLOTS
local SLOT_BY_ID          = W.SLOT_BY_ID
local IsEnchantSlot       = W.IsEnchantSlot
local Print, Dbg          = W.Print, W.Dbg
local GetCharDB, GetDB    = W.GetCharDB, W.GetDB
local ReadGossipOptions   = W.ReadGossipOptions
local ParseItemOption     = W.ParseItemOption
local MatchesSlotLabel    = W.MatchesSlotLabel
local FindNavOptions      = W.FindNavOptions
local IsMainMenu          = W.IsMainMenu

local SCAN_STEP_DELAY = W.SCAN_STEP_DELAY
local SCAN_TIMEOUT    = W.SCAN_TIMEOUT
local SCAN_MAX_PAGES  = W.SCAN_MAX_PAGES

-------------------------------------------------------------------------------
-- STATE
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
W.scanState = scanState

function W.ResetScan()
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
W.ClassifyMainMenu = ClassifyMainMenu

-- Capture items on the current page into char.collection[slotId]. Caller passes
-- isFirstPage=true on the first page of a slot so we reset the entry list and
-- the dedup set. Returns nextIdx, prevIdx, showMainIdx so the state machine
-- can advance.
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
    local isEnchant   = IsEnchantSlot(slotId)
    for _, opt in ipairs(opts) do
        local entry, name, enchIcon = ParseItemOption(opt.text, isEnchant)
        if entry and not seen[entry] then
            seen[entry] = true
            if isEnchant then
                table.insert(items, {
                    entry    = entry,   -- string: enchant name
                    name     = name,
                    link     = nil,
                    quality  = 1,
                    icon     = enchIcon,
                    resolved = true,
                })
            else
                local _, link, quality, _, _, _, _, _, _, icon = GetItemInfo(entry)
                table.insert(items, {
                    entry    = entry,
                    name     = name,
                    link     = link,
                    quality  = quality or 1,
                    icon     = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                    resolved = (link ~= nil),
                })
            end
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

local function FinishScan()
    local char = GetCharDB()
    char.lastScan = time()
    local total = 0
    for _, items in pairs(char.collection) do total = total + #items end
    W.ResetScan()
    Print(string.format("Wardrobe scan complete -- %d appearances cached.", total))
    -- ShowWardrobeUI internally invokes BuildWarmQueue, so no separate call here.
    if W.ShowWardrobeUI then W.ShowWardrobeUI() end
end

local function AbortScan(reason)
    Print("Scan aborted: " .. tostring(reason))
    W.ResetScan()
    W.RestoreGossipFrame()
end

-------------------------------------------------------------------------------
-- DRIVER (shared with Apply.lua and ServerSets.lua via W.ScheduleClick)
-------------------------------------------------------------------------------

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
W.scanDriver = scanDriver

function W.ScheduleClick(fn)
    scanDriver.t = 0
    scanDriver.pendingAction = fn
    scanDriver:Show()
end
local ScheduleClick = W.ScheduleClick

local function ScanNextSlot()
    local char = GetCharDB()
    if #scanState.queue == 0 then
        -- All slots done -- detour into Manage sets to scan server-side
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
        Dbg("no menu mapping for slot " .. slotId .. " -- skipping")
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
W.ReturnToMainStep = ReturnToMainStep

function W.StartScan()
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
    Print("Scanning " .. #scanState.queue .. " slots...")
    W.SuppressGossipFrame()
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
    Print(string.format("Scan ended early (%s) -- %d appearances cached across %d slots.",
        reason, total, slotsHit))
    W.ResetScan()
    if W.ShowWardrobeUI then W.ShowWardrobeUI() end
end

-- Called from GOSSIP_SHOW handler when a scan is in progress.
function W.OnGossipShowDuringScan()
    scanState.timeoutAt = 0
    local opts = ReadGossipOptions()

    if GetDB().debug then
        Dbg(string.format("=== GOSSIP_SHOW phase=%s slot=%s opts=%d ===",
            scanState.phase, tostring(scanState.currentSlot), #opts))
        for _, opt in ipairs(opts) do
            Dbg(string.format("  [%d] %s", opt.index, opt.plain))
        end
    end

    if scanState.phase == "scanning_slot_first" or scanState.phase == "scanning_slot_more" then
        if not scanState.currentSlot then return end
        if IsMainMenu(opts) then
            Dbg("expected submenu but got main -- skipping slot " .. scanState.currentSlot)
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
        -- We're now in the Manage sets menu. Parse the set names and walk back.
        local char = GetCharDB()
        char.serverSets = {}
        local backIdx
        for _, opt in ipairs(opts) do
            if not ParseItemOption(opt.text) then
                local lc = opt.plain:lower()
                if lc:find("back", 1, true) then
                    backIdx = opt.index
                elseif lc == "save set" or lc:find("^save set", 1) then
                    -- skip
                elseif lc:find("how sets work", 1, true) then
                    -- skip
                else
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
            scanDriver:Hide()
            FinishScan()
        end
    elseif scanState.phase == "scanning_sets_back" then
        scanDriver:Hide()
        FinishScan()
    end
end
