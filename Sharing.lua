-------------------------------------------------------------------------------
-- Sharing.lua  --  Outfit sharing via chat: encode/decode WBS1: codes,
-- Share/Import popups, outfit-row context menu, and the chat-frame hooks
-- that turn pasted codes into clickable purple/gold links.
--
-- Outfit encoding format:
--   WBS1:<urlenc-name>~<slotId>:<entry>~<slotId>:<entry>~...
-- where <entry> is a bare integer for item IDs, or "s<urlenc>" for string
-- entries (HIDE marker, enchant illusion names). Slots are emitted in
-- sorted-by-slotId order so the same outfit always encodes to the same
-- string. Chosen format goals:
--   * No `|` characters -- they get auto-converted by chat into hyperlinks
--   * No `~` inside fields (used as separator)
--   * Survives URL-encoding round-trip (we re-encode on output too)
--   * Short enough to fit a full outfit in one chat message (<500 bytes)
-------------------------------------------------------------------------------

local addonName, W = ...

local SLOT_BY_ID   = W.SLOT_BY_ID
local GetCharDB    = W.GetCharDB
local Print        = W.Print
local ErrorMsg     = W.ErrorMsg
local MakeBackdrop = W.MakeBackdrop
local ui           = W.ui

local SHARE_PREFIX     = "WBS1:"
local SHARE_LINK_TYPE  = "wardrobe"
local SHARE_MAX_LEN    = 500
local SHARE_MAX_NAME   = 40
local SHARE_MAX_SLOTS  = 20
local SHARE_MAX_STR_E  = 50    -- max length of a single string entry

