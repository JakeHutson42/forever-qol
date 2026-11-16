local _, Addon = ...
local listener = CreateFrame("Frame")
local bar, chat, selected, dragging
local threads, order = {}, {}
local firstSlot, slots = 1, {}
local gold = { 0.83, 0.66, 0.38, 1 }
local border = { 0.42, 0.33, 0.23, 1 }
local ENAMEL = "Interface\\AddOns\\SmallerUI\\Media\\Foundry.tga"
local PORTRAIT_RIM = "Interface\\AddOns\\SmallerUI\\Media\\PortraitRim.tga"
local incomingFill, incomingEdge = { 0.109, 0.077, 0.049, 0.94 }, { 0.32, 0.25, 0.17, 1 }
local outgoingFill, outgoingEdge = { 0.15, 0.19, 0.16, 0.96 }, { 0.34, 0.42, 0.31, 1 }
local tradeFill, highlight = { 0.20, 0.18, 0.13, 1 }, { 1, 0.81, 0.40, 1 }
local whisperIcon = "Interface\\ChatFrame\\UI-ChatWhisperIcon"
local classIcons = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local portraitUnits = { "target", "focus", "mouseover", "player", "party1", "party2", "party3", "party4" }
local events = { CHAT_MSG_WHISPER = 1, CHAT_MSG_WHISPER_INFORM = 2,
    CHAT_MSG_BN_WHISPER = 3, CHAT_MSG_BN_WHISPER_INFORM = 4 }
