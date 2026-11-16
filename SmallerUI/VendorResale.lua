local _, Addon = ...
local Market = Addon.VendorResaleMarket
local Resale = {}
Addon.VendorResale = Resale
Resale.durationHours = { 2, 8, 24 }

local function Notify()
    if Addon.RefreshVendorResale then Addon:RefreshVendorResale() end
end

function Resale:Settings()
    local settings = Addon.db.vendorResale
    if type(settings) ~= "table" then
        settings = {}
        Addon.db.vendorResale = settings
    end
    if type(settings.minimum) ~= "number" or not (settings.minimum >= 0 and settings.minimum <= 100000000) then
        settings.minimum = 100
    end
    if type(settings.maxAge) ~= "number" or not (settings.maxAge >= 1 and settings.maxAge <= 168) then settings.maxAge = 24 end
    if not self.durationHours[settings.duration] then settings.duration = 2 end
    return settings
end

function Resale:Ledger()
    if not Addon.character.vendorResale then
        Addon.character.vendorResale = { purchases = {}, outcomes = {}, listings = {} }
    end
    return Addon.character.vendorResale
end

function Resale:ItemCount(id)
    return (C_Item and C_Item.GetItemCount or GetItemCount)(id)
end

local function MerchantInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then return C_MerchantFrame.GetItemInfo(index) end
    local name, texture, price, count, available, purchasable, _, extended = GetMerchantItemInfo(index)
    return { name = name, texture = texture, price = price, stackCount = count, numAvailable = available,
        isPurchasable = purchasable, hasExtendedCost = extended }
end

local function MerchantItem(index)
    local item = MerchantInfo(index)
    if not item or not item.name or not item.price or item.price <= 0 or item.numAvailable == 0
        or item.isPurchasable == false or item.hasExtendedCost then return end
    local link = GetMerchantItemLink(index)
    local itemID = GetMerchantItemID(index)
    if not link or not itemID then return end
    local name, _, _, level, _, _, _, _, equipSlot, _, _, _, _, binding = C_Item.GetItemInfo(link)
    if not name or binding == nil or (binding ~= 0 and binding ~= 2 and binding ~= 3) then return end
    local itemLevel = equipSlot and equipSlot ~= "" and level or 0
    local key = C_AuctionHouse.MakeItemKey(itemID, itemLevel, 0)
    return item, key, link
end

function Resale:RememberMerchant()
    if not self:CanReadMerchant() or not GetMerchantNumItems then return end
    local scope = Market:Scope()
    local catalog = Addon.db.vendorResaleCatalog or {}
    Addon.db.vendorResaleCatalog = catalog
    local items = catalog[scope] or {}
    catalog[scope] = items
    for index = 1, GetMerchantNumItems() do
        local _, key = MerchantItem(index)
        if key then items[Market:ItemKey(key)] = key end
    end
end