local function UrlEnc(s)
    return (s:gsub("[^%w%-_.]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function UrlDec(s)
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- EncodeOutfit({name, slots={[sid]=entry,...}}) -> string or (nil, err)
function ui.EncodeOutfit(outfit)
    if type(outfit) ~= "table" then return nil, "no outfit" end
    if type(outfit.name) ~= "string" or outfit.name == "" then return nil, "missing name" end
    if #outfit.name > SHARE_MAX_NAME then return nil, "name too long" end
    if type(outfit.slots) ~= "table" then return nil, "no slots" end

    local sids = {}
    for sid in pairs(outfit.slots) do
        if SLOT_BY_ID[sid] then table.insert(sids, sid) end
    end
    if #sids == 0 then return nil, "no valid slots" end
    if #sids > SHARE_MAX_SLOTS then return nil, "too many slots" end
    table.sort(sids)

    local parts = { SHARE_PREFIX .. UrlEnc(outfit.name) }
    for _, sid in ipairs(sids) do
        local entry = outfit.slots[sid]
        local enc
        if type(entry) == "number" then
            enc = tostring(math.floor(entry))
        elseif type(entry) == "string" then
            if #entry == 0 or #entry > SHARE_MAX_STR_E then
                -- skip silently -- better to share a partial outfit than fail
                enc = nil
            else
                enc = "s" .. UrlEnc(entry)
            end
        end
        if enc then
            table.insert(parts, sid .. ":" .. enc)
        end
    end
    if #parts < 2 then return nil, "no encodable slots" end
    local s = table.concat(parts, "~")
    if #s > SHARE_MAX_LEN then return nil, "encoded too long" end
    return s
end

-- DecodeOutfit(string) -> outfit or (nil, err). Validation-heavy because
-- the source is untrusted chat input.
function ui.DecodeOutfit(s)
    if type(s) ~= "string" then return nil, "not a string" end
    s = s:match("^%s*(.-)%s*$")
    if #s > SHARE_MAX_LEN then return nil, "too long" end
    if s:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then return nil, "bad prefix" end
    s = s:sub(#SHARE_PREFIX + 1)

    local parts = {}
    for p in s:gmatch("[^~]+") do table.insert(parts, p) end
    if #parts < 2 then return nil, "missing slots" end

    local name = UrlDec(parts[1])
    if #name == 0 or #name > SHARE_MAX_NAME then return nil, "bad name" end

    local outfit = { name = name, slots = {} }
    local count = 0
    for i = 2, #parts do
        local sidStr, entryStr = parts[i]:match("^(%d+):(.+)$")
        if not sidStr then return nil, "bad slot syntax" end
        local sid = tonumber(sidStr)
        if not SLOT_BY_ID[sid] then return nil, "unknown slot " .. sidStr end
        local entry
        if entryStr:sub(1,1) == "s" then
            entry = UrlDec(entryStr:sub(2))
            if #entry == 0 or #entry > SHARE_MAX_STR_E then return nil, "bad string entry" end
        else
            entry = tonumber(entryStr)
            if not entry or entry <= 0 or entry > 99999999 then return nil, "bad entry id" end
        end
        outfit.slots[sid] = entry
        count = count + 1
    end
    if count == 0 then return nil, "no slots" end
    if count > SHARE_MAX_SLOTS then return nil, "too many slots" end
    return outfit
end

-- Pick a non-colliding name when importing. Adds " (imported)" suffix,
-- then " (imported 2)", " (imported 3)", ... until a free slot is found.
local function UniqueOutfitName(base)
    local outfits = GetCharDB().outfits or {}
    local taken = {}
    for _, o in ipairs(outfits) do taken[o.name] = true end
    if not taken[base] then return base end
    local candidate = base .. " (imported)"
    if not taken[candidate] then return candidate end
    for i = 2, 99 do
        candidate = base .. " (imported " .. i .. ")"
        if not taken[candidate] then return candidate end
    end
    return base .. " (imported " .. time() .. ")"
end

-- ---- SHARE POPUP --------------------------------------------------------

local sharePopup

local function CreateSharePopup()
    if sharePopup then return sharePopup end
    local f = CreateFrame("Frame", "WardrobeSharePopup", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(440, 150)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    MakeBackdrop(f, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    f:SetBackdropColor(0.08, 0.05, 0.12, 0.97)
    f:SetBackdropBorderColor(0.40, 0.25, 0.70, 1)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetTextColor(0.95, 0.85, 0.45)
    f.title = title

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetText("Ctrl+C to copy this code, or post directly to a channel:")
    hint:SetTextColor(0.78, 0.78, 0.82)

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(400, 22)
    eb:SetPoint("TOP", hint, "BOTTOM", 0, -14)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(SHARE_MAX_LEN)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    eb:SetScript("OnEnterPressed",  function(self) self:HighlightText() end)
    -- Keep the EditBox read-only-ish: re-set the text if it changes.
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.__originalCode and self:GetText() ~= self.__originalCode then
            self:SetText(self.__originalCode)
            self:HighlightText()
        end
    end)
    f.eb = eb

    local function postBtn(label, channel, x)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(72, 22)
        b:SetText(label)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 10)
        b:SetScript("OnClick", function()
            local code = eb.__originalCode or eb:GetText()
            if channel == "GUILD" and not IsInGuild() then
                ErrorMsg("You're not in a guild.")
                return
            end
            if channel == "PARTY" and GetNumPartyMembers() == 0 then
                ErrorMsg("You're not in a party.")
                return
            end
            SendChatMessage(code, channel)
        end)
        return b
    end
    postBtn("Say",   "SAY",   12)
    postBtn("Party", "PARTY", 90)
    postBtn("Guild", "GUILD", 168)

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(72, 22)
    close:SetText("Close")
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    close:SetScript("OnClick", function() f:Hide() end)

    sharePopup = f
    return f
end

function ui.ShowSharePopup(outfitIdx)
    local outfits = GetCharDB().outfits
    local outfit  = outfits and outfits[outfitIdx]
    if not outfit then ErrorMsg("Pick an outfit first.") return end
    local code, err = ui.EncodeOutfit(outfit)
    if not code then ErrorMsg("Couldn't share outfit: " .. (err or "?")) return end
    local f = CreateSharePopup()
    f.title:SetText("Share '" .. outfit.name .. "'")
    f.eb.__originalCode = code
    f.eb:SetText(code)
    f.eb:HighlightText()
    f.eb:SetFocus()
    f:Show()
end

-- ---- IMPORT POPUP -------------------------------------------------------

local importPopup

local function CreateImportPopup()
    if importPopup then return importPopup end
    local f = CreateFrame("Frame", "WardrobeImportPopup", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(440, 170)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    MakeBackdrop(f, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    f:SetBackdropColor(0.08, 0.05, 0.12, 0.97)
    f:SetBackdropBorderColor(0.40, 0.25, 0.70, 1)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetTextColor(0.95, 0.85, 0.45)
    title:SetText("Import outfit")
    f.title = title

    local summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summary:SetPoint("TOP", title, "BOTTOM", 0, -8)
    summary:SetWidth(400)
    summary:SetJustifyH("CENTER")
    summary:SetTextColor(0.95, 0.95, 1.0)
    f.summary = summary

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", summary, "BOTTOM", 0, -4)
    sub:SetWidth(400)
    sub:SetJustifyH("CENTER")
    sub:SetTextColor(0.75, 0.75, 0.80)
    f.sub = sub

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(400, 22)
    eb:SetPoint("TOP", sub, "BOTTOM", 0, -10)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(SHARE_MAX_LEN)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    eb:SetScript("OnEnterPressed",  function(self) self:HighlightText() end)
    f.eb = eb

    local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetSize(90, 24)
    importBtn:SetText("Import")
    importBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    importBtn:SetScript("OnClick", function()
        local outfit = f.__outfit
        if not outfit then f:Hide() return end
        local char = GetCharDB()
        char.outfits = char.outfits or {}
        outfit.name = UniqueOutfitName(outfit.name)
        table.insert(char.outfits, outfit)
        Print("Imported outfit '" .. outfit.name .. "'.")
        if ui.RebuildOutfitMenu then ui.RebuildOutfitMenu() end
        f:Hide()
    end)
    f.importBtn = importBtn

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(90, 24)
    cancel:SetText("Cancel")
    cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    cancel:SetScript("OnClick", function() f:Hide() end)

    importPopup = f
    return f
end

function ui.ShowImportPopup(code)
    if not code or code == "" then
        ErrorMsg("Paste a WBS1:... code after /wb import.")
        return
    end
    local outfit, err = ui.DecodeOutfit(code)
    local f = CreateImportPopup()
    f.eb:SetText(code)
    if not outfit then
        f.__outfit = nil
        f.title:SetText("Import outfit")
        f.summary:SetText("|cffff6060Invalid code|r")
        f.sub:SetText("Reason: " .. (err or "?"))
        f.importBtn:Disable()
    else
        f.__outfit = outfit
        local n = 0
        for _ in pairs(outfit.slots) do n = n + 1 end
        f.title:SetText("Import outfit")
        f.summary:SetText("|cffd4af37" .. outfit.name .. "|r")
        f.sub:SetText(n .. " slot" .. (n == 1 and "" or "s") ..
            " -- will be saved" ..
            (UniqueOutfitName(outfit.name) ~= outfit.name and
                " as '" .. UniqueOutfitName(outfit.name) .. "' (name taken)" or ""))
        f.importBtn:Enable()
    end
    f:Show()
end

-- ---- OUTFIT-ROW CONTEXT MENU -------------------------------------------
-- Reuses the visual style of the row context menu (v1.17). Right-click an
-- outfit name in the dropdown for Load / Share / Delete in one place.

-- `outfitCtxMenu` disambiguates from `ui.outfitMenu` (the outfit-list
-- dropdown). This one is the right-click context menu shown *on* a row of
-- that dropdown.
local outfitCtxMenu

local function HideOutfitCtxMenu()
    if outfitCtxMenu then outfitCtxMenu:Hide() end
end

local function CreateOutfitContextMenu()
    if outfitCtxMenu then return outfitCtxMenu end
    local m = CreateFrame("Frame", "WardrobeOutfitContextMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetWidth(170)
    m:EnableMouse(true)
    MakeBackdrop(m, "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    m:SetBackdropColor(0.08, 0.05, 0.12, 0.97)
    m:SetBackdropBorderColor(0.40, 0.25, 0.70, 1)
    m:Hide()

    m.headFs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.headFs:SetPoint("TOPLEFT",  m, "TOPLEFT",   8, -7)
    m.headFs:SetPoint("TOPRIGHT", m, "TOPRIGHT", -8, -7)
    m.headFs:SetJustifyH("LEFT")
    m.headFs:SetWordWrap(false)
    m.headFs:SetTextColor(0.95, 0.85, 0.45)

    local div = m:CreateTexture(nil, "OVERLAY")
    div:SetTexture("Interface\\Buttons\\WHITE8X8")
    div:SetVertexColor(0.55, 0.42, 0.18, 0.7)
    div:SetHeight(1)
    div:SetPoint("LEFT",  m, "LEFT",   8, 0)
    div:SetPoint("RIGHT", m, "RIGHT", -8, 0)
    div:SetPoint("TOP",   m.headFs, "BOTTOM", 0, -4)
    m.div = div

    m.buttons = {}
    for i = 1, 4 do
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

    outfitCtxMenu = m
    return m
end

function ui.ShowOutfitContextMenu(outfitIdx)
    local outfits = GetCharDB().outfits
    local outfit  = outfits and outfits[outfitIdx]
    if not outfit then return end
    local m = CreateOutfitContextMenu()
    m.headFs:SetText(outfit.name)

    local entries = {
        { label  = "Load",
          colour = {1.00, 0.95, 0.60},
          action = function()
              ui.SelectOutfit(outfitIdx)
              if ui.outfitMenu then ui.outfitMenu:Hide() end
          end },
        { label  = "Share",
          colour = {0.85, 0.85, 1.00},
          action = function()
              ui.ShowSharePopup(outfitIdx)
              if ui.outfitMenu then ui.outfitMenu:Hide() end
          end },
        { label  = "Delete",
          colour = {0.95, 0.50, 0.50},
          action = function()
              ui.selectedOutfitIdx = outfitIdx
              StaticPopupDialogs["WARDROBE_DELETE_OUTFIT"].text =
                  "Delete outfit '" .. outfit.name .. "'?"
              StaticPopup_Show("WARDROBE_DELETE_OUTFIT")
              if ui.outfitMenu then ui.outfitMenu:Hide() end
          end },
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
                HideOutfitCtxMenu()
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
    -- Height = top pad 7 + header line ~14 + 4 + 1 div + 2 + 4*20 + 8
    m:SetHeight(7 + 14 + 4 + 1 + 2 + #entries * 20 + 8)

    local scale  = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    m:ClearAllPoints()
    m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx/scale, cy/scale)
    m:Show()
end

-- Slash-friendly: find an outfit by name (case-insensitive) and share it.
function ui.ShareOutfitByName(name)
    if not name or name == "" then
        ErrorMsg("Usage: /wb share <outfit name>")
        return
    end
    local outfits = GetCharDB().outfits or {}
    local lname = name:lower()
    for i, o in ipairs(outfits) do
        if o.name:lower() == lname then
            ui.ShowSharePopup(i)
            return
        end
    end
    ErrorMsg("No outfit named '" .. name .. "' on this character.")
end

-- ---- CHAT REWRITER + LINK HANDLER --------------------------------------
-- Hook each ChatFrame's AddMessage to turn WBS1:... patterns into
-- clickable purple/gold hyperlinks. Hook SetItemRef to intercept clicks
-- on those links and open the import popup pre-filled.
--
-- Idempotent -- re-running InstallChatHooks() on an already-hooked frame
-- is a no-op. Some UI replacement addons recreate ChatFrameN after we
-- hook, so we re-run from a PLAYER_ENTERING_WORLD event too.

function W.InstallChatHooks()
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and not cf.__wardrobeShareHooked then
            local orig = cf.AddMessage
            if type(orig) == "function" then
                cf.AddMessage = function(self, msg, ...)
                    if type(msg) == "string" and msg:find(SHARE_PREFIX, 1, true) then
                        msg = msg:gsub("(WBS1:[^%s|]+)", function(code)
                            local outfit = ui.DecodeOutfit(code)
                            local label = outfit
                                and ("Wardrobe: " .. outfit.name)
                                or  "Wardrobe outfit (invalid)"
                            return "|cffd4af37|H" .. SHARE_LINK_TYPE .. ":" .. code
                                .. "|h[" .. label .. "]|h|r"
                        end)
                    end
                    return orig(self, msg, ...)
                end
                cf.__wardrobeShareHooked = true
            end
        end
    end

    if not _G.__wardrobeSetItemRefHooked then
        local origSetItemRef = SetItemRef
        SetItemRef = function(link, text, button, ...)
            if type(link) == "string" then
                local prefix = SHARE_LINK_TYPE .. ":"
                if link:sub(1, #prefix) == prefix then
                    local code = link:sub(#prefix + 1)
                    ui.ShowImportPopup(code)
                    return
                end
            end
            return origSetItemRef(link, text, button, ...)
        end
        _G.__wardrobeSetItemRefHooked = true
    end
end