local partyEvents = { CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_INSTANCE_CHAT = "instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "instance" }
local partyThread
local newParty
local defaults = { enabled = true, showBar = true, position = "left", size = 36,
    opacity = 100, width = 360, height = 300, textSize = 13,
    badges = true, timestamps = false, locked = false, saveHistory = false, historyLimit = 500,
    party = true, partyAutoOpen = false, partyInterrupt = false, partyInstances = true,
    tradeHistory = true, tradeRequests = true, tradeExpanded = false, tradeLimit = 30 }
Addon.whisperLimits = { size = { 24, 72 }, opacity = { 20, 100 },
    width = { 240, 720 }, height = { 200, 600 }, textSize = { 10, 24 }, tradeLimit = { 5, 200 },
    historyLimit = { 50, 5000 } }
local positions = { left = true, top = true, right = true, free = true }
local UpdateBar, RefreshMessages, ChangeHistory
local PAGE_SIZE = 60
local LAUNCHER_SIZE, MENU_WIDTH, MENU_HEADER, MENU_FOOTER = 34, 230, 32, 30

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
    if cfg.menuVersion ~= 1 then
        if cfg.position == "top" then cfg.position = "left" end
        if not cfg.partyInterrupt then cfg.partyAutoOpen = false end
        cfg.menuVersion = 1
    end
    if not positions[cfg.position] then cfg.position = defaults.position end
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
    if key == "position" and not positions[value] then return false end
    Settings()[key] = range and math.floor(value + 0.5) or value
    if key == "tradeLimit" then self:TrimTradeHistory() end
    if key == "saveHistory" or key == "historyLimit" then ChangeHistory() end
    if not value and (key == "enabled" or key == "tradeHistory") then self:DiscardPendingTrade() end
    self:ApplyWhispers()
    return true
end

function Addon:ResetWhisperPosition()
    local cfg = Settings()
    cfg.x, cfg.y = nil, nil
    self:SetWhisperOption("position", defaults.position)
end

local function PlainText(text)
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (text:gsub("|", "||"))
end

local function TextValue(value)
    return Public(value) and type(value) == "string" and value ~= "" and value or nil
end

local function BattleTag(value)
    local tag = TextValue(value)
    return tag and tag:match("^[^|#]+#%d+$")
end

local function PublicCall(api, ...)
    if not api then return end
    local ok, value = pcall(api, ...)
    if ok and Public(value) then return value end
end

local battleNetFriends
local function FindBattleNetFriend(key)
    if not key or not (C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
    if not battleNetFriends then
        battleNetFriends = {}
        local count = PublicCall(BNGetNumFriends)
        for index = 1, Number(count) and count or 0 do
            local info = PublicCall(C_BattleNet.GetFriendAccountInfo, index)
            if info then
                local tag, name, id = BattleTag(info.battleTag), TextValue(info.accountName), info.bnetAccountID
                if tag then battleNetFriends["tag:" .. tag:lower()] = info end
                if name then
                    local nameKey = "name:" .. name
                    battleNetFriends[nameKey] = battleNetFriends[nameKey] == nil and info or false
                end
                if Number(id) and id > 0 then battleNetFriends[id] = info end
            end
        end
    end
    return battleNetFriends[key] or nil
end

local function GetBattleNetAccount(id, name, tag)
    if not C_BattleNet then return end
    local foldedTag = tag and tag:lower()
    local account = id and (PublicCall(C_BattleNet.GetAccountInfoByID, id) or FindBattleNetFriend(id))
    local accountTag = account and BattleTag(account.battleTag)
    if account and (not foldedTag or accountTag and accountTag:lower() == foldedTag) then return account end
    if foldedTag then return FindBattleNetFriend("tag:" .. foldedTag) end
    if name then return FindBattleNetFriend("name:" .. name) end
end

local function BattleNetTitle(thread)
    local account = GetBattleNetAccount(thread.account, thread.bnetName, thread.battleTag)
    return account and TextValue(account.accountName) or thread.bnetName
end

function Addon:GetWhisperDisplayName(thread)
    if thread.bnet then
        local title = BattleNetTitle(thread)
        -- Let the client render the session's Real ID name, as it does in the friends list.
        if title and title:match("^|K[^|]+|k$") then return title end
        return PlainText(title or thread.name)
    end
    return PlainText(thread.name)
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
    local key = thread.key
    if thread.bnet then
        -- Account IDs and Real ID tokens belong to the current Battle.net session.
        if thread.battleTag then
            key = "bnet:" .. thread.battleTag:lower()
        elseif thread.archiveKey and thread.archiveKey:match("^bnet:history:%d+:%d+$") then
            key = thread.archiveKey
        else
            local prefix = "bnet:history:" .. thread.messages[1][2] .. ":"
            local sequence = 1
            while archive.threads[prefix .. sequence] do sequence = sequence + 1 end
            key = prefix .. sequence
        end
        if thread.archiveKey and thread.archiveKey ~= key then archive.threads[thread.archiveKey] = nil end
        thread.archiveKey = key
    end
    local entry = archive.threads[key] or {}
    archive.threads[key] = entry
    entry.name = thread.name
    entry.guid, entry.account, entry.battleTag = not thread.bnet and thread.guid or nil, nil, thread.battleTag
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
    if texture.bnetTitle and C_Texture and C_Texture.ClearTitleIconTexture then
        C_Texture.ClearTitleIconTexture(texture)
        texture.bnetTitle = nil
    end
    texture:SetTexCoord(0, 1, 0, 1)
    if thread and thread.party then
        texture:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
        return
    end
    local guid = thread and thread.guid
    local game, client, class
    if thread and thread.bnet then
        local account = GetBattleNetAccount(thread.account, thread.bnetName, thread.battleTag)
        game = account and account.gameAccountInfo
        if not Public(game) then game = nil end
        client = game and TextValue(game.clientProgram)
        if client == (BNET_CLIENT_WOW or "WoW") then
            guid = TextValue(game.playerGuid) or guid
            class = TextValue(game.classFilename)
            if not class and Number(game.classID) and game.classID > 0 and C_CreatureInfo then
                local info = PublicCall(C_CreatureInfo.GetClassInfo, game.classID)
                class = info and TextValue(info.classFile)
            end
        end
    end
    local unit = guid and UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if guid and Public(unit) and not unit and UnitGUID then
        for _, candidate in ipairs(portraitUnits) do
            local id = UnitGUID(candidate)
            if Public(id) and id == guid then unit = candidate; break end
        end
    end
    if SetPortraitTexture and Public(unit) and unit then
        SetPortraitTexture(texture, unit)
        return
    end
    if not class and guid and guid:find("^Player%-") and GetPlayerInfoByGUID then
        local _, file = GetPlayerInfoByGUID(guid)
        class = TextValue(file)
    end
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class:upper()]
    if coords then
        texture:SetTexture(classIcons)
        texture:SetTexCoord(unpack(coords))
    elseif thread and thread.bnet then
        texture:SetTexture("Interface\\FriendsFrame\\Battlenet-Portrait")
        if client and Public(game.isOnline) and game.isOnline and C_Texture and C_Texture.SetTitleIconTexture
            and C_Texture.ClearTitleIconTexture and Enum and Enum.TitleIconVersion then
            C_Texture.SetTitleIconTexture(texture, client, Enum.TitleIconVersion.Medium)
            texture.bnetTitle = true
        end
    else
        texture:SetTexture(whisperIcon)
    end
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
        local name = BattleNetTitle(selected)
        if not name then Addon:Print("This Battle.net contact is unavailable for reply."); return end
        if ChatFrameUtil and ChatFrameUtil.SendBNetTell then ChatFrameUtil.SendBNetTell(name)
        elseif ChatFrame_SendBNetTell then ChatFrame_SendBNetTell(name) end
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

local function FramedPortrait(parent)
    local rim = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    rim:SetTexture(PORTRAIT_RIM)
    rim:SetVertexColor(unpack(gold))
    local avatar = parent:CreateTexture(nil, "ARTWORK")
    avatar:SetPoint("TOPLEFT", rim, "TOPLEFT", 3, -3)
    avatar:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -3, 3)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(avatar)
    avatar:AddMaskTexture(mask)
    return avatar, rim
end

local function CreateBadge(parent)
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetPoint("TOPRIGHT", 3, 3)
    badge:SetSize(16, 16)
    Addon.OptionsUI.Backdrop(badge, { 0.45, 0.16, 0.11, 1 }, { 0.88, 0.62, 0.31, 1 })
    badge.count = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.count:SetPoint("CENTER")
    badge:Hide()
    return badge
end

