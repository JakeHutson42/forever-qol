local _, Addon = ...
local Resale, Market = Addon.VendorResale, Addon.VendorResaleMarket
local Sales = {}
Addon.VendorResaleAuctions = Sales

local durationHours = Resale.durationHours
local MAIL_DAYS = 30

local function Notify()
    if Addon.RefreshVendorResaleAuctions then Addon:RefreshVendorResaleAuctions() end
    if Addon.AuctionScanner then Addon.AuctionScanner:Resume() end
end

local function FindStack(purchase)
    if not C_Container or not ItemLocation then return end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.itemID == purchase.itemID and not item.isLocked and not item.isBound then
                local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                local key = C_AuctionHouse.GetItemKeyFromItem(location)
                if key and Market:ItemKey(key) == purchase.marketKey then
                    return location, key, math.min(item.stackCount, purchase.quantity)
                end
            end
        end
    end
end

function Sales:Review(purchase)
    if self.pending or InCombatLockdown() or not self.open or Resale:Settings().enabled == false then return end
    local scanner, deals = Addon.AuctionScanner, Addon.VendorDeals
    if scanner:HasFlight() or deals.queue or deals.pending then
        self.message = "Waiting for the current Auction House request…"
        scanner.priority = function()
            self:Review(purchase)
            Notify()
        end
        scanner:Resume()
        return
    end
    local location, key, quantity = FindStack(purchase)
    if not location then self.message = "No matching item in your bags."; return end
    local ah = C_AuctionHouse
    if not ah.IsThrottledMessageSystemReady() then self.message = "Auction House busy. Try again."; return end
    local status = ah.GetItemCommodityStatus(location)
    local commodity = status == Enum.ItemCommodityStatus.Commodity
    if status == Enum.ItemCommodityStatus.Unknown then self.message = "Item details are loading. Try again."; return end
    if ah.GetAvailablePostCount then quantity = math.min(quantity, ah.GetAvailablePostCount(location) or 0) end
    if quantity < 1 then self.message = "This item cannot be listed."; return end
    if not commodity then quantity = 1 end
    local duration = Resale:Settings().duration
    local query = { purchase = purchase, key = key, commodity = commodity, quantity = quantity,
        duration = duration, hours = durationHours[duration] }
    self.query, self.quote = query, nil
    local sort = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    local ok = pcall(ah.SendSearchQuery, key, sort and { { sortOrder = sort, reverseSort = false } } or {}, true)
    if not ok then self.query = nil; self.message = "WoW could not check this price."; return end
    self.message = "Checking current asking prices…"
    C_Timer.After(8, function()
        if self.query ~= query then return end
        self.query = nil
        self.message = "Price check timed out. Try again."
        Notify()
    end)
end

local function Deposit(location, itemID, quantity, commodity, duration)
    local ah = C_AuctionHouse
    if commodity then return ah.CalculateCommodityDeposit(itemID, duration, quantity) end
    return ah.CalculateItemDeposit(location, duration, quantity)
end

function Sales:ReadResults(commodity, resultKey)
    local query, ah = self.query, C_AuctionHouse
    if not query or query.commodity ~= commodity then return end
    if commodity then
        if resultKey ~= query.purchase.itemID then return end
    elseif type(resultKey) ~= "table" or Market:ItemKey(resultKey) ~= Market:ItemKey(query.key) then return end
    self.query = nil
    local price
    local count = commodity and ah.GetNumCommoditySearchResults(resultKey) or ah.GetNumItemSearchResults(resultKey)
    for index = 1, count do
        local result
        if commodity then result = ah.GetCommoditySearchResultInfo(resultKey, index)
        else result = ah.GetItemSearchResultInfo(resultKey, index) end
        if result then
            local amount = commodity and result.unitPrice or result.buyoutAmount
            if amount and amount > 0 and not result.containsAccountItem
                and (not price or amount < price) then price = amount end
        end
    end
    if not price then self.message = "There is no current asking price for this item."; return end
    local purchase = query.purchase
    local location, _, quantity = FindStack(purchase)
    if not location or quantity < query.quantity then self.message = "The item stack changed. Check again."; return end
    local deposit = Deposit(location, purchase.itemID, query.quantity, query.commodity, query.duration)
    if type(deposit) ~= "number" then self.message = "The game could not quote a deposit."; return end
    query.price, query.deposit, query.at = price, deposit, Market:Now()
    local total = price * query.quantity
    query.profit = total - math.ceil(total * Market:ScanContext().cut) - purchase.unitCost * query.quantity
    self.quote, self.message = query, nil
    C_Timer.After(61, function()
        if self.quote == query then
            self.quote, self.message = nil, "Price check expired. Check the current price again."
            Notify()
        end
    end)
