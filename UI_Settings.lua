-------------------------------------------------------------------------------
-- UI_Settings.lua  --  centralised settings frame (v1.22).
--
-- Surfaces every persistent toggle in one scrollable dialog. The pre-existing
-- doll-column checkboxes (Background art / Hide applied / Show hidden) and
-- top-row cycle buttons stay as quick-access shortcuts -- this panel is the
-- canonical edit surface plus a home for the previously slash-only knobs
-- (`/wb debug`, `/wb npcname`, scan throttle).
--
-- Opens from:
--   * Gear button beside the close X on the main wardrobe window
--   * /wb settings (or /wb config) slash command
-------------------------------------------------------------------------------

local addonName, W = ...

local QUALITY_COLOR = W.QUALITY_COLOR
local QUALITY_NAME  = W.QUALITY_NAME
local GetDB         = W.GetDB
local Print         = W.Print
local MakeBackdrop  = W.MakeBackdrop
local L             = W.L

local ui = W.ui

local FRAME_W, FRAME_H = 520, 560

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------

-- Vertical layout cursor. Each helper builds a control anchored relative
-- to the previous one, so sections grow naturally.
local function SectionHeader(parent, prev, text)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.83, 0.69, 0.22, 0.7)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0,  -12)
    divider:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0,  -12)

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -6)
    fs:SetText("|cffd4af37" .. text .. "|r")
    return fs
end