local function SetBadge(badge, unread, enabled)
    local count = unread > 99 and "99+" or tostring(unread)
    badge.count:SetText(count)
    badge:SetWidth(math.max(16, #count * 7 + 5))
    badge:SetShown(enabled and unread > 0)
end

local function CreateLauncher(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(LAUNCHER_SIZE, LAUNCHER_SIZE)
    Addon.OptionsUI.Plate(button, { 0.20, 0.145, 0.085, 1 })
    button:SetBackdropBorderColor(unpack(gold))
    for y = -5, 5, 5 do
        local mark = button:CreateTexture(nil, "ARTWORK")
        mark:SetSize(15, 2)
        mark:SetPoint("CENTER", 0, y)
        mark:SetColorTexture(0.96, 0.79, 0.49, 1)
    end
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    button:GetHighlightTexture():SetVertexColor(0.50, 0.32, 0.12, 0.30)
    button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    button:GetPushedTexture():SetVertexColor(0.35, 0.24, 0.12, 0.36)
    button.badge = CreateBadge(button)
    return button
end

function Addon:BuildWhisperIdentityPlate(plate, nameInset)
    local avatar, rim = FramedPortrait(plate)
    rim:SetPoint("LEFT", 0, 0)
    local function Rail(point, offset, height, layer)
        local rail = plate:CreateTexture(nil, "ARTWORK", nil, layer)
        rail:SetPoint(point, rim, "RIGHT", -7, offset)
        rail:SetPoint(point == "BOTTOMLEFT" and "BOTTOMRIGHT" or "TOPRIGHT", plate, "RIGHT", 0, offset)
        rail:SetHeight(height)
        return rail
    end
    local upper = Rail("BOTTOMLEFT", 0, 20, -2)
    upper:SetColorTexture(0.52, 0.39, 0.22, 1)
    local lower = Rail("TOPLEFT", -1, 15, -2)
    lower:SetColorTexture(0.31, 0.29, 0.24, 1)
    local function Fill(rail)
        local fill = plate:CreateTexture(nil, "ARTWORK", nil, -1)
        fill:SetPoint("TOPLEFT", rail, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -1, 1)
        fill:SetTexture(ENAMEL)
        return fill
    end
    local function RailLabel(rail, font, rightInset)
        local label = plate:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint("LEFT", rail, "LEFT", 12, 0)
        label:SetPoint("RIGHT", rail, "RIGHT", -6 - (rightInset or 0), 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        return label
    end
    plate.avatar, plate.rim = avatar, rim
    plate.upper, plate.lower = Fill(upper), Fill(lower)
    plate.title = RailLabel(upper, "GameFontNormalSmall", nameInset)
    plate.context = RailLabel(lower, "GameFontHighlightSmall")
    plate.title:SetTextColor(0.97, 0.83, 0.54)
    plate.context:SetTextColor(0.90, 0.85, 0.75)
end

local function PaintIdentity(plate, thread, attentive)
    plate.upper:SetVertexColor(attentive and 0.37 or 0.23, attentive and 0.27 or 0.17, 0.10, 1)
    if thread.party then
        plate.lower:SetVertexColor(0.18, 0.27, 0.20, 1)
    elseif thread.bnet then
        plate.lower:SetVertexColor(0.14, 0.24, 0.31, 1)
    else
        plate.lower:SetVertexColor(0.24, 0.18, 0.27, 1)
    end
    plate.rim:SetVertexColor(attentive and 1 or 0.83, attentive and 0.84 or 0.69, attentive and 0.55 or 0.47)
end

function Addon:DrawWhisperIdentityPlate(plate, thread, context, attentive)
    plate.title:SetText(self:GetWhisperDisplayName(thread))
    plate.context:SetText(context)
    Portrait(plate.avatar, thread)
    PaintIdentity(plate, thread, attentive)
end

function Addon:CreateWhisperPreview(parent)
    local UI = self.OptionsUI
    local preview = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    preview:SetSize(290, 356)
    UI.Plate(preview, { 0.122, 0.087, 0.050, 1 })
    preview:SetBackdropBorderColor(unpack(border))
    local title = UI.Label(preview, "Appearance preview", 14, -13, "GameFontNormal")
    title:SetTextColor(unpack(gold))

    local conversation = CreateFrame("Frame", nil, preview, "BackdropTemplate")
    conversation:SetPoint("TOP", 0, -39)
    UI.WindowSurface(conversation)
    local header = conversation:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(41)
    header:SetTexture(ENAMEL)
    header:SetVertexColor(0.23, 0.165, 0.09)
    local identity = CreateFrame("Frame", nil, conversation)
    identity:SetPoint("TOPLEFT", 7, -5)
    identity:SetPoint("TOPRIGHT", -7, -5)
    identity:SetHeight(38)
    self:BuildWhisperIdentityPlate(identity)
    identity.rim:SetSize(32, 32)
    identity.avatar:SetTexture("Interface\\Icons\\INV_Helmet_06")
    identity.title:SetText("Vale")
    identity.context:SetText("Whisper")
    PaintIdentity(identity, {}, true)
    preview.conversation = conversation
    preview.messages = {}
    for index, text in ipairs({ "Ready to go?", "On my way." }) do
        local row = CreateFrame("Frame", nil, conversation, "BackdropTemplate")
        local outgoing = index == 2
        UI.Plate(row, outgoing and outgoingFill or incomingFill)
        row:SetBackdropBorderColor(unpack(outgoing and outgoingEdge or incomingEdge))
        if not outgoing then row:SetPoint("TOPLEFT", 7, -49) end
        row.message = UI.Label(row, text, 6, -4, "GameFontHighlightSmall")
        row.stamp = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.stamp:SetPoint("BOTTOMRIGHT", -6, 3)
        row.stamp:SetText(outgoing and "13:43" or "13:42")
        row.stamp:SetTextColor(0.67, 0.75, 0.75)
        preview.messages[index] = row
    end

    local launcher = CreateLauncher(preview)
    local dock = CreateFrame("Frame", nil, launcher, "BackdropTemplate")
    dock:SetPoint("TOPLEFT", launcher, "TOPRIGHT", 8, 0)
    UI.WindowSurface(dock)
    UI.Label(dock, "Conversations", 11, -8, "GameFontNormalSmall")
    local rows = {}
    for index, icon in ipairs({ "Interface\\Icons\\INV_Helmet_06", "Interface\\Icons\\INV_Misc_GroupLooking" }) do
        local row = CreateFrame("Frame", nil, dock)
        self:BuildWhisperIdentityPlate(row)
        row.avatar:SetTexture(icon)
        row.title:SetText(index == 1 and "Vale" or "Party")
        row.context:SetText(index == 1 and "On my way." or "Ready to go?")
        PaintIdentity(row, { party = index == 2 }, index == 2)
        rows[index] = row
    end
    local hidden = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local dimensions = UI.Label(preview, "", 14, -335, "GameFontHighlightSmall")
    dimensions:SetTextColor(0.71, 0.78, 0.79)
    preview.dock, preview.badge = dock, launcher.badge

    function preview:Refresh(cfg)
        local width = math.floor(154 + (cfg.width - 240) * 0.23 + 0.5)
        local height = math.floor(108 + (cfg.height - 200) * 0.16 + 0.5)
        conversation:SetSize(width, height)
        local size = math.floor(8 + (cfg.textSize - 10) * 0.5 + 0.5)
        local rowHeight = size + 9 + (cfg.timestamps and 10 or 0)
        for index, row in ipairs(self.messages) do
            row:SetSize(math.min(width - 20, math.max(76, size * 7 + 8)), rowHeight)
            row.message:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size)
            row.stamp:SetShown(cfg.timestamps)
            if index == 2 then
                row:ClearAllPoints()
                row:SetPoint("TOPRIGHT", -7, -53 - rowHeight)
            end
        end
        local conversationHeight = math.max(height, 60 + 2 * rowHeight)
        conversation:SetHeight(conversationHeight)
        dimensions:SetText(("Conversation size   %d × %d"):format(cfg.width, cfg.height))
        local portrait = 27 + math.floor((cfg.size - 24) * 0.28)
        local rowHeight = math.max(38, portrait + 3)
        local dockTop = -50 - conversationHeight
        launcher:ClearAllPoints()
        launcher:SetPoint("TOPLEFT", 20, dockTop)
        launcher:SetAlpha(cfg.opacity / 100)
        launcher:SetShown(cfg.enabled and cfg.showBar)
        dock:SetSize(208, 29 + 2 * rowHeight)
        for index, row in ipairs(rows) do
            row:SetHeight(rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 9, -24 - (index - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", -9, -24 - (index - 1) * rowHeight)
            row.rim:SetSize(portrait, portrait)
        end
        SetBadge(launcher.badge, 2, cfg.badges)
        hidden:ClearAllPoints()
        hidden:SetPoint("TOP", 0, dockTop - 12)
        hidden:SetText(cfg.enabled and "Chat menu hidden" or "Whisper Manager is off")
        hidden:SetShown(not launcher:IsShown())
        local previewHeight = -dockTop + (launcher:IsShown() and dock:GetHeight() or 25) + 26
        dimensions:ClearAllPoints()
        dimensions:SetPoint("BOTTOMLEFT", 14, 9)
        self:SetHeight(previewHeight)
    end
    return preview
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
    UI.WindowSurface(frame)

    local header = frame:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(48)
    header:SetTexture(ENAMEL)
    header:SetVertexColor(0.19, 0.135, 0.078, 1)
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
    edge:SetHeight(1)
    edge:SetColorTexture(0.62, 0.47, 0.28, 0.75)
    local identity = CreateFrame("Frame", nil, frame)
    identity:SetPoint("TOPLEFT", 10, -3)
    identity:SetPoint("TOPRIGHT", -111, -3)
    identity:SetHeight(44)
    Addon:BuildWhisperIdentityPlate(identity)
    identity.rim:SetSize(38, 38)
    frame.identity = identity
    frame.title, frame.context = identity.title, identity.context
    local close = UI.Button(frame, nil, "\195\151", 0, 0, 25, CloseChat)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", -9, -11)
    UI.Tooltip(close, "Close conversation")
    local allChats = UI.Button(frame, nil, "All chats", 0, 0, 64, function()
        Addon:ShowChatSearch(frame.search:GetText())
    end)
    allChats:ClearAllPoints()
    allChats:SetPoint("TOPRIGHT", -40, -11)
    UI.Tooltip(allChats, "Search across all conversations")
    local footer = frame:CreateTexture(nil, "BACKGROUND")
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(38)
    footer:SetTexture(ENAMEL)
    footer:SetVertexColor(0.14, 0.100, 0.058)
    local reply = UI.Button(frame, nil, "Reply", 0, 0, 72, OpenReply)
    reply:ClearAllPoints()
    reply:SetPoint("BOTTOMRIGHT", -10, 9)
    reply:SetBackdropColor(0.24, 0.20, 0.14, 1)
    reply:SetBackdropBorderColor(unpack(gold))
    UI.Tooltip(reply, "Reply in WoW chat")
    local hide = UI.Button(frame, nil, "Hide chat", 0, 0, 86, HideThread)
    hide:ClearAllPoints()
    hide:SetPoint("BOTTOMLEFT", 10, 9)
    UI.Tooltip(hide, "Hide this conversation until new activity.")
    local search = UI.EditBox(frame, "SmallerUIWhisperSearch", GameFontHighlightSmall)
    search:SetHeight(26)
    search:SetAutoFocus(false)
    search:SetMaxLetters(200)
    search:SetFontObject(GameFontHighlightSmall)
    search:SetTextInsets(29, 23, 0, 0)
    local lens = search:CreateTexture(nil, "ARTWORK")
    lens:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    lens:SetSize(14, 14)
    lens:SetPoint("LEFT", 7, 0)
    lens:SetAlpha(0.65)
    local placeholder = UI.Label(search, "Search messages", 29, -7, "GameFontDisableSmall")
    search.placeholder = placeholder
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
    frame.tradeToggle = UI.Button(frame, "SmallerUIWhisperTrades", "Trades", 0, 0, 83, ToggleTrades)
    frame.tradeClose = UI.Button(frame, "SmallerUIWhisperTradesClose", "\195\151", 0, 0, 25, function()
        selected.tradeExpanded = false
        RefreshMessages(true)
    end)
    frame.tradeClose:ClearAllPoints()
    frame.tradeClose:SetPoint("TOPRIGHT", -10, -55)
    UI.Tooltip(frame.tradeClose, "Dismiss trade history")

    local scroll = UI.ScrollFrame(frame, "SmallerUIWhisperScroll")
    scroll:SetPoint("TOPLEFT", 10, -87)
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
    Addon.OptionsUI.Plate(row)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 9, -6)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(true) end
    local stamp = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    stamp:SetPoint("BOTTOMRIGHT", -8, 5)
    stamp:SetTextColor(0.67, 0.75, 0.75)
    row.label, row.stamp = label, stamp
    return row
end

local function ScreenSize()
    local scale = UIParent:GetEffectiveScale()
    return UIParent:GetWidth() * scale, UIParent:GetHeight() * scale
end

local function SizeChat()
    local cfg = Settings()
    chat:SetSize(cfg.width, cfg.height)
    Addon.OptionsUI.FitScale(chat, cfg.width, cfg.height)
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
    local context = selected.instance and "Instance group" or selected.party and "Group chat"
        or selected.bnet and "Battle.net whisper" or selected.tradeOnly and "Trade history" or "Whisper"
    Addon:DrawWhisperIdentityPlate(chat.identity, selected, context, true)
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
    chat.tradeToggle:ClearAllPoints()
    chat.tradeToggle:SetPoint("TOPRIGHT", showingTrades and -39 or -10, -55)
    chat.search:ClearAllPoints()
    chat.search:SetPoint("TOPLEFT", 10, -55)
    chat.search:SetPoint("TOPRIGHT", trades == 0 and -10 or showingTrades and -128 or -99, -55)
    chat.search.placeholder:SetText(trades > 0 and chat:GetWidth() < 290 and "Search" or "Search messages")
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 10, -87)
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
        local label = row.label
        if STANDARD_TEXT_FONT then label:SetFont(STANDARD_TEXT_FONT, cfg.textSize) end
        local text = message[1]
        label:SetText(message[4] and ("|cffffd17f" .. message[4] .. "|r\n" .. text) or text)
        local showTime = cfg.timestamps or showingTrades
        local timestamp = showTime and FormatTimestamp(message[2], message[5]) or ""
        row.stamp:SetText(timestamp or "")
        local bubbleWidth = showingTrades and width or math.floor(width * 0.88)
        if not showingTrades and label.GetUnboundedStringWidth then
            local measured = label:GetUnboundedStringWidth() or 0
            local stampWidth = showTime and row.stamp:GetUnboundedStringWidth() or 0
            bubbleWidth = math.min(bubbleWidth, math.max(72, math.ceil(math.max(measured, stampWidth) + 20)))
        end
        row:ClearAllPoints()
        row:SetPoint(outgoing and "TOPRIGHT" or "TOPLEFT", 0, -y)
        row:SetWidth(bubbleWidth)
        label:SetWidth(bubbleWidth - 18)
        row:SetBackdropColor(unpack(showingTrades and tradeFill or outgoing and outgoingFill or incomingFill))
        row:SetBackdropBorderColor(unpack(message == chat.highlight and highlight or showingTrades and gold
            or outgoing and outgoingEdge or incomingEdge))
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
    bar.menu:Hide()
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
    bar.menu:Hide()
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
        cfg.position, cfg.x, cfg.y = "free", x * barScale - cx * scale, y * barScale - cy * scale
    end
    Addon:ApplyWhispers()
end

local function CreateBar()
    local UI = Addon.OptionsUI
    local frame = CreateFrame("Frame", "SmallerUIWhisperBar", UIParent)
    frame:Hide()
    frame:SetIgnoreParentScale(true)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetSize(LAUNCHER_SIZE, LAUNCHER_SIZE)
    local launcher = CreateLauncher(frame)
    launcher:SetAllPoints(frame)
    frame.launcher = launcher

    local menu = CreateFrame("Frame", "SmallerUIWhisperMenu", frame, "BackdropTemplate")
    menu:Hide()
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    local function ScrollMenu(step)
        firstSlot = firstSlot + step
        UpdateBar()
    end
    menu:SetScript("OnMouseWheel", function(_, delta) ScrollMenu(delta > 0 and -1 or 1) end)
    UI.WindowSurface(menu)
    UI.Label(menu, "Conversations", 13, -11, "GameFontNormal")
    menu.previous = UI.Button(menu, nil, "<", 0, 0, 24, function() ScrollMenu(-1) end)
    menu.previous:ClearAllPoints()
    menu.previous:SetPoint("BOTTOMLEFT", 10, 7)
    menu.previous:SetHeight(20)
    UI.Tooltip(menu.previous, "Previous conversations")
    menu.next = UI.Button(menu, nil, ">", 0, 0, 24, function() ScrollMenu(1) end)
    menu.next:ClearAllPoints()
    menu.next:SetPoint("BOTTOMRIGHT", -10, 7)
    menu.next:SetHeight(20)
    UI.Tooltip(menu.next, "More conversations")
    menu.status = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    menu.status:SetPoint("BOTTOM", 0, 11)
    frame.menu = menu
    table.insert(UISpecialFrames, menu:GetName())

    launcher:RegisterForDrag("LeftButton")
    launcher:SetScript("OnDragStart", StartDrag)
    launcher:SetScript("OnDragStop", StopDrag)
    launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    launcher:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Addon:ShowOptions("whispers")
        elseif menu:IsShown() then
            menu:Hide()
        else
            local thread = selected
            CloseChat()
            menu:Show()
            UpdateBar(thread)
        end
    end)
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(menu:IsShown() and "Close chat menu" or "Open chat menu")
        if frame.unread > 0 then GameTooltip:AddLine(frame.unread .. " unread messages", 1, 0.75, 0.54) end
        if not Settings().locked then GameTooltip:AddLine("Drag to move.", 0.87, 0.77, 0.65) end
        GameTooltip:AddLine("Right-click for Whisper Manager settings.", 0.87, 0.77, 0.65)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
    menu:SetScript("OnShow", function()
        launcher:SetBackdropColor(0.34, 0.245, 0.115, 1)
        GameTooltip:Hide()
    end)
    menu:SetScript("OnHide", function()
        launcher:SetBackdropColor(0.20, 0.145, 0.085, 1)
        GameTooltip:Hide()
    end)
    frame:SetScript("OnHide", function()
        menu:Hide()
        frame:StopMovingOrSizing()
        dragging = nil
    end)
    return frame
end

local function CreateSlot()
    local button = CreateFrame("Button", nil, bar.menu)
    Addon:BuildWhisperIdentityPlate(button)
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    button:GetHighlightTexture():SetVertexColor(0.50, 0.40, 0.24, 0.25)
    button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    button:GetPushedTexture():SetVertexColor(0.28, 0.21, 0.12, 0.32)
    button:EnableMouseWheel(true)
    button:SetScript("OnMouseWheel", bar.menu:GetScript("OnMouseWheel"))
    button.badge = CreateBadge(button)
    button.badge:ClearAllPoints()
    button.badge:SetPoint("TOPRIGHT", button.rim, "TOPRIGHT", 2, 1)
    button:SetScript("OnClick", function(self)
        if self.thread then OpenChat(self.thread) end
    end)
    button:SetScript("OnEnter", function(self)
        if not self.thread then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Addon:GetWhisperDisplayName(self.thread))
        if self.thread.unread > 0 then GameTooltip:AddLine(self.thread.unread .. " unread", 1, 0.55, 0.5) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function PositionBar()
    if dragging then return end
    local cfg = Settings()
    local target = ChatFrame1 or DEFAULT_CHAT_FRAME
    bar:ClearAllPoints()
    if cfg.position == "free" then
        local scale = bar:GetEffectiveScale()
        bar:SetPoint("CENTER", UIParent, "CENTER", (cfg.x or 0) / scale, (cfg.y or 0) / scale)
    elseif cfg.position == "right" and target then
        bar:SetPoint("TOPLEFT", target, "TOPRIGHT", 8, 0)
    elseif cfg.position == "top" and target then
        bar:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, 9)
    else
        local height, scale = UIParent:GetHeight(), UIParent:GetEffectiveScale()
        local y = height * 0.30
        if target then
            local _, bottom, _, chatHeight = target:GetRect()
            local _, rootBottom = UIParent:GetRect()
            if Number(bottom) and Number(chatHeight) and Number(rootBottom) then
                local chatTop = (bottom + chatHeight) * target:GetEffectiveScale() / scale - rootBottom
                y = math.min(height * 0.55, math.max(y, chatTop + 9))
            end
        end
        bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 8, y)
    end
