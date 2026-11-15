local _, Addon = ...
local listener = CreateFrame("Frame")
local trade

local function Public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function Text(value)
    return Public(value) and type(value) == "string" and value ~= ""
end

local function Number(value)
    return Public(value) and type(value) == "number" and value >= 0 and value < math.huge
end

local function History()
    local history = Addon.character.tradeHistory
    if type(history) ~= "table" then history = {}; Addon.character.tradeHistory = history end
    return history
end

function Addon:GetTradeHistory(key)
    local entries = History()[key]
    return type(entries) == "table" and entries or nil
end

function Addon:TrimTradeHistory()
    local limit = self:GetWhisperSettings().tradeLimit
    local history = History()
    for key, entries in pairs(history) do
        if type(key) ~= "string" or type(entries) ~= "table" then
            history[key] = nil
        else
            while #entries > limit do table.remove(entries) end
        end
    end
end

function Addon:DiscardPendingTrade()
    trade = nil
end

local function Save(attempt, status)
    local entry = attempt.entry
    if not entry then
        local history = History()
        local entries = history[attempt.key]
        if type(entries) ~= "table" then entries = {}; history[attempt.key] = entries end
        entry = {}
        attempt.entry = entry
        table.insert(entries, 1, entry)
        while #entries > Addon:GetWhisperSettings().tradeLimit do table.remove(entries) end
    end
    entry.status, entry.time = status, (GetServerTime or time)()
    entry.request = attempt.request
    if status == "complete" then
        entry.sent, entry.received = attempt.sent, attempt.received
    end
    Addon:RefreshWhisperTrade(attempt.name, attempt.key, attempt.guid)
end

local function Attempt(name, guid, request)
    return { name = name, key = Addon:GetWhisperCharacterKey(name), guid = Public(guid) and guid or nil, request = request }
end

local function Offer(getItem, getMoney)
    local items = {}
    if getItem then
        for slot = 1, MAX_TRADABLE_ITEMS or 6 do
            local name, _, count = getItem(slot)
            if Text(name) then
                items[#items + 1] = { name = name, count = Number(count) and math.max(1, count) or 1 }
            end
        end
    end
    local money = getMoney and getMoney()
    return { items = items, money = Number(money) and money or 0 }
end

local function Snapshot()
    trade.sent = Offer(GetTradePlayerItemInfo, GetPlayerTradeMoney)
    trade.received = Offer(GetTradeTargetItemInfo, GetTargetTradeMoney)
end

local function OpenTrade(cfg)
    local name
    if GetUnitName then name = GetUnitName("NPC", true) else name = UnitName("NPC") end
    if not Text(name) then return end
    local guid = UnitGUID and UnitGUID("NPC")
    local key = Addon:GetWhisperCharacterKey(name)
    if not trade or trade.key ~= key or trade.closedAt then trade = Attempt(name, guid) end
    trade.guid = Public(guid) and guid or trade.guid
    trade.open = true
    trade.accepted = nil
    Snapshot()
    if cfg.tradeRequests then Save(trade, "opened") end
end

local function OnEvent(_, event, arg1, arg2)
    if not Addon.db or not Addon.character then return end
    local cfg = Addon:GetWhisperSettings()
    if not cfg.enabled or not cfg.tradeHistory then trade = nil; return end
    if event == "TRADE_REQUEST" then
        if not Text(arg1) then return end
        trade = Attempt(arg1, nil, "received")
        if cfg.tradeRequests then Save(trade, "request") end
    elseif event == "TRADE_REQUEST_CANCEL" then
        if trade and not trade.open and not trade.closedAt then
            if trade.entry then Save(trade, "cancelled") end
            trade = nil
        end
    elseif event == "TRADE_SHOW" then
        OpenTrade(cfg)
    elseif event == "TRADE_CLOSED" then
        -- A close can precede the game message and can also mean cancellation.
        if trade and trade.open then
            trade.open, trade.closedAt = nil, GetTime()
            if trade.entry then Save(trade, "closed") end
        end
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" or event == "CHAT_MSG_SYSTEM" then
        local message = arg2
        if event == "CHAT_MSG_SYSTEM" then message = arg1 end
        if not trade or not Text(message) then return end
        if trade.closedAt and GetTime() - trade.closedAt > 2 then trade = nil; return end
        if message == ERR_TRADE_COMPLETE and (trade.open or trade.closedAt) then
            Save(trade, "complete")
            trade = nil
        elseif message == ERR_TRADE_CANCELLED or message == ERR_TRADE_BAG_FULL then
            if trade.entry then Save(trade, "cancelled") end
            trade = nil
        end
    elseif trade and trade.open then
        if event == "TRADE_ACCEPT_UPDATE" then
            trade.accepted = Public(arg1) and Public(arg2)
                and (arg1 == 1 or arg1 == true) and (arg2 == 1 or arg2 == true)
            Snapshot()
        elseif not trade.accepted then
            Snapshot()
        end
    end
end

for _, event in ipairs({ "TRADE_REQUEST", "TRADE_REQUEST_CANCEL", "TRADE_SHOW", "TRADE_CLOSED",
    "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_MONEY_CHANGED", "PLAYER_TRADE_MONEY", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM" }) do
    listener:RegisterEvent(event)
end
listener:SetScript("OnEvent", OnEvent)

if hooksecurefunc and InitiateTrade then
    hooksecurefunc("InitiateTrade", function(unit)
        if not Addon.db or not Addon.character or not Text(unit) then return end
        local cfg = Addon:GetWhisperSettings()
        if not cfg.enabled or not cfg.tradeHistory or not cfg.tradeRequests or trade and trade.open then return end
        if UnitIsPlayer then
            local player = UnitIsPlayer(unit)
            if not Public(player) or not player then return end
        end
        local name
        if GetUnitName then name = GetUnitName(unit, true) else name = UnitName(unit) end
        if not Text(name) then return end
        trade = Attempt(name, UnitGUID and UnitGUID(unit), "initiated")
        Save(trade, "request")
    end)
end
