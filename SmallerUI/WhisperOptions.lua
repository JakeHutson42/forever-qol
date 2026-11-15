local _, Addon = ...
local page
local placements = { { "top", "Above chat" }, { "right", "Right of chat" }, { "free", "Free placement" } }
local directions = { { "auto", "Follow placement" }, { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }

function Addon:RefreshWhisperOptions()
    if not page then return end
    local cfg = self:GetWhisperSettings()
    for key, control in pairs(page.switches) do control:SetChecked(cfg[key]) end
    page.switches.partyAutoOpen:SetEnabled(cfg.party)
    page.switches.partyInterrupt:SetEnabled(cfg.party and cfg.partyAutoOpen)
    page.switches.partyInstances:SetEnabled(cfg.party)
    page.switches.tradeRequests:SetEnabled(cfg.tradeHistory)
    page.switches.tradeExpanded:SetEnabled(cfg.tradeHistory)
    page.inputs.historyLimit:SetEnabled(cfg.saveHistory)
    page.inputs.historyLimit.up:SetEnabled(cfg.saveHistory)
    page.inputs.historyLimit.down:SetEnabled(cfg.saveHistory)
    for key, input in pairs(page.inputs) do
        if not input.HasFocus or not input:HasFocus() then input:SetText(tostring(cfg[key])) end
    end
    if page:IsShown() then
        page.position:GenerateMenu()
        page.direction:GenerateMenu()
    end
end

function Addon:BuildWhisperOptions()
    local UI = self.OptionsUI
    page = UI.Page("SmallerUIWhisperOptions", "Whisper Manager", 681)
    page.switches, page.inputs = {}, {}
    local content = page.content
    local function Current(key) return Addon:GetWhisperSettings()[key] end
    local function Switch(key, label, x, y, tip)
        page.switches[key] = UI.Switch(content, "SmallerUIWhisper_" .. key, label, x, y,
            function(value) Addon:SetWhisperOption(key, value) end, tip)
    end
    local function Select(key, label, choices, x, y)
        UI.Label(content, label, x, y - 6)
        return UI.Select(content, "SmallerUIWhisper_" .. key, x + 110, y, 164, choices,
            function() return Current(key) end, function(value) Addon:SetWhisperOption(key, value) end)
    end
    local function Input(key, label, x, y)
        UI.Label(content, label, x, y - 6)
        local input = CreateFrame("EditBox", "SmallerUIWhisper_" .. key, content, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", x + 110, y)
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
    end

    UI.Section(content, "Whisper bar", 0)
    UI.Button(content, "SmallerUIWhisperReset", "Reset placement", 446, 0, 150, function() Addon:ResetWhisperPosition() end)
    Switch("enabled", "Enable Whisper Manager", 12, -30)
    Switch("badges", "Show unread counts", 314, -30)
    page.position = Select("position", "Placement", placements, 12, -72)
    page.direction = Select("direction", "Orientation", directions, 314, -72)
    Switch("locked", "Lock position", 12, -108, "Unlock and drag the bar's handle to place it anywhere.")
    Switch("showBar", "Show whisper bar", 314, -108, "Shift-right-click the minimap button to toggle it.")
    Input("size", "Portrait size", 12, -151)
    Input("opacity", "Bar opacity %", 314, -151)
    UI.Section(content, "Conversation", -197)
    Switch("timestamps", "Show timestamps", 12, -228)
    Input("textSize", "Text size", 314, -228)
    Input("width", "Bubble width", 12, -273)
    Input("height", "Bubble height", 314, -273)
    UI.Section(content, "Party chat", -320)
    Switch("party", "Show Party conversation", 12, -349)
    Switch("partyAutoOpen", "Open on new messages", 314, -349)
    Switch("partyInterrupt", "Switch away from whispers", 12, -381,
        "When Party opens automatically, let it replace the conversation you are reading.")
    Switch("partyInstances", "Include instance parties", 314, -381)
    UI.Button(content, "SmallerUIWhisperPopups", "Chat pop-up settings", 12, -414, 170, function()
        if Addon:HideOptions() then Addon:ShowPartyAlertOptions() end
    end)
    UI.Section(content, "Trade history", -463)
    Switch("tradeHistory", "Record trade history", 12, -492)
    Switch("tradeRequests", "Include trade requests", 314, -492)
    Switch("tradeExpanded", "Expand history by default", 12, -524)
    Input("tradeLimit", "Entries per player", 314, -524)
    UI.Tooltip(page.inputs.tradeLimit, "Keep this many trade entries per player on this character. Lowering the limit removes older entries.")
    UI.Section(content, "Chat history", -575)
    Switch("saveHistory", "Save chat history", 12, -608,
        "Restore whispers and Party messages on this character. Turning this off removes the saved copy.")
    Input("historyLimit", "Messages per chat", 314, -608)
    UI.Button(content, nil, "Search all chats", 12, -644, 150, function() Addon:ShowChatSearch() end)
    UI.Tooltip(page.inputs.historyLimit, "Keep the newest messages in each conversation. Lowering this removes older saved messages.")
    page:SetScript("OnShow", function() Addon:RefreshWhisperOptions() end)
    page:SetScript("OnHide", function()
        for _, input in pairs(page.inputs) do input:ClearFocus() end
    end)
    return page
end