end

local function PositionPanel(panel)
    local x, y = bar:GetCenter()
    local width, height = ScreenSize()
    if not Number(x) or not Number(y) then return end
    local left, bottom = UIParent:GetRect()
    if not Number(left) or not Number(bottom) then return end
    local rootScale, barScale, panelScale = UIParent:GetEffectiveScale(), bar:GetEffectiveScale(), panel:GetEffectiveScale()
    local margin, gap = 8, 8
    x, y = x * barScale - left * rootScale, y * barScale - bottom * rootScale
    local halfSize = LAUNCHER_SIZE * barScale / 2
    local panelWidth, panelHeight = panel:GetWidth() * panelScale, panel:GetHeight() * panelScale
    local panelLeft, panelTop
    local dockedTop = y - halfSize + panelHeight
    if x + halfSize + gap + panelWidth <= width - margin then
        panelLeft, panelTop = x + halfSize + gap, dockedTop
    elseif x - halfSize - gap - panelWidth >= margin then
        panelLeft, panelTop = x - halfSize - gap - panelWidth, dockedTop
    else
        panelLeft = x - panelWidth / 2
        local above = height - y - halfSize - gap
        local below = y - halfSize - gap
        panelTop = (above >= panelHeight + margin or above >= below)
            and y + halfSize + gap + panelHeight or below
    end
    panelLeft = math.max(margin, math.min(panelLeft, width - margin - panelWidth))
    panelTop = math.min(height - margin, math.max(panelHeight + margin, panelTop))
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", panelLeft / panelScale, panelTop / panelScale)
end

