local _, Addon = ...
local pages, notices, window = {}, {}, nil
local UI = {}
Addon.OptionsUI = UI
local WHITE = "Interface\\Buttons\\WHITE8X8"
local HEADER_ART = "Interface\\AddOns\\SmallerUI\\Media\\SettingsHeader.tga"
local ENAMEL = "Interface\\AddOns\\SmallerUI\\Media\\Foundry.tga"
local BRONZE = "Interface\\Tooltips\\UI-Tooltip-Border"
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local BUTTON_ATLAS = "common-dropdown-c-button"
local WINDOW_WIDTH, MIN_HEIGHT, MAX_HEIGHT = 878, 520, 690
local gold = { 0.94, 0.78, 0.50, 1 }
local ink = { 0.95, 0.93, 0.88, 1 }
local quiet = { 0.70, 0.74, 0.74, 1 }
local muted = { 0.32, 0.30, 0.25, 1 }
local buttonFill = { 0.15, 0.19, 0.21, 1 }
local selectedFill = { 0.30, 0.24, 0.16, 1 }
local navigation = {
    { "scaling", "Interface", "INV_Misc_Gear_01", "Display & combat" },
    { "resources", "Personal bars", "INV_Potion_54" },
    { "party", "Party bars", "INV_Misc_GroupLooking" },
    { "pet", "Pet bars", "Ability_Hunter_BeastCall" },
    { "swing", "Swing timer", "INV_Sword_04" },
    { "whispers", "Whisper Manager", "INV_Letter_15", "Utilities" },
    { "loot", "Loot & Rolls", "INV_Misc_Bag_10" },
    { "vendorDeals", "Vendor Deals", "INV_Misc_Coin_01" },
}

local function Animate(frame, duration, update)
    local elapsed = 0
    update(0)
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local progress = math.min(elapsed / duration, 1)
        update(1 - (1 - progress) ^ 2)
        if progress == 1 then self:SetScript("OnUpdate", nil) end
    end)
end

function UI.Label(parent, text, x, y, font, width)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    if width then label:SetWidth(width); label:SetWordWrap(true) end
    label:SetText(text)
    return label
end

function UI.Tooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.NumberArrows(input, step, minimum, maximum, savedValue, apply)
    local function Adjust(direction)
        local value = tonumber(input:GetText())
        if not value or value ~= value or math.abs(value) == math.huge then value = savedValue() end
        value = math.max(minimum, math.min(maximum, math.floor((value + direction * step) * 100 + 0.5) / 100))
        if value == savedValue() then input:SetText(string.format("%.2f", value)); return end
        if apply(value) ~= false then input:SetText(string.format("%.2f", value)) end
    end
    local function Arrow(suffix, direction, y, texture)
        local button = CreateFrame("Button", input:GetName() .. suffix, input)
        button:SetSize(18, 12)
        button:SetPoint("TOPLEFT", input:GetWidth() + 2, y)
        button:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. texture .. "Button-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. texture .. "Button-Down")
        button:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. texture .. "Button-Highlight")
        button.stepper, button.stepDirection = true, direction
        local function Stop(self) self:SetScript("OnUpdate", nil) end
        button:SetScript("OnMouseDown", function(self, mouse)
            if mouse ~= "LeftButton" then return end
            self.mouseStepped = true
            Adjust(direction)
            local nextStep = GetTime() + 0.35
            self:SetScript("OnUpdate", function(current)
                if not IsMouseButtonDown("LeftButton") then Stop(current); return end
                if GetTime() >= nextStep then Adjust(direction); nextStep = GetTime() + 0.07 end
            end)
        end)
        button:SetScript("OnMouseUp", Stop)
        button:SetScript("OnHide", function(self) Stop(self); self.mouseStepped = nil end)
        button:SetScript("OnClick", function(self, mouse)
            if mouse == "LeftButton" and not self.mouseStepped then Adjust(direction) end
            self.mouseStepped = nil
        end)
        UI.Tooltip(button, "Click to adjust. Hold to keep adjusting.")
        return button
    end
    input.up = Arrow("Up", 1, 0, "Up")
    input.down = Arrow("Down", -1, -12, "Down")
