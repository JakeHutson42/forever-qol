local _, Addon = ...
local listener = CreateFrame("Frame")
local bar, chat, selected, dragging
local threads, order = {}, {}
local firstSlot, slots = 1, {}
local gold = { 0.69, 0.51, 0.26, 1 }
local border = { 0.32, 0.29, 0.23, 1 }
local surface = { 0.048, 0.065, 0.085, 0.98 }
local whisperIcon = "Interface\\ChatFrame\\UI-ChatWhisperIcon"
local classIcons = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local portraitUnits = { "target", "focus", "mouseover", "player", "party1", "party2", "party3", "party4" }
local events = { CHAT_MSG_WHISPER = 1, CHAT_MSG_WHISPER_INFORM = 2,
    CHAT_MSG_BN_WHISPER = 3, CHAT_MSG_BN_WHISPER_INFORM = 4 }
local partyEvents = { CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_INSTANCE_CHAT = "instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "instance" }
local partyThread
local newParty
local defaults = { enabled = true, showBar = true, position = "top", direction = "auto", size = 36,
    opacity = 100, width = 360, height = 300, textSize = 13,
    badges = true, timestamps = false, locked = false, saveHistory = false, historyLimit = 500,
    party = true, partyAutoOpen = true, partyInterrupt = false, partyInstances = true,
    tradeHistory = true, tradeRequests = true, tradeExpanded = false, tradeLimit = 30 }
Addon.whisperLimits = { size = { 24, 72 }, opacity = { 20, 100 },
    width = { 240, 720 }, height = { 200, 600 }, textSize = { 10, 24 }, tradeLimit = { 5, 200 },
    historyLimit = { 50, 5000 } }
local positions = { top = true, right = true, free = true }
local directions = { auto = true, horizontal = true, vertical = true }
local UpdateBar, RefreshMessages, ChangeHistory
local PAGE_SIZE = 60

local function RevealThread(thread, capacity)
    for index, active in ipairs(order) do
        if active == thread then
            firstSlot = math.max(index - capacity + 1, math.min(firstSlot, index))
            return
        end
    end
end

local function Public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Settings()
    return Addon.db.whispers
end

local function IsVertical(cfg)
    if cfg.direction ~= "auto" then return cfg.direction == "vertical" end
    return cfg.position == "right" or cfg.position == "free" and cfg.freeVertical == true
end

function Addon:ValidateWhispers()
    local cfg = self.db.whispers
    if type(cfg) ~= "table" then cfg = {}; self.db.whispers = cfg end
    for key, fallback in pairs(defaults) do
        if type(cfg[key]) ~= type(fallback) then cfg[key] = fallback end
        local range = self.whisperLimits[key]
        if range then
            cfg[key] = Number(cfg[key]) and math.max(range[1], math.min(range[2], math.floor(cfg[key] + 0.5))) or fallback
        end
    end
    if not positions[cfg.position] then cfg.position = defaults.position end
    if not directions[cfg.direction] then cfg.direction = defaults.direction end
    if not Number(cfg.x) or not Number(cfg.y) then cfg.x, cfg.y = nil, nil end
    local archive = self.character.chatHistory
    if not cfg.saveHistory or type(archive) ~= "table" or archive.version ~= 1 or type(archive.threads) ~= "table" then
        self.character.chatHistory = nil
    end
end

function Addon:GetWhisperSettings() return Settings() end

function Addon:SetWhisperOption(key, value)
    if defaults[key] == nil or type(value) ~= type(defaults[key]) then return false end
    local range = self.whisperLimits[key]
    if range and (not Number(value) or value < range[1] or value > range[2]) then return false end
    if key == "position" and not positions[value] or key == "direction" and not directions[value] then return false end
    Settings()[key] = range and math.floor(value + 0.5) or value
    if key == "tradeLimit" then self:TrimTradeHistory() end
    if key == "saveHistory" or key == "historyLimit" then ChangeHistory() end
    if not value and (key == "enabled" or key == "tradeHistory") then self:DiscardPendingTrade() end
    self:ApplyWhispers()
    return true
end

function Addon:ResetWhisperPosition()
    local cfg = Settings()
    cfg.x, cfg.y, cfg.freeVertical = nil, nil, nil
    self:SetWhisperOption("position", "top")
end

local function PlainText(text)
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (text:gsub("|", "||"))
end

function Addon:GetWhisperCharacterKey(name)
    local character, realm = name:match("^([^%-]+)%-(.+)$")
    if not character then character, realm = name, GetNormalizedRealmName and GetNormalizedRealmName() or "" end
    return "character:" .. character:lower() .. "-" .. realm:gsub("%s", ""):lower()
end

local function GetThread(key, name)
    if not threads[key] then threads[key] = { key = key, name = name, messages = {}, unread = 0 } end
    return threads[key]
end

local function SaveThread(thread)
    if not Settings().saveHistory or #thread.messages == 0 then return end
    local archive = Addon.character.chatHistory
    if not archive then
        archive = { version = 1, threads = {} }
        Addon.character.chatHistory = archive
    end
    local entry = archive.threads[thread.key] or {}
    archive.threads[thread.key] = entry
    entry.name, entry.guid, entry.account = thread.name, thread.guid, thread.account
    entry.bnet, entry.party, entry.instance = thread.bnet or nil, thread.party or nil, thread.instance or nil
    entry.unread, entry.hidden = thread.unread > 0 and thread.unread or nil, thread.hidden or nil
    entry.messages = thread.messages
end

local function TrimMessages(thread)
    local messages = thread.messages
    local excess = #messages - Settings().historyLimit
    if excess <= 0 then return false end
    local keep = #messages - excess
    for index = 1, keep do messages[index] = messages[index + excess] end
    for index = keep + 1, keep + excess do messages[index] = nil end
    return true
end

ChangeHistory = function()
    if not Settings().saveHistory then
        Addon.character.chatHistory = nil
        return
    end
    for _, thread in pairs(threads) do
        TrimMessages(thread)
        SaveThread(thread)
    end
end

local function Activate(thread)
    if thread.active then return end
    thread.active, thread.hidden = true, nil
    table.insert(order, 1, thread)
    firstSlot = 1
end

local function Portrait(texture, thread)
    if thread and thread.party then
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
        return
    end
    local guid = thread and thread.guid
    if thread and thread.account and C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local account = C_BattleNet.GetAccountInfoByID(thread.account)
        if Public(account) and account then
            local game = account.gameAccountInfo
            if Public(game) and game and Public(game.playerGuid) then guid = game.playerGuid end
        end
    end
    local unit = guid and UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if guid and Public(unit) and not unit and UnitGUID then
        for _, candidate in ipairs(portraitUnits) do
            local id = UnitGUID(candidate)
            if Public(id) and id == guid then unit = candidate; break end
        end
    end
    texture:SetTexCoord(0, 1, 0, 1)
    if SetPortraitTexture and Public(unit) and unit then
        SetPortraitTexture(texture, unit)
        return
    end
    if guid and guid:find("^Player%-") and GetPlayerInfoByGUID and CLASS_ICON_TCOORDS then
        local _, class = GetPlayerInfoByGUID(guid)
        local coords = Public(class) and class and CLASS_ICON_TCOORDS[class]
        if coords then
            texture:SetTexture(classIcons)
            texture:SetTexCoord(unpack(coords))
            return
        end
    end
    texture:SetTexture(whisperIcon)
end

local function CloseChat()
    if chat then chat:Hide() end
end

local function OpenReply()
    if not selected then return end
    if selected.party then
        local prefix = selected.instance and (SLASH_INSTANCE_CHAT1 or "/i") or (SLASH_PARTY1 or "/p")
        if ChatFrameUtil and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat(prefix .. " ")
        elseif ChatFrame_OpenChat then ChatFrame_OpenChat(prefix .. " ") end
    elseif selected.bnet then
        if ChatFrameUtil and ChatFrameUtil.SendBNetTell then ChatFrameUtil.SendBNetTell(selected.name)
        elseif ChatFrame_SendBNetTell then ChatFrame_SendBNetTell(selected.name) end
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(selected.name)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(selected.name)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. selected.name .. " ")
    end
