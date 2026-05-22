-------------------------------------------------------------------------------
-- Apply.lua  --  Drives gossip clicks to apply/hide one slot at a time;
-- batches multiple staged previews into a single Save Pending commit; and
-- warms the client item-info cache so scanned items resolve to real names.
--
-- Flow per apply:
--   1. Ensure gossip is open with Warpweaver (UI is shown alongside).
--   2. Click slot's main-menu option -> wait for slot submenu.
--   3. Find the option matching desired entry -> click it.
--   4. Cost popup may appear -- let WoW handle it (passes through to user).
--   5. Server reopens slot menu via Timed event; we walk back to main and
--      re-show the wardrobe UI.
-------------------------------------------------------------------------------

local addonName, W = ...

local Print, Dbg, ErrorMsg = W.Print, W.Dbg, W.ErrorMsg
local GetCharDB, GetDB     = W.GetCharDB, W.GetDB
local ReadGossipOptions    = W.ReadGossipOptions
local ParseItemOption      = W.ParseItemOption
local FindNavOptions       = W.FindNavOptions
local IsMainMenu           = W.IsMainMenu
local IsEnchantSlot        = W.IsEnchantSlot
local SCAN_MAX_PAGES       = W.SCAN_MAX_PAGES

-------------------------------------------------------------------------------
-- APPLY STATE
-------------------------------------------------------------------------------

-- Unified per-slot action state. Used by both "apply an appearance" and
-- "hide this slot" -- the only difference is which option to look for inside
-- the slot submenu, encoded in the findTarget predicate.
local applyState = {
    active     = false,
    phase      = "idle",
    slotId     = nil,
    findTarget = nil,
    label      = nil,
    pageCount  = 0,
    onComplete = nil,   -- callback fired when state returns to idle
}
W.applyState = applyState

local function ResetApply()
    -- onComplete is the hook used by the outfit-apply queue to chain the
    -- next item once the current ApplyEntry returns to idle. Swap it out
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
W.ResetApply = ResetApply

local function StartSlotAction(slotId, findTarget, label)
    if applyState.active then
        ErrorMsg("Already busy -- please wait.")
        return
    end
    if W.scanState and W.scanState.active then
        ErrorMsg("Scan still running -- please wait.")
        return
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not W.suppressing) then
        ErrorMsg("Open the Warpweaver first.")
        return
    end
    local char = GetCharDB()
    local optIdx = char.slotMenuMap[slotId]
    if not optIdx then
        ErrorMsg("No mapping for that slot -- try /wb rescan.")
        return
    end
    applyState.active     = true
    applyState.slotId     = slotId
    applyState.findTarget = findTarget
    applyState.label      = label
    applyState.pageCount  = 0
    applyState.phase      = "entering_slot"
    W.SuppressGossipFrame()
    W.ScheduleClick(function() SelectGossipOption(optIdx) end)
end

function W.ApplyEntry(slotId, entry)
    local isEnchant = IsEnchantSlot(slotId)
    StartSlotAction(slotId, function(opts)
        for _, opt in ipairs(opts) do
            local e = ParseItemOption(opt.text, isEnchant)
            if e == entry then return opt.index end
        end
    end, "apply " .. tostring(entry))
end

-- "Hide item" lives on page 1 of each slot's submenu (regular slots) and
-- enchant slots emit the same idea as "Hide enchant". Both variants match
-- the "^hide " regex (literal "hide" followed by a space), which excludes
-- item names like "Hideous Plate" because there's no space after "hide".
function W.HideSlot(slotId)
    local isEnchant = IsEnchantSlot(slotId)
    StartSlotAction(slotId, function(opts)
        for _, opt in ipairs(opts) do
            if not ParseItemOption(opt.text, isEnchant) then
                local lc = opt.plain:lower()
                if lc:find("^hide ", 1) then
                    return opt.index
                end
            end
        end
    end, "hide slot " .. slotId)
end

function W.OnGossipShowDuringApply()
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
            W.scanState.timeoutAt = 0
            W.ScheduleClick(function() SelectGossipOption(hit) end)
            return
        end
        local nextIdx = FindNavOptions(opts)
        if nextIdx and applyState.pageCount < SCAN_MAX_PAGES then
            W.ScheduleClick(function() SelectGossipOption(nextIdx) end)
        else
            ErrorMsg("Target not found in this slot (" .. (applyState.label or "?") .. "). Try /wb rescan.")
            applyState.phase = "walking_back"
            if not W.ReturnToMainStep(opts) then
                ResetApply()
                if W.ShowWardrobeUI then W.ShowWardrobeUI() end
            end
        end
    elseif applyState.phase == "confirming_item" then
        -- Server reopened a menu after applying/hiding. Could be the slot
        -- submenu or back at main. Detect which.
        --
        -- Record successful applies in char.applied so the "Hide applied"
        -- filter knows. Skip HIDE entries because they're slot removals.
        if applyState.slotId and applyState.entry
           and applyState.entry ~= "HIDE" then
            local char = GetCharDB()
            char.applied = char.applied or {}
            char.applied[applyState.slotId] = applyState.entry
        end
        if IsMainMenu(opts) then
            ResetApply()
            if W.ShowWardrobeUI then W.ShowWardrobeUI() end
            return
        end
        applyState.phase = "walking_back"
        if not W.ReturnToMainStep(opts) then
            ResetApply()
            if W.ShowWardrobeUI then W.ShowWardrobeUI() end
        end
    elseif applyState.phase == "walking_back" then
        if IsMainMenu(opts) then
            ResetApply()
            if W.ShowWardrobeUI then W.ShowWardrobeUI() end
            return
        end
        if not W.ReturnToMainStep(opts) then
            ResetApply()
            if W.ShowWardrobeUI then W.ShowWardrobeUI() end
        end
    end
