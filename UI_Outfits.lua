-------------------------------------------------------------------------------
-- UI_Outfits.lua  --  Doll preview, outfit save/load/delete, row context
-- menu (right-click on an item), StaticPopup dialogs, and the main
-- ShowWardrobeUI entry point.
-------------------------------------------------------------------------------

local addonName, W = ...

local SLOTS         = W.SLOTS
local SLOT_BY_ID    = W.SLOT_BY_ID
local QUALITY_COLOR = W.QUALITY_COLOR
local IsEnchantSlot = W.IsEnchantSlot
local GetDB         = W.GetDB
local GetCharDB     = W.GetCharDB
local Print         = W.Print
local ErrorMsg      = W.ErrorMsg
local MakeBackdrop  = W.MakeBackdrop

local ui           = W.ui
local previewSlots = W.previewSlots

function ui.UpdatePreviewLabel()
    if not ui.previewLbl then return end
    local nTransmog, nHide = 0, 0
    for _, v in pairs(previewSlots) do
        if v == "HIDE" then nHide = nHide + 1 else nTransmog = nTransmog + 1 end
    end
    if nTransmog == 0 and nHide == 0 then
        ui.previewLbl:SetText("Previewing current look\nLeft-click to stage, right-click for menu")
        ui.previewLbl:SetTextColor(0.6, 0.6, 0.65)
    else
        local parts = {}
        if nTransmog > 0 then table.insert(parts, nTransmog .. " transmog" .. (nTransmog > 1 and "s" or "")) end
        if nHide     > 0 then table.insert(parts, nHide     .. " hide"     .. (nHide     > 1 and "s" or "")) end
        ui.previewLbl:SetText(table.concat(parts, " + ") .. " staged\nApply Preview to commit")
        ui.previewLbl:SetTextColor(0.95, 0.85, 0.45)
    end
    -- Re-render slot tab counters so the gold "*" badge appears/disappears
    -- in sync with the staged-preview set.
    if ui.RefreshTabs then ui.RefreshTabs() end
end

-- Walk previewSlots and TryOn each item's link. Reset to the player's
-- current equipped+transmogged look first via SetUnit("player"). A preview
-- value of "HIDE" tries to undress that slot (best-effort: 3.3.5a may not
-- have UndressSlot, in which case the doll still shows the current item but
-- the preview label still records the pending hide). Enchant pseudo-slots
-- (synthetic IDs 96/97) are skipped -- DressUpModel can't render enchant
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
            -- Enchant illusion -- no doll preview, just stays staged.
        elseif entry == "HIDE" then
            pcall(function() ui.doll:UndressSlot(slotId) end)
        else
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

-- Clear the staged preview for a single slot, leaving previews on other
-- slots intact. Triggered by right-clicking a slot tab.
function ui.ClearSlotPreview(slotId)
    if slotId == nil or previewSlots[slotId] == nil then return end
    previewSlots[slotId] = nil
    ui.RefreshDoll()
    ui.UpdatePreviewLabel()
end

-- Toggle the favourite flag for an item/enchant entry. Favourites are
-- per-character (each alt has its own go-to looks) and persist in the
-- SavedVariables.
function ui.ToggleFavourite(entry)
    if entry == nil then return end
    local char = GetCharDB()
    char.favourites = char.favourites or {}
    if char.favourites[entry] then
        char.favourites[entry] = nil
    else
        char.favourites[entry] = true
    end
    ui.RefreshList()
end

-- Toggle the per-row "Hide from List" flag. Hidden entries are filtered
-- out of the wardrobe unless the "Show hidden items" doll-column toggle
-- is on.
function ui.ToggleHidden(entry)
    if entry == nil then return end
    local char = GetCharDB()
    char.hiddenEntries = char.hiddenEntries or {}
    if char.hiddenEntries[entry] then
        char.hiddenEntries[entry] = nil
    else
        char.hiddenEntries[entry] = true
    end
    ui.RefreshList()
end

-------------------------------------------------------------------------------
-- ROW CONTEXT MENU (right-click)
--
-- A single shared menu reused across all rows; populated per-row in
-- ui.ShowRowContextMenu. Closes when the mouse goes down outside the menu
-- (polled via OnUpdate). Doesn't sit behind a click-eater frame so the
-- click that closes the menu still reaches the underlying widget.
-------------------------------------------------------------------------------

local rowMenu

local function HideRowMenu()
    if rowMenu then rowMenu:Hide() end
end