end

local function Deactivate(thread)
    if not thread or not thread.active then return end
    for index, active in ipairs(order) do
        if active == thread then table.remove(order, index); break end
    end
    thread.active = false
    if selected == thread then CloseChat() end
end

local function HideThread()
    local thread = selected
    if not thread then return end
    thread.hidden = true
    SaveThread(thread)
    Deactivate(thread)
    UpdateBar()
end

local function TradeEntries()
    if not selected or selected.party or selected.bnet or not Settings().tradeHistory then return end
    return Addon:GetTradeHistory(selected.key)
end

local function ToggleTrades()
    if not TradeEntries() then return end
    local expanded = selected.tradeExpanded
    if expanded == nil then expanded = Settings().tradeExpanded end
    selected.tradeExpanded = not expanded
    chat.search:ClearFocus()
    if chat.search:GetText() ~= "" then chat.search:SetText("")
    else RefreshMessages(true) end
end

local function CreateChat()
    local UI = Addon.OptionsUI
    local frame = CreateFrame("Frame", "SmallerUIWhisperChat", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetIgnoreParentScale(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetScript("OnHide", function()
        selected = nil
        frame.search:ClearFocus()
        frame.search:SetText("")
    end)
    table.insert(UISpecialFrames, frame:GetName())
    UI.Backdrop(frame, surface, gold)

    frame.avatar = frame:CreateTexture(nil, "ARTWORK")
    frame.avatar:SetSize(24, 24)
    frame.avatar:SetPoint("TOPLEFT", 11, -10)
    frame.title = UI.Label(frame, "", 43, -15, "GameFontNormal")
    frame.title:SetPoint("TOPRIGHT", -47, -15)
    frame.title:SetWordWrap(false)
    local close = UI.Button(frame, nil, "X", 0, 0, 25, CloseChat)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", -9, -9)
    UI.Tooltip(close, "Close conversation")
    local allChats = UI.Button(frame, nil, "All chats", 0, 0, 66, function()
        Addon:ShowChatSearch(frame.search:GetText())
    end)
    allChats:ClearAllPoints()
    allChats:SetPoint("TOPRIGHT", -41, -9)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", 43, -15)
    frame.title:SetPoint("TOPRIGHT", -115, -15)
    local reply = UI.Button(frame, nil, "Reply", 0, 0, 72, OpenReply)
    reply:ClearAllPoints()
    reply:SetPoint("BOTTOMRIGHT", -10, 9)
    UI.Tooltip(reply, "Reply in WoW chat")
    local hide = UI.Button(frame, nil, "Hide from bar", 0, 0, 95, HideThread)
    hide:ClearAllPoints()
    hide:SetPoint("BOTTOMLEFT", 10, 9)
    UI.Tooltip(hide, "Hide this conversation until new activity.")
    local search = CreateFrame("EditBox", "SmallerUIWhisperSearch", frame, "BackdropTemplate")
    search:SetPoint("TOPLEFT", 10, -42)
    search:SetPoint("TOPRIGHT", -10, -42)
    search:SetHeight(26)
    search:SetAutoFocus(false)
    search:SetMaxLetters(200)
    search:SetFontObject(GameFontHighlightSmall)
    search:SetTextInsets(29, 23, 0, 0)
    UI.Backdrop(search, { 0.07, 0.10, 0.13, 1 }, border)
    local lens = search:CreateTexture(nil, "ARTWORK")
    lens:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    lens:SetSize(14, 14)
    lens:SetPoint("LEFT", 7, 0)
    lens:SetAlpha(0.65)
    local placeholder = UI.Label(search, "Search messages", 29, -7, "GameFontDisableSmall")
    local clear = UI.Button(search, nil, "X", 0, 0, 20, function() search:SetText("") end)
    clear:ClearAllPoints()
    clear:SetPoint("RIGHT", -2, 0)
    clear:SetHeight(20)
    clear:Hide()
    search:SetScript("OnTextChanged", function(field)
        local empty = field:GetText() == ""
        placeholder:SetShown(empty)
        clear:SetShown(not empty)
        if not frame.opening then RefreshMessages(true) end
    end)
    search:SetScript("OnEnterPressed", function(field) field:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(field) field:SetText(""); field:ClearFocus() end)
    frame.search = search
    frame.tradeToggle = UI.Button(frame, "SmallerUIWhisperTrades", "Trades", 0, 0, 100, ToggleTrades)
    frame.tradeToggle:ClearAllPoints()
    frame.tradeToggle:SetPoint("TOPLEFT", 10, -74)
    frame.tradeClose = UI.Button(frame, "SmallerUIWhisperTradesClose", "X", 0, 0, 25, function()
        selected.tradeExpanded = false
        RefreshMessages(true)
    end)
    frame.tradeClose:ClearAllPoints()
    frame.tradeClose:SetPoint("TOPRIGHT", -10, -74)
    UI.Tooltip(frame.tradeClose, "Dismiss trade history")

    local tail = frame:CreateTexture(nil, "BORDER")
    tail:SetSize(14, 14)
    tail:SetTexture("Interface\\AddOns\\SmallerUI\\Media\\TrimJewel.tga")
    tail:SetVertexColor(unpack(gold))
    frame.tail = tail

    local scroll = CreateFrame("ScrollFrame", "SmallerUIWhisperScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -74)
    scroll:SetPoint("BOTTOMRIGHT", -30, 43)
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function(self, offset)
        if selected and selected.unread > 0 and not frame.rendering and not frame.showingTrades
            and frame.search:GetText() == "" and frame.pageOffset == 0 and frame:IsVisible()
            and offset >= self:GetVerticalScrollRange() - 4 then
            selected.unread = 0
            SaveThread(selected)
            UpdateBar()
        end
    end)
    frame.scroll, frame.content, frame.rows = scroll, content, {}
    frame.older = UI.Button(frame, nil, "<", 0, 0, 24, function()
        frame.pageOffset = frame.pageOffset + PAGE_SIZE
        RefreshMessages(false, false, true)
    end)
    frame.older:ClearAllPoints()
    frame.older:SetPoint("BOTTOMLEFT", 10, 42)
    UI.Tooltip(frame.older, "Older messages")
    frame.newer = UI.Button(frame, nil, ">", 0, 0, 24, function()
        frame.pageOffset = math.max(0, frame.pageOffset - PAGE_SIZE)
        RefreshMessages(false, false, true)
    end)
    frame.newer:ClearAllPoints()
    frame.newer:SetPoint("LEFT", frame.older, "RIGHT", 4, 0)
    UI.Tooltip(frame.newer, "Newer messages")
    frame.pageLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.pageLabel:SetPoint("LEFT", frame.newer, "RIGHT", 8, 0)
    frame.empty = UI.Label(content, "", 6, -8, "GameFontDisableSmall")
    return frame
end

local function CreateMessage()
    local row = CreateFrame("Frame", nil, chat.content, "BackdropTemplate")
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 9, -6)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(true) end
    local stamp = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    stamp:SetPoint("BOTTOMRIGHT", -8, 5)
    row.label, row.stamp = label, stamp
    return row
end

local function ScreenSize()
    local scale = UIParent:GetEffectiveScale()
    return UIParent:GetWidth() * scale, UIParent:GetHeight() * scale
end

local function SizeChat()
    local cfg = Settings()
    local width, height = ScreenSize()
    chat:SetSize(math.max(160, math.min(cfg.width, width - 16)), math.max(140, math.min(cfg.height, height - 16)))
end

local tradeTitles = { opened = "Trade opened", cancelled = "Trade cancelled",
    closed = "Trade closed", complete = "Trade completed" }

local function FormatOffer(offer)
    local parts = {}
    if type(offer) == "table" then
        for _, item in ipairs(type(offer.items) == "table" and offer.items or {}) do
            if type(item) == "table" and type(item.name) == "string" and Number(item.count) then
                parts[#parts + 1] = (item.count > 1 and (item.count .. " x ") or "") .. PlainText(item.name)
            end
        end
        if Number(offer.money) and offer.money > 0 then
            local goldCoins = math.floor(offer.money / 10000)
            local silver = math.floor(offer.money / 100) % 100
            local copper = offer.money % 100
            local coins = {}
            if goldCoins > 0 then coins[#coins + 1] = goldCoins .. "g" end
            if silver > 0 then coins[#coins + 1] = silver .. "s" end
            if copper > 0 then coins[#coins + 1] = copper .. "c" end
            parts[#parts + 1] = table.concat(coins, " ")
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "None"
end

local function ShowTradeEntry(entry)
    return type(entry) == "table" and (entry.status == "complete" or Settings().tradeRequests)
end

local function FormatTimestamp(timestamp, savedText)
    if timestamp then return date("%d/%m/%Y %H:%M", timestamp) end
    if not savedText then return "" end
    return (savedText:gsub("^(%d%d%d%d)%-(%d%d)%-(%d%d)( %d%d:%d%d)$", "%3/%2/%1%4"))
end

RefreshMessages = function(reset, append, pageChanged)
    if not selected or not chat:IsShown() then return end
    SizeChat()
    local cfg = Settings()
    local scroll = chat.scroll
    local entries = TradeEntries()
    local trades = 0
    if entries then
        for _, entry in ipairs(entries) do
            if ShowTradeEntry(entry) then trades = trades + 1 end
        end
    end
    local query = chat.search:GetText():match("^%s*(.-)%s*$"):lower()
    local expanded = selected.tradeExpanded
    if expanded == nil then expanded = cfg.tradeExpanded end
    local showingTrades = trades > 0 and expanded and query == ""
    if chat.showingTrades ~= showingTrades then append = false end
    chat.showingTrades = showingTrades
    chat.tradeToggle:SetShown(trades > 0)
    chat.tradeToggle:SetText((showingTrades and "Trades -" or "Trades +") .. " (" .. trades .. ")")
    chat.tradeClose:SetShown(showingTrades)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 10, trades > 0 and -105 or -74)
    local offset = scroll:GetVerticalScroll()
    local atEnd = not showingTrades and query == "" and (reset or pageChanged or offset >= scroll:GetVerticalScrollRange() - 4)
    local width = chat:GetWidth() - 40
    local y = append and chat.messageBottom or 3
    local messages = selected.messages
    if showingTrades then
        messages = {}
        for _, entry in ipairs(entries) do
            if ShowTradeEntry(entry) then
                local text = tradeTitles[entry.status]
                if entry.status == "request" then
                    text = entry.request == "initiated" and "Request initiated" or "Request received"
                end
                text = text or "Trade"
                if entry.status == "complete" then
                    text = text .. "\nSent: " .. FormatOffer(entry.sent) .. "\nReceived: " .. FormatOffer(entry.received)
                end
                local timestamp = Number(entry.time) and entry.time or nil
                messages[#messages + 1] = { text, timestamp, nil, nil, type(entry.time) == "string" and entry.time or nil }
            end
        end
        append, y = false, 3
    elseif query ~= "" then
        messages = {}
        for _, message in ipairs(selected.messages) do
            if message[1]:lower():find(query, 1, true)
                or message[4] and message[4]:lower():find(query, 1, true) then
                messages[#messages + 1] = message
            end
        end
        append, y = false, 3
    end
    local total = #messages
    if reset then chat.pageOffset = 0 end
    chat.pageOffset = math.min(chat.pageOffset or 0, math.max(0, total - 1))
    local last = total - chat.pageOffset
    local first = math.max(1, last - PAGE_SIZE + 1)
    if chat.pageOffset > 0 or chat.renderFirst ~= first then append, y = false, 3 end
    chat.renderFirst = first
    local paged = total > PAGE_SIZE
    scroll:SetPoint("BOTTOMRIGHT", -30, paged and 72 or 43)
    chat.older:SetShown(paged)
    chat.newer:SetShown(paged)
    chat.older:SetEnabled(first > 1)
    chat.newer:SetEnabled(chat.pageOffset > 0)
    chat.pageLabel:SetShown(paged)
    if paged then chat.pageLabel:SetText(string.format("%d-%d of %d", first, last, total)) end
    chat.empty:SetText(query ~= "" and total == 0 and "No matching messages" or "")
    local start = append and last or first
    chat.rendering = true
    for index = start, last do
        local message = messages[index]
        local rowIndex = index - first + 1
        local row = chat.rows[rowIndex] or CreateMessage()
        chat.rows[rowIndex] = row
        local outgoing = message[3] == true
        local bubbleWidth = showingTrades and width or math.floor(width * 0.85)
        row:ClearAllPoints()
        row:SetPoint(outgoing and "TOPRIGHT" or "TOPLEFT", 0, -y)
        row:SetWidth(bubbleWidth)
        Addon.OptionsUI.Backdrop(row, outgoing and { 0.15, 0.20, 0.26, 1 } or { 0.10, 0.13, 0.17, 1 },
            message == chat.highlight and { 1, 0.81, 0.40, 1 } or outgoing and gold or border)
        local label = row.label
        if STANDARD_TEXT_FONT then label:SetFont(STANDARD_TEXT_FONT, cfg.textSize) end
        label:SetWidth(bubbleWidth - 18)
        local text = message[1]
        label:SetText(message[4] and ("|cffffd17f" .. message[4] .. "|r\n" .. text) or text)
        local showTime = cfg.timestamps or showingTrades
        local timestamp = showTime and FormatTimestamp(message[2], message[5]) or ""
        row.stamp:SetText(timestamp or "")
        local height = math.max(cfg.textSize + 12, label:GetStringHeight() + 12) + (showTime and 12 or 0)
        row:SetHeight(height)
        if message == chat.highlight then chat.highlightTop = y end
        row:Show()
        y = y + height + 6
    end
    chat.messageBottom = y
    for index = math.max(0, last - first + 1) + 1, #chat.rows do chat.rows[index]:Hide() end
    chat.content:SetSize(width, math.max(query ~= "" and total == 0 and 25 or 1, y))
    scroll:UpdateScrollChildRect()
    local scrollToEnd = atEnd and (not pageChanged or chat.pageOffset == 0)
    scroll:SetVerticalScroll(scrollToEnd and scroll:GetVerticalScrollRange()
        or (reset or pageChanged) and 0 or math.min(offset, scroll:GetVerticalScrollRange()))
    chat.rendering = nil
    if scrollToEnd and chat.pageOffset == 0 and selected.unread > 0 then
        selected.unread = 0
        SaveThread(selected)
        UpdateBar()
    end
end

local function OpenChat(thread, match, matchIndex)
    if not Settings().showBar then return end
    chat = chat or CreateChat()
    selected = thread
    if match then thread.tradeExpanded = false end
    chat.highlight, chat.highlightTop = match, nil
    chat.opening = true
    chat.search:ClearFocus()
    chat.search:SetText("")
    chat.opening = nil
    chat.title:SetText(PlainText(thread.name))
    Portrait(chat.avatar, thread)
    chat:Show()
    UpdateBar()
    chat.pageOffset = matchIndex and math.floor((#thread.messages - matchIndex) / PAGE_SIZE) * PAGE_SIZE or 0
    RefreshMessages(not match, false, match ~= nil)
    if chat.highlightTop then
        chat.scroll:SetVerticalScroll(math.min(chat.highlightTop, chat.scroll:GetVerticalScrollRange()))
    end
end

local function StartDrag()
    if Settings().locked then return end
    dragging = true
    CloseChat()
    bar:StartMoving()
end

local function StopDrag()
    if not dragging then return end
    dragging = nil
    bar:StopMovingOrSizing()
    local x, y = bar:GetCenter()
    local cx, cy = UIParent:GetCenter()
    local scale = UIParent:GetEffectiveScale()
    if Number(x) and Number(y) and Number(cx) and Number(cy) then
        local cfg = Settings()
        local barScale = bar:GetEffectiveScale()
        cfg.freeVertical = IsVertical(cfg)
        cfg.position, cfg.x, cfg.y = "free", x * barScale - cx * scale, y * barScale - cy * scale
    end
    Addon:ApplyWhispers()
end

local function CreateBar()
    local frame = CreateFrame("Frame", "SmallerUIWhisperBar", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetIgnoreParentScale(true)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        firstSlot = firstSlot + (delta > 0 and -1 or 1)
        UpdateBar()
    end)
    frame:SetScript("OnEnter", function(self)
        if not self.overflow then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Scroll to see more conversations.")
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnHide", function() frame:StopMovingOrSizing(); dragging = nil end)
    Addon.OptionsUI.Backdrop(frame, surface, border)
    local grip = CreateFrame("Button", nil, frame, "BackdropTemplate")
    grip:SetSize(17, 17)
    grip:SetPoint("TOPLEFT", 4, -4)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", StartDrag)
    grip:SetScript("OnDragStop", StopDrag)
    Addon.OptionsUI.Backdrop(grip, { 0.12, 0.16, 0.19, 1 }, gold)
    local mark = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mark:SetPoint("CENTER")
    mark:SetText("=")
    Addon.OptionsUI.Tooltip(grip, "Drag to move. Right-click for Whisper Manager settings.")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnClick", function() Addon:ShowOptions("whispers") end)
    grip:EnableMouseWheel(true)
    grip:SetScript("OnMouseWheel", frame:GetScript("OnMouseWheel"))
    frame.grip = grip
    return frame
end

local function CreateSlot()
    local button = CreateFrame("Button", nil, bar, "BackdropTemplate")
    Addon.OptionsUI.Backdrop(button, { 0.11, 0.15, 0.19, 1 }, gold)
    button.avatar = button:CreateTexture(nil, "ARTWORK")
    button.avatar:SetPoint("TOPLEFT", 3, -3)
    button.avatar:SetPoint("BOTTOMRIGHT", -3, 3)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:EnableMouseWheel(true)
    button:SetScript("OnMouseWheel", bar:GetScript("OnMouseWheel"))
    local badge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    badge:SetPoint("TOPRIGHT", 3, 3)
    badge:SetSize(16, 16)
    Addon.OptionsUI.Backdrop(badge, { 0.69, 0.08, 0.12, 1 }, { 0.93, 0.42, 0.35, 1 })
    badge.count = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.count:SetPoint("CENTER")
    button.badge = badge
    button:SetScript("OnClick", function(self)
        if selected and selected == self.thread then CloseChat(); UpdateBar()
        elseif self.thread then OpenChat(self.thread) end
    end)
    button:SetScript("OnEnter", function(self)
        if not self.thread then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(PlainText(self.thread.name))
        if self.thread.unread > 0 then GameTooltip:AddLine(self.thread.unread .. " unread", 1, 0.55, 0.5) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function PositionBar()
    if dragging then return end
    local cfg = Settings()
    local target = ChatFrame1 or DEFAULT_CHAT_FRAME or UIParent
    bar:ClearAllPoints()
    if cfg.position == "free" then
        bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 0)
    elseif cfg.position == "right" then
        bar:SetPoint("TOPLEFT", target, "TOPRIGHT", 8, 0)
    else
        bar:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, 9)
    end
end

local function PositionChat()
    if not selected or not chat:IsShown() then return end
    SizeChat()
    local anchor = bar
    for _, button in ipairs(slots) do if button.thread == selected then anchor = button; break end end
    local x, y = anchor:GetCenter()
    local width, height = ScreenSize()
    if not Number(x) or not Number(y) then return end
    local left, bottom = UIParent:GetRect()
    if not Number(left) or not Number(bottom) then return end
    local rootScale = UIParent:GetEffectiveScale()
    left = left * rootScale
    local relativeY = y - bottom * rootScale
    local popupWidth = chat:GetWidth()
    local dx = math.max(left + 8 + popupWidth / 2, math.min(left + width - 8 - popupWidth / 2, x)) - x
    chat:ClearAllPoints()
    chat.tail:ClearAllPoints()
    local tailX = math.max(-popupWidth / 2 + 14, math.min(popupWidth / 2 - 14, -dx))
    if relativeY + chat:GetHeight() + anchor:GetHeight() / 2 + 10 <= height or relativeY < height / 2 then
        chat:SetPoint("BOTTOM", anchor, "TOP", dx, 9)
        chat.tail:SetPoint("CENTER", chat, "BOTTOM", tailX, 0)
    else
        chat:SetPoint("TOP", anchor, "BOTTOM", dx, -9)
        chat.tail:SetPoint("CENTER", chat, "TOP", tailX, 0)
    end
end

UpdateBar = function(reveal)
    if not bar then return end
    local cfg = Settings()
    local vertical = IsVertical(cfg)
    local width, height = ScreenSize()
    local step = cfg.size + 5
    local capacity = math.max(1, math.floor(((vertical and height or width) - 40) / step))
    if reveal then RevealThread(reveal, capacity) end
    local visible = math.min(#order, capacity)
    bar.overflow = #order > visible
    firstSlot = math.max(1, math.min(math.max(1, #order - visible + 1), firstSlot))
    local grip = cfg.locked and 0 or 21
    local length = math.max(cfg.size, visible * step - 5) + grip + 8
    bar:SetSize(vertical and cfg.size + 8 or length, vertical and length or cfg.size + 8)
    bar:SetAlpha(cfg.opacity / 100)
    bar.grip:ClearAllPoints()
    bar.grip:SetPoint(vertical and "TOP" or "LEFT", vertical and 0 or 4, vertical and -4 or 0)
    bar.grip:SetShown(not cfg.locked)
    for index = 1, visible do
        local button = slots[index] or CreateSlot()
        slots[index] = button
        local thread = order[firstSlot + index - 1]
        if button.thread ~= thread or button.guid ~= thread.guid then Portrait(button.avatar, thread) end
        button.thread = thread
        button.guid = thread.guid
        button:SetSize(cfg.size, cfg.size)
        button:ClearAllPoints()
        local offset = 4 + grip + (index - 1) * step
        button:SetPoint("TOPLEFT", vertical and 4 or offset, vertical and -offset or -4)
        button:SetBackdropBorderColor(unpack(thread == selected and gold or border))
        local count = tostring(thread.unread)
        button.badge.count:SetText(count)
        button.badge:SetWidth(math.max(16, #count * 7 + 5))
        button.badge:SetShown(cfg.badges and thread.unread > 0)
        button:Show()
    end
    for index = visible + 1, #slots do slots[index].thread = nil; slots[index]:Hide() end
    if not cfg.enabled or not cfg.showBar or #order == 0 then CloseChat() end
    PositionBar()
    bar:SetShown(cfg.enabled and cfg.showBar and #order > 0)
    PositionChat()
end

function Addon:ApplyWhispers()
    if not self.db then return end
    if not Settings().party then Deactivate(partyThread)
    elseif partyThread and not partyThread.hidden then Activate(partyThread) end
    if not Settings().tradeHistory then
        if selected and selected.tradeOnly then CloseChat() end
        for _, thread in pairs(threads) do
            if thread.tradeOnly then Deactivate(thread) end
        end
    end
    UpdateBar()
    if selected then RefreshMessages(false) end
    if self.RefreshWhisperOptions then self:RefreshWhisperOptions() end
end

function Addon:ToggleWhisperBar()
    if not Settings().enabled then self:Print("Enable Whisper Manager to show the whisper bar."); return end
    self:SetWhisperOption("showBar", not Settings().showBar)
end

function Addon:GetChatSearchThreads()
    local available = {}
    for _, thread in pairs(threads) do
        if #thread.messages > 0 then available[#available + 1] = thread end
    end
    return available
end

function Addon:OpenChatSearchResult(thread, message)
    if not Settings().enabled then self:Print("Enable Whisper Manager to open conversations."); return false end
    if thread.party and not Settings().party then self:Print("Enable the Party conversation to open this result."); return false end
    if threads[thread.key] ~= thread then return false end
    local found
    for index, entry in ipairs(thread.messages) do if entry == message then found = index; break end end
    if not found then self:Print("That message is outside the retained history."); return false end
    Settings().showBar = true
    Activate(thread)
    bar = bar or CreateBar()
    UpdateBar(thread)
    OpenChat(thread, message, found)
    return true
end

function Addon:RestoreWhispers()
    local archive = self.character.chatHistory
    if not archive then return end
    local restored = {}
    for key, entry in pairs(archive.threads) do
        if type(key) == "string" and type(entry) == "table" and type(entry.name) == "string"
            and entry.name ~= "" and type(entry.messages) == "table" then
            local thread = GetThread(key, entry.name)
            thread.guid = type(entry.guid) == "string" and entry.guid or nil
            thread.account = Number(entry.account) and entry.account or nil
            thread.bnet, thread.party, thread.instance = entry.bnet == true, key == "party", entry.instance == true
            thread.hidden = entry.hidden == true
            local count = #entry.messages
            for index = math.max(1, count - Settings().historyLimit + 1), count do
                local message = entry.messages[index]
                if type(message) == "table" and type(message[1]) == "string"
                    and Number(message[2]) and message[2] >= 0 and message[2] < 4102444800 then
                    local author = type(message[4]) == "string" and message[4] or nil
                    local messages = thread.messages
                    messages[#messages + 1] = { message[1], message[2], message[3] == true, author }
                end
            end
            thread.unread = Number(entry.unread) and math.max(0, math.min(#thread.messages, math.floor(entry.unread))) or 0
            if thread.party then partyThread, newParty = thread, true end
            if #thread.messages > 0 then
                SaveThread(thread)
                if not thread.hidden and (not thread.party or Settings().party) then restored[#restored + 1] = thread end
            else
                archive.threads[key] = nil
            end
        else
            archive.threads[key] = nil
        end
    end
    table.sort(restored, function(a, b)
        return a.messages[#a.messages][2] < b.messages[#b.messages][2]
    end)
    for _, thread in ipairs(restored) do Activate(thread) end
    if #restored > 0 then
        bar = bar or CreateBar()
        UpdateBar()
    end
end

function Addon:RefreshWhisperTrade(name, key, guid)
    local thread = GetThread(key, name)
    if #thread.messages == 0 then thread.tradeOnly = true end
    if Public(guid) and type(guid) == "string" and guid ~= "" then thread.guid = guid end
    Activate(thread)
    bar = bar or CreateBar()
    UpdateBar(not selected and thread or nil)
    if selected == thread then RefreshMessages(false) end
end

local function Receive(event, message, name, ...)
    if not Addon.db or not Settings().enabled or not Public(message) or not Public(name)
        or type(message) ~= "string" or type(name) ~= "string" or name == "" then return end
    local cfg = Settings()
    local channel = partyEvents[event]
    if channel and not cfg.party then return end
    if channel == "instance" and (not cfg.partyInstances or IsInRaid and IsInRaid(LE_PARTY_CATEGORY_INSTANCE)) then return end
    local kind = events[event]
    local outgoing, bnet
    if kind then outgoing, bnet = kind % 2 == 0, kind >= 3 end
    local lineID, guid, account = select(9, ...)
    if Number(lineID) and C_ChatInfo and C_ChatInfo.IsChatLineCensored then
        local ok, censored = pcall(C_ChatInfo.IsChatLineCensored, lineID)
        if ok and Public(censored) and censored then return end
    end
    local thread
    if channel then
        local playerGUID = UnitGUID and UnitGUID("player")
        if Public(guid) and type(guid) == "string" and guid ~= "" and Public(playerGUID) and playerGUID then
            outgoing = guid == playerGUID
        else
            local player = UnitName("player")
            outgoing = Public(player) and type(player) == "string"
                and Addon:GetWhisperCharacterKey(player) == Addon:GetWhisperCharacterKey(name)
        end
        partyThread = GetThread("party", "Party")
        thread = partyThread
        thread.party, thread.instance = true, channel == "instance"
    else
        account = bnet and Number(account) and account > 0 and account or nil
        local key = bnet and ("bnet:" .. (account or name:lower())) or Addon:GetWhisperCharacterKey(name)
        thread = GetThread(key, name)
        thread.name, thread.account, thread.bnet, thread.tradeOnly = name, account, bnet, nil
        if Public(guid) and type(guid) == "string" and guid ~= "" then thread.guid = guid end
    end
    Activate(thread)
    local now = (GetServerTime or time)()
    if channel and newParty then
        if #thread.messages > 0 then thread.messages[#thread.messages + 1] = { "New party session", now, false } end
        newParty = nil
    end
    thread.messages[#thread.messages + 1] = {
        PlainText(message), now, outgoing == true,
        channel and PlainText(outgoing and "You" or name) or nil,
    }
    local trimmed = Settings().saveHistory and TrimMessages(thread)
    local reading = selected == thread and chat:IsVisible() and not chat.showingTrades
        and chat.pageOffset == 0 and chat.search:GetText() == ""
        and chat.scroll:GetVerticalScroll() >= chat.scroll:GetVerticalScrollRange() - 4
    if not outgoing and not reading then thread.unread = thread.unread + 1 end
    SaveThread(thread)
    bar = bar or CreateBar()
    UpdateBar(not selected and thread or nil)
    if selected == thread then
        if not chat.showingTrades then RefreshMessages(false, not trimmed) end
    elseif channel and cfg.partyAutoOpen and not dragging and (not selected or cfg.partyInterrupt) then
        OpenChat(thread)
    end
end

for event in pairs(events) do listener:RegisterEvent(event) end
for event in pairs(partyEvents) do listener:RegisterEvent(event) end
listener:RegisterEvent("GROUP_LEFT")
listener:RegisterEvent("GROUP_JOINED")
listener:RegisterEvent("DISPLAY_SIZE_CHANGED")
listener:RegisterEvent("UI_SCALE_CHANGED")
listener:SetScript("OnEvent", function(_, event, ...)
    if events[event] or partyEvents[event] then
        Receive(event, ...)
    elseif event == "GROUP_LEFT" or event == "GROUP_JOINED" then
        if Addon.db and Settings().saveHistory then
            newParty = true
            if selected == partyThread then CloseChat(); UpdateBar() end
        else
            Deactivate(partyThread)
            partyThread, threads.party = nil, nil
            UpdateBar()
        end
    else Addon:ApplyWhispers() end
end)
