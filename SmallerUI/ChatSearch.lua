local _, Addon = ...
local window
local PAGE_SIZE = 8
local gold = { 0.83, 0.66, 0.35, 1 }

local function Draw()
    local total = #window.results
    for index, button in ipairs(window.rows) do
        local result = window.results[window.offset + index]
        button.result = result
        button:SetShown(result ~= nil)
        if result then
            local thread, message = result[1], result[2]
            button.label:SetText((thread.name:gsub("|", "||")))
            button.message:SetText(message[4] and (message[4] .. ": " .. message[1]) or message[1])
            button.stamp:SetText(date("%d/%m/%Y %H:%M", message[2]))
        end
    end
    window.previous:SetEnabled(window.offset > 0)
    window.next:SetEnabled(window.offset + PAGE_SIZE < total)
    local status = "No matching messages"
    if total > 0 then status = string.format("%d-%d of %d", window.offset + 1, math.min(total, window.offset + PAGE_SIZE), total) end
    window.status:SetText(status)
end

local function Search()
    Addon:CancelHistorySearch(window.driver)
    window.offset, window.results = 0, {}
    Draw()
    local terms = Addon:HistoryTerms(window.search:GetText())
    if #terms == 0 then window.status:SetText("Enter a search term"); return end
    window.status:SetText("Searching...")
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
        if not name then name = thread.name:lower(); names[thread] = name end
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
    frame:SetSize(510, 458)
    frame:SetPoint("CENTER")
    frame:SetIgnoreParentScale(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    table.insert(UISpecialFrames, frame:GetName())
    UI.Backdrop(frame, { 0.048, 0.065, 0.085, 0.99 }, gold)
    UI.Label(frame, "Search all chats", 14, -14, "GameFontNormalLarge")
    UI.Button(frame, nil, "X", 470, -9, 26, function() frame:Hide() end)
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
    local search = CreateFrame("EditBox", "SmallerUIAllChatSearchInput", frame, "BackdropTemplate")
    search:SetPoint("TOPLEFT", 14, -43)
    search:SetSize(482, 27)
    search:SetAutoFocus(false)
    search:SetMaxLetters(200)
    search:SetFontObject(GameFontHighlightSmall)
    search:SetTextInsets(28, 10, 0, 0)
    UI.Backdrop(search, { 0.07, 0.10, 0.13, 1 })
    local icon = search:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetPoint("LEFT", 7, 0)
    icon:SetSize(14, 14)
    local prompt = UI.Label(search, "Message, player, or date", 28, -7, "GameFontDisableSmall")
    search:SetScript("OnTextChanged", function(field)
        prompt:SetShown(field:GetText() == "")
        Addon:CancelHistorySearch(frame.driver)
        frame.offset, frame.results = 0, {}
        Draw()
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
        row = UI.Button(frame, nil, "", 14, -80 - (index - 1) * 42, 482, function()
            local result = row.result
            if result and Addon:OpenChatSearchResult(result[1], result[2]) then
                frame:Hide()
                Addon:HideOptions()
            end
        end)
        row:SetHeight(38)
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", 8, -5)
        row.label:SetPoint("TOPRIGHT", -145, -5)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.label:SetTextColor(unpack(gold))
        row.stamp = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.stamp:SetPoint("TOPRIGHT", -8, -5)
        row.message = UI.Label(row, "", 8, -20, "GameFontHighlightSmall", 463)
        row.message:SetWordWrap(false)
        row:Hide()
        frame.rows[index] = row
    end
    frame.previous = UI.Button(frame, nil, "Previous", 14, -424, 84, function()
        frame.offset = frame.offset - PAGE_SIZE
        Draw()
    end)
    frame.next = UI.Button(frame, nil, "Next", 107, -424, 70, function()
        frame.offset = frame.offset + PAGE_SIZE
        Draw()
    end)
    frame.status = UI.Label(frame, "", 190, -430, "GameFontHighlightSmall")
    frame:SetScript("OnHide", function()
        Addon:CancelHistorySearch(frame.driver)
        frame.refresh:Hide()
        search:ClearFocus()
    end)
    return frame
end

function Addon:ShowChatSearch(query)
    window = window or CreateWindow()
    local width, height = UIParent:GetSize()
    local scale = UIParent:GetEffectiveScale()
    window:SetScale(math.max(0.1, math.min(1, (width * scale - 24) / 510, (height * scale - 24) / 458)))
    if query and query ~= "" then window.search:SetText(query) end
    window:Show()
    window.refresh:Hide()
    Search()
    if window.search.SetFocus then window.search:SetFocus() end
end
