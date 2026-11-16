local _, Addon = ...
local page
local DISPLAY_HEIGHT = 414
local placements = {
    { "left", "Left side" }, { "top", "Above chat" }, { "right", "Right of chat" }, { "free", "Free placement" },
}

function Addon:RefreshWhisperOptions()
    if not page then return end
    local cfg = self:GetWhisperSettings()
    for key, control in pairs(page.switches) do control:SetChecked(cfg[key]) end
    page.switches.partyAutoOpen:SetEnabled(cfg.party)
    page.switches.partyInterrupt:SetEnabled(cfg.party and cfg.partyAutoOpen)
    page.switches.partyInstances:SetEnabled(cfg.party)
    page.switches.tradeRequests:SetEnabled(cfg.tradeHistory)
    page.switches.tradeExpanded:SetEnabled(cfg.tradeHistory)
    for key, enabled in pairs({ historyLimit = cfg.saveHistory, tradeLimit = cfg.tradeHistory }) do
        local input = page.inputs[key]
        input:SetEnabled(enabled)
        input.up:SetEnabled(enabled)
        input.down:SetEnabled(enabled)
    end
    for key, input in pairs(page.inputs) do
        if not input.HasFocus or not input:HasFocus() then input:SetText(tostring(cfg[key])) end
    end
    if page:IsShown() then
        page.position:GenerateMenu()
        page.preview:Refresh(cfg)
    end
end

function Addon:BuildWhisperOptions()
    local UI = self.OptionsUI
    page = UI.Page("SmallerUIWhisperOptions", "Whisper Manager", DISPLAY_HEIGHT)
    page.switches, page.inputs = {}, {}
    local function Panel(height)
        local panel = CreateFrame("Frame", nil, page.content)
        panel:SetPoint("TOPLEFT")
        panel:SetSize(620, height)
        return panel
    end
    local display, messages, history = Panel(DISPLAY_HEIGHT), Panel(192), Panel(279)
    local controls = CreateFrame("Frame", nil, display)
    controls:SetPoint("TOPLEFT", 0, -39)
    controls:SetSize(306, 320)
    local function Current(key) return Addon:GetWhisperSettings()[key] end
    local function Switch(parent, key, label, x, y, tip)
        local widget = UI.Switch(parent, "SmallerUIWhisper_" .. key, label, x, y,
            function(value) Addon:SetWhisperOption(key, value) end, tip)
        page.switches[key] = widget
        return widget
    end
    local function Select(key, label, choices, y)
        UI.Label(controls, label, 12, y - 6)
        return UI.Select(controls, "SmallerUIWhisper_" .. key, 136, y, 154, choices,
            function() return Current(key) end, function(value) Addon:SetWhisperOption(key, value) end)
    end
    local function Input(parent, key, label, x, y)
        UI.Label(parent, label, x, y - 6)
        local input = UI.EditBox(parent, "SmallerUIWhisper_" .. key)
        input:SetPoint("TOPLEFT", x + 124, y)
        input:SetSize(64, 24)
        input:SetAutoFocus(false)
        input:SetMaxLetters(6)
        local low, high = unpack(self.whisperLimits[key])
        local function Read() return Current(key) end
        local function Save(value) return Addon:SetWhisperOption(key, value) end
        input:SetScript("OnEnterPressed", function(field)
            if not Save(tonumber(field:GetText())) then
                Addon:OptionsFeedback(string.format("Enter a number from %d to %d.", low, high), true, "whispers")
            else
                Addon:OptionsFeedback("", false, "whispers")
            end
            field:SetText(tostring(Read()))
            field:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(field) field:SetText(tostring(Read())); field:ClearFocus() end)
        UI.NumberArrows(input, 1, low, high, Read, Save)
        page.inputs[key] = input
        return input
    end

    Switch(display, "enabled", "Enable Whisper Manager", 12, 0)
    Switch(display, "showBar", "Show chat menu", 318, 0, "Shift-right-click the minimap button to toggle it.")
    UI.Section(controls, "Chat menu", 0)
    local reset = UI.Button(controls, "SmallerUIWhisperReset", "Reset placement", 170, 0, 120,
        function() Addon:ResetWhisperPosition() end)
    reset:SetHeight(24)
    page.position = Select("position", "Placement", placements, -32)
    Input(controls, "size", "Portrait size", 12, -64)
    Input(controls, "opacity", "Menu opacity %", 12, -96)
    Switch(controls, "badges", "Unread badges", 12, -123):SetWidth(137)
    Switch(controls, "locked", "Lock position", 158, -123, "Unlock to drag the chat menu to a new position."):SetWidth(132)
    UI.Section(controls, "Conversation", -161)
    Input(controls, "width", "Window width", 12, -193)
    Input(controls, "height", "Window height", 12, -225)
    Input(controls, "textSize", "Text size", 12, -257)
    Switch(controls, "timestamps", "Show timestamps", 12, -284):SetWidth(278)
    page.preview = self:CreateWhisperPreview(display)
    page.preview:SetPoint("TOPLEFT", 318, -39)

    UI.Section(messages, "Party chat", 0)
    Switch(messages, "party", "Show Party conversation", 12, -32)
    Switch(messages, "partyAutoOpen", "Open Party chat automatically", 314, -32,
        "Open the conversation when a Party message arrives. With this off, open it from the chat menu when you are ready.")
    Switch(messages, "partyInterrupt", "Switch away from whispers", 12, -64,
        "When Party opens automatically, let it replace the conversation you are reading.")
    Switch(messages, "partyInstances", "Include instance parties", 314, -64)
    UI.Section(messages, "On-screen alerts", -111)
    UI.Button(messages, "SmallerUIWhisperPopups", "Chat pop-up settings", 12, -146, 170, function()
        if Addon:HideOptions() then Addon:ShowPartyAlertOptions() end
    end)

    UI.Section(history, "Chat history", 0)
    Switch(history, "saveHistory", "Save chat history", 12, -32,
        "Restore whispers and Party messages on this character. Turning this off removes the saved copy.")
    local historyLimit = Input(history, "historyLimit", "Messages per chat", 314, -34)
    UI.Tooltip(historyLimit, "Keep the newest messages in each conversation. Lowering this removes older saved messages.")
    UI.Button(history, nil, "Search all chats", 12, -69, 150, function() Addon:ShowChatSearch() end)
    UI.Section(history, "Trade history", -124)
    Switch(history, "tradeHistory", "Record trade history", 12, -156)
    Switch(history, "tradeRequests", "Include trade requests", 314, -156)
    Switch(history, "tradeExpanded", "Expand history by default", 12, -188)
    local tradeLimit = Input(history, "tradeLimit", "Entries per player", 314, -190)
    UI.Tooltip(tradeLimit, "Keep this many trade entries per player on this character. Lowering the limit removes older entries.")

    UI.Tabs(page, { { "display", "Display", display }, { "messages", "Messages", messages }, { "history", "History", history } })
    page:SetScript("OnShow", function() Addon:RefreshWhisperOptions() end)
    page:SetScript("OnHide", function()
        for _, input in pairs(page.inputs) do input:ClearFocus() end
    end)
    return page
end