end

-------------------------------------------------------------------------------
-- BATCH ACTIONS  --  Save Pending / Cancel Pending / Restore Original
-------------------------------------------------------------------------------

function W.ClickExtra(key, friendly)
    local char = GetCharDB()
    local idx = char.extras[key]
    if not idx then
        Print("'" .. friendly .. "' option not found -- try /wb rescan.")
        return
    end
    -- Let cost popup pass through to user
    W.RestoreGossipFrame()
    SelectGossipOption(idx)
end

-------------------------------------------------------------------------------
-- PREVIEW APPLICATION  --  drain the staged previewSlots set, one apply at a
-- time, then click Save Pending to commit them all.
-------------------------------------------------------------------------------

-- Outfit application queue. Filled by ApplyPreview, drained one slot at a
-- time as each ApplyEntry completes its state machine.
W.outfitQueue    = nil
W.outfitFinalize = false   -- after queue drains, click Save Pending

function W.ApplyPreview()
    if applyState.active or (W.scanState and W.scanState.active) then
        ErrorMsg("Already busy -- wait for current action to finish.")
        return
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not W.suppressing) then
        ErrorMsg("Open the Warpweaver first.")
        return
    end
    local q = {}
    for slotId, entry in pairs(W.previewSlots) do
        table.insert(q, {slotId = slotId, entry = entry})
    end
    if #q == 0 then
        ErrorMsg("Nothing to apply -- pick at least one appearance first.")
        return
    end
    W.outfitQueue    = q
    W.outfitFinalize = true
    Print(string.format("Queuing %d transmog change(s)...", #q))
    -- Kick off the first one. Each completion chains the next via onComplete.
    local function dispatchNext()
        while W.outfitQueue and #W.outfitQueue > 0 do
            local item = table.remove(W.outfitQueue, 1)
            local char = GetCharDB()
            if not char.slotMenuMap[item.slotId] then
                Print(string.format("Skipping slot %d (no menu mapping -- try /wb rescan)", item.slotId))
            else
                -- Set onComplete BEFORE the action call so the chain is in
                -- place before any state transitions happen.
                applyState.onComplete = dispatchNext
                if item.entry == "HIDE" then
                    W.HideSlot(item.slotId)
                else
                    W.ApplyEntry(item.slotId, item.entry)
                end
                if applyState.active then return end
                -- Action early-returned (preconditions failed). Clear the
                -- onComplete and try the next item.
                applyState.onComplete = nil
            end
        end
        W.outfitQueue = nil
        if W.outfitFinalize then
            W.outfitFinalize = false
            Print("All changes queued -- committing via Save Pending.")
            W.ScheduleClick(function() W.ClickExtra("savePending", "Save pending transmogrifications") end)
        end
    end
    dispatchNext()
end

function W.CancelPreviewQueue()
    W.outfitQueue    = nil
    W.outfitFinalize = false
    applyState.onComplete = nil
end

-------------------------------------------------------------------------------
-- ITEM CACHE WARMING
--
-- In WoW 3.3.5a, GetItemInfo(id) does NOT trigger a server fetch when the
-- item isn't cached -- it just returns nil. The cache only warms when the
-- client encounters the item through inventory, loot, or hyperlink display
-- (tooltip, chat). Without help, scanned appearances that the player has
-- never owned show up as "Common" with a question-mark icon.
--
-- Workaround: a hidden GameTooltip; calling :SetHyperlink("item:N") on it
-- causes the client to request the item info from the server, which
-- populates the cache. We throttle ~20 pings/second so we don't flood.
-------------------------------------------------------------------------------

local scannerTip         -- created lazily on first use
W.warmQueue = {}         -- list of item entry IDs to ping
W.warmIdx   = 1
W.warmTotal = 0

local function GetScannerTip()
    if not scannerTip then
        scannerTip = CreateFrame("GameTooltip", "WardrobeScannerTip", UIParent, "GameTooltipTemplate")
        scannerTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scannerTip
end

function W.BuildWarmQueue()
    W.warmQueue = {}
    W.warmIdx   = 1
    local seen = {}
    local char = GetCharDB()
    for _, items in pairs(char.collection or {}) do
        for _, it in ipairs(items) do
            if not it.resolved and it.entry and not seen[it.entry] then
                seen[it.entry] = true
                table.insert(W.warmQueue, it.entry)
            end
        end
    end
    -- v1.21: also warm the master item list so "Missing" rows display real
    -- names/icons instead of "Item 12345" stubs. Only do this if the master
    -- list is populated.
    local master = _G.WardrobeItemsBySlot
    if master then
        for _, list in pairs(master) do
            for _, itemId in ipairs(list) do
                if type(itemId) == "number" and not seen[itemId] and not GetItemInfo(itemId) then
                    seen[itemId] = true
                    table.insert(W.warmQueue, itemId)
                end
            end
        end
    end
    W.warmTotal = #W.warmQueue
    if W.warmTotal > 0 then
        Dbg("warming cache for " .. W.warmTotal .. " items")
    end
end

function W.WarmingActive()
    return W.warmIdx <= #W.warmQueue
end

-- Ping the next unresolved item via the scanner tooltip. Returns true if it
-- did some work, false when the queue is drained.
function W.WarmTick()
    while W.warmIdx <= #W.warmQueue do
        local entry = W.warmQueue[W.warmIdx]
        W.warmIdx = W.warmIdx + 1
        if not GetItemInfo(entry) then
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
