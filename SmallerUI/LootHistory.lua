local _, Addon = ...
local listener = CreateFrame("Frame")
local defaultLimit = 20000
local archive, settings
local completed = {}
local lootFormats, randomFormat
local rollStates = { [0] = "Need", [1] = "Off-spec need", [2] = "Transmog", [3] = "Greed", [5] = "Pass" }
local kinds = { "Loot", "Group roll", "Random roll" }

local function Public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function Text(value)
    return Public(value) and type(value) == "string" and value ~= ""
end

local function ItemLink(link)
    return Text(link) and (link:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h%[[^|]+%]|h|r)")
        or link:match("(|Hitem:[^|]+|h%[[^|]+%]|h)"))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Trim(force)
    local first = archive.first
    local last = #archive.rows
    archive.first = math.max(first, last - settings.limit + 1)
    if archive.first == 1 or not force and archive.first - 1 < math.max(256, settings.limit / 4) then return end
    local rows = {}
    for index = archive.first, last do rows[#rows + 1] = archive.rows[index] end
    archive.rows, archive.first = rows, 1
end

function Addon:ValidateLootHistory()
    local cfg = self.db.lootHistory
    if type(cfg) ~= "table" then cfg = {}; self.db.lootHistory = cfg end
    cfg.enabled = cfg.enabled ~= false
    cfg.showLauncher = cfg.showLauncher == true
    cfg.limit = Number(cfg.limit) and math.max(1000, math.min(100000, math.floor(cfg.limit))) or defaultLimit
    settings = cfg
    archive = self.character.lootHistory
    if type(archive) ~= "table" or archive.version ~= 1 or type(archive.rows) ~= "table" then
        archive = { version = 1, rows = {}, first = 1 }
        self.character.lootHistory = archive
    end
    local first = Number(archive.first) and math.floor(archive.first) or 1
    archive.first = math.max(1, math.min(#archive.rows + 1, first))
    Trim(true)
end

function Addon:GetLootSettings() return settings end

function Addon:GetLootRecords()
    return archive.rows, archive.first
end

function Addon:SetLootLimit(limit)
    if not Number(limit) or limit < 1000 or limit > 100000 then return false end
    settings.limit = math.floor(limit)
    Trim(true)
    self:RefreshLootLedger()
    return true
end

-- Rows store time, kind, item link, player, count or roll, then optional details.
local function Record(kind, link, player, amount, extra, rolls)
    local row = { (GetServerTime or time)(), kind, link, player, amount, extra, rolls }
    archive.rows[#archive.rows + 1] = row
    Trim()
    Addon:RefreshLootLedger()
end

local function ItemName(link)
    return link and link:match("|h%[(.-)%]|h") or nil
end

local function EscapeText(text)
    return (text:gsub("|", "||"))
end

function Addon:DescribeLootRecord(row)
    local title = ItemName(row[3])
    title = title and EscapeText(title) or "Random roll"
    local player = row[4] and EscapeText(row[4]) or ""
    if row[2] == 1 then return title, player .. (row[5] > 1 and ("  x" .. row[5]) or "") end
    if row[2] == 3 then return title, string.format("%s rolled %d (%s)", player, row[5], row[6]) end
    if row[6] == "All passed" then return title, row[6] end
    return title, player .. " won" .. (row[5] and ("  " .. row[5]) or "")
        .. (row[6] and ("  " .. row[6]) or "")
end

function Addon:LootMatches(row, filter, terms)
    if filter ~= 0 and row[2] ~= filter then return false end
    if #terms == 0 then return true end
    local title, detail = self:DescribeLootRecord(row)
    local values = { title, detail, kinds[row[2]] }
    for _, term in ipairs(terms) do
        if term:find("%d") then values[#values + 1] = date("%d/%m/%Y %H:%M", row[1]); break end
    end
    for _, roll in ipairs(row[7] or {}) do
        values[#values + 1] = roll[1]
        values[#values + 1] = roll[2]
        if roll[3] then values[#values + 1] = tostring(roll[3]) end
    end
    return self:HistoryMatches(table.concat(values, " "):lower(), terms)
end

local function FormatPattern(format)
    if type(format) ~= "string" then return end
    local pattern, fields, from = { "^" }, {}, 1
    while true do
        local first, last, position, spec = format:find("%%(%d*)%$?([sd])", from)
        local literal = format:sub(from, first and first - 1 or -1)
        pattern[#pattern + 1] = literal:gsub("(%W)", "%%%1")
        if not first then break end
        fields[#fields + 1] = tonumber(position) or #fields + 1
        pattern[#pattern + 1] = spec == "d" and "(%d+)" or "(.-)"
        from = last + 1
    end
    pattern[#pattern + 1] = "$"
    return { table.concat(pattern), fields }
end

local function MatchFormat(message, format)
    if not format then return end
    local captures = { message:match(format[1]) }
    if not captures[1] then return end
    local fields = {}
    for index, position in ipairs(format[2]) do fields[position] = captures[index] end
    return fields
end

local function CurrentPlayer()
    local player = UnitName("player")
    return Text(player) and player or "You"
end

local function ObserveLoot(message, sender)
    if not Text(message) then return end
    if not lootFormats then
        lootFormats = {
            { FormatPattern(LOOT_ITEM_SELF_MULTIPLE), true }, { FormatPattern(LOOT_ITEM_SELF), true },
            { FormatPattern(LOOT_ITEM_MULTIPLE), false }, { FormatPattern(LOOT_ITEM), false },
        }
    end
    for _, format in ipairs(lootFormats) do
        local fields = MatchFormat(message, format[1])
        if fields then
            local selfLoot = format[2]
            local link = ItemLink(fields[selfLoot and 1 or 2])
            if not link then return end
            local player = selfLoot and CurrentPlayer() or Text(sender) and sender or fields[1]
            local amount = tonumber(fields[selfLoot and 2 or 3]) or 1
            Record(1, link, player, amount)
            return
        end
    end
end

local function ObserveRandom(message)
    if not Text(message) then return end
    if not randomFormat then randomFormat = FormatPattern(RANDOM_ROLL_RESULT) end
    local fields = MatchFormat(message, randomFormat)
    if not fields then return end
    local roll, low, high = tonumber(fields[2]), tonumber(fields[3]), tonumber(fields[4])
    if roll and low and high then Record(3, false, fields[1], roll, low .. "-" .. high) end
end

local function ObserveGroup(encounter, lootKey)
    if not Number(encounter) or not Number(lootKey) or not C_LootHistory or not C_LootHistory.GetSortedInfoForDrop then return end
    local info = C_LootHistory.GetSortedInfoForDrop(encounter, lootKey)
    if not Public(info) or not info then return end
    local link = ItemLink(info.itemHyperlink)
    if not link then return end
    local winner = info.winner
    local passed = Public(info.allPassed) and info.allPassed == true
    if not Public(winner) or not winner and not passed then return end
    local timestamp = Number(info.startTime) and info.startTime or 0
    local key = encounter .. ":" .. lootKey .. ":" .. tostring(timestamp)
    if completed[key] then return end
    local name, result, method
    if winner and Text(winner.playerName) then
        name = winner.playerName
        result = Number(winner.roll) and winner.roll or nil
        method = Number(winner.state) and rollStates[winner.state] or nil
    elseif not passed then
        return
    end
    local rolls = {}
    if Public(info.rollInfos) and type(info.rollInfos) == "table" then
        for _, roll in ipairs(info.rollInfos) do
            if Public(roll) and Text(roll.playerName) and Number(roll.state) and rollStates[roll.state] then
                rolls[#rolls + 1] = { roll.playerName, rollStates[roll.state], Number(roll.roll) and roll.roll or nil }
            end
        end
    end
    completed[key] = true
    Record(2, link, name, result, passed and "All passed" or method, #rolls > 0 and rolls or nil)
end

for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM", "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_CLEAR_HISTORY", "PLAYER_LOGOUT" }) do
    listener:RegisterEvent(event)
end

listener:SetScript("OnEvent", function(_, event, ...)
    if event == "LOOT_HISTORY_CLEAR_HISTORY" then completed = {}; return end
    if not settings then return end
    if event == "PLAYER_LOGOUT" then Trim(true); return end
    if not settings.enabled then return end
    if event == "CHAT_MSG_LOOT" then ObserveLoot(...)
    elseif event == "CHAT_MSG_SYSTEM" then ObserveRandom(...)
    else ObserveGroup(...) end
end)