local function CreateRowMenu()
    if rowMenu then return rowMenu end
    local m = CreateFrame("Frame", "WardrobeRowContextMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetWidth(190)
    m:EnableMouse(true)
    MakeBackdrop(m, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    m:SetBackdropColor(0.08, 0.05, 0.12, 0.97)
    m:SetBackdropBorderColor(0.40, 0.25, 0.70, 1)
    m:Hide()

    -- Header: small item icon + quality-coloured name.
    m.headIcon = m:CreateTexture(nil, "ARTWORK")
    m.headIcon:SetSize(16, 16)
    m.headIcon:SetPoint("TOPLEFT", m, "TOPLEFT", 8, -8)

    m.headFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.headFs:SetPoint("LEFT",  m.headIcon, "RIGHT",   6, 0)
    m.headFs:SetPoint("RIGHT", m,          "RIGHT", -10, 0)
    m.headFs:SetJustifyH("LEFT")
    m.headFs:SetWordWrap(false)

    local div = m:CreateTexture(nil, "OVERLAY")
    div:SetTexture("Interface\\Buttons\\WHITE8X8")
    div:SetVertexColor(0.55, 0.42, 0.18, 0.7)
    div:SetHeight(1)
    div:SetPoint("LEFT",  m, "LEFT",   8, 0)
    div:SetPoint("RIGHT", m, "RIGHT", -8, 0)
    div:SetPoint("TOP",   m.headIcon, "BOTTOM", 0, -5)
    m.div = div

    m.buttons = {}
    for i = 1, 5 do
        local b = CreateFrame("Button", nil, m)
        b:SetHeight(20)
        local hi = b:CreateTexture(nil, "BACKGROUND")
        hi:SetAllPoints()
        hi:SetTexture("Interface\\Buttons\\WHITE8X8")
        hi:SetVertexColor(0.45, 0.30, 0.65, 0)
        b.hi = hi
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", 6, 0)
        fs:SetJustifyH("LEFT")
        b.fs = fs
        b:SetScript("OnEnter", function(self) self.hi:SetVertexColor(0.45,0.30,0.65,0.55) end)
        b:SetScript("OnLeave", function(self) self.hi:SetVertexColor(0.45,0.30,0.65,0)    end)
        b:Hide()
        m.buttons[i] = b
    end

    -- Outside-click closer (poll only while shown).
    m:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self)
            if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
               and not MouseIsOver(self) then
                self:Hide()
            end
        end)
    end)
    m:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        for _, b in ipairs(self.buttons) do b:Hide() end
    end)

    rowMenu = m
    return m
end

function ui.ShowRowContextMenu(slotId, itemData)
    if not (slotId and itemData) then return end
    local m = CreateRowMenu()
    local char = GetCharDB()
    char.hiddenEntries = char.hiddenEntries or {}
    char.favourites    = char.favourites    or {}
    local isFav    = char.favourites[itemData.entry]    and true or false
    local isHidden = char.hiddenEntries[itemData.entry] and true or false

    m.headIcon:SetTexture(itemData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local qc = QUALITY_COLOR[itemData.quality or 1] or {1,1,1}
    m.headFs:SetText(string.format("|cff%02x%02x%02x%s|r",
        qc[1]*255, qc[2]*255, qc[3]*255, itemData.name or "?"))

    local entries = {
        { label  = "Apply",
          colour = {1.00, 0.95, 0.60},
          action = function() W.ApplyEntry(slotId, itemData.entry) end },
        { label  = "Try On (preview)",
          colour = {0.85, 0.85, 1.00},
          action = function()
              if ui.PreviewItem then ui.PreviewItem(slotId, itemData) end
          end },
        { label  = isFav and "Unfavourite" or "Favourite",
          colour = {1.00, 0.85, 0.30},
          action = function() ui.ToggleFavourite(itemData.entry) end },
        { label  = isHidden and "Unhide (restore to list)" or "Hide from List",
          colour = {0.85, 0.55, 0.55},
          action = function() ui.ToggleHidden(itemData.entry) end },
        { label  = "Cancel",
          colour = {0.65, 0.65, 0.70},
          action = function() end },
    }
    for i, b in ipairs(m.buttons) do
        local e = entries[i]
        if e then
            b.fs:SetText(e.label)
            b.fs:SetTextColor(e.colour[1], e.colour[2], e.colour[3])
            b:SetScript("OnClick", function()
                e.action()
                HideRowMenu()
            end)
            b:ClearAllPoints()
            b:SetPoint("LEFT",  m, "LEFT",   6, 0)
            b:SetPoint("RIGHT", m, "RIGHT", -6, 0)
            b:SetPoint("TOP",   m.div, "BOTTOM", 0, -2 - (i-1)*20)
            b:Show()
        else
            b:Hide()
        end
    end
    -- Height = top pad 8 + icon 16 + div pad 5 + 1 div + 2 top inset
    --        + 5 entries * 20 + bottom pad 8
    m:SetHeight(8 + 16 + 5 + 1 + 2 + #entries * 20 + 8)

    local scale  = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    m:ClearAllPoints()
    m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx/scale, cy/scale)
    m:Show()
end

-------------------------------------------------------------------------------
-- OUTFIT DROPDOWN MENUS
-------------------------------------------------------------------------------

function ui.RebuildOutfitMenu()
    local menu = ui.outfitMenu
    if not menu then return end
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
    for i, outfit in ipairs(outfits) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, -4 - (i-1)*20)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i-1)*20)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                -- Right-click: Load / Share / Delete context menu.
                -- Don't auto-hide the outfit dropdown -- keep it open so the
                -- user can right-click another outfit immediately.
                if ui.ShowOutfitContextMenu then
                    ui.ShowOutfitContextMenu(idx)
                end
            else
                ui.SelectOutfit(idx)
                menu:Hide()
            end
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
            menu.empty:SetText("(no server sets -- Save one first)")
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
            W.StartUseServerSet(setName)
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
    Print("Loaded outfit '" .. outfit.name .. "' -- click Apply Preview to commit.")
