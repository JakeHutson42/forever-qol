local _, Addon = ...
local window
local PAGE_SIZE = 8
local WIDTH, ROW_HEIGHT = 480, 43

local function Draw(message)
    local total = #window.results
    for index, button in ipairs(window.rows) do
        local result = window.results[window.offset + index]
        button.result = result
        button:SetShown(result ~= nil)
        if result then
            local thread, message = result[1], result[2]
            local context = message[4] and (message[4] .. ": " .. message[1]) or message[1]
            Addon:DrawWhisperIdentityPlate(button.identity, thread, (context:gsub("%s+", " ")))
            button.stamp:SetText(date("%d/%m/%Y %H:%M", message[2]))
        end
    end
    local paged = total > PAGE_SIZE
    window.previous:SetShown(paged)
    window.next:SetShown(paged)
    window.previous:SetEnabled(window.offset > 0)
    window.next:SetEnabled(window.offset + PAGE_SIZE < total)
    window.empty:SetShown(total == 0)
    window.empty:SetText(message or "No matching messages")
    window.status:SetShown(paged)
    if paged then
        window.status:SetText(string.format("%d–%d of %d", window.offset + 1, math.min(total, window.offset + PAGE_SIZE), total))
    end
    local height = math.max(125, 104 + math.min(PAGE_SIZE, total - window.offset) * ROW_HEIGHT + (paged and 28 or 0))
    window:SetHeight(height)
    Addon.OptionsUI.FitScale(window, WIDTH, height)
end

