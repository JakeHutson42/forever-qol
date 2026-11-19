local addonName, Addon = ...
local frame = CreateFrame("Frame")
local Deals = { rows = {}, purchasedAuctions = {}, status = "Scan the Auction House to find items below vendor value." }
local Gaps = Addon.AuctionPriceGaps
Addon.VendorDeals = Deals

local function Update(message, gap)
    if message then
        if gap or Deals.mode == "gap" then Gaps.status = message
        else Deals.status = message end
    end
    if Addon.RefreshVendorDealsTab then Addon:RefreshVendorDealsTab() end
    if Addon.AuctionScanner then Addon.AuctionScanner:Resume() end
end

function Addon:GetVendorDealSettings()
    if type(self.db.vendorDeals) ~= "table" then self.db.vendorDeals = {} end
    local settings = self.db.vendorDeals
    settings.enabled = settings.enabled ~= false
    if type(settings.reserve) ~= "number" or not (settings.reserve >= 0 and settings.reserve <= 9999999990000) then
        settings.reserve = 0
    end
    return settings
end

local auctionDefaults = {
    vendorMinimum = { 0, 0, 100000000 }, gapDiscount = { 15, 1, 99 }, gapUnits = { 200, 1, 10000 },
    gapSupport = { 5, 1, 10000 }, gapAge = { 15, 1, 120 }, category = { 7, 0, 20 },
    historyDays = { 30, 14, 90 }, typicalDays = { 7, 2, 14 },
}

function Addon:GetAuctionSettings()
    if type(self.db.auctionSettings) ~= "table" then self.db.auctionSettings = {} end
    local settings = self.db.auctionSettings
    if self.validatedAuctionSettings == settings then return settings end
    for key, rule in pairs(auctionDefaults) do
        local value = settings[key]
        if type(value) ~= "number" or not (value >= rule[2] and value <= rule[3]) then settings[key] = rule[1] end
    end
    self.validatedAuctionSettings = settings
    return settings
end

local equipmentFilters = {
    [0] = { [2] = "showGreyWeapons", [4] = "showGreyArmour" },
    [1] = { [2] = "showWhiteWeapons", [4] = "showWhiteArmour" },
}

function Deals:IsItemVisible(row)
    local quality, classID = row.quality, row.classID
    if (quality == nil or classID == nil) and C_Item and C_Item.GetItemInfo then
        local _, _, itemQuality, _, _, _, _, _, _, _, _, itemClass = C_Item.GetItemInfo(row.link or row.key.itemID)
        quality, classID = quality or itemQuality, classID or itemClass
        row.quality, row.classID = quality, classID
    end
    local key = equipmentFilters[quality] and equipmentFilters[quality][classID]
    return not key or Addon:GetVendorDealSettings()[key] ~= false
end

