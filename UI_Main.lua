-------------------------------------------------------------------------------
-- UI_Main.lua  --  Main wardrobe window: frame, tabs, search/quality/hide
-- controls, list of appearances, and the bottom action bar.
--
-- The doll-column controls (outfits, server sets, preview management) and
-- the row context menu live in UI_Outfits.lua so this file can focus on the
-- window chrome and the list rendering.
-------------------------------------------------------------------------------

local addonName, W = ...

local SLOTS         = W.SLOTS
local SLOT_BY_ID    = W.SLOT_BY_ID
local QUALITY_COLOR = W.QUALITY_COLOR
local QUALITY_NAME  = W.QUALITY_NAME
local IsEnchantSlot = W.IsEnchantSlot
local GetDB         = W.GetDB
local GetCharDB     = W.GetCharDB
local Print         = W.Print
local MakeBackdrop  = W.MakeBackdrop
local L             = W.L
local UI_WIDTH      = W.UI_WIDTH
local UI_HEIGHT     = W.UI_HEIGHT
local DOLL_WIDTH    = W.DOLL_WIDTH
local TAB_COL_WIDTH = W.TAB_COL_WIDTH

local ui           = W.ui
local previewSlots = W.previewSlots

function W.CreateMainFrame()
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
    -- the BACKGROUND layer at sublevel 7 so it sits above the main frame's
    -- bgFile fill. Child frame backdrops have been dimmed to ~0.5 alpha so
    -- this image shows through the columns.
    local bgTex = f:CreateTexture(nil, "BACKGROUND", nil, 7)
    bgTex:SetPoint("TOPLEFT",     f, "TOPLEFT",      5,  -5)
    bgTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5,   5)
    bgTex:SetTexture("Interface\\AddOns\\Wardrobe\\Media\\Background.tga")
    bgTex:SetVertexColor(1, 1, 1, 1)
    ui.bgTex = bgTex

    -- Title bar
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffd4af37" .. L["Wardrobe"] .. "|r")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOP", 0, -32)
    subtitle:SetText(L["Project Ebonhold transmog browser"] .. "  |  v" ..
        W.ADDON_VERSION .. " by |cffd4af37" .. W.ADDON_AUTHOR .. "|r")
    subtitle:SetTextColor(0.7, 0.7, 0.75)
    ui.subtitle = subtitle

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Settings (gear) button. Sits to the LEFT of the info badge. Opens the
    -- v1.22 settings dialog with every persistent toggle grouped by section.
    local gearBtn = CreateFrame("Button", nil, f)
    gearBtn:SetSize(22, 22)
    gearBtn:SetPoint("TOPRIGHT", -56, -10)
    gearBtn:EnableMouse(true)
    local gearBg = gearBtn:CreateTexture(nil, "BACKGROUND")
    gearBg:SetAllPoints()
    gearBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    gearBg:SetVertexColor(0.18, 0.10, 0.30, 0.85)
    local gearFs = gearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gearFs:SetPoint("CENTER", 0, 0)
    gearFs:SetText("|cffffd700[S]|r")
    gearBtn:SetScript("OnClick", function()
        if W.ToggleSettingsFrame then W.ToggleSettingsFrame() end
    end)
    gearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Settings")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Open the Wardrobe settings panel. Also opens with |cffffd200/wb settings|r.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- "?" info badge next to the close button. Hover -> addon info, slash
    -- command list, license, and project URL.
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
        GameTooltip:AddLine("|cffd4af37" .. W.ADDON_NAME .. "|r v" .. W.ADDON_VERSION)
        GameTooltip:AddLine("|cff888866by " .. W.ADDON_AUTHOR .. "|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700About:|r")
        GameTooltip:AddLine("|cffaaaaaaInteractive transmog browser for Project Ebonhold's Warpweaver NPC. Replaces the gossip-menu paging UI with a searchable per-slot wardrobe, 3D paper-doll preview, outfits, and Manage Sets integration.|r", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700Slash commands:|r")
        GameTooltip:AddLine("|cffaaaaaa/wb|r |cff888866 or |r|cffaaaaaa/wardrobe|r   |cff666666open/close|r")
        GameTooltip:AddLine("|cffaaaaaa/wb settings|r   |cff666666open the settings panel|r")
        GameTooltip:AddLine("|cffaaaaaa/wb rescan|r   |cff666666rescan collection + server sets|r")
        GameTooltip:AddLine("|cffaaaaaa/wb reset|r   |cff666666wipe all saved data|r")
        GameTooltip:AddLine("|cffaaaaaa/wb debug|r   |cff666666toggle verbose chat logging|r")
        GameTooltip:AddLine("|cffaaaaaa/wb minimap|r   |cff666666hide/show minimap button|r")
        GameTooltip:AddLine("|cffaaaaaa/wb minimap reset|r   |cff666666recentre the minimap button|r")
        GameTooltip:AddLine("|cffaaaaaa/wb share <Outfit>|r   |cff666666post an outfit code to chat|r")
        GameTooltip:AddLine("|cffaaaaaa/wb import <code>|r   |cff666666import an outfit from a code|r")
        GameTooltip:AddLine("|cffaaaaaa/wb npcname <Name>|r   |cff666666register a custom NPC name|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700In-window controls:|r")
        GameTooltip:AddLine("|cffaaaaaaLeft-click item|r   |cff666666stage on the doll|r")
        GameTooltip:AddLine("|cffaaaaaaRight-click item|r   |cff666666menu: Apply / Try On / Favourite / Hide|r")
        GameTooltip:AddLine("|cffaaaaaaRight-click outfit|r   |cff666666menu: Load / Share / Delete|r")
        GameTooltip:AddLine("|cffaaaaaaClick star|r   |cff666666favourite (pin to top)|r")
        GameTooltip:AddLine("|cffaaaaaaLeft-click slot tab|r   |cff666666switch slots|r")
        GameTooltip:AddLine("|cffaaaaaaRight-click slot tab|r   |cff666666clear that slot's preview|r")
        GameTooltip:AddLine("|cffaaaaaaLeft-drag doll|r   |cff666666rotate model|r")
        GameTooltip:AddLine("|cffaaaaaaRight-drag doll|r   |cff666666pan vertically|r")
        GameTooltip:AddLine("|cffaaaaaaMouse wheel on doll|r   |cff666666zoom in/out|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd700License:|r")
        GameTooltip:AddLine("|cffaaaaaaSource-available. Attribution required. See LICENSE for full terms.|r", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888866" .. W.ADDON_URL .. "|r")
        GameTooltip:Show()
    end)
    infoBadge:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Closing the wardrobe ends the gossip session cleanly. Calling
    -- CloseGossip() fires GOSSIP_CLOSED which restores GossipFrame visibility.
    -- The Server Menu button sets ui.skipCloseGossip = true so it can hand
    -- control back to the native gossip frame without ending the session.
    f:SetScript("OnHide", function()
        if ui.skipCloseGossip then return end
        if GossipFrame and (GossipFrame:IsShown() or W.suppressing) then
            CloseGossip()
        end
    end)

    -- Dual ticker:
    --   * Cache warming  -- pings the scanner tooltip ~20x/sec to fetch
    --     item info from the server for entries the client hasn't seen.
    --   * Display refresh -- every ~0.4s, re-resolve unresolved items in
    --     the current slot via GetItemInfo (now likely cached) and update
    --     the list when any new ones come through.
    f.warmAccum    = 0
    f.refreshAccum = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.warmAccum    = self.warmAccum    + elapsed
        self.refreshAccum = self.refreshAccum + elapsed

        if self.warmAccum >= 0.05 and W.WarmingActive() then
            self.warmAccum = 0
            W.WarmTick()
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

    -- Search box
    local search = CreateFrame("EditBox", "WardrobeSearchBox", right, "InputBoxTemplate")
    search:SetSize(240, 22)
    search:SetPoint("TOPLEFT", 8, -4)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    -- Debounce: each keystroke resets a 100ms timer; we only call RefreshList
    -- once typing pauses. Avoids running a full filter pass on every char.
    local searchDeb = CreateFrame("Frame", nil, search)
    searchDeb:Hide()
    searchDeb.timer = 0
    searchDeb:SetScript("OnUpdate", function(self, elapsed)
        self.timer = self.timer + elapsed
        if self.timer >= 0.1 then
            self.timer = 0
            self:Hide()
            ui.RefreshList()
        end
    end)
    search:SetScript("OnTextChanged", function()
        searchDeb.timer = 0
        searchDeb:Show()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    ui.search = search

    -- Small "X" clear button inside the search box's right edge.
    local clearBtn = CreateFrame("Button", nil, search)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", search, "RIGHT", -4, 0)
    clearBtn:SetFrameLevel(search:GetFrameLevel() + 2)
    local clearFs = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearFs:SetAllPoints()
    clearFs:SetJustifyH("CENTER")
    clearFs:SetText("X")
    clearFs:SetTextColor(0.6, 0.6, 0.6)
    clearBtn.fs = clearFs
    clearBtn:SetScript("OnEnter", function(self) self.fs:SetTextColor(1, 0.4, 0.4) end)
    clearBtn:SetScript("OnLeave", function(self) self.fs:SetTextColor(0.6, 0.6, 0.6) end)
    clearBtn:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)
    clearBtn:Hide()
    search:HookScript("OnTextChanged", function(self)
        if self:GetText() ~= "" then clearBtn:Show() else clearBtn:Hide() end
    end)
    ui.searchClear = clearBtn

    local searchLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", -2, 2)
    searchLabel:SetText(L["Search"])

    -- Quality filter dropdown (simple cycle button)
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

    -- Sort dropdown (v1.20). Sits BELOW the quality button on a second
    -- filter row so the existing top row stays uncluttered and there's room
    -- next to it for the v1.21 missing-collections filter.
    local sortBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    sortBtn:SetSize(120, 22)
    sortBtn:SetPoint("TOPLEFT", qf, "BOTTOMLEFT", 0, -4)
    ui.sortBtn = sortBtn

    -- Sort popup menu. Same purple-bordered look as the outfit dropdown.
    local sortMenu = CreateFrame("Frame", nil, right)
    sortMenu:SetSize(160, 4)
    sortMenu:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", 0, -2)
    sortMenu:SetFrameStrata("DIALOG")
    MakeBackdrop(sortMenu, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    sortMenu:SetBackdropBorderColor(0.5, 0.4, 0.7)
    sortMenu:Hide()
    sortMenu.rows = {}
    ui.sortMenu = sortMenu
    -- Outside-click closer (poll only while shown). Same pattern as the
    -- row context menu in UI_Outfits.lua.
    sortMenu:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self)
            if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
               and not MouseIsOver(self) and not MouseIsOver(sortBtn) then
                self:Hide()
            end
        end)
    end)
    sortMenu:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    sortBtn:SetScript("OnClick", function()
        if sortMenu:IsShown() then sortMenu:Hide()
        else ui.RebuildSortMenu(); sortMenu:Show() end
    end)
    sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Change list sort order")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Favourites always bubble to the top when 'Favourites first' is on. The secondary sort decides the rest.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hide Slot button -- stages a "hide this slot" preview.
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

    -- Collection cycle button (v1.21). Sits BELOW the Hide Slot button on the
    -- second filter row -- same row as the Sort dropdown. Three states:
    -- All / Owned / Missing. Missing requires Data/ItemsBySlot.lua to be
    -- populated; otherwise the list shows an explanatory empty state.
    local coll = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    coll:SetSize(130, 22)
    coll:SetPoint("TOPLEFT", hide, "BOTTOMLEFT", 0, -4)
    coll:SetScript("OnClick", function()
        local db = GetDB()
        local cur = db.ui.collectionFilter or "all"
        local next = (cur == "all") and "owned" or (cur == "owned" and "missing") or "all"
        db.ui.collectionFilter = next
        ui.UpdateCollectionButton()
        ui.RefreshList()
    end)
    coll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Collection filter")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to cycle: All -> Owned only -> Missing only.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Missing requires |cffffd200Data/ItemsBySlot.lua|r to be populated. Without a master list, Missing shows an empty list with installation hints.", 0.85, 0.85, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Missing rows are dimmed and can be Tried On but not Applied -- you don't actually own the appearance yet.", 0.95, 0.65, 0.30, true)
        GameTooltip:Show()
    end)
    coll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.collBtn = coll

    -- List frame. Top inset bumped from -32 to -58 in v1.20 to make room
    -- for the second filter row (sort dropdown / future missing toggle).
    local listBg = CreateFrame("Frame", nil, right)
    listBg:SetPoint("TOPLEFT", 4, -58)
    listBg:SetPoint("BOTTOMRIGHT", -4, 4)
    MakeBackdrop(listBg, "Interface\\ChatFrame\\ChatFrameBackground")
    listBg:SetBackdropColor(0.05, 0.04, 0.08, 0.55)
    ui.listBgFrame = listBg
    listBg:SetBackdropBorderColor(0.3, 0.25, 0.4)

    local scroll = CreateFrame("ScrollFrame", "WardrobeListScroll", listBg, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 22, ui.RefreshList)
    end)
    ui.listScroll = scroll
    ui.listBg = listBg

    -- Row pool: 22 rows x 22px = 484px
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

        -- Star widget on the left edge. Left-click toggles the favourite
        -- flag for this row's entry; left-click on the rest of the row
        -- previews the item.
        local star = CreateFrame("Button", nil, row)
        star:SetSize(14, 22)
        star:SetPoint("LEFT", row, "LEFT", 4, 0)
        star:RegisterForClicks("LeftButtonUp")
        local starFs = star:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        starFs:SetAllPoints()
        starFs:SetJustifyH("CENTER")
        starFs:SetText("*")
        starFs:SetTextColor(0.35, 0.35, 0.40)
        star.fs = starFs
        star:SetScript("OnClick", function(self)
            if row.itemData then ui.ToggleFavourite(row.itemData.entry) end
        end)
        star:SetScript("OnEnter", function(self)
            self.fs:SetTextColor(1, 0.95, 0.5)
        end)
        star:SetScript("OnLeave", function(self)
            local isFav = row.itemData and W.GetFavouritesTable()[row.itemData.entry]
            if isFav then
                self.fs:SetTextColor(1, 0.85, 0.30)
            else
                self.fs:SetTextColor(0.35, 0.35, 0.40)
            end
        end)
        row.star = star

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", 20, 0)   -- shifted right to clear the star widget
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
                if ui.ShowRowContextMenu then
                    ui.ShowRowContextMenu(ui.currentSlot, self.itemData)
                end
            else
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
    ui.MakeBtn = MakeBtn

    -- ===== Doll column content =====
    local dollBg = CreateFrame("Frame", nil, dollCol)
    dollBg:SetPoint("TOPLEFT", 0, 0)
    dollBg:SetPoint("TOPRIGHT", 0, 0)
    dollBg:SetHeight(348)
    MakeBackdrop(dollBg, "Interface\\ChatFrame\\ChatFrameBackground")
    dollBg:SetBackdropColor(0.05, 0.04, 0.08, 0.55)
    ui.dollBgFrame = dollBg
    dollBg:SetBackdropBorderColor(0.3, 0.25, 0.4)

    local doll = CreateFrame("DressUpModel", "WardrobeDoll", dollBg)
    doll:SetPoint("TOPLEFT", 6, -6)
    doll:SetPoint("BOTTOMRIGHT", -6, 6)
    doll:SetUnit("player")
    ui.doll = doll

    -- 3D view controls -- left-drag rotates, right-drag pans, wheel zooms.
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
                self:SetPosition(px, py, (pz or 0) + dy)
                self.panStart = y
            end
        end
    end)
    doll:SetScript("OnMouseWheel", function(self, delta)
        local px, py, pz = self:GetPosition()
        self:SetPosition((px or 0) + delta * 0.4, py, pz)
    end)

    -- Snapshot the initial camera so the Reset View button can restore it.
    -- Note: any RefreshDoll call that hits its needsReset path (i.e. a
    -- preview gets cleared, or a HIDE'd slot un-hidden) will snap the
    -- camera back to the client's default for a DressUpModel SetUnit --
    -- the 3.3.5a client doesn't expose a way to defeat that, so we live
    -- with it. See UI_Outfits.lua RefreshDoll for the full rationale.
    local initialFacing = doll:GetFacing() or 0
    local ipx, ipy, ipz = doll:GetPosition()
    doll.resetView = function()
        doll:SetFacing(initialFacing)
        doll:SetPosition(ipx or 0, ipy or 0, ipz or 0)
    end

    local resetView = CreateFrame("Button", nil, dollBg, "UIPanelButtonTemplate")
    resetView:SetSize(56, 18)
    resetView:SetPoint("BOTTOMRIGHT", -8, 8)
    resetView:SetText(L["Reset"])
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

    -- Preview label below the doll
    local previewLbl = dollCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLbl:SetPoint("TOP", dollBg, "BOTTOM", 0, -4)
    previewLbl:SetWidth(DOLL_WIDTH)
    previewLbl:SetJustifyH("CENTER")
    previewLbl:SetTextColor(0.85, 0.78, 0.45)
    ui.previewLbl = previewLbl

    -- Outfit dropdown (custom button)
    local outfitBtn = CreateFrame("Button", nil, dollCol, "UIPanelButtonTemplate")
    outfitBtn:SetSize(DOLL_WIDTH, 22)
    outfitBtn:SetPoint("TOP", previewLbl, "BOTTOM", 0, -8)
    outfitBtn:SetText(L["Outfits (v)"])
    ui.outfitBtn = outfitBtn

    local outfitMenu = CreateFrame("Frame", nil, dollCol)
    outfitMenu:SetSize(DOLL_WIDTH, 4)
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

    -- Save / Apply / Reset / Delete buttons
    local saveBtn = MakeBtn(L["Save as Outfit"], (DOLL_WIDTH - 4) / 2, dollCol, function()
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

    local delBtn = MakeBtn(L["Delete Outfit"], (DOLL_WIDTH - 4) / 2, dollCol, function()
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

    local applyPrevBtn = MakeBtn(L["Apply Preview"], (DOLL_WIDTH - 4) / 2, dollCol, function()
        W.ApplyPreview()
    end)
    applyPrevBtn:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -4)
    ui.applyPrevBtn = applyPrevBtn

    local resetPrevBtn = MakeBtn(L["Reset Preview"], (DOLL_WIDTH - 4) / 2, dollCol, function()
        wipe(previewSlots)
        ui.RefreshDoll()
        ui.UpdatePreviewLabel()
    end)
    resetPrevBtn:SetPoint("TOPRIGHT", delBtn, "BOTTOMRIGHT", 0, -4)
    ui.resetPrevBtn = resetPrevBtn

    -- ===== Server Sets section =====
    local serverSetsBtn = CreateFrame("Button", nil, dollCol, "UIPanelButtonTemplate")
    serverSetsBtn:SetSize(DOLL_WIDTH, 22)
    serverSetsBtn:SetPoint("TOPLEFT", applyPrevBtn, "BOTTOMLEFT", 0, -10)
    serverSetsBtn:SetText(L["Server Sets (v)"])
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
        GameTooltip:AddLine("Click a set name to re-apply it to your equipped slots. The server still charges the per-transmog fee on apply -- only the paper-doll preview is free.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    serverSetsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local serverSaveBtn = MakeBtn(L["Save Server Set"], (DOLL_WIDTH - 4) / 2, dollCol, function()
        StaticPopup_Show("WARDROBE_NAME_SERVER_SET")
    end)
    serverSaveBtn:SetPoint("TOPLEFT", serverSetsBtn, "BOTTOMLEFT", 0, -4)
    serverSaveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Save current transmogs as a server set")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Captures your currently-applied transmogs into a named server set you can re-Use later. Stored server-side so it survives reinstalls.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffff8c40Costs gold|r based on the set contents (server-side fee). The cost is taken when you click Save in the popup.", 0.9, 0.7, 0.4, true)
        GameTooltip:Show()
    end)
    serverSaveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.serverSaveBtn = serverSaveBtn

    local serverDelBtn = MakeBtn(L["Delete Server Set"], (DOLL_WIDTH - 4) / 2, dollCol, function()
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

    -- Background-art toggle. Saved in db.ui.showBackground.
    local bgChk = CreateFrame("CheckButton", "WardrobeBgChk", dollCol, "UICheckButtonTemplate")
    bgChk:SetSize(22, 22)
    bgChk:SetPoint("TOP", serverDelBtn, "BOTTOM", 0, -6)
    _G["WardrobeBgChkText"]:SetText(L["Background art"])
    _G["WardrobeBgChkText"]:SetFontObject("GameFontNormalSmall")
    bgChk:SetScript("OnClick", function(self)
        GetDB().ui.showBackground = self:GetChecked() and true or false
        if ui.ApplyBackgroundPref then ui.ApplyBackgroundPref() end
    end)
    bgChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Background art")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("When checked, the custom transmog scene shows behind the wardrobe and the columns turn translucent so it shows through. When unchecked, the original opaque dark backdrop is restored.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bgChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.bgChk = bgChk

    -- Hide-applied filter
    local appChk = CreateFrame("CheckButton", "WardrobeAppliedChk", dollCol, "UICheckButtonTemplate")
    appChk:SetSize(22, 22)
    appChk:SetPoint("TOPLEFT", bgChk, "BOTTOMLEFT", 0, -2)
    _G["WardrobeAppliedChkText"]:SetText(L["Hide applied items"])
    _G["WardrobeAppliedChkText"]:SetFontObject("GameFontNormalSmall")
    appChk:SetScript("OnClick", function(self)
        GetDB().ui.hideApplied = self:GetChecked() and true or false
        if ui.RefreshList then ui.RefreshList() end
    end)
    appChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Hide applied items")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Filters items out of the list once you've applied them, so they don't clutter future browsing. Tracking begins the moment you install Wardrobe -- anything applied earlier (or via the Server Menu) won't be hidden until you re-apply via the addon.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    appChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.appChk = appChk

    -- Show-hidden toggle. Layout: sits on the same row as the Background-art
    -- checkbox, to its LEFT. The auto-generated text label is flipped to the
    -- LEFT of the box so it doesn't run into bgChk's box on the right.
    local hidChk = CreateFrame("CheckButton", "WardrobeShowHiddenChk", dollCol, "UICheckButtonTemplate")
    hidChk:SetSize(22, 22)
    hidChk:SetPoint("TOPRIGHT", bgChk, "TOPLEFT", -8, 0)
    local hidText = _G["WardrobeShowHiddenChkText"]
    hidText:SetText(L["Show hidden items"])
    hidText:SetFontObject("GameFontNormalSmall")
    hidText:ClearAllPoints()
    hidText:SetPoint("RIGHT", hidChk, "LEFT", -4, 1)
    hidText:SetJustifyH("RIGHT")
    hidChk:SetScript("OnClick", function(self)
        GetDB().ui.showHidden = self:GetChecked() and true or false
        if ui.RefreshList then ui.RefreshList() end
    end)
    hidChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Show hidden items")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("When unchecked, items you right-clicked as 'Hide from List' are filtered out of the wardrobe. Check this to see them again (dimmed) so you can unhide them via the same context menu.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hidChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.hidChk = hidChk

    -- ===== Bottom action bar =====
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT", 10, 10)
    bar:SetPoint("BOTTOMRIGHT", -10, 10)
    bar:SetHeight(44)
    MakeBackdrop(bar, "Interface\\DialogFrame\\UI-DialogBox-Background")
    bar:SetBackdropColor(0.1, 0.08, 0.14, 0.55)
    ui.barFrame = bar
    bar:SetBackdropBorderColor(0.4, 0.3, 0.55)

    local applyPrevBottom = MakeBtn(L["Apply Preview"], 115, bar, function()
        W.ApplyPreview()
    end)
    applyPrevBottom:SetPoint("LEFT", 8, 0)
    applyPrevBottom:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Apply staged previews")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drives every staged preview through the gossip flow one at a time, then auto-commits with a single Save Pending popup.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    applyPrevBottom:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.applyPrevBottom = applyPrevBottom

    local applyAll = MakeBtn(L["Save Pending"], 100, bar, function()
        W.ClickExtra("savePending", "Save pending transmogrifications")
    end)
    applyAll:SetPoint("LEFT", applyPrevBottom, "RIGHT", 6, 0)

    local cancelAll = MakeBtn(L["Cancel Pending"], 110, bar, function()
        W.ClickExtra("cancelPending", "Cancel pending transmogrifications")
    end)
    cancelAll:SetPoint("LEFT", applyAll, "RIGHT", 6, 0)

    -- Restore Original is destructive -- wrap in a confirmation popup.
    local restore = MakeBtn(L["Restore Original"], 130, bar, function()
        StaticPopup_Show("WARDROBE_CONFIRM_RESTORE_ORIGINAL")
    end)
    restore:SetPoint("LEFT", cancelAll, "RIGHT", 6, 0)

    -- Server Menu -- hands the user back to the native gossip frame.
    local serverMenu = MakeBtn(L["Server Menu"], 110, bar, function()
        if not GossipFrame then return end
        ui.userInServerMenu = true
        ui.skipCloseGossip  = true
        ui.frame:Hide()
        ui.skipCloseGossip  = false
        W.RestoreGossipFrame()
        Print("Type |cffffd200/wb|r to return to Wardrobe (or just close gossip).")
    end)
    serverMenu:SetPoint("LEFT", restore, "RIGHT", 6, 0)
    serverMenu:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Show the native gossip menu")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hides Wardrobe and reveals the underlying Warpweaver gossip frame. Use this to reach |cffffd200Manage sets|r, |cffffd200How transmogrification works|r, and other server-side options.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Note: Wardrobe's saved outfits are separate from the server's Manage sets -- they live in your addon SavedVariables, not the server's preset table.", 0.7, 0.7, 0.75, true)
        GameTooltip:Show()
    end)
    serverMenu:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rescan = MakeBtn(L["Rescan"], 80, bar, function()
        if not GossipFrame:IsShown() and not W.suppressing then
            Print("Talk to the Warpweaver first.")
            return
        end
        W.StartScan()
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

function W.BuildSlotTabs()
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

        tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        tab:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if previewSlots[s.id] ~= nil then
                    ui.ClearSlotPreview(s.id)
                end
            else
                ui.SelectSlot(s.id)
            end
        end)
        tab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(s.label)
            local list = GetCharDB().collection[s.id]
            local n = list and #list or 0
            GameTooltip:AddLine(n .. " appearance" .. (n == 1 and "" or "s") .. " cached",
                                0.7, 0.7, 0.75)
            if previewSlots[s.id] ~= nil then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffd200Right-click|r to clear the staged preview for this slot.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tab.slotId = s.id
        ui.slotTabs[s.id] = tab
    end
