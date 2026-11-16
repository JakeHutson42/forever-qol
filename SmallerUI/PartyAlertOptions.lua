local _, Addon = ...
local panel
local WIDTH, HEIGHT = 590, 464
local styles = { { "bounce", "Bounce" }, { "pop", "Pop" }, { "cascade", "Cascade" } }
local outlines = { { "none", "None" }, { "thin", "Thin" }, { "thick", "Thick" } }
local sounds = { { "off", "Off" }, { "chime", "WoW chime" }, { "mp3", "Custom MP3" } }

local function Settings()
    return Addon:GetPartyAlertSettings()
end

local function Refresh()
    local cfg = Settings()
    for key, widget in pairs(panel.switches) do widget:SetChecked(cfg[key]) end
    for key, widget in pairs(panel.inputs) do
        if not widget.HasFocus or not widget:HasFocus() then widget:SetText(tostring(cfg[key])) end
    end
    for _, dropdown in ipairs(panel.dropdowns) do dropdown:GenerateMenu() end
    panel.swatch:SetColorTexture(cfg.r, cfg.g, cfg.b, 1)
    panel.inputs.recipient:SetEnabled(cfg.whisper)
    panel.testSound:SetEnabled(cfg.sound ~= "off")
end

local function PickColour()
    if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame")
    end
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
        Addon:Print("The colour picker is unavailable.")
        return
    end
    local cfg = Settings()
    local r, g, b = cfg.r, cfg.g, cfg.b
    local function Apply(red, green, blue)
        cfg.r, cfg.g, cfg.b = red, green, blue
        Refresh()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
        cancelFunc = function() Apply(r, g, b) end,
    })
end

local function CreateOptions()
    local UI = Addon.OptionsUI
    local window = CreateFrame("Frame", "SmallerUIPartyAlertOptions", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetIgnoreParentScale(true)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    UI.WindowSurface(window)
    UI.Header(window, "Chat pop-ups", "INV_Letter_15", function() window:Hide() end)
    table.insert(UISpecialFrames, window:GetName())
    window.switches, window.inputs, window.dropdowns = {}, {}, {}

    local function Save(key, value)
        if not Addon:SetPartyAlertOption(key, value) then return false end
        Refresh()
        return true
    end
    local function Switch(key, label, x, y, width, tip)
        local widget = UI.Switch(window, nil, label, x, y, function(value) Save(key, value) end, tip)
        widget:SetWidth(width)
        window.switches[key] = widget
    end
    local function Select(key, label, entries, x, y)
        UI.Label(window, label, x, y - 6)
        local dropdown = UI.Select(window, nil, x + 104, y, 150, entries,
            function() return Settings()[key] end, function(value) Save(key, value) end)
        window.dropdowns[#window.dropdowns + 1] = dropdown
    end
    local function Input(key, label, x, y, width)
        UI.Label(window, label, x, y - 6)
        local name = "SmallerUIPartyAlert_" .. key
        local input = UI.EditBox(window, name)
        input:SetPoint("TOPLEFT", x + 104, y)
        input:SetSize(width, 24)
        input:SetAutoFocus(false)
        local range = Addon.partyAlertLimits[key]
        input:SetMaxLetters(range and 6 or 64)
        local function Current() return Settings()[key] end
        local function Finish(field)
            field:SetText(tostring(Current()))
            field:ClearFocus()
        end
        input:SetScript("OnEscapePressed", Finish)
        input:SetScript("OnEnterPressed", function(field)
            local text = field:GetText():match("^%s*(.-)%s*$")
            local value = text
            if range then value = tonumber(text) end
            if not Save(key, value) then
                if range then Addon:Print(string.format("Enter a value between %d and %d.", range[1], range[2]))
                else Addon:Print("Enter a character name, with realm if needed.") end
            end
            Finish(field)
        end)
        if range then UI.NumberArrows(input, 1, range[1], range[2], Current, function(value) return Save(key, value) end) end
        window.inputs[key] = input
        return input
    end

    UI.Section(window, "Delivery", -88)
    Switch("enabled", "Enable pop-ups", 12, -114, 185)
    Switch("party", "Party", 207, -114, 120, "Send to and receive from your regular party.")
    Switch("whisper", "Whisper", 347, -114, 155, "Send and receive character whisper pop-ups.")
    local recipient = Input("recipient", "Recipient", 16, -150, 250)
    UI.Tooltip(recipient, "Enter a character name, then press Enter. Leave blank to use your most recent character whisper.")

    UI.Section(window, "Appearance", -189)
    Select("style", "Animation", styles, 16, -216)
    Select("thickness", "Text outline", outlines, 302, -216)
    local size = Input("size", "Max text size", 16, -250, 58)
    UI.Tooltip(size, "Long messages can use smaller text to fit the screen.")
    local intensity = Input("intensity", "Motion %", 302, -250, 58)
    UI.Tooltip(intensity, "Set to zero for a simple fade.")
    local colour = UI.Button(window, nil, "Text colour", 16, -284, 122, PickColour)
    window.swatch = colour:CreateTexture(nil, "OVERLAY")
    window.swatch:SetSize(12, 12)
    window.swatch:SetPoint("RIGHT", -8, 0)
    local preview = UI.Button(window, nil, "Preview alert", 302, -284, 120, function() Addon:PreviewPartyAlert() end)
    UI.Tooltip(preview, "Play an alert with your current appearance and sound settings.")

    UI.Section(window, "Sound", -325)
    Select("sound", "Playback", sounds, 16, -353)
    Input("soundLength", "Limit (sec)", 302, -353, 58)
    window.testSound = UI.Button(window, nil, "Play sound", 16, -389, 122, function() Addon:TestPartyAlertSound() end)
    UI.Label(window, "Custom file  SmallerUI/Media/Popup.mp3", 151, -396, "GameFontDisableSmall")
    UI.Label(window, "Copy your MP3 there, then restart WoW.", 151, -416, "GameFontDisableSmall")

    window:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        for _, input in pairs(self.inputs) do input:ClearFocus() end
    end)
    window:RegisterEvent("UI_SCALE_CHANGED")
    window:RegisterEvent("DISPLAY_SIZE_CHANGED")
    window:SetScript("OnEvent", function(self)
        if self:IsShown() then UI.FitScale(self, WIDTH, HEIGHT) end
    end)
    return window
end

function Addon:ShowPartyAlertOptions()
    panel = panel or CreateOptions()
    self.OptionsUI.FitScale(panel, WIDTH, HEIGHT)
    Refresh()
    panel:Show()
end
