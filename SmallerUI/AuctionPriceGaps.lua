local _, Addon = ...
local Market = Addon.VendorResaleMarket
local Gaps = { rows = {}, status = "Scan your watchlist or check a commodity directly." }
Addon.AuctionPriceGaps = Gaps

local MAX_TIERS = 5
function Gaps:IsCurrent(row, now, marketScope)
    local at, scope = row and row.at or self.at, row and row.scope or self.scope
    return at and (now or Market:Now()) - at <= Addon:GetAuctionSettings().gapAge * 60
        and scope == (marketScope or Market:ScanContext().scope)
end

function Gaps:Add(scan, key, price, quantity, link, tiers, at)
    local item = scan.gaps[key.itemID]
    if not item then
        item = { key = key, link = link, low = price, tiers = tiers or (scan.replicate and {} or nil), at = at or scan.at }
        scan.gaps[key.itemID] = item
    end
    if price < item.low then item.low = price end
    if tiers or not item.tiers then return end
    local tiers = item.tiers
    for index = 1, MAX_TIERS do
        local tier = tiers[index]
        if tier and tier.price == price then tier.quantity = tier.quantity + quantity; return end
        if not tier or price < tier.price then
            table.insert(tiers, index, { price = price, quantity = quantity })
            tiers[MAX_TIERS + 1] = nil
            return
        end
    end
end

local function BuyLimit(target, cut, settings)
    return math.min(math.floor(target * (100 - settings.gapDiscount) / 100), math.floor(target * (1 - cut)) - 1)
end

local function Reference(tiers, historical, settings)
    local low = tiers[1]
    if not low then return end
    local first, below = nil, low.quantity
    for index = 2, #tiers do
        local tier = tiers[index]
        local support = tier.marketQuantity or tier.quantity
        if tier.price > low.price and support >= settings.gapSupport then
            first = first or tier.price
            if not historical or (tier.price >= historical and support >= below) then return tier.price end
        end
        below = below + tier.quantity
        if below > settings.gapUnits then break end
    end
    return first
end

function Gaps:VisibleRows()
    local settings = Addon:GetAuctionSettings()
    local rows = {}
    for _, row in ipairs(self.rows) do
        local reference = row.tiers and Reference(row.tiers, row.target, settings)
        local target = reference and math.min(reference, row.target) or row.target
        if (not row.tiers or reference) and row.price <= BuyLimit(target, row.cut, settings) then
            rows[#rows + 1] = row
        end
    end
    return rows
end

function Gaps:Publish(scan, priorRows, preview)
    local settings = Addon:GetAuctionSettings()
    if settings.priceGaps == false then
        self.rows, self.scanning = {}, false
        return
    end
    local rows = {}
    if scan.coverage then
        for _, row in ipairs(priorRows or {}) do
            local key = Market:ItemKey(row.key)
            if row.scope == scan.scope and not scan.gaps[row.key.itemID] and not Market:Covered(scan.coverage, key, row) then
                rows[#rows + 1] = row
            end
        end
    end
    for _, item in pairs(scan.gaps) do
        local historical, _, days = Market:GetTypicalPrice(Market:ItemKey(item.key), scan.scope)
        historical = days and days >= 2 and math.floor(historical) or nil
        local shelf = item.tiers and Reference(item.tiers, historical, settings)
        if historical then shelf = math.min(shelf or historical, historical) end
        local target = shelf and math.floor(shelf)
        if target and item.low <= BuyLimit(target, scan.cut, settings) then
            local info = C_AuctionHouse.GetItemKeyInfo(item.key)
            if info and info.isCommodity then
                local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item.key.itemID)
                item.name = info.itemName or name or tostring(item.key.itemID)
                item.icon, item.link, item.quality = info.iconFileID or icon, item.link or link, info.quality or quality
                item.gap, item.price, item.target, item.cut, item.scope = true, item.low, target, scan.cut, scan.scope
                item.classID = scan.coverage and scan.coverage.classID
                item.margin = math.floor(target * (1 - scan.cut)) - item.price
                rows[#rows + 1] = item
            end
        end
    end
    table.sort(rows, function(a, b)
        local left, right = a.margin / a.price, b.margin / b.price
        if left == right then return a.key.itemID < b.key.itemID end
        return left > right
    end)
    self.rows, self.at, self.scope, self.scanning = rows, scan.at, scan.scope, preview == true
    self.status = #rows > 0 and ("%d scan leads. Check a row for a live price gap."):format(#rows)
        or "No supported price gaps in this scan. More scan history can surface additional leads."
end

function Gaps:ManualRow(text, allowUnverified)
    text = text:match("^%s*(.-)%s*$")
    if text == "" then return end
    local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
    local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id or text)
    id = id or (link and tonumber(link:match("item:(%d+)")))
    if not id or id < 1 or id >= 2147483648 or id % 1 ~= 0 then return end
    local key = C_AuctionHouse.MakeItemKey(id)
    local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, key)
    if not ok then info = nil end
    if info and not info.isCommodity or not info and not allowUnverified then return end
    info = info or {}
    local context = Market:ScanContext()
    local historical, _, days = Market:GetTypicalPrice(Market:ItemKey(key), context.scope)
    return { gap = true, manual = true, key = key, name = info.itemName or name or tostring(id), icon = info.iconFileID or icon,
        quality = info.quality or quality, link = link, target = days and days >= 2 and math.floor(historical) or nil,
        cut = context.cut }