end

function Sales:CanPost()
    local quote = self.quote
    local settings = Resale:Settings()
    return self.open and not InCombatLockdown() and settings.enabled ~= false and settings.assistedPosting == true
        and quote and quote.duration == settings.duration
        and Market:Now() - quote.at <= 60 and quote.profit > 0 and GetMoney() >= quote.deposit
        and not self.pending and C_AuctionHouse.IsThrottledMessageSystemReady()
end

function Sales:Post()
    if not self:CanPost() then self.message = "Check the current price and deposit again."; return end
    local quote, ah = self.quote, C_AuctionHouse
    local purchase = quote.purchase
    local location, _, quantity = FindStack(purchase)
    if not location or quantity < quote.quantity
        or Deposit(location, purchase.itemID, quote.quantity, quote.commodity, quote.duration) ~= quote.deposit then
        self.quote = nil
        self.message = "The item or deposit changed. Check the price again."
        return
    end
    quote.before = Resale:ItemCount(purchase.itemID)
    self.pending, self.quote = quote, nil
    local ok, confirmation
    if quote.commodity then
        ok, confirmation = pcall(ah.PostCommodity, location, quote.duration, quote.quantity, quote.price)
    else
        ok, confirmation = pcall(ah.PostItem, location, quote.duration, 1, quote.price, quote.price)
    end
    if not ok then
        self.pending, self.message = nil, "WoW could not submit the listing."
        return
    end
    if confirmation then
        local native = quote.commodity and AuctionHouseFrame.CommoditiesSellFrame or AuctionHouseFrame.ItemSellFrame
        if native and native.CachePendingPost then
            if quote.commodity then native:CachePendingPost(location, quote.duration, quote.quantity, quote.price)
            else native:CachePendingPost(location, quote.duration, 1, quote.price, quote.price) end
        end
    end
    self.message = "Waiting for the Auction House…"
    C_Timer.After(20, function()
        if self.pending ~= quote then return end
        self.pending = nil
        self.message = "Listing unconfirmed. Check your auctions before retrying."
        Notify()
    end)
end

local function ObservePost(commodity, location, duration, quantity, bid, buyout)
    if not Sales.open or Sales.pending or not Addon.character or not location or not durationHours[duration]
        or type(quantity) ~= "number" or quantity < 1 then return end
    local key = C_AuctionHouse.GetItemKeyFromItem(location)
    if not key then return end
    local price = commodity and bid or buyout
    if type(price) ~= "number" or price <= 0 then return end
    local marketKey, purchase = Market:ItemKey(key)
    for _, candidate in ipairs(Resale:Ledger().purchases) do
        if candidate.marketKey == marketKey and candidate.quantity >= quantity then
            if purchase then return end
            purchase = candidate
        end
    end
    if not purchase then return end
    local deposit = Deposit(location, key.itemID, quantity, commodity, duration)
    if type(deposit) ~= "number" then return end
    local post = { purchase = purchase, quantity = quantity, price = price, bid = not commodity and bid or nil,
        deposit = deposit, before = Resale:ItemCount(key.itemID), hours = durationHours[duration] }
    Sales.pending = post
    C_Timer.After(20, function()
        if Sales.pending == post then Sales.pending = nil; Notify() end
    end)
end