function Deals:VisibleRows()
    local minimum = Addon:GetAuctionSettings().vendorMinimum
    local rows = {}
    for _, row in ipairs(self.rows) do
        if not row.depleted and row.vendor - row.price >= minimum and self:IsItemVisible(row) then
            rows[#rows + 1] = row
        end
    end
    return rows
end

function Deals:AvailableGold()
    local reserve = (self.mode == "budget" or self.mode == "gap") and Addon:GetVendorDealSettings().reserve or 0
    return math.max(0, GetMoney() - reserve)
end

function Deals:Cancel(message)
    local gap = self.mode == "gap"
    local cancelQuote = self.stage == "quote" or self.stage == "confirmCommodity"
    self.queue, self.search, self.purchase, self.offers = nil, nil, nil, nil
    self.stage, self.mode, self.quote, self.quoteRequest = nil, nil, nil, nil
    if cancelQuote then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
    Update(message, gap)
end

local function KeyString(key)
    return table.concat({ key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0 }, ":")
end

local function ScanEntry(entry, replicate)
    if not replicate then return entry.itemKey, entry.minPrice, entry.totalQuantity, entry.itemLink end
    local data = entry.replicateInfo
    local link = entry.itemLink
    local quantity = data and data[3]
    if not quantity or quantity <= 0 or not data[17] or not data[10] then return end
    if link and link:find("battlepet:", 1, true) then return end
    local suffix = link and link:match("item:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:]*)")
    return C_AuctionHouse.MakeItemKey(data[17], 0, tonumber(suffix) or 0), data[10] / quantity, quantity, link
end

function Deals:BeginSnapshot(replicate, marketScope, coverage, native)
    local token, rows, byKey, itemInfo, missing = {}, {}, {}, {}, {}
    local market = Addon.VendorResaleMarket
    local scan = market:StartScan(replicate, marketScope)
    scan.gaps, scan.coverage = {}, coverage
    local previousDeals, previousGaps = Deals.rows, Gaps.rows
    local previousGapTime, previousGapScope = Gaps.at, Gaps.scope
    Gaps.scanning = true
    Deals.scanRun = token
    if Addon:GetVendorDealSettings().enabled then
        Deals.snapshot = token
        Deals.scanning = true
        if not native then Deals:Cancel("Checking vendor prices from the scan…") end
    end
    local function Check(key, price, link, quantity, tiers)
        local metadata = itemInfo[key.itemID]
        if not metadata then
            local name, itemLink, quality, _, _, _, _, _, _, icon, vendor, classID = C_Item.GetItemInfo(link or key.itemID)
            if vendor == nil then return false end
            metadata = { name = name, link = itemLink, vendor = vendor, quality = quality, icon = icon, classID = classID }
            itemInfo[key.itemID] = metadata
        end
        if metadata.vendor > price then
            local id = KeyString(key)
            local row = byKey[id]
            if not row then
                local info = C_AuctionHouse.GetItemKeyInfo(key)
                row = { key = key, name = info and info.itemName or metadata.name or tostring(key.itemID),
                    link = link or metadata.link, vendor = metadata.vendor, price = price,
                    icon = info and info.iconFileID or metadata.icon, quality = info and info.quality or metadata.quality,
                    scope = scan.scope, classID = metadata.classID or coverage and coverage.classID, quantity = 0 }
                byKey[id], rows[#rows + 1] = row, row
            elseif price < row.price then
                row.price, row.link = price, link or row.link
            end
            local eligible
            if tiers then
                eligible = 0
                for _, tier in ipairs(tiers) do
                    if not tier.owned and metadata.vendor - tier.price >= Addon:GetAuctionSettings().vendorMinimum
                        and tier.price < metadata.vendor then eligible = eligible + tier.quantity end
                end
            end
            row.quantity = row.quantity + (eligible or quantity or 0)
            row.quantityKnown = tiers ~= nil or replicate
        end
        return true
    end
    local function Publish(unavailable, preview)
        local visible = {}
        if coverage then
            for _, row in ipairs(previousDeals) do
                if row.scope == scan.scope and not scan.items[KeyString(row.key)]
                    and not market:Covered(coverage, KeyString(row.key), row) then visible[#visible + 1] = row end
            end
        end
        for _, row in ipairs(rows) do visible[#visible + 1] = row end
        table.sort(visible, function(a, b)
            local left, right = a.vendor - a.price, b.vendor - b.price
            if left == right then return a.name < b.name end
            return left > right
        end)
        Deals.rows, Deals.scanning = visible, preview == true
        local message = #visible > 0 and ("%d candidates. Use Buy to check live prices."):format(#visible)
            or "No listings below vendor value were found."
        if unavailable > 0 then message = message .. (" Vendor prices unavailable for %d item types."):format(unavailable) end
        Update(message)
    end
    local session = {}
    function session:Push(entries, first, last)
        if Deals.scanRun ~= token then return false end
        local checkDeals = Deals.snapshot == token
        for i = first or 1, last or #entries do
            local entry = entries[i]
            local key, price, quantity, link = ScanEntry(entry, replicate)
            if key and price and price > 0 and quantity and quantity > 0 and (key.battlePetSpeciesID or 0) == 0 then
                local id = market:ItemKey(key)
                market:AddObservation(scan, id, price, quantity, entry.observedAt)
                if coverage and coverage.classID then scan.items[id].classID = coverage.classID end
                if entry.tiers then
                    for _, tier in ipairs(entry.tiers) do
                        if tier.price == price then scan.items[id].atFloor = tier.marketQuantity; break end
                    end
                end
                Gaps:Add(scan, key, price, quantity, link, entry.tiers, entry.observedAt)
                if checkDeals and not Check(key, price, link, quantity, entry.tiers) then
                    local requests = missing[key.itemID]
                    if not requests then
                        requests = {}
                        missing[key.itemID] = requests
                        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(key.itemID) end
                    end
                    requests[#requests + 1] = { key = key, price = price, link = link, quantity = quantity, tiers = entry.tiers }
                end
            end
        end
        return true
    end
    function session:Preview(showGaps)
        if Deals.scanRun ~= token then return end
        if showGaps then Gaps:Publish(scan, previousGaps, true) end
        if Deals.snapshot == token then Publish(0, true) else Update() end
    end
    function session:Cancel()
        if Deals.scanRun ~= token then return end
        Deals.scanRun, Deals.snapshot = nil, nil
        Deals.rows, Gaps.rows = previousDeals, previousGaps
        Gaps.at, Gaps.scope = previousGapTime, previousGapScope
        Deals.scanning, Gaps.scanning = false, false
        Update()
    end
    function session:Finish()
        if Deals.scanRun ~= token then return end
        market:SaveScan(scan)
        Gaps:Publish(scan, previousGaps)
        Update()
        if Deals.snapshot ~= token then return end
        if not next(missing) then Publish(0); return end
        if native then Publish(0) end
        C_Timer.After(2, function()
            if Deals.snapshot ~= token then return end
            local unavailable = 0
            for _, requests in pairs(missing) do
                for _, request in ipairs(requests) do
                    if not Check(request.key, request.price, request.link, request.quantity, request.tiers) then
                        unavailable = unavailable + 1
                        break
                    end
                end
            end
            Publish(unavailable)
        end)
    end
    return session
end

local function BuildSnapshot(entries, replicate, marketScope)
    Deals.importing = true
    local session = Deals:BeginSnapshot(replicate, marketScope)
    local index = 1
    local function Process()
        local last = math.min(index + 249, #entries)
        if not session:Push(entries, index, last) then return end
        index = last + 1
        if index <= #entries then C_Timer.After(0, Process)
        else Deals.importing = nil; session:Finish() end
    end
    C_Timer.After(0, Process)
end

local function LiveOffers(row, commodity)
    local ah, offers = C_AuctionHouse, {}
    local itemID = row.key.itemID
    local minimum = Addon:GetAuctionSettings().vendorMinimum
    local count = commodity and ah.GetNumCommoditySearchResults(itemID) or ah.GetNumItemSearchResults(row.key)
    for index = 1, count do
        local result
        if commodity then result = ah.GetCommoditySearchResultInfo(itemID, index)
        else result = ah.GetItemSearchResultInfo(row.key, index) end
        if result and not Deals.purchasedAuctions[result.auctionID] and not result.containsOwnerItem and not result.containsAccountItem
            and result.quantity and result.quantity > 0 then
            local unitPrice = commodity and result.unitPrice or nil
            local cost = unitPrice and unitPrice * result.quantity or not commodity and result.buyoutAmount
            local vendor = row.vendor
            if not commodity and result.itemLink then vendor = select(11, C_Item.GetItemInfo(result.itemLink)) end
            local profit = cost and vendor and vendor * result.quantity - cost
            if cost and cost > 0 and profit and profit > 0 and profit >= minimum * result.quantity
                and (commodity or result.auctionID) then
                offers[#offers + 1] = { deal = row, auctionID = not commodity and result.auctionID or nil,
                    link = result.itemLink, seller = not commodity and result.owners and result.owners[1] or nil,
                    quantity = result.quantity, cost = cost, profit = profit, vendor = vendor, unitPrice = unitPrice }
            end
        end
    end
    table.sort(offers, function(a, b) return (a.unitPrice or a.cost) > (b.unitPrice or b.cost) end)
    return offers
end

local function AdvanceRow(message)
    local queue = Deals.queue
    if not queue then return end
    Deals.search, Deals.purchase, Deals.offers, Deals.stage, Deals.quote = nil, nil, nil, nil, nil
    queue.index = queue.index + 1
    if not queue[queue.index] then Deals:Cancel(Deals.mode == "gap" and message or message .. " Queue finished.")
    else Update(message) end
end

local function Ready()
    return C_AuctionHouse.IsThrottledMessageSystemReady()
end

local function RunAuctionAction(action, ...)
    local ok, reason = pcall(action, ...)
    if not ok then Addon:Print(tostring(reason)) end
    return ok
end

local function AuctionError(code, fallback)
    if type(code) ~= "number" or (issecretvalue and issecretvalue(code)) then return fallback end
    local text = AuctionHouseUtil and AuctionHouseUtil.GetErrorText and AuctionHouseUtil.GetErrorText(code)
    if text and text ~= "" then return text end
    return ("%s (Auction House error %d)"):format(fallback, code)
end

local function SendSearch()
    local search = Deals.search
    if not search or search.sent or (Addon.AuctionScanner and Addon.AuctionScanner:HasFlight())
        or Addon.VendorResaleAuctions.query or not Ready() then return end
    local ah, key = C_AuctionHouse, search.row.key
    if not ah.GetItemKeyInfo(key) then return end
    local price = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    search.sent = true
    C_Timer.After(8, function()
        if Deals.search == search and search.sent then AdvanceRow("The live price check timed out.") end
    end)
    if not RunAuctionAction(ah.SendSearchQuery, key, price and { { sortOrder = price, reverseSort = false } } or {}, true)
        and Deals.search == search then
        AdvanceRow("The Auction House could not check this item.")
    end
end

function Deals:ResumeSearch()
    SendSearch()
end

local function StageItem(message)
    local offers = Deals.offers
    local purchase, gold = nil, Deals:AvailableGold()
    while #offers > 0 do
        local offer = table.remove(offers)
        if offer.cost <= gold then purchase = offer; break end
    end
    if not purchase then AdvanceRow(message or "No profitable auctions fit your available gold."); return end
    Deals.purchase, Deals.stage = purchase, "confirmItem"
    Update(message or "Live buyout ready. Review the price and confirm.")
end

local function StageCommodity(row, offers)
    local gold = Deals:AvailableGold()
    local order = { deal = row, quantity = 0, cost = 0, profit = 0, vendor = row.vendor }
    for index = #offers, 1, -1 do
        local offer = offers[index]
        local price = offer.unitPrice
        local quantity = math.min(offer.quantity, math.floor((gold - order.cost) / price))
        if quantity < 1 then break end
        order.quantity = order.quantity + quantity
        order.cost = order.cost + quantity * price
        order.profit = order.profit + quantity * (offer.vendor - price)
        order.unitPrice = price
    end
    if not order.unitPrice then AdvanceRow("No profitable units fit your available gold."); return end
    Deals.purchase, Deals.stage = order, "quoteReady"
    Update("Request the Auction House quote for this quantity.")
end

local function ReadSearch(event, key)
    local search = Deals.search
    if not search or not search.sent then return end
    local row = search.row
    local commodity = event == "COMMODITY_SEARCH_RESULTS_UPDATED"
    if commodity then
        if key ~= row.key.itemID then return end
    elseif type(key) ~= "table" or KeyString(key) ~= KeyString(row.key) then
        return
    end
    if row.gap then
        if not commodity then
            AdvanceRow("Price Gaps checks commodities.")
            return
        end
        local order = Gaps:LiveOrder(row, Deals:AvailableGold())
        local full = C_AuctionHouse.HasFullCommoditySearchResults
        if not order and not search.retried and full and not full(key) then
            search.retried, search.sent = true, false
            SendSearch()
            return
        end
        Deals.search = nil
        if not order then
            AdvanceRow("The live price gap closed or no units fit your available gold.")
        else
            Deals.purchase, Deals.stage = order, "quoteReady"
            Update("Live gap verified. Get a quote for the discounted units.")
        end
        return
    end
    local offers = LiveOffers(row, commodity)
    local ah = C_AuctionHouse
    local full = commodity and ah.HasFullCommoditySearchResults or ah.HasFullItemSearchResults
    -- Some searches return an empty, incomplete page before the real results arrive.
    if #offers == 0 and not search.retried and full and not full(key) then
        search.retried, search.sent = true, false
        SendSearch()
        return
    end
    Deals.search = nil
    row.quantity, row.quantityKnown = 0, true
    for _, offer in ipairs(offers) do row.quantity = row.quantity + offer.quantity end
    row.depleted = row.quantity == 0
    if #offers == 0 then
        AdvanceRow("No profitable live listings for this item.")
    elseif commodity then
        StageCommodity(row, offers)
    else
        Deals.offers = offers
        StageItem()
    end
end

function Deals:Prepare(mode, row)
    local gap = row and row.gap
    if row and not gap and not self:IsItemVisible(row) then return end
    local native = row and Addon.AuctionScanner.job
    if (not native and ((gap and Gaps.scanning) or (not gap and self.scanning))) or self.queue or self.pending
        or (not row and #self:VisibleRows() == 0) then return end
    if row and row.gap then
        if not row.manual and not Gaps:IsCurrent(row) then Update("Run a new scan or check a specific commodity.", true); return end
        mode = "gap"
    end
    local queue = { index = 1 }
    if row then queue[1] = row
    else
        for _, candidate in ipairs(self:VisibleRows()) do queue[#queue + 1] = candidate end
    end
    self.queue, self.mode = queue, mode
    Addon.AuctionScanner.last = nil
    Update("Queue ready. Buy Next checks the first item's live price.")
    if row then self:BuyNext() end
end

local function Acceptable(purchase, total, unitPrice)
    return type(total) == "number" and total > 0 and total <= purchase.cost and total <= Deals:AvailableGold()
        and (purchase.deal.gap or total < purchase.vendor * purchase.quantity)
        and (not unitPrice or (type(unitPrice) == "number" and unitPrice > 0 and unitPrice <= purchase.unitPrice))
end

local function CompletePurchase(message)
    local gap = Deals.pending and Deals.pending.deal.gap
    Deals.pending = nil
    Deals.stage, Deals.quote = nil, nil
    if not Deals.queue then Update(message, gap); return end
    if Deals.offers then StageItem(message)
    else AdvanceRow(message) end
end

function Deals:BuyNext()
    if not self.queue or self.pending or InCombatLockdown() then return end
    local api, purchase = C_AuctionHouse, self.purchase
    if not self.stage then
        local search = { row = self.queue[self.queue.index] }
        self.search, self.stage = search, "search"
        Update("Checking live listings…")
        C_Timer.After(25, function()
            if self.search == search and not search.sent then AdvanceRow("The Auction House stayed busy. Check again.") end
        end)
        SendSearch()
    elseif self.stage == "quoteReady" then
        if not Ready() then Update("Auction House is busy. Try Get Quote again."); return end
        if not Acceptable(purchase, purchase.cost) then self:Skip("This quantity no longer fits your gold."); return end
        self.stage = "quote"
        local quoteRequest = {}
        self.quoteRequest = quoteRequest
        -- On Forever the clicked button must remain enabled until the action is sent.
        local ok = RunAuctionAction(api.StartCommoditiesPurchase, purchase.deal.key.itemID, purchase.quantity)
        if self.quoteRequest ~= quoteRequest or self.stage ~= "quote" then return end
        if not ok then
            self:Skip("The commodity quote call failed. See chat for the client error.")
            return
        end
        Update("Waiting for the commodity quote…")
        C_Timer.After(8, function()
            if self.quoteRequest == quoteRequest and self.stage == "quote" then self:Skip("The commodity quote timed out.") end
        end)
    elseif self.stage == "confirmItem" or self.stage == "confirmCommodity" then
        local commodity = self.stage == "confirmCommodity"
        local total = commodity and self.quote or purchase.cost
        if not Acceptable(purchase, total) then self:Skip("This purchase no longer fits your gold."); return end
        if commodity then
            local remaining = api.GetQuoteDurationRemaining and api.GetQuoteDurationRemaining()
            if type(remaining) == "number" and remaining <= 0 then
                self:Skip("That commodity quote expired."); return
            end
        else
            local live
            for _, offer in ipairs(LiveOffers(purchase.deal, false)) do
                if offer.auctionID == purchase.auctionID and offer.quantity == purchase.quantity then live = offer; break end
            end
            if not live or not Acceptable(purchase, live.cost) then
                StageItem("That auction is gone or its buyout increased."); return
            elseif live.cost ~= purchase.cost then
                self.purchase = live
                Update("The buyout dropped. Review the new price and confirm.")
                return
            end
        end
        self.pending, self.stage = purchase, nil
        purchase.paid = total
        local ok
        -- Submit before refreshing the tab, which disables the confirming button.
        if commodity then ok = RunAuctionAction(api.ConfirmCommoditiesPurchase, purchase.deal.key.itemID, purchase.quantity)
        else ok = RunAuctionAction(api.PlaceBid, purchase.auctionID, total) end
        if self.pending ~= purchase then return end
        if not ok then
            CompletePurchase("The purchase call failed. See chat for the client error.")
            if commodity then RunAuctionAction(api.CancelCommoditiesPurchase) end
            return
        end
        Update("Purchase submitted. Waiting for the Auction House…")
        C_Timer.After(8, function()
            if self.pending == purchase then
                self.pending = nil
                self:Cancel("Purchase result unknown. Check your gold and auction mail before rebuilding the queue.")
            end
        end)
    end
end

function Deals:Skip(message)
    if not self.queue or self.pending then return end
    local cancelQuote = self.stage == "quote" or self.stage == "confirmCommodity"
    self.quoteRequest = nil
    if self.stage == "confirmItem" and self.offers then StageItem(message or "Buyout skipped.")
    else AdvanceRow(message or "Item skipped.") end
    if cancelQuote then RunAuctionAction(C_AuctionHouse.CancelCommoditiesPurchase) end
end

function Deals:ConnectAuctionator()
    if Addon:GetAuctionSettings().importAuctionator == false then return false end
    if self.connected then return true end
    local auctionator = Auctionator
    local summary = auctionator and auctionator.IncrementalScan and auctionator.IncrementalScan.Events
    local full = auctionator and auctionator.FullScan and auctionator.FullScan.Events
    if not summary or not summary.ScanComplete or not full or not full.ScanComplete or not auctionator.EventBus then return false end
    local listener = {}
    function listener:ReceiveEvent(event, data)
        if Addon:GetAuctionSettings().importAuctionator == false then return end
        local dealsEnabled = Addon:GetVendorDealSettings().enabled
        if event == summary.ScanStart or event == full.ScanStart then
            if Addon.AuctionScanner.job then Addon.AuctionScanner:Stop() end
            local pending = {}
            Deals.importing = pending
            C_Timer.After(60, function()
                if Deals.importing ~= pending then return end
                Deals.importing, Deals.scanning, Gaps.scanning = nil, false, false
                Gaps.status = "Auctionator did not finish. Start a native scan to refresh prices."
                Update("Auctionator did not finish. Start a native scan to refresh prices.")
            end)
            Deals.scanRun = nil
            Gaps.scanning, Gaps.status = true, "Auctionator scan in progress…"
            self.marketScope = Addon.VendorResaleMarket:ScanContext()
            if dealsEnabled then
                Deals.snapshot, Deals.scanning = nil, true
                Deals:Cancel("Auctionator scan in progress…")
            else
                Update()
            end
        elseif event == summary.ScanFailed or event == full.ScanFailed then
            Deals.importing = nil
            self.marketScope = nil
            Gaps.scanning, Gaps.status = false, "Auctionator's scan did not finish. Check an item or run Full Scan again."
            if dealsEnabled then
                Deals.scanning = false
                Update("Auctionator's scan did not finish. Run Full Scan again.")
            else
                Update()
            end
        elseif type(data) == "table" then
            if Addon.AuctionScanner.job then self.marketScope = nil; return end
            Deals.importing = nil
            BuildSnapshot(data, event == full.ScanComplete, self.marketScope)
            self.marketScope = nil
        else
            Deals.importing = nil
            self.marketScope = nil
            Gaps.scanning, Gaps.status = false, "Auctionator did not provide scan results."
            if dealsEnabled then
                Deals.scanning = false
                Update("Auctionator did not provide scan results.")
            else
                Update()
            end
        end
    end
    auctionator.EventBus:Register(listener, { summary.ScanStart, summary.ScanComplete, summary.ScanFailed,
        full.ScanStart, full.ScanComplete, full.ScanFailed })
    self.connected = true
    return true
end

for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "AUCTION_HOUSE_CLOSED", "PLAYER_MONEY",
    "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "ITEM_KEY_ITEM_INFO_RECEIVED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
    "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE" }) do
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, first, second)
    if not Addon.db then return end
    if event == "AUCTION_HOUSE_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        and Enum.PlayerInteractionType and first == Enum.PlayerInteractionType.Auctioneer) then
        C_Timer.After(0, function()
            if Addon:GetVendorDealSettings().enabled then Addon:CreateVendorDealsTab() end
        end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Deals.importing = nil
        if Deals.pending then
            Deals:Cancel("Auction House closed during a purchase. Check your gold and auction mail.")
        elseif Deals.queue then
            Deals:Cancel("Auction House closed. Check live deals before buying again.")
        end
    elseif event == "PLAYER_MONEY" then
        if Deals.queue then Update() end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" or event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        SendSearch()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        ReadSearch(event, first)
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if first ~= addonName or type(second) ~= "string" then return end
        if Deals.pending and (second:find("PlaceBid", 1, true) or second:find("ConfirmCommoditiesPurchase", 1, true)) then
            CompletePurchase("WoW blocked the purchase call (" .. second .. ").")
        elseif Deals.stage == "quote" and second:find("StartCommoditiesPurchase", 1, true) then
            Deals:Skip("WoW blocked the commodity quote call.")
        end
    elseif event == "UI_ERROR_MESSAGE" then
        if Deals.pending and type(second) == "string" and not (issecretvalue and issecretvalue(second))
            and (second == ERR_AUCTION_DATABASE_ERROR or second == ERR_AUCTION_HIGHER_BID or second == ERR_ITEM_NOT_FOUND
                or second == ERR_AUCTION_BID_OWN or second == ERR_NOT_ENOUGH_MONEY or second == ERR_ITEM_MAX_COUNT) then
            CompletePurchase(second)
        end
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" or event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local purchase = Deals.pending
        local commodity = event == "COMMODITY_PURCHASE_SUCCEEDED"
        if purchase and ((commodity and purchase.unitPrice)
            or (not commodity and purchase.auctionID and first == purchase.auctionID)) then
            if purchase.auctionID then Deals.purchasedAuctions[purchase.auctionID] = true end
            local row = purchase.deal
            row.quantity = math.max(0, (row.quantity or purchase.quantity) - purchase.quantity)
            row.depleted = row.quantity == 0
            if purchase.deal.gap then
                CompletePurchase("Purchase confirmed. Collect the mail for resale review. Target per item: "
                    .. GetMoneyString(purchase.target, true) .. ".")
            else
                CompletePurchase("Purchase confirmed. Collect the auction mail as usual.")
            end
            Addon:RecordVendorFlipPurchase(purchase, purchase.paid)
        else
            local auctionInfo = not commodity and first and C_AuctionHouse.GetAuctionInfoByID
                and C_AuctionHouse.GetAuctionInfoByID(first)
            local itemID = auctionInfo and auctionInfo.itemKey and auctionInfo.itemKey.itemID
            Addon:RecordOtherAuctionPurchase(commodity, itemID)
        end
    elseif Deals.pending and (event == "AUCTION_HOUSE_SHOW_ERROR"
        or (event == "COMMODITY_PURCHASE_FAILED" and Deals.pending.unitPrice)) then
        CompletePurchase(AuctionError(first, "The Auction House rejected that purchase."))
    elseif Deals.queue then
        local purchase = Deals.purchase
        local awaitingQuote = Deals.stage == "quote" or Deals.stage == "confirmCommodity"
        if event == "COMMODITY_PRICE_UPDATED" and awaitingQuote then
            if type(first) == "number" and type(second) == "number" and Acceptable(purchase, second, first) then
                Deals.stage, Deals.quote = "confirmCommodity", second
                Update("Current quote verified. Confirm to make the purchase.")
                local request = Deals.quoteRequest
                local duration = C_AuctionHouse.GetQuoteDurationRemaining
                    and C_AuctionHouse.GetQuoteDurationRemaining()
                C_Timer.After(type(duration) == "number" and math.max(0, duration) or 12, function()
                    if Deals.stage == "confirmCommodity" and Deals.quoteRequest == request then
                        Deals:Skip("The commodity quote expired.")
                    end
                end)
            else
                Deals:Skip("The new commodity price exceeds the planned price or available gold.")
            end
        elseif awaitingQuote and event == "AUCTION_HOUSE_SHOW_ERROR" then
            Deals:Skip(AuctionError(first, "The Auction House rejected the commodity quote."))
        elseif awaitingQuote and event == "COMMODITY_PRICE_UNAVAILABLE" then
            Deals:Skip("That commodity quantity is no longer available.")
        end
    end
end)
