-------------------------------------------------------------------------------
-- Wardrobe  v1.19
-- Copyright (c) 2026 Veronica-Vasilieva and the Wardrobe contributors.
-- Released under the Wardrobe Source-Available License -- see LICENSE.
-- Project home: https://github.com/Veronica-Vasilieva/Wardrobe
--
-- Interactive transmog browser for Project Ebonhold's Warpweaver NPC.
-- Replaces the gossip-menu paging UI with a searchable per-slot wardrobe.
--
-- This file is the slim entry point: ADDON_LOADED/PLAYER_LOGIN/gossip event
-- dispatch and the /wardrobe (/wb) slash command. All feature code lives
-- in the sibling modules (Core, Scan, Apply, ServerSets, UI_Main, UI_Outfits,
-- Minimap, Sharing). See Wardrobe.toc for the load order.
--
-- Slash commands: /wardrobe  /wb  /wb rescan  /wb reset  /wb debug
--                 /wb minimap [reset]  /wb share <Outfit>  /wb import <code>
--                 /wb npcname <Name>
-------------------------------------------------------------------------------

local addonName, W = ...

local SCAN_TTL = W.SCAN_TTL

-------------------------------------------------------------------------------
-- EVENT DISPATCH
-------------------------------------------------------------------------------

local function NeedsScan()
    local char = W.GetCharDB()
    return (time() - (char.lastScan or 0)) > SCAN_TTL
end

local function OnGossipShow()
    -- Driver phases first
    if W.scanState.active then
        W.OnGossipShowDuringScan()
        return
    end
    if W.applyState.active then
        W.OnGossipShowDuringApply()
        return
    end
    if W.setActionState.active then
        W.OnGossipShowDuringSetAction()
        return
    end
    -- If the user clicked "Server Menu" they want to interact with the native
    -- gossip frame directly -- don't re-suppress on every option click.
    if W.ui.userInServerMenu then
        W.Dbg("user in server menu -- letting native gossip render")
        return
    end
    -- Fresh open
    if not W.IsTransmogNPC() then return end
    W.Dbg("Warpweaver gossip detected")
    if NeedsScan() then
        W.StartScan()
    else
        W.SuppressGossipFrame()
        W.ClassifyMainMenu()
        W.ShowWardrobeUI()
    end
end

local function OnGossipClosed()
    if W.scanState.active then
        -- Save partial progress rather than losing it.
        local char = W.GetCharDB()
        char.lastScan = time()
        local total, slotsHit = 0, 0
        for _, items in pairs(char.collection) do
            total = total + #items
            if #items > 0 then slotsHit = slotsHit + 1 end
        end
        W.Print(string.format("Gossip closed mid-scan -- saved %d appearances across %d slots. Reopen Warpweaver and /wb rescan to continue.",
            total, slotsHit))
        W.ResetScan()
    end
    if W.applyState.active or W.outfitQueue then
        -- Clear queue first so the chained onComplete doesn't try to start
        -- a new ApplyEntry against a closed gossip session.
        W.outfitQueue           = nil
        W.outfitFinalize        = false
        W.applyState.onComplete = nil
        W.ResetApply()
    end
    if W.setActionState.active then
        W.ResetSetAction()
    end
    -- Closing gossip ends any Server Menu detour
    W.ui.userInServerMenu = false
    W.RestoreGossipFrame()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == W.ADDON then
        W.GetDB()
    elseif event == "PLAYER_LOGIN" then
        W.GetCharDB()
        W.InstallGossipSuppression()
        W.CreateMinimapButton()
        W.InstallChatHooks()
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
    -- Preserve original casing for arguments to share/import (outfit
    -- names are case-sensitive in storage; WBS1 codes use mixed case).
    local raw   = (msg or ""):gsub("^%s+",""):gsub("%s+$","")
    local lower = raw:lower()
    if lower:sub(1, 6) == "share " then
        W.ui.ShareOutfitByName(raw:sub(7):gsub("^%s+",""):gsub("%s+$",""))
        return
    end
    if lower:sub(1, 7) == "import " then
        W.ui.ShowImportPopup(raw:sub(8):gsub("^%s+",""):gsub("%s+$",""))
        return
    end
    msg = lower
    if msg == "rescan" then
        if GossipFrame and GossipFrame:IsShown() or W.suppressing then
            W.StartScan()
        else
            W.Print("Talk to the Warpweaver, then /wb rescan.")
        end
    elseif msg == "reset" then
        WardrobeDB = nil
        W.Print("All data reset. Reload with /reload.")
    elseif msg == "debug" then
        local db = W.GetDB()
        db.debug = not db.debug
        W.Print("Debug " .. (db.debug and "ON" or "OFF"))
    elseif msg:sub(1,8) == "npcname " then
        local n = msg:sub(9):gsub("^%s+",""):gsub("%s+$","")
        if n ~= "" then
            -- preserve original casing of typed name
            W.GetDB().npcNames[n:gsub("^%l", string.upper)] = true
            W.Print("Registered NPC name: " .. n)
        end
    elseif msg == "minimap" then
        local m = W.GetDB().ui.minimap
        m.hide = not m.hide
        W.UpdateMinimapButtonVisibility()
        W.Print("Minimap button " .. (m.hide and "hidden" or "shown") .. ".")
    elseif msg == "minimap reset" then
        local m = W.GetDB().ui.minimap
        m.angle = 210
        m.hide  = false
        W.PositionMinimapButton()
        W.UpdateMinimapButtonVisibility()
        W.Print("Minimap button position reset.")
    elseif msg == "" or msg == "show" then
        if W.ui.frame and W.ui.frame:IsShown() then W.ui.frame:Hide() else W.ShowWardrobeUI() end
    else
        W.Print("|cffd4af37" .. W.ADDON_NAME .. "|r v" .. W.ADDON_VERSION ..
              " by " .. W.ADDON_AUTHOR .. "  -  " .. W.ADDON_URL)
        W.Print("Commands: /wb (toggle), /wb rescan, /wb reset, /wb debug, /wb minimap [reset], /wb share <Outfit>, /wb import <code>, /wb npcname <Name>")
    end
end

W.Print("v" .. W.ADDON_VERSION .. " by |cffd4af37" .. W.ADDON_AUTHOR ..
      "|r loaded. Talk to a Warpweaver to begin.")
