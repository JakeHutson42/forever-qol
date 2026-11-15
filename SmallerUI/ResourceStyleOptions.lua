local _, Addon = ...
local formats = { { 0, "Hidden" }, { 1, "Current" }, { 2, "Current / maximum" },
    { 3, "Percentage" }, { 4, "Current + percentage" }, { 5, "Current / max + %" } }
local fonts = { { 1, "Game default" }, { 2, "Arial" }, { 3, "Skurri" } }
local alignments = { { 1, "Left" }, { 2, "Centre" }, { 3, "Right" } }
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function PreviewBar(parent, scope, kind, value)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar.resourceKind, bar.view, bar.sampleValue = kind, { scope = scope }, value
    bar.fill = CreateFrame("StatusBar", nil, bar)
    bar.fill:SetStatusBarTexture(WHITE)
    bar.fill:SetMinMaxValues(0, 100)
    bar.fill:SetValue(value)
    bar.trimLayer = CreateFrame("Frame", nil, bar)
    bar.trimLayer:SetAllPoints()
    bar.trimLayer:SetFrameLevel(bar.fill:GetFrameLevel() + 1)
    bar.label = bar.trimLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetText(kind == "health" and "Health" or "Power")
    bar.valueText = bar.trimLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.valueText:SetWordWrap(false)
    bar.pulse = bar.fill:CreateTexture()
    bar.pulse:Hide()
    return bar
end

local function RefreshPreview(bar, sample, curved, x, y, r, g, b)
    Addon:SetResourceBarCurved(bar, curved)
    local size = sample[bar.resourceKind]
    bar:SetSize(size.width, size.height)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", x, y)
    local pixel = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor() or 1) / bar:GetEffectiveScale()
    if pixel ~= bar.pixel then
        bar.pixel = pixel
        bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = pixel })
    end
    local inset = sample.style.border and not curved and pixel or 0
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("TOPLEFT", inset, -inset)
    bar.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
    Addon:SetResourceFillColour(bar.fill, r, g, b)
    Addon:StyleResourceBar(bar, sample, false)
    -- Keep the sample readable without requiring the pointer to cover its controls.
    Addon:SetResourceTextHovered(bar, true)
    bar:SetMouseMotionEnabled(false)
    Addon:RenderResourceText(bar, bar.sampleValue, 100, true)
end