end

function ui.SaveCurrentPreviewAsOutfit(name)
    local n = 0; for _ in pairs(previewSlots) do n = n + 1 end
    if n == 0 then
        ErrorMsg("Nothing to save -- preview some items first.")
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

-------------------------------------------------------------------------------
-- STATIC POPUP DIALOGS
--
-- IMPORTANT: WoW 3.3.5a's StaticPopup_Show does NOT set `dialog.editBox` as
-- a field -- it only creates the named child frame "<DialogName>EditBox".
-- Accessing self.editBox returns nil and any :GetText() call errors silently.
-- We have to fetch the edit box via the global lookup. The `self.editBox or`
-- guard keeps the addon forward-compatible with later clients that DO set
-- the field.
-------------------------------------------------------------------------------

local function PopupEditBox(dialog)
    if not dialog then return nil end
    return dialog.editBox or _G[dialog:GetName() .. "EditBox"]
end
W.PopupEditBox = PopupEditBox

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
        if name ~= "" then W.StartSaveServerSet(name) end
    end,
    OnShow = function(self)
        local eb = PopupEditBox(self)
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    EditBoxOnEnterPressed = function(self)
        local name = (self:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
        if name ~= "" then W.StartSaveServerSet(name) end
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
        if idx and sets[idx] then W.StartDeleteServerSet(sets[idx].name) end
    end,
}

StaticPopupDialogs["WARDROBE_CONFIRM_RESTORE_ORIGINAL"] = {
    text         = "Remove transmogs from |cffff8c40every equipped slot|r?\n\nThis can't be undone -- you'll have to re-apply each appearance individually (which costs gold per slot).",
    button1      = "Restore",
    button2      = "Cancel",
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function()
        -- Server is stripping all transmogs; our local "applied" tracker
        -- needs to match or the "Hide applied" filter will lie.
        local char = GetCharDB()
        if char.applied then wipe(char.applied) end
        W.ClickExtra("restore", "Restore original look")
    end,
}

function ui.SelectSlot(slotId)
    ui.currentSlot = slotId
    ui.RefreshTabs()
    ui.UpdateHideButton()
    ui.RefreshList()
end

function W.ShowWardrobeUI()
    W.CreateMainFrame()
    W.BuildSlotTabs()
    ui.UpdateQualityButton()
    if not ui.currentSlot then ui.currentSlot = SLOTS[1].id end
    ui.RefreshTabs()
    ui.UpdateHideButton()
    ui.UpdatePreviewLabel()
    ui.ApplyBackgroundPref()
    if ui.appChk then ui.appChk:SetChecked(GetDB().ui.hideApplied and true or false) end
    if ui.hidChk then ui.hidChk:SetChecked(GetDB().ui.showHidden and true or false) end
    ui.RefreshDoll()
    ui.RefreshList()
    -- Pre-warm any unresolved item cache entries -- without this, items the
    -- player has never owned appear as "Common ?" until manually hovered.
    W.BuildWarmQueue()
    ui.frame:Show()
end