end

function Gaps:ReadTiers(id)
    local ah = C_AuctionHouse
    local tiers, byPrice = {}, {}
    for index = 1, ah.GetNumCommoditySearchResults(id) do
        local result = ah.GetCommoditySearchResultInfo(id, index)
        if result and result.unitPrice and result.unitPrice > 0 and result.quantity and result.quantity > 0 then
            local owned = result.containsAccountItem or result.containsOwnerItem or (result.numOwnerItems or 0) > 0
            local tier = byPrice[result.unitPrice]
            if not tier then
                tier = { price = result.unitPrice, quantity = 0, marketQuantity = 0 }
                tiers[#tiers + 1], byPrice[result.unitPrice] = tier, tier
            end
            tier.quantity = tier.quantity + result.quantity
            tier.marketQuantity = tier.marketQuantity + (owned and 0 or result.quantity)
            tier.owned = tier.owned or owned
        end
    end
    table.sort(tiers, function(a, b) return a.price < b.price end)
    return tiers
end

function Gaps:LiveOrder(row, gold)
    local settings = Addon:GetAuctionSettings()
    if settings.priceGaps == false then return end
    local ah, id = C_AuctionHouse, row.key.itemID
    local tiers = self:ReadTiers(id)
    local live = Reference(tiers, row.target, settings)
    if not live then return end
    local target = math.min(row.target or live, live)
    local limit = BuyLimit(target, row.cut, settings)
    local order = { deal = row, quantity = 0, cost = 0, target = target }
    for _, tier in ipairs(tiers) do
        if tier.price > limit or tier.owned then break end
        local quantity = math.min(tier.quantity, math.floor((gold - order.cost) / tier.price), settings.gapUnits - order.quantity)
        if quantity <= 0 then break end
        order.quantity = order.quantity + quantity
        order.cost = order.cost + quantity * tier.price
        order.unitPrice = tier.price
    end
    if order.quantity == 0 then return end
    local gross = order.quantity * target
    order.profit = gross - math.ceil(gross * row.cut) - order.cost
    if order.profit <= 0 then return end
    if ah.CalculateCommodityDeposit then
        local ok, deposit = pcall(ah.CalculateCommodityDeposit, id, Addon.VendorResale:Settings().duration, order.quantity)
        if ok and type(deposit) == "number" then order.deposit = deposit end
    end
    return order
end