end

function UI.Backdrop(frame, color, border)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(border or muted))
end

function UI.Plate(frame, color)
    frame:SetBackdrop({ bgFile = ENAMEL, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(color or { 0.12, 0.16, 0.18, 1 }))
    frame:SetBackdropBorderColor(unpack(muted))
end

local function Bronze(frame, fill, edge)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = BRONZE, edgeSize = edge,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(unpack(fill))
    frame:SetBackdropBorderColor(0.70, 0.52, 0.30, 1)
end

function UI.WindowSurface(frame)
    Bronze(frame, { 0.105, 0.075, 0.046, 1 }, 14)
    local stone = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    stone:SetPoint("TOPLEFT", 4, -4)
    stone:SetPoint("BOTTOMRIGHT", -4, 4)
    stone:SetTexture(ROCK, "REPEAT", "REPEAT")
    if stone.SetHorizTile then stone:SetHorizTile(true); stone:SetVertTile(true) end
    stone:SetDesaturated(true)
    stone:SetVertexColor(0.37, 0.28, 0.18)
    local wash = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    wash:SetAllPoints(stone)
    wash:SetColorTexture(0.041, 0.029, 0.019, 0.38)
end

function UI.EditBox(parent, name, font)
    local input = CreateFrame("EditBox", name, parent, "BackdropTemplate")
    Bronze(input, { 0.075, 0.054, 0.030, 1 }, 8)
    input:SetFontObject(font or GameFontHighlight)
    input:SetTextInsets(7, 7, 0, 0)
    input:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(1, 0.77, 0.38, 1) end)
    input:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.70, 0.52, 0.30, 1) end)
    return input
end

function UI.FitScale(frame, width, height)
    local root = UIParent:GetEffectiveScale()
    local availableWidth, availableHeight = UIParent:GetSize()
    local scale = math.min(root, math.max(0.1,
        math.min((availableWidth * root - 24) / width, (availableHeight * root - 24) / height)))
    frame:SetScale(scale)
    return scale
end

function UI.ScrollFrame(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    local track = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    track:SetFrameLevel(scroll:GetFrameLevel() + 2)
    track:SetScale(0.75)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 0)
    track:Hide()
    local updating
    local function Update()
        local range, height = scroll:GetVerticalScrollRange() or 0, scroll:GetHeight() or 0
        local show = scroll:IsShown() and range > 0.5 and height > 0 and track.RegisterCallback ~= nil
        track:SetShown(show)
        if not show then return end
        updating = true
        local visible = height / (range + height)
        track:SetVisibleExtentPercentage(visible)
        track:SetPanExtentPercentage(visible * 0.24)
        track:SetScrollPercentage(math.min(1, (scroll:GetVerticalScroll() or 0) / range), true)
        updating = false
    end
    if track.RegisterCallback then
        track:RegisterCallback("OnScroll", function(_, percent)
            if not updating then scroll:SetVerticalScroll(percent * scroll:GetVerticalScrollRange()) end
        end, track)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
    end)
    for _, event in ipairs({ "OnShow", "OnHide", "OnSizeChanged", "OnScrollRangeChanged", "OnVerticalScroll" }) do
        scroll:HookScript(event, Update)
    end
    return scroll
end