local function Search()
    Addon:CancelHistorySearch(window.driver)
    window.offset, window.results = 0, {}
    local terms = Addon:HistoryTerms(window.search:GetText())
    if #terms == 0 then Draw("Search your whispers, party messages, and saved history."); return end
    Draw("Searching…")
    local threads = Addon:GetChatSearchThreads()
    local results, threadIndex, messageIndex = {}, 1, 1
    local days, orderedDays = {}, {}
    local names = {}
    local function Next()
        local thread = threads[threadIndex]
        if not thread then return false end
        local message = thread.messages[messageIndex]
        if not message then
            threadIndex, messageIndex = threadIndex + 1, 1
            return true
        end
        local name = names[thread]
        if not name then
            name = (thread.battleTag or thread.name):lower()
            if thread.bnet then
                local displayName = Addon:GetWhisperDisplayName(thread)
                if not displayName:find("|K", 1, true) then name = name .. " " .. displayName:lower() end
            end
            names[thread] = name
        end
        local matches = true
        local body = message[1]:lower()
        local author = message[4] and message[4]:lower()
        local timestamp
        for _, term in ipairs(terms) do
            if not name:find(term, 1, true) and not body:find(term, 1, true)
                and not (author and author:find(term, 1, true)) then
                if not term:find("%d") then matches = false; break end
                timestamp = timestamp or date("%d/%m/%Y %H:%M", message[2])
                if not timestamp:find(term, 1, true) then matches = false; break end
            end
        end
        if matches then
            local day = math.floor(message[2] / 86400)
            local bucket = days[day]
            if not bucket then
                bucket = {}
                days[day] = bucket
                orderedDays[#orderedDays + 1] = day
            end
            bucket[#bucket + 1] = { thread, message, messageIndex }
        end
        messageIndex = messageIndex + 1
        return true
    end
    Addon:RunHistorySearch(window.driver, Next, function()
        table.sort(orderedDays, function(a, b) return a > b end)
        local function NewestFirst(a, b)
            if a[2][2] ~= b[2][2] then return a[2][2] > b[2][2] end
            if a[1] == b[1] then return a[3] > b[3] end
            return a[1].key < b[1].key
        end
        local dayIndex, bucket, cursor = 0, nil, 1
        Addon:RunHistorySearch(window.driver, function()
            if not bucket or cursor > #bucket then
                dayIndex, cursor = dayIndex + 1, 1
                local day = orderedDays[dayIndex]
                if not day then return false end
                bucket = days[day]
                table.sort(bucket, NewestFirst)
                days[day] = nil
            end
            results[#results + 1] = bucket[cursor]
            cursor = cursor + 1
            return true
        end, function()
            window.results = results
            Draw()
        end)
    end)
end

local function CreateWindow()
    local UI = Addon.OptionsUI
    local frame = CreateFrame("Frame", "SmallerUIChatSearch", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(WIDTH, 125)
    frame:SetPoint("CENTER")
    frame:SetIgnoreParentScale(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    table.insert(UISpecialFrames, frame:GetName())
    UI.WindowSurface(frame)
    UI.Header(frame, "Chat search", "INV_Letter_15", function() frame:Hide() end, nil, 51)
    frame.rows, frame.results, frame.offset = {}, {}, 0
    frame.driver = CreateFrame("Frame", nil, frame)
    frame.driver:Hide()
    frame.refresh = CreateFrame("Frame", nil, frame)
    frame.refresh:Hide()
    frame.refresh:SetScript("OnUpdate", function(self, delta)
        self.delay = self.delay - delta
        if self.delay > 0 then return end
        self:Hide()
        Search()
    end)
    local search = UI.EditBox(frame, "SmallerUIAllChatSearchInput", GameFontHighlightSmall)
    search:SetPoint("TOPLEFT", 14, -58)
    search:SetSize(WIDTH - 28, 28)
    search:SetAutoFocus(false)
    search:SetMaxLetters(200)
    search:SetFontObject(GameFontHighlightSmall)
    search:SetTextInsets(28, 10, 0, 0)
    local icon = search:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetPoint("LEFT", 7, 0)
    icon:SetSize(14, 14)
    local prompt = UI.Label(search, "Message, player, or date", 28, -7, "GameFontDisableSmall")
    search:SetScript("OnTextChanged", function(field)
        prompt:SetShown(field:GetText() == "")
        Addon:CancelHistorySearch(frame.driver)
        frame.offset, frame.results = 0, {}
        Draw(field:GetText() == "" and "Search your whispers, party messages, and saved history." or "Searching…")
        frame.refresh.delay = 0.15
        frame.refresh:Show()
    end)
    search:SetScript("OnEnterPressed", function(field)
        field:ClearFocus()
        frame.refresh:Hide()
        Search()
    end)
    search:SetScript("OnEscapePressed", function(field) field:ClearFocus() end)
    frame.search = search
    for index = 1, PAGE_SIZE do
        local row
        row = UI.Button(frame, nil, "", 14, -93 - (index - 1) * ROW_HEIGHT, WIDTH - 28, function()
            local result = row.result
            if result and Addon:OpenChatSearchResult(result[1], result[2]) then
                frame:Hide()
                Addon:HideOptions()
            end
        end, true)
        row:SetHeight(40)
        local identity = CreateFrame("Frame", nil, row)
        identity:SetPoint("TOPLEFT", 4, 0)
        identity:SetPoint("BOTTOMRIGHT", -4, 0)
        Addon:BuildWhisperIdentityPlate(identity, 124)
        identity.rim:SetSize(34, 34)
        row.identity = identity
        row.stamp = identity:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.stamp:SetPoint("RIGHT", -7, 10)
        row.stamp:SetTextColor(0.85, 0.77, 0.64)
        row:Hide()
        frame.rows[index] = row
    end
    frame.previous = UI.Button(frame, nil, "Previous", 0, 0, 84, function()
        frame.offset = frame.offset - PAGE_SIZE
        Draw()
    end)
    frame.previous:ClearAllPoints()
    frame.previous:SetPoint("BOTTOMLEFT", 14, 8)
    frame.next = UI.Button(frame, nil, "Next", 0, 0, 70, function()
        frame.offset = frame.offset + PAGE_SIZE
        Draw()
    end)
    frame.next:ClearAllPoints()
    frame.next:SetPoint("LEFT", frame.previous, "RIGHT", 7, 0)
    frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.status:SetPoint("LEFT", frame.next, "RIGHT", 15, 0)
    frame.empty = UI.Label(frame, "", 16, -96, "GameFontHighlightSmall", WIDTH - 32)
    frame.empty:SetTextColor(0.78, 0.69, 0.54)
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() then UI.FitScale(self, WIDTH, self:GetHeight()) end
    end)
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        Addon:CancelHistorySearch(frame.driver)
        frame.refresh:Hide()
        search:ClearFocus()
    end)
    return frame
end

function Addon:ShowChatSearch(query)
    window = window or CreateWindow()
    if query and query ~= "" then window.search:SetText(query) end
    window:Show()
    window.refresh:Hide()
    Search()
    if window.search.SetFocus then window.search:SetFocus() end
end