local function RecordListing()
    local post = Sales.pending
    if not post or not post.created then return end
    local purchase = post.purchase
    if post.before - Resale:ItemCount(purchase.itemID) ~= post.quantity then return end
    local entry = { auctionID = post.auctionID, itemID = purchase.itemID, name = purchase.name, quantity = post.quantity,
        unitCost = purchase.unitCost, price = post.price, bid = post.bid, deposit = post.deposit, at = Market:Now(),
        hours = post.hours }
    local ledger = Resale:Ledger()
    purchase.quantity = purchase.quantity - post.quantity
    if purchase.quantity <= 0 then
        for i, candidate in ipairs(ledger.purchases) do
            if candidate == purchase then table.remove(ledger.purchases, i); break end
        end
    end
    if Resale:Settings().trackSales ~= false then ledger.listings[#ledger.listings + 1] = entry end
    Sales.pending, Sales.message = nil, "Listing confirmed."
end

local function RecordMail(index)
    local _, _, _, subject, money, cod, days, attachments = GetInboxHeaderInfo(index)
    if type(days) ~= "number" or days <= 0 then return end
    local kind, name, _, bid, buyout, deposit, cut = GetInboxInvoiceInfo(index)
    local price = type(buyout) == "number" and buyout > 0 and buyout or bid
    local at = Market:Now() - math.max(0, MAIL_DAYS - days) * 86400
    local received, quantity, itemID
    local expiration = AUCTION_EXPIRED_MAIL_SUBJECT and AUCTION_EXPIRED_MAIL_SUBJECT:match("^(.-)%%s")
    if kind == "seller" and type(money) == "number" and money > 0
        and type(price) == "number" and type(deposit) == "number" and type(cut) == "number"
        and price + deposit - cut == money then
        received = money
    elseif expiration and expiration ~= "" and subject and subject:sub(1, #expiration) == expiration
        and money == 0 and cod == 0 and attachments == 1 then
        local _, id, _, count = GetInboxItem(index, 1)
        itemID, quantity = id, count
    else
        return
    end
    local ledger, match = Resale:Ledger()
    local invoice
    if received then
        invoice = table.concat({ "sale", name or "", price, deposit, cut }, ":")
    elseif itemID and quantity then
        invoice = table.concat({ "expiry", itemID, quantity, subject }, ":")
    else
        return
    end
    for _, outcome in ipairs(ledger.outcomes) do
        if outcome.invoice == invoice and math.abs(outcome.at - at) <= 120 then return end
    end
    for i, listing in ipairs(ledger.listings) do
        local deadline = listing.at + (listing.hours or 8) * 3600
        local sameTime = at >= listing.at - 120 and at <= deadline + 3600
        local sold = received and listing.name == name
            and (listing.price * listing.quantity == price or (listing.bid and listing.bid == price))
            and deposit == listing.deposit
        local expired = itemID and listing.itemID == itemID and listing.quantity == quantity
            and at >= deadline - 120
        if sameTime and (sold or expired) then
            if match then return end
            match = i
        end
    end
    if not match then return end
    local listing = table.remove(ledger.listings, match)
    local cost = listing.unitCost * listing.quantity
    ledger.outcomes[#ledger.outcomes + 1] = { name = listing.name, itemID = listing.itemID, quantity = listing.quantity,
        cost = cost, at = at, invoice = invoice, sold = received ~= nil,
        profit = received and received - listing.deposit - cost or -listing.deposit }
    if #ledger.outcomes > 100 then table.remove(ledger.outcomes, 1) end
end

local function ReadInbox()
    if Resale:Settings().trackSales == false then return end
    local ledger = Resale:Ledger()
    if #ledger.listings == 0 or not GetInboxNumItems then return end
    for index = 1, GetInboxNumItems() do RecordMail(index) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "MAIL_INBOX_UPDATE", "MAIL_SHOW",
    "PLAYER_MONEY", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "BAG_UPDATE_DELAYED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if not Addon.character then return end
    if event == "PLAYER_LOGIN" then
        local ah = C_AuctionHouse
        if ah and hooksecurefunc then
            if ah.PostCommodity then hooksecurefunc(ah, "PostCommodity", function(...) ObservePost(true, ...) end) end
            if ah.PostItem then hooksecurefunc(ah, "PostItem", function(...) ObservePost(false, ...) end) end
        end
        return
    elseif event == "AUCTION_HOUSE_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        and Enum.PlayerInteractionType and arg == Enum.PlayerInteractionType.Auctioneer) then
        Sales.open, Sales.message = true, nil
        C_Timer.After(0, Notify)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Sales.open, Sales.query, Sales.quote = nil, nil, nil
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        Sales:ReadResults(event == "COMMODITY_SEARCH_RESULTS_UPDATED", arg)
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" and Sales.pending then
        local post = Sales.pending
        local info = type(arg) == "number" and C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(arg)
        if not info or not info.itemKey or Market:ItemKey(info.itemKey) == post.purchase.marketKey then
            post.created, post.auctionID = true, arg
            RecordListing()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        RecordListing()
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" and Sales.pending then
        Sales.pending, Sales.message = nil, "The Auction House rejected the listing. Check before retrying."
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        ReadInbox()
    end
    Notify()
end)