function UI.Button(parent, name, text, x, y, width, callback, row)
    local button = CreateFrame("Button", name, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 26)
    UI.Plate(button, row and { 0.091, 0.068, 0.042, 0.45 } or buttonFill)
    local textLabel = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    textLabel:SetPoint("CENTER")
    button.label = textLabel
    button:SetFontString(textLabel)
    button:SetText(text)
    textLabel:SetTextColor(unpack(row and ink or gold))
    button:SetHighlightTexture(WHITE, "ADD")
    button:GetHighlightTexture():SetVertexColor(0.55, 0.38, 0.16, 0.23)
    button:SetPushedTexture(WHITE)
    local pressed = button:GetPushedTexture()
    pressed:SetBlendMode("ADD")
    pressed:SetVertexColor(0.52, 0.41, 0.22, 0.35)
    button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    button:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    button:SetScript("OnClick", callback)
    if not row and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BUTTON_ATLAS) then
        local face = button:CreateTexture(nil, "BACKGROUND", nil, 2)
        face:SetPoint("TOPLEFT", -4, 4)
        face:SetPoint("BOTTOMRIGHT", 4, -4)
        face:SetAtlas(BUTTON_ATLAS)
        button.face = face
        button:GetHighlightTexture():SetAlpha(0)
        pressed:SetAlpha(0)
        button:SetBackdropColor(0, 0, 0, 0)
        button:SetBackdropBorderColor(0, 0, 0, 0)
        local function Paint(self)
            local suffix = not self:IsEnabled() and "-disabled" or self.faceDown and "-pressed-1"
                or self.faceOver and "-hover-1" or self.faceSelected and "-open" or ""
            face:SetShown(not self.marker or self.faceSelected or self.faceOver or self.faceDown)
            face:SetAtlas(BUTTON_ATLAS .. suffix)
        end
        button.paintFace = Paint
        button:HookScript("OnEnter", function(self) self.faceOver = true; Paint(self) end)
        button:HookScript("OnLeave", function(self) self.faceOver = nil; Paint(self) end)
        button:HookScript("OnMouseDown", function(self) self.faceDown = true; Paint(self) end)
        button:HookScript("OnMouseUp", function(self) self.faceDown = nil; Paint(self) end)
        button:HookScript("OnHide", function(self) self.faceDown, self.faceOver = nil, nil end)
        button:HookScript("OnShow", Paint)
        button:HookScript("OnEnable", Paint)
        button:HookScript("OnDisable", Paint)
    end
    return button
end

local function SelectButton(button, selected)
    if button.face then
        button.faceSelected = selected
        button.paintFace(button)
    elseif button.marker and not selected then
        button:SetBackdropColor(0.07, 0.105, 0.14, 0)
        button:SetBackdropBorderColor(0, 0, 0, 0)
    else
        button:SetBackdropColor(unpack(selected and selectedFill or buttonFill))
        button:SetBackdropBorderColor(unpack(selected and gold or muted))
    end
    button.label:SetTextColor(unpack(selected and gold or ink))
    if button.marker then button.marker:SetShown(selected) end
end

function UI.Select(parent, name, x, y, width, entries, get, set, initializeRow)
    local dropdown = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    dropdown:SetSize(width, 26)
    dropdown:SetupMenu(function(_, root)
        local choices = type(entries) == "function" and entries() or entries
        for _, entry in ipairs(choices) do
            local row = root:CreateRadio(entry[2], function(value) return get() == value end, set, entry[1])
            if initializeRow then
                row:AddInitializer(function(button) return initializeRow(button, entry) end)
            end
        end
    end)
    return dropdown
end

