-------------------------------------------------------------------------------
-- ServerSets.lua  --  Drive the Manage Sets gossip menu for Use/Save/Delete.
--
-- Use:    re-apply a previously-saved set's items to your equipped slots.
--         The Ebonhold/Valanior fork charges per-transmog fees on each
--         apply (NOT the "paid at Save time, free thereafter" model that
--         Rochet2 vanilla advertised -- only the addon's doll preview is
--         truly free).
-- Save:   costs gold based on currently-applied transmogs. Uses gossip
--         text input via SelectGossipOption(idx, code).
-- Delete: removes a saved set; no gold cost.
--
-- Each operation walks a chain of gossip menus. We bypass the server's
-- built-in confirmation popups (binding warnings, cost confirms) because
-- we surface our own confirmations in the addon UI before starting.
-------------------------------------------------------------------------------

local addonName, W = ...

local Print, Dbg, ErrorMsg = W.Print, W.Dbg, W.ErrorMsg
local GetCharDB, GetDB     = W.GetCharDB, W.GetDB
local ReadGossipOptions    = W.ReadGossipOptions
local ParseItemOption      = W.ParseItemOption

local setActionState = {
    active     = false,
    phase      = "idle",
    op         = nil,   -- "use" / "save" / "delete"
    setName    = nil,
    onComplete = nil,
}
W.setActionState = setActionState

local function ResetSetAction()
    local cb = setActionState.onComplete
    setActionState.active     = false
    setActionState.phase      = "idle"
    setActionState.op         = nil
    setActionState.setName    = nil
    setActionState.onComplete = nil
    if cb then cb() end
end
W.ResetSetAction = ResetSetAction

-- Find an option matching a predicate and click it; transition to nextPhase.
-- Returns true if clicked, false if not found.
local function ClickMatchAndAdvance(opts, predicate, nextPhase, code)
    for _, opt in ipairs(opts) do
        if predicate(opt) then
            setActionState.phase = nextPhase
            local idx = opt.index
            W.ScheduleClick(function()
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
    if GossipFrame and (GossipFrame:IsShown() or W.suppressing) then
        CloseGossip()
    end
end

function W.OnGossipShowDuringSetAction()
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
                FailSetAction("set '" .. name .. "' not found in Manage sets -- try /wb rescan")
            end
        elseif phase == "use_enter_set" then
            if not ClickMatchAndAdvance(opts, function(opt)
                return not ParseItemOption(opt.text)
                   and opt.plain:lower():find("^use set", 1) ~= nil
            end, "use_applied") then
                FailSetAction("'Use set' option not found")
            end
        elseif phase == "use_applied" then
            if not BackFromCurrentMenu(opts, "use_back_manage") then
                FailSetAction("no Back option from set view")
            end
        elseif phase == "use_back_manage" then
            if not BackFromCurrentMenu(opts, "use_done") then
                FailSetAction("no Back option from Manage sets")
            end
        elseif phase == "use_done" then
            Print("Applied set '" .. name .. "'")
            ResetSetAction()
            if W.ShowWardrobeUI then W.ShowWardrobeUI() end
        end

    -- =========================================================== SAVE flow
    elseif op == "save" then
        if phase == "save_enter_manage" then
            if not ClickMatchAndAdvance(opts, function(opt)
                if ParseItemOption(opt.text) then return false end
                local lc = opt.plain:lower()
                return lc == "save set" or lc:find("^save set", 1) ~= nil
            end, "save_done", name) then
                FailSetAction("'Save set' option not available -- make sure you have pending transmogs that cost something to set")
            end
        elseif phase == "save_done" then
            -- Server reopened Manage sets. The new set should be in the list.
            -- Locally append so the UI sees the change without a rescan.
            local exists = false
            for _, s in ipairs(GetCharDB().serverSets) do
                if s.name == name then exists = true break end
            end
            if not exists then
                table.insert(GetCharDB().serverSets, { name = name })
            end
            Print("Saved set '" .. name .. "'")
            if not BackFromCurrentMenu(opts, "save_done2") then
                FailSetAction("no Back option from Manage sets after save")
            end
        elseif phase == "save_done2" then
            ResetSetAction()
            if W.ShowWardrobeUI then W.ShowWardrobeUI() end
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
            if W.ShowWardrobeUI then W.ShowWardrobeUI() end
        end
    end
end

-- Entry points -------------------------------------------------------------

local function precheckBusy()
    if (W.applyState and W.applyState.active)
       or (W.scanState and W.scanState.active)
       or setActionState.active then
        ErrorMsg("Already busy -- please wait.")
        return false
    end
    if not GossipFrame or (not GossipFrame:IsShown() and not W.suppressing) then
        ErrorMsg("Open the Warpweaver first.")
        return false
    end
    local char = GetCharDB()
    if not char.extras.manageSets then
        ErrorMsg("'Manage sets' option not found -- try /wb rescan.")
        return false
    end
    return true
end

function W.StartUseServerSet(setName)
    if not precheckBusy() then return end
    setActionState.active  = true
    setActionState.op      = "use"
    setActionState.setName = setName
    setActionState.phase   = "use_enter_manage"
    W.SuppressGossipFrame()
    local idx = GetCharDB().extras.manageSets
    W.ScheduleClick(function() SelectGossipOption(idx) end)
end

function W.StartSaveServerSet(setName)
    if not precheckBusy() then return end
    setActionState.active  = true
    setActionState.op      = "save"
    setActionState.setName = setName
    setActionState.phase   = "save_enter_manage"
    W.SuppressGossipFrame()
    local idx = GetCharDB().extras.manageSets
    W.ScheduleClick(function() SelectGossipOption(idx) end)
end

function W.StartDeleteServerSet(setName)
    if not precheckBusy() then return end
    setActionState.active  = true
    setActionState.op      = "delete"
    setActionState.setName = setName
    setActionState.phase   = "delete_enter_manage"
    W.SuppressGossipFrame()
    local idx = GetCharDB().extras.manageSets
    W.ScheduleClick(function() SelectGossipOption(idx) end)
end