end

-------------------------------------------------------------------------------
-- SORT DROPDOWN (v1.20)
--
-- Each entry: { key, label, comparator }.  Comparator returns true if `a`
-- should come before `b`.  All entries except "favourites_disabled" prepend
-- favourites-first so starred rows still bubble to the top.
-------------------------------------------------------------------------------

W.SORT_ORDERS = {
    { key = "favourites_quality",
      label = "Favourites + Quality",
      cmp = function(a, b)
          if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) > (b.quality or 1) end
          return (a.name or "") < (b.name or "")
      end },
    { key = "quality_desc",
      label = "Quality (high to low)",
      cmp = function(a, b)
          if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) > (b.quality or 1) end
          return (a.name or "") < (b.name or "")
      end },
    { key = "quality_asc",
      label = "Quality (low to high)",
      cmp = function(a, b)
          if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) < (b.quality or 1) end
          return (a.name or "") < (b.name or "")
      end },
    { key = "name_asc",
      label = "Name (A to Z)",
      cmp = function(a, b)
          return (a.name or "") < (b.name or "")
      end },
    { key = "name_desc",
      label = "Name (Z to A)",
      cmp = function(a, b)
          return (a.name or "") > (b.name or "")
      end },
    { key = "recent",
      label = "Recently scanned",
      cmp = function(a, b)
          -- Higher lastSeen first. Items captured before v1.20 have no
          -- lastSeen field -- sort them to the bottom (0).
          local al = a.lastSeen or 0
          local bl = b.lastSeen or 0
          if al ~= bl then return al > bl end
          return (a.name or "") < (b.name or "")
      end },
}