function UI.Switch(parent, name, text, x, y, callback, tip)
    local button = CreateFrame("Button", name, parent)
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(text == "" and 42 or 292, 28)
    local track = CreateFrame("Frame", nil, button, "BackdropTemplate")
    track:SetSize(36, 18)
    track:SetPoint("LEFT", 2, 0)
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(13, 12)
    local label = UI.Label(button, text, 48, -7)
    label:SetWordWrap(false)
    label:SetTextColor(unpack(ink))
    UI.Backdrop(track, { 0.075, 0.10, 0.13, 1 })
    local function PlaceThumb(offset)
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", offset, 0)
        button.thumbOffset = offset
    end
    function button:SetChecked(enabled, animate)
        enabled = enabled == true
        if self.checked == enabled then return end
        self.checked = enabled
        track:SetBackdropColor(unpack(enabled and { 0.16, 0.29, 0.26, 1 } or { 0.075, 0.10, 0.13, 1 }))
        track:SetBackdropBorderColor(unpack(enabled and gold or muted))
        thumb:SetColorTexture(unpack(enabled and gold or quiet))
        local target = enabled and 20 or 3
        if animate then
            local start = self.thumbOffset
            Animate(self, 0.12, function(progress) PlaceThumb(start + (target - start) * progress) end)
        else
            self:SetScript("OnUpdate", nil)
            PlaceThumb(target)
        end
    end
    function button:GetChecked() return self.checked end
    button:SetChecked(false)
    button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    button:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    button:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked(), true)
        callback(self:GetChecked())
    end)
    button:SetHighlightTexture(WHITE, "ADD")
    button:GetHighlightTexture():SetVertexColor(0.16, 0.22, 0.28, 0.22)
    button:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        PlaceThumb(self.checked and 20 or 3)
    end)
    if tip then UI.Tooltip(button, tip) end
    return button
end

function UI.Section(parent, text, y)
    local band = parent:CreateTexture(nil, "BACKGROUND")
    band:SetTexture(ENAMEL)
    band:SetPoint("TOPLEFT", 12, y)
    band:SetPoint("TOPRIGHT", -12, y)
    band:SetHeight(24)
    band:SetVertexColor(0.13, 0.15, 0.16, 0.94)
    local heading = UI.Label(parent, text, 22, y - 4, "GameFontNormal")
    heading:SetTextColor(unpack(gold))
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.70, 0.54, 0.32, 0.7)
    line:SetPoint("TOPLEFT", 12, y)
    line:SetSize(2, 24)
    return heading
end

function UI.Page(name, title, height)
    local page = CreateFrame("Frame", name, window)
    page:SetPoint("TOPLEFT", 196, -93)
    page:SetPoint("BOTTOMRIGHT", -18, 53)
    page:Hide()
    page.title = UI.Label(page, title, 12, -4, "GameFontNormalLarge")
    page.title:SetTextColor(unpack(ink))
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 12, -37)
    rule:SetPoint("TOPRIGHT", -12, -37)
    rule:SetHeight(1)
    rule:SetColorTexture(0.23, 0.27, 0.30, 1)
    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -49)
    scroll:SetPoint("BOTTOMRIGHT", -25, 0)
    local content = CreateFrame("Frame", name .. "Content", scroll)
    content:SetSize(620, height)
    scroll:SetScrollChild(content)
    page.scroll, page.content = scroll, content
    return page
end

function UI.Tabs(page, entries)
    page.tab = entries[1][1]
    for index, entry in ipairs(entries) do
        entry.button = UI.Button(page, nil, entry[2], 648 - (#entries - index) * 105 - 98, 0, 98,
            function() page:SelectTab(entry[1]) end)
    end
    function page:SelectTab(key)
        self.tab = key
        for _, entry in ipairs(entries) do
            entry[3]:SetShown(entry[1] == key)
            SelectButton(entry.button, entry[1] == key)
            if entry[1] == key then self.content:SetHeight(entry[3]:GetHeight()) end
        end
        self.scroll:SetVerticalScroll(0)
        Addon:OptionsFeedback("")
    end
    page:SelectTab(page.tab)
end

function Addon:SetPageStatus(key, text)
    local page = pages[key]
    if not page then return end
    page.defaultStatus = text
    if not window or self.currentOptionsPage ~= key then return end
    local notice = notices[key]
    window.status:SetText(notice and notice.text or text)
    window.status:SetTextColor(unpack(notice and (notice.error and { 1, 0.64, 0.55, 1 } or gold) or quiet))
end

function Addon:OptionsFeedback(text, error, key)
    key = key or self.currentOptionsPage or "scaling"
    notices[key] = text ~= "" and { text = text, error = error } or nil
    local page = pages[key]
    if page then self:SetPageStatus(key, page.defaultStatus or "") end
end

local function ExactInput(parent, name, x, y, callback)
    local input = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", x, y)
    input:SetSize(80, 24)
    input:SetAutoFocus(false)
    input:SetMaxLetters(12)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function() callback() end)
    return input