function Resale:KnownStock()
    local catalog = Addon.db.vendorResaleCatalog or {}
    local list = {}
    for _, key in pairs(catalog[Market:Scope()] or {}) do list[#list + 1] = key end
    table.sort(list, function(a, b) return Market:ItemKey(a) < Market:ItemKey(b) end)
    return list
end

function Resale:ReadOffer(index, snapshot)
    local item, key, link = MerchantItem(index)
    if not item then return end
    local itemID = key.itemID
    local marketKey = Market:ItemKey(key)
    local observation = snapshot.items[marketKey]
    local at = observation and (observation.at or snapshot.at)
    if not observation or Market:Now() - at > self:Settings().maxAge * 3600 then return end
    local pack = math.max(1, item.stackCount or 1)
    local ask = math.floor(observation.price)
    if ask < 1 then return end
    local gross = ask * pack
    local cut = math.ceil(gross * (snapshot.cut or 0.05))
    local profit = gross - cut - item.price
    if profit <= 0 or profit < self:Settings().minimum then return end
    local typical, scans = Market:GetTypicalPrice(marketKey, snapshot.scope)
    return { index = index, name = item.name, icon = item.texture, link = link,
        itemID = itemID, key = key, marketKey = marketKey, market = snapshot.scope, price = item.price,
        pack = pack, available = item.numAvailable, ask = ask,
        cutRate = snapshot.cut or 0.05, profit = profit, typical = typical, scans = scans,
        observation = observation, at = at }
end

function Resale:DepositEstimate(row, packs)
    local ah = C_AuctionHouse
    if not ah.GetItemKeyInfo or not ah.CalculateCommodityDeposit then return end
    local info = ah.GetItemKeyInfo(row.key)
    if not info or not info.isCommodity then return end
    local ok, deposit = pcall(ah.CalculateCommodityDeposit, row.itemID, self:Settings().duration, row.pack * packs)
    if ok and type(deposit) == "number" then return deposit end
end

function Resale:CanReadMerchant()
    return self:Settings().enabled ~= false and self.merchant and MerchantFrame and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1
end

function Resale:Offers()
    if not self:CanReadMerchant() then return {} end
    local snapshot = Market:GetLatest()
    if not snapshot then return {}, "Scan at the Auction House to check this merchant." end
    if Market:Now() - snapshot.at > self:Settings().maxAge * 3600 then return {}, "Auction prices are stale. Scan again." end
    local offers = {}
    for index = 1, GetMerchantNumItems() do
        local row = self:ReadOffer(index, snapshot)
        if row then offers[#offers + 1] = row end
    end
    table.sort(offers, function(a, b)
        if a.profit == b.profit then return a.name < b.name end
        return a.profit > b.profit
    end)
    return offers, #offers == 0 and "No matching deals with fresh prices." or nil
end

function Resale:PurchaseLimit(row)
    if self.pending or InCombatLockdown() or not self:CanReadMerchant() then return 0 end
    local limit = GetMerchantItemMaxStack and GetMerchantItemMaxStack(row.index) or row.pack
    local available = row.available and row.available >= 0 and row.available or math.huge
    return math.min(math.floor(limit / row.pack), math.floor(GetMoney() / row.price), available)
end

function Resale:Buy(row, packs)
    if not self:CanReadMerchant() then return end
    local snapshot = Market:GetLatest()
    local current = snapshot and self:ReadOffer(row.index, snapshot)
    if not current or current.link ~= row.link or current.price ~= row.price or current.pack ~= row.pack
        or current.at ~= row.at or current.market ~= row.market or current.ask ~= row.ask then return "Offer changed. Review it again." end
    if packs < 1 or packs % 1 ~= 0 or packs > self:PurchaseLimit(current) then return "Check the quantity, vendor stock, and your gold." end
    local pending = { row = current, quantity = packs * current.pack, cost = packs * current.price,
        before = self:ItemCount(row.itemID), money = GetMoney() }
    self.pending = pending
    local ok = pcall(BuyMerchantItem, current.index, pending.quantity)
    if not ok then
        self.pending = nil
        return "WoW could not submit the vendor purchase."
    end
    C_Timer.After(5, function()
        if self.pending ~= pending then return end
        self.pending = nil
        self.message = "Purchase unconfirmed. Check your bags before trying again."
        Notify()
    end)
    self.message = "Waiting for the vendor purchase…"
    return self.message
end

local function ConfirmPurchase()
    local pending = Resale.pending
    if not pending or Resale:ItemCount(pending.row.itemID) - pending.before ~= pending.quantity
        or pending.money - GetMoney() ~= pending.cost then return end
    local row, ledger = pending.row, Resale:Ledger()
    ledger.purchases[#ledger.purchases + 1] = { itemID = row.itemID, name = row.name, link = row.link,
        marketKey = row.marketKey, market = row.market, unitCost = pending.cost / pending.quantity,
        quantity = pending.quantity, at = Market:Now() }
    Resale.pending = nil
    Resale.message = ("Bought %d × %s."):format(pending.quantity, row.name)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "GET_ITEM_INFO_RECEIVED",
    "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_LOGIN",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event)
    if not Addon.db then return end
    if event == "PLAYER_LOGIN" then
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("MerchantFrame.MerchantTabShow", Notify, Resale)
            EventRegistry:RegisterCallback("MerchantFrame.BuyBackTabShow", Notify, Resale)
        end
        return
    elseif event == "MERCHANT_SHOW" then
        Resale.merchant, Resale.dismissed, Resale.message = true, false, nil
        C_Timer.After(0, function() Resale:RememberMerchant(); Notify() end)
    elseif event == "MERCHANT_CLOSED" then
        Resale.merchant = nil
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        ConfirmPurchase()
    elseif not Resale.merchant then
        return
    elseif event == "MERCHANT_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" then
        Resale:RememberMerchant()
    end
    Notify()
end)