UpdateBar = function(reveal)
    if not bar then return end
    local cfg = Settings()
    local scale = UIParent:GetEffectiveScale()
    bar:SetScale(scale)
    bar:SetAlpha(cfg.opacity / 100)
    local menu = bar.menu
    if not cfg.enabled or not cfg.showBar or #order == 0 then
        CloseChat()
        bar:Hide()
        return
    end
    local unread = 0
    for _, thread in ipairs(order) do unread = unread + thread.unread end
    bar.unread = unread
    SetBadge(bar.launcher.badge, unread, cfg.badges)
    PositionBar()
    bar:Show()
    if menu:IsShown() then
        local width, height = ScreenSize()
        local step = math.max(40, cfg.size + 6)
        local available = math.min(330, (height - 20) / scale)
        local maxRows = math.max(1, math.floor((available - MENU_HEADER - 8) / step))
        local overflow = #order > maxRows
        local footer = overflow and MENU_FOOTER or 8
        local capacity = math.max(1, math.floor((available - MENU_HEADER - footer) / step))
        if reveal then RevealThread(reveal, capacity) end
        local visible = math.min(#order, capacity)
        firstSlot = math.max(1, math.min(#order - visible + 1, firstSlot))
        menu:SetSize(math.min(MENU_WIDTH, (width - 20) / scale), MENU_HEADER + footer + visible * step)
        menu.previous:SetShown(overflow)
        menu.previous:SetEnabled(firstSlot > 1)
        menu.next:SetShown(overflow)
        menu.next:SetEnabled(firstSlot + visible <= #order)
        menu.status:SetShown(overflow)
        menu.status:SetText(("%d–%d of %d"):format(firstSlot, firstSlot + visible - 1, #order))
        for index = 1, visible do
            local button = slots[index] or CreateSlot()
            slots[index] = button
            local thread = order[firstSlot + index - 1]
            button.thread = thread
            button.rim:SetSize(cfg.size, cfg.size)
            button:SetHeight(step - 2)
            button:ClearAllPoints()
            local offset = -MENU_HEADER - (index - 1) * step
            button:SetPoint("TOPLEFT", 10, offset)
            button:SetPoint("TOPRIGHT", -10, offset)
            local message = thread.messages[#thread.messages]
            local context = message and (message[1]:gsub("%s+", " ")) or "Trade history"
            Addon:DrawWhisperIdentityPlate(button, thread, context, thread.unread > 0)
            SetBadge(button.badge, thread.unread, cfg.badges)
            button:Show()
        end
        for index = visible + 1, #slots do slots[index].thread = nil; slots[index]:Hide() end
        PositionPanel(menu)
    end
    if selected and chat:IsShown() then
        SizeChat()
        PositionPanel(chat)
    end
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
    if not Settings().enabled then self:Print("Enable Whisper Manager to show the chat menu."); return end
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
    while thread.mergedInto do thread = thread.mergedInto end
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
    local restored, retained = {}, {}
    for key, entry in pairs(archive.threads) do
        if type(key) == "string" and type(entry) == "table" and type(entry.name) == "string"
            and entry.name ~= "" and type(entry.messages) == "table" then
            local bnet = entry.bnet == true
            local tag = bnet and (BattleTag(entry.battleTag) or BattleTag(entry.name))
            local name = tag and tag:match("^[^#]+") or entry.name
            if bnet and name:find("|K", 1, true) then name = "Battle.net contact" end
            local thread = GetThread(key, name)
            thread.guid = not bnet and type(entry.guid) == "string" and entry.guid or nil
            thread.bnet, thread.party, thread.instance = bnet, key == "party", entry.instance == true
            if bnet then
                thread.battleTag = tag
                thread.archiveKey = key
            end
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
                retained[#retained + 1] = thread
                if not thread.hidden and (not thread.party or Settings().party) then restored[#restored + 1] = thread end
            else
                archive.threads[key] = nil
            end
        else
            archive.threads[key] = nil
        end
    end
    for _, thread in ipairs(retained) do SaveThread(thread) end
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

local function MergeBattleNetThreads(known, pending)
    local first, second = known.messages, pending.messages
    local messages, left, right = {}, 1, 1
    while left <= #first or right <= #second do
        local older, newer = first[left], second[right]
        if older and (not newer or older[2] <= newer[2]) then
            messages[#messages + 1], left = older, left + 1
        else
            messages[#messages + 1], right = newer, right + 1
        end
    end
    local thread, removed = known, pending
    if selected == pending or not known.active and pending.active then thread, removed = pending, known end
    thread.messages = messages
    thread.unread = known.unread + pending.unread
    Deactivate(removed)
    threads[removed.key], removed.mergedInto = nil, thread
    local archive = Addon.character.chatHistory
    if archive and removed.archiveKey then archive.threads[removed.archiveKey] = nil end
    return thread
end

local function GetBattleNetThread(name, account, info)
    info = info or GetBattleNetAccount(account, name)
    local tag = info and BattleTag(info.battleTag) or BattleTag(name)
    local id = info and info.bnetAccountID
    if Number(id) and id > 0 then account = id end
    local foldedTag = tag and tag:lower()
    local key = foldedTag and ("bnet:" .. foldedTag) or ("bnet:session:" .. (account or name))
    local thread, merged = threads[key]
    if not thread or tag then
        for _, candidate in pairs(threads) do
            if candidate.bnet and candidate ~= thread then
                local sameTag = foldedTag and candidate.battleTag and foldedTag == candidate.battleTag:lower()
                local sameSession = account and candidate.account == account
                    or not candidate.account and candidate.bnetName == name
                if sameTag or sameSession and (not tag or not candidate.battleTag) then
                    if not thread then
                        thread = candidate
                        break
                    elseif not candidate.battleTag then
                        thread, merged = MergeBattleNetThreads(thread, candidate), true
                        break
                    end
                end
            end
        end
    end
    local label = tag and tag:match("^[^#]+") or not name:find("|K", 1, true) and name or "Battle.net contact"
    thread = thread or GetThread(key, label)
    thread.bnet, thread.bnetName, thread.account = true, name, account or thread.account
    if tag then
        if thread.key ~= key then
            threads[thread.key], threads[key], thread.key = nil, thread, key
        end
        thread.battleTag, thread.name = tag, label
    end
    return thread, merged
end

local function ResolvePendingBattleNetThreads()
    local pending, selectedMerged = {}
    for _, thread in pairs(threads) do
        if thread.bnet and not thread.battleTag and thread.bnetName then pending[#pending + 1] = thread end
    end
    for _, thread in ipairs(pending) do
        if threads[thread.key] == thread then
            local info = GetBattleNetAccount(thread.account, thread.bnetName)
            if info and BattleTag(info.battleTag) then
                local resolved, merged = GetBattleNetThread(thread.bnetName, thread.account, info)
                if Settings().saveHistory then TrimMessages(resolved); SaveThread(resolved) end
                if resolved == selected and merged then selectedMerged = true end
            end
        end
    end
    return selectedMerged
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
    local thread, merged
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
    elseif bnet then
        thread, merged = GetBattleNetThread(name, Number(account) and account > 0 and account or nil)
    else
        thread = GetThread(Addon:GetWhisperCharacterKey(name), name)
        thread.name, thread.tradeOnly = name, nil
        thread.guid = TextValue(guid) or thread.guid
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
        if not chat.showingTrades then RefreshMessages(false, not trimmed and not merged) end
    elseif channel and cfg.partyAutoOpen and not dragging and (not selected or cfg.partyInterrupt) then
        OpenChat(thread)
    end
end

for event in pairs(events) do listener:RegisterEvent(event) end
for event in pairs(partyEvents) do listener:RegisterEvent(event) end
local battleNetEvents = { BN_CONNECTED = true, BN_DISCONNECTED = true, BN_FRIEND_INFO_CHANGED = true,
    BN_FRIEND_LIST_SIZE_CHANGED = true, BN_FRIEND_ACCOUNT_ONLINE = true, BN_FRIEND_ACCOUNT_OFFLINE = true }
for event in pairs(battleNetEvents) do listener:RegisterEvent(event) end
listener:RegisterEvent("GROUP_LEFT")
listener:RegisterEvent("GROUP_JOINED")
listener:RegisterEvent("DISPLAY_SIZE_CHANGED")
listener:RegisterEvent("UI_SCALE_CHANGED")
listener:SetScript("OnEvent", function(_, event, ...)
    if events[event] or partyEvents[event] then
        Receive(event, ...)
    elseif battleNetEvents[event] then
        battleNetFriends = nil
        local selectedMerged
        if event == "BN_DISCONNECTED" then
            for _, thread in pairs(threads) do thread.account, thread.bnetName = nil, nil end
        elseif Addon.db then
            selectedMerged = ResolvePendingBattleNetThreads()
        end
        if bar then UpdateBar() end
        if selectedMerged then
            RefreshMessages(false)
        elseif selected and selected.bnet then
            chat.title:SetText(Addon:GetWhisperDisplayName(selected))
            Portrait(chat.identity.avatar, selected)
        end
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