end

function Addon:RefreshOptions(syncInput)
    local page = pages.scaling
    if not page then return end
    local status = string.format("Current scale: %.3f", UIParent:GetScale())
    if self:IsResetPending() then
        status = status .. ". Reset and reload queued after combat."
    elseif InCombatLockdown() then
        status = status .. ". Scale changes apply after combat."
    else
        status = status .. (self.db.enabled and ". Custom scale enabled." or ". Using the game's scale.")
    end
    self:SetPageStatus("scaling", status)
    page.showMinimap:SetChecked(self.db.showMinimap)
    if syncInput then
        local value = self.db.enabled and self.db.scale or UIParent:GetScale()
        page.global.syncing = true
        page.global.slider:SetValue(math.max(self.MIN_SCALE, math.min(self.MAX_SCALE, value)))
        page.global.input:SetText(string.format("%.3f", value))
        page.global.syncing = false
    end
    for key, row in pairs(page.rows) do
        row.keep:SetChecked(self.db.elements[key] ~= nil)
        if syncInput == true then row.input:SetText(string.format("%.2f", self.db.elements[key] or 1)) end
    end
    self:RefreshResourceOptions(syncInput == true)
    self:RefreshSwingOptions()
end

local function BuildScalingOptions(self)
    local page = UI.Page("SmallerUIOptions", "Interface", 502)
    local content = page.content
    UI.Section(content, "UI scale", 0)
    local control = {}
    page.global = control
    local slider = CreateFrame("Slider", "SmallerUIGlobalSlider", content, "UISliderTemplateWithLabels")
    control.slider = slider
    slider:SetPoint("TOPLEFT", 14, -66)
    slider:SetSize(280, 16)
    slider:SetMinMaxValues(self.MIN_SCALE, self.MAX_SCALE)
    slider:SetValueStep(0.01)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("0.10")
    slider.High:SetText("1.50")
    slider.Text:SetText("Global UI scale")
    local function ApplyGlobal()
        if not Addon:SetScale(tonumber(control.input:GetText())) then
            Addon:OptionsFeedback("Enter a scale between 0.10 and 1.50.", true, "scaling")
            return
        end
        control.input:ClearFocus()
        Addon:OptionsFeedback(InCombatLockdown() and "Saved. Scale changes apply after combat." or "UI scale saved.", false, "scaling")
    end
    control.input = ExactInput(content, "SmallerUIGlobalInput", 332, -62, ApplyGlobal)
    control.apply = UI.Button(content, "SmallerUIGlobalApply", "Apply", 432, -62, 90, ApplyGlobal)
    control.input:SetScript("OnTextChanged", function(self)
        if control.syncing then return end
        Addon:OptionsFeedback("", false, "scaling")
        local value = tonumber(self:GetText())
        if Addon:IsValidScale(value) then
            control.syncing = true
            slider:SetValue(value)
            control.syncing = false
        end
    end)
    slider:SetScript("OnValueChanged", function(_, value)
        if control.syncing then return end
        control.syncing = true
        control.input:SetText(string.format("%.3f", value))
        control.syncing = false
        Addon:OptionsFeedback("", false, "scaling")
    end)

    UI.Section(content, "Element sizes", -118)
    UI.Label(content, "Element", 12, -158, "GameFontNormalSmall")
    UI.Label(content, "Independent", 228, -158, "GameFontNormalSmall")
    UI.Label(content, "Size", 332, -158, "GameFontNormalSmall")
    page.rows = {}
    for index, element in ipairs(self.elements) do
        local key, y = element.key, -183 - (index - 1) * 38
        local row = {}
        page.rows[key] = row
        UI.Label(content, element.label, 12, y - 7)
        row.keep = UI.Switch(content, "SmallerUIKeep_" .. key, "", 246, y - 1, function(enabled)
            Addon:SetElementIndependent(key, enabled)
            row.input:SetText("1.00")
            Addon:OptionsFeedback(InCombatLockdown() and "Saved. Scale changes apply after combat."
                or (enabled and element.label .. ": original size preserved." or element.label .. ": follows the global scale."), false, "scaling")
        end, "Keep the element at an independent scale.")
        local function ApplyElement()
            if not Addon:SetElementScale(key, tonumber(row.input:GetText())) then
                Addon:OptionsFeedback("Enter an element size between 0.25 and 2.00.", true, "scaling")
                return
            end
            row.input:ClearFocus()
            Addon:OptionsFeedback(InCombatLockdown() and "Saved. Scale changes apply after combat."
                or element.label .. ": size saved.", false, "scaling")
        end
        row.input = ExactInput(content, "SmallerUIElementInput_" .. key, 332, y, ApplyElement)
        row.apply = UI.Button(content, "SmallerUIElementApply_" .. key, "Apply", 432, y, 90, ApplyElement)
        UI.Tooltip(row.input, "1.00 = original size. 0.75 = 75%. 1.25 = 125%. Applying a value turns on Independent for this element.")
    end
    UI.Section(content, "General", -420)
    page.showMinimap = UI.Switch(content, "SmallerUIShowMinimap", "Show minimap button", 12, -455, function(enabled)
        Addon.db.showMinimap = enabled
        Addon:UpdateMinimap()
    end, "Click the minimap button to open this page. Drag it around the minimap to reposition it.")
    UI.Button(content, "SmallerUIResetButton", "Restore game scale", 338, -455, 190, function() Addon:Reset() end)
    page:SetScript("OnShow", function()
        Addon.currentOptionsPage = "scaling"
        Addon:OptionsFeedback("", false, "scaling")
        Addon:RefreshOptions(true)
    end)
    page:SetScript("OnHide", function()
        control.input:ClearFocus()
        for _, row in pairs(page.rows) do row.input:ClearFocus() end
    end)
    return page