local function MakeCheckbox(parent, name, label, prev, get, set, tooltipBody)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
    local txt = _G[name .. "Text"]
    txt:SetText(label)
    txt:SetFontObject("GameFontNormalSmall")
    cb:SetChecked(get())
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    if tooltipBody then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(tooltipBody, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb.refresh = function() cb:SetChecked(get()) end
    return cb
end

local function MakeSlider(parent, name, label, prev, minV, maxV, step, get, set, fmt)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(380, 44)
    container:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10)

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetText(label)

    local valFs = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valFs:SetPoint("TOPRIGHT", 0, 0)
    valFs:SetJustifyH("RIGHT")
    valFs:SetTextColor(1, 0.95, 0.6)

    local slider = CreateFrame("Slider", name, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -8)
    slider:SetSize(380, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetValue(get())
    _G[name .. "Low"]:SetText(tostring(minV))
    _G[name .. "High"]:SetText(tostring(maxV))
    _G[name .. "Text"]:SetText("")
    local updateVal = function(v)
        valFs:SetText(fmt and fmt(v) or string.format("%.2f", v))
    end
    updateVal(get())
    slider:SetScript("OnValueChanged", function(self, value)
        -- Snap to step grid (3.3.5a doesn't enforce SetValueStep on drag).
        value = math.floor(value / step + 0.5) * step
        set(value)
        updateVal(value)
    end)
    slider.refresh = function()
        slider:SetValue(get())
        updateVal(get())
    end
    return container, slider
end

-------------------------------------------------------------------------------
-- NPC NAME EDITOR
-- Wraps a small scroll frame listing each currently-recognised NPC name with
-- a Remove button per row, plus an Add row at the bottom.
-------------------------------------------------------------------------------

local function RebuildNpcList(listFrame)
    -- Clear existing rows.
    if listFrame.rows then
        for _, r in ipairs(listFrame.rows) do r:Hide() end
    else
        listFrame.rows = {}
    end
    local db    = GetDB()
    local names = {}
    for n, on in pairs(db.npcNames or {}) do
        if on then table.insert(names, n) end
    end
    table.sort(names)
    for i, name in ipairs(names) do
        local row = listFrame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, listFrame)
            row:SetSize(380, 20)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("LEFT", 4, 0)
            row.fs = fs
            local rm = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            rm:SetSize(70, 18)
            rm:SetPoint("RIGHT", -2, 0)
            rm:SetText(L["Remove"])
            row.rm = rm
            listFrame.rows[i] = row
        end
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(i - 1) * 22)
        row.fs:SetText(name)
        row.rm:SetScript("OnClick", function()
            GetDB().npcNames[name] = nil
            RebuildNpcList(listFrame)
        end)
        row:Show()
    end
    listFrame:SetHeight(math.max(20, #names * 22))
end

-------------------------------------------------------------------------------
-- MAIN FRAME
-------------------------------------------------------------------------------

function W.CreateSettingsFrame()
    if ui.settingsFrame then return ui.settingsFrame end
    local f = CreateFrame("Frame", "WardrobeSettingsFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    MakeBackdrop(f, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    f:SetBackdropBorderColor(0.40, 0.25, 0.70)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffd4af37" .. L["Wardrobe Settings"] .. "|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Scrollable content area.
    local outer = CreateFrame("Frame", nil, f)
    outer:SetPoint("TOPLEFT",     12, -40)
    outer:SetPoint("BOTTOMRIGHT", -12, 12)

    local sf = CreateFrame("ScrollFrame", "WardrobeSettingsSF", outer, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     outer, "TOPLEFT",      4, -4)
    sf:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(FRAME_W - 60, 1)   -- height set after we lay everything out
    sf:SetScrollChild(content)

    -- A first invisible anchor so SectionHeader has something to chain from.
    local cursor = CreateFrame("Frame", nil, content)
    cursor:SetSize(1, 1)
    cursor:SetPoint("TOPLEFT", 0, 0)

    f.controls = {}
    local function add(c) table.insert(f.controls, c); return c end

    -- ===== Filters & sort =====
    local h1 = SectionHeader(content, cursor, L["Filters & sort"])
    local sortLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortLabel:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -8)
    sortLabel:SetText("Default sort order: open the Sort dropdown in the main window.")
    sortLabel:SetTextColor(0.75, 0.75, 0.80)

    local qualityLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualityLabel:SetPoint("TOPLEFT", sortLabel, "BOTTOMLEFT", 0, -4)
    qualityLabel:SetText("Quality filter and Collection filter live on the second filter row.")
    qualityLabel:SetTextColor(0.75, 0.75, 0.80)

    -- ===== Visibility =====
    local h2 = SectionHeader(content, qualityLabel, L["Visibility"])

    add(MakeCheckbox(content, "WardrobeSetBg", L["Background art"], h2,
        function() return GetDB().ui.showBackground end,
        function(v)
            GetDB().ui.showBackground = v
            if ui.ApplyBackgroundPref then ui.ApplyBackgroundPref() end
        end,
        "Show the custom transmog scene behind the wardrobe. When off, columns return to opaque dark."))
    add(MakeCheckbox(content, "WardrobeSetApplied", L["Hide applied items"], f.controls[#f.controls],
        function() return GetDB().ui.hideApplied end,
        function(v)
            GetDB().ui.hideApplied = v
            if ui.appChk then ui.appChk:SetChecked(v) end
            if ui.RefreshList then ui.RefreshList() end
        end,
        "Once an item is applied via Wardrobe, hide it from the list. Tracking begins on install -- pre-existing transmogs aren't known until re-applied through Wardrobe."))
    add(MakeCheckbox(content, "WardrobeSetHidden", L["Show hidden items"], f.controls[#f.controls],
        function() return GetDB().ui.showHidden end,
        function(v)
            GetDB().ui.showHidden = v
            if ui.hidChk then ui.hidChk:SetChecked(v) end
            if ui.RefreshList then ui.RefreshList() end
        end,
        "Show items you've right-clicked as 'Hide from List'. Off by default."))
    add(MakeCheckbox(content, "WardrobeSetMinimap", L["Hide minimap button"], f.controls[#f.controls],
        function() return GetDB().ui.minimap and GetDB().ui.minimap.hide end,
        function(v)
            GetDB().ui.minimap = GetDB().ui.minimap or {}
            GetDB().ui.minimap.hide = v
            if W.UpdateMinimapButtonVisibility then W.UpdateMinimapButtonVisibility() end
        end,
        "Hide the small minimap button. /wb minimap toggles this too."))
    -- v1.24: favourites scope toggle. Checkbox semantics chosen over a
    -- dropdown because there are only two options. Switching MERGES the
    -- current scope's favourites into the destination (lossless union) so
    -- flipping the toggle never drops an existing pin.
    add(MakeCheckbox(content, "WardrobeSetFavScope", L["Share favourites across all my characters"], f.controls[#f.controls],
        function() return (GetDB().ui.favouritesScope or "character") == "account" end,
        function(v)
            W.SetFavouritesScope(v and "account" or "character")
            if ui.RefreshList then ui.RefreshList() end
        end,
        "When OFF (default), each character keeps its own favourite list. When ON, all your characters share one favourite list -- starring an item on your warrior shows it starred on your mage too. Switching either direction MERGES the lists (lossless), so you can flip this freely without losing anything."))

    -- ===== Behaviour =====
    local lastCb = f.controls[#f.controls]
    local h3 = SectionHeader(content, lastCb, L["Behaviour"])

    local _, slider = MakeSlider(content, "WardrobeSetScanDelay",
        L["Scan step delay (seconds)"], h3,
        0.05, 0.50, 0.05,
        function() return GetDB().scanStepDelay or W.SCAN_STEP_DELAY end,
        function(v) GetDB().scanStepDelay = v end,
        function(v) return string.format("%.2fs", v) end)
    table.insert(f.controls, slider)

    local sliderHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sliderHelp:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -4)
    sliderHelp:SetWidth(380)
    sliderHelp:SetJustifyH("LEFT")
    sliderHelp:SetText("Higher values are slower but safer on laggy servers. 0.10s works on local servers; bump to 0.20-0.30s if scans drop clicks.")
    sliderHelp:SetTextColor(0.75, 0.75, 0.80)

    -- ===== NPC names =====
    local h4 = SectionHeader(content, sliderHelp, L["Recognised NPC names"])
    local npcHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    npcHelp:SetPoint("TOPLEFT", h4, "BOTTOMLEFT", 0, -6)
    npcHelp:SetWidth(380)
    npcHelp:SetJustifyH("LEFT")
    npcHelp:SetText("Talking to any of these NPCs replaces the gossip frame with Wardrobe. Add custom transmog NPCs here.")
    npcHelp:SetTextColor(0.75, 0.75, 0.80)

    local npcList = CreateFrame("Frame", nil, content)
    npcList:SetPoint("TOPLEFT", npcHelp, "BOTTOMLEFT", 0, -4)
    npcList:SetSize(380, 20)
    f.npcList = npcList

    local addRow = CreateFrame("Frame", nil, content)
    addRow:SetSize(380, 22)
    addRow:SetPoint("TOPLEFT", npcList, "BOTTOMLEFT", 0, -4)
    f.npcAddRow = addRow

    local addBox = CreateFrame("EditBox", "WardrobeSetNpcAdd", addRow, "InputBoxTemplate")
    addBox:SetSize(220, 22)
    addBox:SetPoint("LEFT", 4, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(40)

    local addBtn = CreateFrame("Button", nil, addRow, "UIPanelButtonTemplate")
    addBtn:SetSize(70, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 12, 0)
    addBtn:SetText(L["Add"])
    addBtn:SetScript("OnClick", function()
        local name = (addBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return end
        GetDB().npcNames = GetDB().npcNames or {}
        GetDB().npcNames[name] = true
        addBox:SetText("")
        addBox:ClearFocus()
        RebuildNpcList(npcList)
        Print("Added '" .. name .. "' to recognised NPC names.")
    end)
    addBox:SetScript("OnEnterPressed", function() addBtn:Click() end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- ===== Debug =====
    local h5 = SectionHeader(content, addRow, L["Debug"])
    add(MakeCheckbox(content, "WardrobeSetDebug", L["Verbose chat logging"], h5,
        function() return GetDB().debug end,
        function(v) GetDB().debug = v end,
        "Print scan-state transitions and gossip-option dumps to chat. Useful when something isn't scanning correctly. /wb debug toggles this too."))

    -- Content height: section sizes are static except the NPC list which
    -- depends on how many names are registered. Recompute on each Show.
    -- v1.24 added one checkbox row (favourites scope) so STATIC_HEIGHT
    -- grew from 540 to 570.
    local STATIC_HEIGHT = 570  -- everything above + below the NPC list
    f:SetScript("OnShow", function(self)
        for _, c in ipairs(self.controls) do
            if c.refresh then c.refresh() end
        end
        RebuildNpcList(npcList)
        content:SetHeight(STATIC_HEIGHT + npcList:GetHeight())
    end)

    ui.settingsFrame = f
    return f
end

function W.ShowSettingsFrame()
    local f = W.CreateSettingsFrame()
    f:Show()
end

function W.ToggleSettingsFrame()
    local f = W.CreateSettingsFrame()
    if f:IsShown() then f:Hide() else f:Show() end
end
