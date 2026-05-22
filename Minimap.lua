-------------------------------------------------------------------------------
-- Minimap.lua  --  Self-contained minimap button (no LibDBIcon dependency).
-- Position is stored as an angle (degrees) around the minimap rim; the
-- button can be dragged around the rim and right-clicked to hide.
--
--   /wb minimap        toggles visibility
--   /wb minimap reset  re-centres
--
-- The UI it opens still requires a prior Warpweaver scan for the lists to
-- have content, but inspection/staging works anywhere -- apply chains are
-- the only thing that need to be at the NPC.
-------------------------------------------------------------------------------

local addonName, W = ...

local GetDB = W.GetDB
local Print = W.Print

local minimapButton

local function PositionMinimapButton()
    if not minimapButton then return end
    local m = GetDB().ui.minimap
    local rad = math.rad(m.angle or 210)
    -- 80px from minimap centre puts the button on the standard rim arc.
    local x = 80 * math.cos(rad)
    local y = 80 * math.sin(rad)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
W.PositionMinimapButton = PositionMinimapButton

local function UpdateMinimapButtonVisibility()
    if not minimapButton then return end
    if GetDB().ui.minimap.hide then
        minimapButton:Hide()
    else
        minimapButton:Show()
    end
end
W.UpdateMinimapButtonVisibility = UpdateMinimapButtonVisibility

function W.CreateMinimapButton()
    if minimapButton then return end
    if not Minimap then return end  -- shouldn't happen, but guard anyway

    local btn = CreateFrame("Button", "WardrobeMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetSize(31, 31)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Icon sits inside the ring. SetTexCoord trims the corner glow so the
    -- square Blizzard icon fits cleanly inside the round border overlay.
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\ICONS\\INV_Misc_Cape_18")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Blizzard's standard minimap-button ring. 54x54 anchored at TOPLEFT
    -- is the exact size/position every stock and third-party minimap
    -- button uses -- change at your peril.
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffd4af37" .. W.ADDON_NAME .. "|r  |cff888866v" .. W.ADDON_VERSION .. "|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("|cffffffffLeft-click|r",  "toggle the wardrobe",                          1,1,1, 0.85,0.85,0.85)
        GameTooltip:AddDoubleLine("|cffffffffRight-click|r", "hide this button",                             1,1,1, 0.85,0.85,0.85)
        GameTooltip:AddDoubleLine("|cffffffffDrag|r",        "reposition around the minimap",               1,1,1, 0.85,0.85,0.85)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888866/wb minimap|r to restore after hiding.", 0.78,0.65,0.25)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            GetDB().ui.minimap.hide = true
            UpdateMinimapButtonVisibility()
            Print("Minimap button hidden. Type |cffd4af37/wb minimap|r to bring it back.")
            return
        end
        local ui = W.ui
        if ui.frame and ui.frame:IsShown() then
            ui.frame:Hide()
        else
            W.ShowWardrobeUI()
        end
    end)

    -- Drag-to-reposition. OnUpdate is only attached while a drag is in
    -- progress; the angle is recomputed from the cursor's position
    -- relative to the minimap centre on every frame.
    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            if not mx then return end
            local scale = Minimap:GetEffectiveScale()
            local px, py = GetCursorPosition()
            px, py = px / scale, py / scale
            GetDB().ui.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            PositionMinimapButton()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)

    minimapButton = btn
    PositionMinimapButton()
    UpdateMinimapButtonVisibility()
end