end

local function FitWindow()
    local width, height = UIParent:GetSize()
    local rootScale = UIParent:GetEffectiveScale()
    local availableWidth, availableHeight = width * rootScale - 24, height * rootScale - 24
    -- Use the active UI scale unless the settings window needs to shrink further to fit.
    local scale = math.min(rootScale, math.max(0.1, math.min(availableWidth / WINDOW_WIDTH, availableHeight / MIN_HEIGHT)))
    window:SetScale(scale)
    window:SetHeight(math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(availableHeight / scale + 0.001))))
end

local function CompactHeader(frame, title, icon, onClose, artwork, height)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(height)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    if artwork then
        local art = header:CreateTexture(nil, "BACKGROUND")
        art:SetAllPoints()
        art:SetTexture(artwork)
    end
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT", 12, 1)
    rule:SetPoint("BOTTOMRIGHT", -12, 1)
    rule:SetHeight(1)
    rule:SetColorTexture(0.68, 0.52, 0.31, 0.58)
    local rim = header:CreateTexture(nil, "ARTWORK")
    local diameter = height >= 65 and 44 or 33
    rim:SetSize(diameter, diameter)
    rim:SetPoint("LEFT", 16, 0)
    rim:SetTexture("Interface\\AddOns\\SmallerUI\\Media\\PortraitRim.tga")
    rim:SetVertexColor(1, 0.81, 0.51)
    local emblem = header:CreateTexture(nil, "OVERLAY")
    emblem:SetSize(diameter - 8, diameter - 8)
    emblem:SetPoint("CENTER", rim, "CENTER")
    emblem:SetTexture("Interface\\Icons\\" .. icon)
    emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = header:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(emblem)
    emblem:AddMaskTexture(mask)
    local heading = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("LEFT", rim, "RIGHT", 10, 0)
    heading:SetText(title)
    heading:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", height >= 65 and 22 or 17, "")
    heading:SetTextColor(unpack(gold))
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -10, 0)
    close:SetScript("OnClick", onClose)
    UI.Tooltip(close, "Close " .. title)
    return header