W.SORT_BY_KEY = {}
for _, e in ipairs(W.SORT_ORDERS) do W.SORT_BY_KEY[e.key] = e end

-- Whether the chosen order keeps favourites pinned to the top. The first
-- entry, "favourites_quality", is the only one that does -- it preserves the
-- v1.13 behaviour exactly. Every other order is "raw" so power users who
-- want pure Name A-Z can opt out.
local function FavouritesFirstEnabled(orderKey)
    return orderKey == "favourites_quality"
end
W.FavouritesFirstEnabled = FavouritesFirstEnabled

function ui.UpdateSortButton()
    if not ui.sortBtn then return end
    local key   = GetDB().ui.sortOrder or "favourites_quality"
    local entry = W.SORT_BY_KEY[key] or W.SORT_ORDERS[1]
    ui.sortBtn:SetText(string.format(L["Sort: %s"], L[entry.label] or entry.label))
end

function ui.RebuildSortMenu()
    local menu = ui.sortMenu
    if not menu then return end
    for _, row in ipairs(menu.rows) do row:Hide() end
    local currentKey = GetDB().ui.sortOrder or "favourites_quality"
    for i, entry in ipairs(W.SORT_ORDERS) do
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
        local lbl = L[entry.label] or entry.label
        if entry.key == currentKey then
            row.fs:SetText("|cffffd700>|r " .. lbl)
            row.fs:SetTextColor(1, 0.95, 0.6)
        else
            row.fs:SetText("   " .. lbl)
            row.fs:SetTextColor(0.92, 0.92, 0.95)
        end
        local k = entry.key
        row:SetScript("OnClick", function()
            GetDB().ui.sortOrder = k
            ui.UpdateSortButton()
            ui.RefreshList()
            menu:Hide()
        end)
        row:Show()
    end
    menu:SetHeight(8 + #W.SORT_ORDERS * 20)
end

-------------------------------------------------------------------------------
-- COLLECTION FILTER (v1.21)
--
-- Cycles All -> Owned -> Missing. Missing requires Data/ItemsBySlot.lua to
-- be populated. Button label colour-codes the active state so it's visible
-- at a glance.
-------------------------------------------------------------------------------

function ui.UpdateCollectionButton()
    if not ui.collBtn then return end
    local s = GetDB().ui.collectionFilter or "all"
    if s == "all" then
        ui.collBtn:SetText(L["Collection: All"])
    elseif s == "owned" then
        -- Strip any embedded colour from the localised string, then re-apply
        -- the state colour. This way translators only need to translate the
        -- words; the colouring stays consistent across locales.
        local label = L["Collection: Owned"]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local prefix, state = label:match("^(.-: ?)(.*)$")
        ui.collBtn:SetText((prefix or "") .. "|cff5ce05c" .. (state or label) .. "|r")
    elseif s == "missing" then
        local label = L["Collection: Missing"]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local prefix, state = label:match("^(.-: ?)(.*)$")
        ui.collBtn:SetText((prefix or "") .. "|cffff7f4e" .. (state or label) .. "|r")
    end
end

function ui.UpdateQualityButton()
    local q = GetDB().ui.qualityFilter
    if q == 0 then
        ui.qualityBtn:SetText(L["Quality: All"])
    else
        local c    = QUALITY_COLOR[q] or {1,1,1}
        local qstr = L[QUALITY_NAME[q] or "?"] or QUALITY_NAME[q] or "?"
        ui.qualityBtn:SetText(string.format(L["Quality: %s+"],
            string.format("|cff%02x%02x%02x%s|r", c[1]*255, c[2]*255, c[3]*255, qstr)))
    end
end

function ui.RefreshTabs()
    local char = GetCharDB()
    for _, tab in pairs(ui.slotTabs) do
        local list        = char.collection[tab.slotId]
        local hasPreview  = previewSlots[tab.slotId] ~= nil
        -- Prefix a gold asterisk on tabs with a staged preview so the user
        -- can see at a glance where their pending changes sit.
        if hasPreview then
            tab.count:SetText("* " .. (list and tostring(#list) or "-"))
            tab.count:SetTextColor(1, 0.85, 0.30)
        else
            tab.count:SetText(list and tostring(#list) or "-")
            tab.count:SetTextColor(0.6, 0.6, 0.7)
        end
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
    -- Re-entry guard. FauxScrollFrame_Update internally calls
    -- SetMinMaxValues, which auto-clamps the scrollbar value and fires
    -- OnVerticalScroll -> FauxScrollFrame_OnVerticalScroll, which then
    -- calls ui.RefreshList again as its update function. Without this
    -- guard the recursive call competes with the outer call's row
    -- rendering and the list can end up showing nothing.
    if ui._refreshing then return end
    ui._refreshing = true

    local char         = GetCharDB()
    local owned        = (char.collection[ui.currentSlot] or {})
    local filter       = (ui.search:GetText() or ""):lower()
    local qf           = GetDB().ui.qualityFilter
    local hideApplied  = GetDB().ui.hideApplied
    local showHidden   = GetDB().ui.showHidden
    local appliedEntry = char.applied and char.applied[ui.currentSlot]
    local hidden       = char.hiddenEntries or {}
    local collFilter   = GetDB().ui.collectionFilter or "all"

    -- Collection filter source selection (v1.21):
    --   all     -> owned list, plus missing items synthesised from master list
    --   owned   -> owned list only (original v1.20 behaviour)
    --   missing -> master list minus what's owned (synthetic rows, dimmed)
    -- Enchant slots ignore the collection filter -- no master list ships for
    -- them. Falls back to "owned" for the source set.
    local rowsAreEnchant = IsEnchantSlot(ui.currentSlot)
    local effectiveFilter = rowsAreEnchant and "owned" or collFilter

    -- Build the owned-entry set once -- used for both "missing detection"
    -- and the "is this entry already owned" lookup.
    local ownedSet = {}
    for _, it in ipairs(owned) do ownedSet[it.entry] = it end

    local sourceItems = {}
    if effectiveFilter == "owned" or effectiveFilter == "all" then
        for _, it in ipairs(owned) do table.insert(sourceItems, it) end
    end
    if effectiveFilter == "missing" or effectiveFilter == "all" then
        local master = W.GetMasterItemList(ui.currentSlot)
        if master then
            for _, itemId in ipairs(master) do
                if not ownedSet[itemId] then
                    -- Lazy-resolve from GetItemInfo. Unresolved rows render
                    -- with a placeholder icon until the cache warms.
                    local _, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemId)
                    table.insert(sourceItems, {
                        entry    = itemId,
                        name     = link and link:match("|h%[(.-)%]|h") or ("Item " .. tostring(itemId)),
                        link     = link,
                        quality  = quality or 1,
                        icon     = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                        resolved = (link ~= nil),
                        missing  = true,
                    })
                end
            end
        end
    end

    local filtered = {}
    for _, it in ipairs(sourceItems) do
        if not it.resolved and it.entry then
            local _, link, quality, _, _, _, _, _, _, icon = GetItemInfo(it.entry)
            if link then
                it.link     = link
                if it.missing then it.name = link:match("|h%[(.-)%]|h") or it.name end
                it.quality  = quality or it.quality
                it.icon     = icon or it.icon
                it.resolved = true
            end
        end
        local passQuality = qf == 0 or (it.quality or 1) >= qf
        local passSearch  = filter == "" or (it.name or ""):lower():find(filter, 1, true)
        local passApplied = not (hideApplied and appliedEntry == it.entry)
        local passHidden  = showHidden or not hidden[it.entry]
        if passQuality and passSearch and passApplied and passHidden then
            table.insert(filtered, it)
        end
    end
    -- Sort: dispatch on db.ui.sortOrder. The favourites-first behaviour from
    -- v1.13 is preserved by the default order key ("favourites_quality");
    -- other orders are raw so power users can pick pure Name A-Z, etc.
    local favs       = W.GetFavouritesTable()
    local orderKey   = GetDB().ui.sortOrder or "favourites_quality"
    local orderEntry = W.SORT_BY_KEY[orderKey] or W.SORT_ORDERS[1]
    local favFirst   = W.FavouritesFirstEnabled(orderKey)
    local cmp        = orderEntry.cmp
    table.sort(filtered, function(a, b)
        if favFirst then
            local af = favs[a.entry] and 1 or 0
            local bf = favs[b.entry] and 1 or 0
            if af ~= bf then return af > bf end
        end
        return cmp(a, b)
    end)

    FauxScrollFrame_Update(ui.listScroll, #filtered, #ui.rows, 22)
    -- CRITICAL: 3.3.5a's FauxScrollFrame_Update calls `frame:Hide()` when
    -- numItems <= numToDisplay. Force it visible after every Update so the
    -- rows stay rendered. This was the root cause of "search past 2 letters
    -- shows nothing".
    ui.listScroll:Show()
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
            local isHidden  = hidden[it.entry] and true or false
            local isMissing = it.missing and true or false
            row.icon:SetTexture(it.icon)
            row.icon:SetDesaturated(isHidden or isMissing)
            local c = QUALITY_COLOR[it.quality or 1] or {1,1,1}
            row.nameFs:SetText(it.name or "?")
            if rowsAreEnchant then
                -- Enchants have no item quality (everything falls to "Common"
                -- which is misleading). Show "Enchant" in a gold tint instead.
                row.nameFs:SetTextColor(0.95, 0.85, 0.45)
                row.qualFs:SetText(isHidden and L["Enchant (hidden)"] or L["Enchant"])
                row.qualFs:SetTextColor(0.75, 0.60, 0.25)
            else
                row.nameFs:SetTextColor(c[1], c[2], c[3])
                row.qualFs:SetText((L[QUALITY_NAME[it.quality or 1] or ""] or "") ..
                                   (isHidden and L[" (hidden)"] or "") ..
                                   (isMissing and L[" (uncollected)"] or ""))
                row.qualFs:SetTextColor(c[1]*0.8, c[2]*0.8, c[3]*0.8)
            end
            if isHidden then
                row.nameFs:SetTextColor(0.55, 0.55, 0.55)
                row.qualFs:SetTextColor(0.50, 0.40, 0.40)
            elseif isMissing then
                -- Dim missing rows so they're visually distinct from owned
                -- ones but still readable. Quality tint still hints at rarity.
                row.nameFs:SetTextColor(c[1]*0.55, c[2]*0.55, c[3]*0.55)
                row.qualFs:SetTextColor(c[1]*0.45, c[2]*0.45, c[3]*0.45)
            end
            if favs[it.entry] then
                row.star.fs:SetTextColor(1, 0.85, 0.30)
            else
                row.star.fs:SetTextColor(0.35, 0.35, 0.40)
            end
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
        local slotLabel = SLOT_BY_ID[ui.currentSlot] and SLOT_BY_ID[ui.currentSlot].label or "?"
        if effectiveFilter == "missing" and W.MasterListIsEmpty() then
            base = L["Missing list empty -- populate Data/ItemsBySlot.lua to see uncollected items"]
        else
            base = string.format(L["Last scan: %dm ago  |  %d items in %s"], mins, #filtered, slotLabel)
            if effectiveFilter ~= "all" and effectiveFilter ~= "owned" then
                base = base .. " (" .. effectiveFilter .. ")"
            end
        end
    else
        base = L["No scan yet"]
    end
    if W.WarmingActive() then
        ui.stamp:SetText("|cffffd200" .. string.format(L["Warming %d/%d"],
            W.warmIdx - 1, W.warmTotal) .. "|r")
    else
        ui.stamp:SetText(base)
    end

    ui._refreshing = false
end

function ui.UpdateHideButton()
    if not ui.hideBtn then return end
    local s = SLOT_BY_ID[ui.currentSlot]
    ui.hideBtn:SetText(s and string.format(L["Hide %s"], s.label) or L["Hide Slot"])
    ui.hideBtn:Enable()
end

-- Apply the background-art preference: show/hide the wallpaper texture and
-- swap the column backdrops between translucent (so the art shows through)
-- and opaque (the original look from before the artwork existed).
function ui.ApplyBackgroundPref()
    local on = GetDB().ui.showBackground
    if ui.bgTex then
        if on then ui.bgTex:Show() else ui.bgTex:Hide() end
    end
    local alpha = on and 0.55 or 0.85
    if ui.listBgFrame then ui.listBgFrame:SetBackdropColor(0.05, 0.04, 0.08, alpha) end
    if ui.dollBgFrame then ui.dollBgFrame:SetBackdropColor(0.05, 0.04, 0.08, alpha) end
    if ui.barFrame    then ui.barFrame:SetBackdropColor   (0.10, 0.08, 0.14, alpha) end
    if ui.bgChk       then ui.bgChk:SetChecked(on) end
end