function Addon:BuildResourceStyleOptions(page, scope, prefix, look, text)
    local UI = self.OptionsUI
    local function Settings() return Addon:GetResourceSettings()[scope] end
    local function Style() return Settings().style end
    local dropdowns, inputs = {}, {}
    local function Select(parent, key, caption, choices, labelX, x, y, width, swatch)
        local setting = key:gsub("^%u", string.lower)
        UI.Label(parent, caption, labelX, y - 7)
        local dropdown = UI.Select(parent, prefix .. key, x, y, width, choices,
            function() return Style()[setting] end,
            function(value) Addon:SetResourceStyle(scope, setting, value) end, swatch)
        dropdowns[#dropdowns + 1] = dropdown
        return dropdown
    end
    local function Switch(parent, key, name, caption, x, y, tip)
        return UI.Switch(parent, prefix .. name, caption, x, y,
            function(enabled) Addon:SetResourceStyle(scope, key, enabled) end, tip)
    end
    local function Input(parent, key, caption, labelX, x, y, low, high)
        UI.Label(parent, caption, labelX, y - 7)
        local input = CreateFrame("EditBox", prefix .. key, parent, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", x, y)
        input:SetSize(70, 24)
        input:SetAutoFocus(false)
        input:SetMaxLetters(3)
        local function Current() return Style()[key] end
        local function Apply(value) return Addon:SetResourceStyle(scope, key, value) end
        local function Restore(self) self:SetText(tostring(Current())); self:ClearFocus() end
        input:SetScript("OnEnterPressed", function(self)
            if not Apply(tonumber(self:GetText())) then
                Addon:OptionsFeedback(string.format("Enter a whole number from %d to %d.", low, high), true)
            else
                Addon:OptionsFeedback("")
            end
            Restore(self)
        end)
        input:SetScript("OnEscapePressed", Restore)
        UI.NumberArrows(input, 1, low, high, Current, Apply)
        inputs[key] = input
    end
    local function ColourButton(parent, name, label, x, y, kind, token, width)
        local button = UI.Button(parent, prefix .. name, label, x, y, width or 180,
            function() Addon:OpenResourceColourPicker(scope, kind, token and page.resourceToken or nil) end)
        button.swatch = button:CreateTexture(nil, "OVERLAY")
        button.swatch:SetSize(14, 14)
        button.swatch:SetPoint("RIGHT", -9, 0)
        return button
    end

    local card = CreateFrame("Frame", nil, look, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 12, -2)
    card:SetSize(596, 108)
    UI.Plate(card)
    UI.Label(card, "Preset & preview", 15, -13, "GameFontNormal")
    local theme = UI.Select(card, prefix .. "Theme", 15, -38, 245, Addon.resourceThemes,
        function() return Style().theme end,
        function(value) Addon:CancelResourceColourPicker(scope); Addon:ApplyResourceTheme(scope, value) end)
    dropdowns[#dropdowns + 1] = theme
    UI.Tooltip(theme, "Apply a coordinated texture, trim and palette to these bars.")
    page.themeColours = Switch(card, "themeColours", "ThemeColours", "Apply preset colours", 12, -70,
        "Turn off to keep your custom palette when switching themes.")
    page.themeColours:SetWidth(255)
    local sample = { health = {}, power = {}, arc = { width = 30, gap = 112 } }
    local healthPreview = PreviewBar(card, scope, "health", 78)
    local powerPreview = PreviewBar(card, scope, "power", 61)

    UI.Section(look, "Surface & feedback", -124)
    page.texture = Select(look, "BarTexture", "Bar texture", Addon.resourceTextures, 12, 126, -155, 180,
        function(button, entry)
            local swatch = button:AttachTexture()
            swatch:SetPoint("RIGHT", -8, 0)
            swatch:SetSize(112, 12)
            swatch:SetTexture(entry[3])
            swatch:SetVertexColor(Addon:GetResourceColour(scope, "health"))
            return 252, 22
        end)
    local motion = Select(look, "Motion", "Motion", Addon.resourceMotion, 328, 430, -155, 176)
    UI.Tooltip(motion, "Choose how strongly the bars flash or trail when values change.")
    Select(look, "Trim", "Edge detail", Addon.resourceTrims, 12, 126, -192, 180)
    page.border = Switch(look, "border", "Border", "Show frame", 320, -192)
    Input(look, "backgroundOpacity", "Track opacity %", 12, 126, -230, 0, 100)
    if scope == "player" then
        page.smooth = UI.Switch(look, prefix .. "Smooth", "Animate change trail", 320, -230,
            function(enabled) Addon:SetResourceOption("root", "smooth", enabled) end,
            "Animate the trailing fill. Current health and power update immediately.")
    end

    UI.Section(look, "Palette", -274)
    page.healthColour = ColourButton(look, "healthColour", "Health colour", 12, -305, "health")
    page.powerColour = ColourButton(look, "powerColour", "Power colour", 208, -305, "power")
    UI.Button(look, prefix .. "ResetColours", "Reset palette", 404, -305, 202, function()
        Addon:CancelResourceColourPicker(scope)
        Addon:ResetResourceColours(scope)
        Addon:OptionsFeedback("Default palette restored.")
    end)
    page.powerByType = UI.Switch(look, prefix .. "PowerByType", "Match power type", 4, -342, function(enabled)
        Addon:CancelResourceColourPicker(scope)
        Addon:SetResourcePowerByType(scope, enabled)
    end, "Use Mana, Rage, Energy, Focus and other resource colours.")
    page.borderColour = ColourButton(look, "BorderColour", "Frame colour", 12, -380, "borderColour")
    page.trackColour = ColourButton(look, "TrackColour", "Track colour", 208, -380, "trackColour")
    page.accentColour = ColourButton(look, "AccentColour", "Accent colour", 404, -380, "accentColour", nil, 202)

    local resources = CreateFrame("Frame", prefix .. "ResourceColours", look)
    resources:SetPoint("TOPLEFT", 0, -429)
    resources:SetSize(620, 84)
    resources:Hide()
    page.resourceToken = "MANA"
    local unit = scope == "party" and "party1" or scope
    if UnitExists(unit) then
        local _, token = UnitPowerType(unit)
        if Addon:IsResourceColourToken(token) then page.resourceToken = token end
    end
    local resourceToggle = UI.Button(look, prefix .. "ResourceColoursToggle", "Edit type colours", 328, -342, 180, function(button)
        Addon:CancelResourceColourPicker(scope)
        local open = not resources:IsShown()
        resources:SetShown(open)
        button:SetText(open and "Hide type colours" or "Edit type colours")
        look:SetHeight(open and 507 or 426)
        page.content:SetHeight(look:GetHeight())
    end)
    UI.Tooltip(resourceToggle, "Override the colour of an individual power type.")
    UI.Label(resources, "Resource", 12, -7)
    page.resourceSelect = UI.Select(resources, prefix .. "ResourceToken", 126, 0, 180,
        function() return Addon:GetResourceColourChoices(page.resourceToken) end,
        function() return page.resourceToken end,
        function(token) Addon:CancelResourceColourPicker(scope); page.resourceToken = token; Addon:RefreshResourceOptions() end)
    page.resourceColour = ColourButton(resources, "ResourceColour", "Resource colour", 328, 0, "power", true)
    UI.Button(resources, prefix .. "ResetResourceColour", "Use default colour", 328, -36, 180, function()
        Addon:CancelResourceColourPicker(scope)
        Addon:SetResourcePowerOverride(scope, page.resourceToken, nil)
    end)

    UI.Section(text, "Bar text", 0)
    page.values = UI.Switch(text, prefix .. "Values", "Show bar values", 4, -30,
        function(enabled) Addon:SetResourceOption(scope, "values", enabled) end)
    Select(text, "healthFormat", "Health text", formats, 12, 126, -72, 180)
    Select(text, "powerFormat", "Power text", formats, 328, 430, -72, 176)
    page.healthTextOnHover = Switch(text, "healthTextOnHover", "healthTextOnHover", "Health text on hover", 4, -106)
    page.powerTextOnHover = Switch(text, "powerTextOnHover", "powerTextOnHover", "Power text on hover", 320, -106)
    UI.Section(text, "Typography", -150)
    Select(text, "font", "Font", fonts, 12, 126, -181, 180)
    Select(text, "alignment", "Alignment", alignments, 328, 430, -181, 176)
    Input(text, "fontSize", "Text size", 12, 126, -218, 6, 48)
    page.autoFontSize = Switch(text, "autoFontSize", "AutoFontSize", "Automatic size", 320, -218)
    page.shortNumbers = Switch(text, "shortNumbers", "ShortNumbers", "Short numbers (12.3k)", 4, -257,
        "Use compact numbers when the game makes readable values available.")
    page.textColour = ColourButton(text, "TextColour", "Text colour", 328, -257, "textColour")
    text:SetScript("OnHide", function()
        Addon:CancelResourceColourPicker(scope)
        inputs.fontSize:ClearFocus()
    end)
    look:SetScript("OnHide", function()
        Addon:CancelResourceColourPicker(scope)
        inputs.backgroundOpacity:ClearFocus()
    end)
    look:SetScript("OnShow", function()
        if look:IsVisible() then page:RefreshStyling() end
    end)

    function page:RefreshStyling(syncInput)
        local settings, style = Settings(), Style()
        self.border:SetChecked(style.border)
        self.themeColours:SetChecked(style.themeColours)
        self.autoFontSize:SetChecked(style.autoFontSize)
        self.shortNumbers:SetChecked(style.shortNumbers)
        self.healthTextOnHover:SetChecked(style.healthTextOnHover)
        self.powerTextOnHover:SetChecked(style.powerTextOnHover)
        if look:IsVisible() then
            local curved = settings.curved == true
            sample.style, sample.values = style, settings.values
            sample.health.width, sample.health.height = curved and 30 or 278, curved and 53 or math.min(26, settings.health.height)
            sample.power.width, sample.power.height = curved and 30 or 278, curved and 53 or math.min(22, settings.power.height)
            RefreshPreview(healthPreview, sample, curved, curved and 367 or 302, curved and -30 or -32,
                Addon:GetResourceColour(scope, "health"))
            RefreshPreview(powerPreview, sample, curved, curved and 487 or 302, curved and -30 or -37 - sample.health.height,
                Addon:GetResourceColour(scope, "power"))
        end
        for name in pairs(Addon.resourceStyleColours) do
            local color = style[name]
            self[name].swatch:SetColorTexture(color.r, color.g, color.b)
        end
        self.resourceColour.swatch:SetColorTexture(Addon:GetResourceColour(scope, "power", self.resourceToken))
        inputs.fontSize:SetEnabled(not style.autoFontSize)
        inputs.fontSize.up:SetEnabled(not style.autoFontSize)
        inputs.fontSize.down:SetEnabled(not style.autoFontSize)
        inputs.fontSize:SetAlpha(style.autoFontSize and 0.45 or 1)
        if syncInput then
            for key, input in pairs(inputs) do input:SetText(tostring(style[key])) end
        end
        if self:IsShown() then
            for _, dropdown in ipairs(dropdowns) do dropdown:GenerateMenu() end
            self.resourceSelect:GenerateMenu()
        end
    end
end