end

function UI.Header(frame, title, icon, onClose, artwork, height)
    if height then return CompactHeader(frame, title, icon, onClose, artwork, height) end
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(74)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local background = header:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.04, 0.075, 0.105, 1)
    local art = header:CreateTexture(nil, "BORDER")
    art:SetAllPoints()
    art:SetTexture(artwork or HEADER_ART)
    local rule = header:CreateTexture(nil, "OVERLAY")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(0.68, 0.52, 0.31, 0.58)
    local engraved = header:CreateTexture(nil, "ARTWORK")
    engraved:SetPoint("TOPLEFT", 8, -6)
    engraved:SetPoint("TOPRIGHT", -8, -6)
    engraved:SetHeight(1)
    engraved:SetColorTexture(0.74, 0.58, 0.34, 0.36)
    local rim = header:CreateTexture(nil, "ARTWORK")
    rim:SetSize(38, 38)
    rim:SetPoint("LEFT", 19, 0)
    rim:SetColorTexture(0.70, 0.55, 0.34, 1)
    local emblem = header:CreateTexture(nil, "OVERLAY")
    emblem:SetSize(34, 34)
    emblem:SetPoint("CENTER", rim, "CENTER")
    emblem:SetTexture("Interface\\Icons\\" .. icon)
    emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local heading = UI.Label(header, title, 73, -25, "GameFontNormalLarge")
    heading:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 23, "OUTLINE")
    heading:SetTextColor(unpack(gold))
    local close = UI.Button(header, nil, "\195\151", 0, 0, 32, onClose)
    close:ClearAllPoints()
    close:SetPoint("RIGHT", -15, 0)
    close:SetHeight(32)
    close.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 17, "")
    UI.Tooltip(close, "Close " .. title)
    return header
end

