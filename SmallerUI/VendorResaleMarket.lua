local _, Addon = ...
local Market = {}
Addon.VendorResaleMarket = Market

local DAY = 24 * 60 * 60
local factionCities = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }

function Market:ItemKey(key)
    return table.concat({ key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0 }, ":")
end

function Market:Now()
    return GetServerTime and GetServerTime() or time()
end

function Market:Scope()
    local realm
    local rules = Enum and Enum.GameRule
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() and rules and C_GameRules then
        local function Active(rule) return rule and C_GameRules.IsGameRuleActive(rule) end
        local pvp, rp = Active(rules.PvPRuleset), Active(rules.RPRuleset)
        realm = pvp and (rp and "RPPvP" or "PvP") or rp and "RP" or Active(rules.HardcoreRuleset) and "HC" or "PvE"
    else
        local connected = GetAutoCompleteRealms and GetAutoCompleteRealms() or {}
        for _, name in ipairs(connected) do
            if not realm or name < realm then realm = name end
        end
    end
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
    local region = GetCurrentRegion and GetCurrentRegion() or 0
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Unknown"
    return table.concat({ region, realm, faction }, ":")
end

function Market:ScanContext()
    local base = self:Scope()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return { base = base, scope = base, cut = 0.05 } end
    local map = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if factionCities[mapID] then return { base = base, scope = base, cut = 0.05, venue = map and map.name } end
    return { base = base, scope = base .. ":" .. mapID, cut = 0.15, venue = map and map.name }
end

function Market:GetBook(scope, create)
    local books = Addon.db.vendorResaleMarkets
    if type(books) ~= "table" then
        if not create then return end
        books = {}
        Addon.db.vendorResaleMarkets = books
    end
    if not books[scope] and create then books[scope] = { days = {} } end
    return books[scope]
end

function Market:StartScan(replicate, context)
    context = context or self:ScanContext()
    return { at = self:Now(), scope = context.scope, base = context.base, cut = context.cut, venue = context.venue,
        replicate = replicate, items = {} }
end

function Market:AddObservation(scan, key, price, quantity, observedAt)
    local item = scan.items[key]
    if not item then
        item = { price = price, quantity = 0, atFloor = scan.replicate and 0 or nil, at = observedAt or scan.at }
        scan.items[key] = item
    end
    item.quantity = item.quantity + quantity
    if price < item.price then
        item.price = price
        if scan.replicate then item.atFloor = 0 end
    end
    if scan.replicate and price == item.price then item.atFloor = item.atFloor + quantity end
end

function Market:Covered(coverage, key, item)
    if not coverage then return true end
    if coverage.keys then return coverage.keys[key] == true end
    if item and item.classID ~= nil then return item.classID == coverage.classID end
    local id = tonumber(key:match("^%d+"))
    local _, _, _, _, _, classID
    if id and C_Item and C_Item.GetItemInfoInstant then
        _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
    end
    return classID ~= nil and classID == coverage.classID
end

function Market:SaveScan(scan)
    local book = self:GetBook(scan.scope, true)
    local previous = book.latest
    local items = scan.items
    if scan.coverage and previous then
        items = {}
        for key, item in pairs(previous.items) do
            if not scan.items[key] and not self:Covered(scan.coverage, key, item) then
                item.at = item.at or previous.at
                items[key] = item
            end
        end
        for key, item in pairs(scan.items) do items[key] = item end
    end
    book.latest = { at = scan.at, items = items, scope = scan.scope, cut = scan.cut, venue = scan.venue }
    self:GetBook(scan.base, true).lastScope = scan.scope
    local day = math.floor(scan.at / DAY)
    local retention = Addon:GetAuctionSettings().historyDays
    for past in pairs(book.days) do
        if past <= day - retention then book.days[past] = nil end
    end
    for key, item in pairs(scan.items) do
        local observedDay = math.floor(item.at / DAY)
        local samples = book.days[observedDay] or {}
        book.days[observedDay] = samples
        local sample = samples[key]
        if sample then
            sample.total = sample.total + item.price
            sample.count = sample.count + 1
            sample.low = math.min(sample.low, item.price)
            sample.high = math.max(sample.high, item.price)
        else
            samples[key] = { total = item.price, count = 1, low = item.price, high = item.price }
        end
    end
    if Addon.RefreshVendorResale then Addon:RefreshVendorResale() end
end

function Market:GetLatest(scope)
    local book = self:GetBook(scope or self:Scope())
    if not scope and book and book.lastScope then book = self:GetBook(book.lastScope) end
    return book and book.latest
end

function Market:GetTypicalPrice(key, scope)
    local snapshot = not scope and self:GetLatest()
    local book = self:GetBook(scope or (snapshot and snapshot.scope) or self:Scope())
    if not book then return end
    local day = math.floor(self:Now() / DAY)
    local prices, observations = {}, 0
    for past = day - Addon:GetAuctionSettings().typicalDays + 1, day do
        local sample = book.days[past] and book.days[past][key]
        if sample then
            prices[#prices + 1] = sample.total / sample.count
            observations = observations + sample.count
        end
    end
    local count = #prices
    if count == 0 then return end
    table.sort(prices)
    local lower, upper = math.floor((count + 1) / 2), math.ceil((count + 1) / 2)
    return (prices[lower] + prices[upper]) / 2, observations, count
end