function Addon:CreateOptions()
    if window then return true end
    if not self.db then return false end
    window = CreateFrame("Frame", "SmallerUISettings", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetSize(WINDOW_WIDTH, MAX_HEIGHT)
    window:SetPoint("CENTER")
    window:SetIgnoreParentScale(true)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    UI.Backdrop(window, { 0.048, 0.061, 0.068, 1 }, { 0.65, 0.49, 0.31, 1 })
    FitWindow()
    window.header = UI.Header(window, self.displayName, "INV_Misc_Gear_01", function() Addon:HideOptions() end)
    local rail = window:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("TOPLEFT", 1, -75)
    rail:SetPoint("BOTTOMLEFT", 1, 41)
    rail:SetWidth(184)
    rail:SetTexture(ENAMEL)
    rail:SetVertexColor(0.092, 0.112, 0.122)
    local divider = window:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", rail, "TOPRIGHT")
    divider:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT")
    divider:SetWidth(1)
    divider:SetColorTexture(0.36, 0.29, 0.21, 1)
    local well = CreateFrame("Frame", nil, window, "BackdropTemplate")
    well:SetFrameLevel(window:GetFrameLevel())
    well:SetPoint("TOPLEFT", 191, -82)
    well:SetPoint("BOTTOMRIGHT", -10, 45)
    UI.Backdrop(well, { 0.066, 0.082, 0.089, 1 }, { 0.24, 0.25, 0.23, 1 })
    local footer = window:CreateTexture(nil, "BORDER")
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(39)
    footer:SetColorTexture(0.038, 0.054, 0.071, 1)
    local rule = window:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", footer, "TOPLEFT")
    rule:SetPoint("TOPRIGHT", footer, "TOPRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(0.20, 0.25, 0.30, 1)
    local move = UI.Button(window, "SmallerUISettingsMove", "Move Mode", 0, 0, 157, function() Addon:BeginResourceEdit() end)
    move:SetHeight(32)
    move:ClearAllPoints()
    move:SetPoint("BOTTOMLEFT", 14, 53)
    SelectButton(move, true)
    UI.Tooltip(move, "Reposition or resize your bars, swing timer, and other UI elements.")
    window.status = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.status:SetPoint("BOTTOMLEFT", 18, 9)
    window.status:SetPoint("BOTTOMRIGHT", -18, 9)
    window.status:SetHeight(22)
    window.status:SetJustifyH("LEFT")
    window.status:SetWordWrap(true)
    window.entries = {}
    local y = -93
    for _, entry in ipairs(navigation) do
        local key = entry[1]
        if entry[4] then
            UI.Label(window, entry[4], 19, y, "GameFontHighlightSmall"):SetTextColor(unpack(quiet))
            y = y - 21
        end
        local item = UI.Button(window, nil, entry[2], 12, y, 160,
            function() Addon:ShowOptions(key) end)
        item:SetHeight(32)
        item.label:ClearAllPoints()
        item.label:SetPoint("LEFT", 39, 0)
        item.label:SetPoint("RIGHT", -6, 0)
        item.label:SetJustifyH("LEFT")
        item.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(19, 19)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexture("Interface\\Icons\\" .. entry[3])
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        item.marker = item:CreateTexture(nil, "OVERLAY")
        item.marker:SetSize(2, 18)
        item.marker:SetPoint("LEFT", 0, 0)
        item.marker:SetColorTexture(unpack(gold))
        SelectButton(item, false)
        window.entries[key] = item
        y = y - 36
    end
    window:RegisterEvent("DISPLAY_SIZE_CHANGED")
    window:RegisterEvent("UI_SCALE_CHANGED")
    window:SetScript("OnEvent", function(self) if self:IsShown() then FitWindow() end end)
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing()
        local page = pages[Addon.currentOptionsPage]
        if page then page:Hide() end
    end)
    table.insert(UISpecialFrames, window:GetName())
    pages.scaling = BuildScalingOptions(self)
    self.options = pages.scaling
    pages.resources, pages.party, pages.pet = self:BuildResourceOptions()
    pages.swing = self:BuildSwingOptions()
    pages.whispers = self:BuildWhisperOptions()
    pages.loot = self:BuildLootOptions()
    pages.vendorDeals = self:BuildVendorDealOptions()
    for _, page in pairs(pages) do
        page:HookScript("OnHide", function(self)
            if self:GetAlpha() < 1 then
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(1)
            end
        end)
    end
    self:RefreshOptions(true)
    return true
end

function Addon:ShowOptions(key)
    key = key or self.currentOptionsPage or "scaling"
    if self:IsEditingResources() then
        self:FinishResourceEdit(true)
        return true
    end
    if InCombatLockdown() then
        self.pendingOptionsPage = key
        self:Print("Settings will open after combat.")
        return false
    end
    if not self:CreateOptions() then return false end
    if not pages[key] then key = "scaling" end
    local activePage = pages[key]
    local entering = not activePage:IsVisible()
    self.currentOptionsPage = key
    for name, page in pairs(pages) do
        if name ~= key then page:Hide() end
        SelectButton(window.entries[name], name == key)
    end
    FitWindow()
    window:Show()
    activePage:Show()
    if entering then Animate(activePage, 0.14, function(progress) activePage:SetAlpha(0.82 + 0.18 * progress) end) end
    self:SetPageStatus(key, activePage.defaultStatus or "")
    return true
end

function Addon:OpenPendingOptions()
    if self.pendingOptionsPage and not InCombatLockdown() then
        local key = self.pendingOptionsPage
        self.pendingOptionsPage = nil
        self:ShowOptions(key)
    end
end

function Addon:HideOptions()
    if window then window:Hide() end
    return true
end
