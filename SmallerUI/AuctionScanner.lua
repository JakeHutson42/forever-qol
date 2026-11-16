local _, Addon = ...
local Deals, Market, Gaps = Addon.VendorDeals, Addon.VendorResaleMarket, Addon.AuctionPriceGaps
local Scanner = {}
Addon.AuctionScanner = Scanner

local TIMEOUT = 12
local ESTIMATE_AGE = 7 * 24 * 60 * 60
local frame = CreateFrame("Frame")

local function Update()
    if Addon.RefreshVendorDealsTab then Addon:RefreshVendorDealsTab() end
    if Addon.RefreshVendorResaleAuctions then Addon:RefreshVendorResaleAuctions() end
end

local function Settings()
    if type(Addon.db.auctionWatchlist) ~= "table" then Addon.db.auctionWatchlist = {} end
    return Addon.db.auctionWatchlist
end

function Scanner:Watchlist()
    return Settings()
end

function Scanner:ToggleWatch(row)
    local list = Settings()
    for i, item in ipairs(list) do
        if item.key.itemID == row.key.itemID then table.remove(list, i); return false end
    end
    list[#list + 1] = { key = row.key, name = row.name }
    return true
end

function Scanner:HasFlight()
    return self.flight ~= nil or self.draining ~= nil
end

function Scanner:GetProgress()
    local job = self.job
    if not job then return self.last and self.outcome end
    local elapsed = math.max(0, GetTime() - job.started)
    local total = job.keys and #job.keys or job.expected
    if not job.keys and total and job.count >= total then total = nil end
    local sales = Addon.VendorResaleAuctions
    local paused = Deals.queue or Deals.pending or self.priority or sales.query or sales.pending or InCombatLockdown()
    local eta
    if not paused and total and job.count > 0 and job.countedAt and job.countedAt >= 1 then
        local remaining = job.countedAt * total / job.count - elapsed
        if remaining > 0 then eta = math.ceil(remaining) end
    end
    return {
        label = job.label, state = paused and "paused" or "running", count = job.count, total = total,
        estimated = not job.keys, elapsed = elapsed, fraction = total and job.count / total,
        eta = eta,
    }
end

function Scanner:Resume()
    if not (self.job or self.priority or Deals.search) or self.scheduled then return end
    self.scheduled = true
    C_Timer.After(0, function()
        self.scheduled = nil
        self:Pump()
    end)
end

function Scanner:Finish(message, success)
    local job = self.job
    if not job then return end
    if self.flight then
        local flight = self.flight
        self.draining, self.flight = flight, nil
        C_Timer.After(TIMEOUT, function()
            if self.draining == flight then self.draining = nil; self:Resume() end
        end)
    end
    local progress = self:GetProgress()
    progress.state, progress.message, progress.eta = success and "complete" or "ended", message, nil
    progress.requests, progress.first = job.requests, job.first
    if success then
        progress.fraction, progress.total, progress.estimated = 1, job.keys and #job.keys or job.count, false
    end
    self.outcome, self.job = progress, nil
    if success then job.snapshot:Finish() else job.snapshot:Cancel() end
    if success and not job.keys then
        local book = Market:GetBook(job.scope, true)
        book.scanSizes = book.scanSizes or {}
        book.scanSizes[job.classID or "all"] = { count = job.count, at = Market:Now() }
    end
    local seconds = math.max(0, GetTime() - job.started)
    local first = job.first and (" · first results %.1fs"):format(job.first) or ""
    self.last = ("%s · %s · %d %s in %.1fs%s"):format(job.label, message, job.requests,
        job.requests == 1 and "request" or "requests", seconds, first)
    Update()
    self:Resume()
end

function Scanner:Stop()
    self:Finish("Stopped", false)
end

local function CanStart(scanner)
    local sales = Addon.VendorResaleAuctions
    return AuctionHouseFrame and AuctionHouseFrame:IsShown() and not InCombatLockdown() and not scanner.job
        and not scanner:HasFlight() and not Deals.queue and not Deals.pending and not sales.pending and not sales.query
        and not Deals.importing
end

function Scanner:Start(label, classID, keys, watchlist)
    if not CanStart(self) then return false end
    if keys and #keys == 0 then
        self.outcome = nil
        self.last = label .. " · No items to scan."
        Update()
        return false
    end
    local coverage, context = nil, Market:ScanContext()
    if keys then
        coverage = { keys = {} }
        for _, key in ipairs(keys) do coverage.keys[Market:ItemKey(key)] = true end
    elseif classID then
        coverage = { classID = classID }
    end
    self.last, self.outcome = nil, nil
    local book = not keys and Market:GetBook(context.scope)
    local sample = book and book.scanSizes and book.scanSizes[classID or "all"]
    local expected = sample and sample.count > 0 and Market:Now() - sample.at <= ESTIMATE_AGE and sample.count or nil
    self.job = { label = label, classID = classID, keys = keys, index = 1, phase = keys and "item" or "browse",
        scope = context.scope, started = GetTime(), requests = 0, seen = {}, count = 0, watchlist = watchlist, expected = expected,
        snapshot = Deals:BeginSnapshot(false, context, coverage, true) }
    Update()
    self:Pump()
    return true
end

local function PriceSort()
    local price = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    return price and { { sortOrder = price, reverseSort = false } } or {}
end

function Scanner:Pump()
    if self:HasFlight() or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() or InCombatLockdown() then return end
    if Deals.search then Deals:ResumeSearch(); return end
    if Deals.queue or Deals.pending then return end
    local ah, sales = C_AuctionHouse, Addon.VendorResaleAuctions
    if not ah or not ah.IsThrottledMessageSystemReady() or sales.query or sales.pending then return end
    if self.priority then
        local action = self.priority
        self.priority = nil
        action()
        return
    end
    local job = self.job
    if not job then return end
    if Market:ScanContext().scope ~= job.scope then self:Finish("Market changed", false); return end
    local key = job.keys and job.keys[job.index]
    if job.keys and not key then self:Finish("Complete", true); return end
    local flight = { phase = job.phase, key = key }
    self.flight = flight
    job.requests = job.requests + 1
    self.sending = true
    local ok
    if job.phase == "browse" then
        local filters = job.classID and { { classID = job.classID } } or {}
        ok = pcall(ah.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = filters })
    elseif job.phase == "page" then
        ok = pcall(ah.RequestMoreBrowseResults)
    elseif job.phase == "commodityPage" then
        ok = pcall(ah.RequestMoreCommoditySearchResults, key.itemID)
    elseif job.phase == "itemPage" then
        ok = pcall(ah.RequestMoreItemSearchResults, key)
    else
        ok = pcall(ah.SendSearchQuery, key, PriceSort(), true)
    end
    self.sending = nil
    if not ok and self.flight == flight then
        self.flight = nil
        self:Finish("Request rejected", false)
        return
    end
    C_Timer.After(TIMEOUT, function()
        if self.flight == flight then
            self:Finish("Request timed out", false)
        end
    end)
end

local function Matching(flight, event, value)
    if not flight then return false end
    if not flight.key then
        return flight.phase == "browse" and event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
            or flight.phase == "page" and event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED"
    end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        return value == flight.key.itemID
    end
    return (event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED")
        and type(value) == "table" and Market:ItemKey(value) == Market:ItemKey(flight.key)
end

local function ReadItem(key, commodity)
    local ah = C_AuctionHouse
    local result = { itemKey = key, totalQuantity = 0, observedAt = Market:Now() }
    if commodity then
        result.tiers = Gaps:ReadTiers(key.itemID)
        for _, tier in ipairs(result.tiers) do
            result.totalQuantity = result.totalQuantity + tier.marketQuantity
            if tier.marketQuantity > 0 and not result.minPrice then result.minPrice = tier.price end
        end
    else
        for i = 1, ah.GetNumItemSearchResults(key) do
            local row = ah.GetItemSearchResultInfo(key, i)
            if row and row.buyoutAmount and row.buyoutAmount > 0 and row.quantity and row.quantity > 0 then
                local unit = row.buyoutAmount / row.quantity
                result.totalQuantity = result.totalQuantity + row.quantity
                if not result.minPrice or unit < result.minPrice then
                    result.minPrice, result.itemLink = unit, row.itemLink
                end
            end
        end
    end
    return result
end

function Scanner:Read(event, value)
    if self.draining and Matching(self.draining, event, value) then
        self.draining = nil
        self:Resume()
        return
    end
    local flight, job = self.flight, self.job
    if not job or not Matching(flight, event, value) then return end
    self.flight = nil
    local before = job.count
    local ah = C_AuctionHouse
    if flight.key then
        local commodity = type(value) == "number"
        local full, page
        if commodity then full, page = ah.HasFullCommoditySearchResults, ah.RequestMoreCommoditySearchResults
        else full, page = ah.HasFullItemSearchResults, ah.RequestMoreItemSearchResults end
        if full and page and not full(value) then
            job.phase = commodity and "commodityPage" or "itemPage"
            self:Resume()
            return
        end
        local result = ReadItem(flight.key, commodity)
        job.snapshot:Push({ result })
        job.index, job.count, job.phase = job.index + 1, job.count + 1, "item"
    else
        local entries = {}
        local browse = event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" and value or ah.GetBrowseResults()
        local observedAt = Market:Now()
        for _, row in ipairs(browse or {}) do
            if row.itemKey then
                local id = Market:ItemKey(row.itemKey)
                if not job.seen[id] then
                    job.seen[id] = true
                    entries[#entries + 1] = { itemKey = row.itemKey, minPrice = row.minPrice,
                        totalQuantity = row.totalQuantity, observedAt = observedAt }
                end
            end
        end
        job.snapshot:Push(entries)
        job.count, job.phase = job.count + #entries, "page"
        if ah.HasFullBrowseResults() then
            if not job.first and job.count > 0 then job.first = GetTime() - job.started end
            self:Finish("Complete", true)
            return
        end
    end
    if job.count > before then job.countedAt = GetTime() - job.started end
    if not job.first and job.count > 0 then job.first = GetTime() - job.started end
    if job.keys and not job.keys[job.index] then self:Finish("Complete", true); return end
    job.snapshot:Preview(job.watchlist)
    self:Resume()
end

local function CancelOnExternalBrowse()
    if Scanner.job and not Scanner.sending then Scanner:Finish("Another browse search started", false) end
end

local function CancelOnConcurrentQuery()
    if Scanner.flight and not Scanner.sending then Scanner:Finish("Another Auction House request started", false) end
end

for _, event in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_DISABLED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "PLAYER_REGEN_ENABLED" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, value)
    if not Addon.db then return end
    if event == "PLAYER_LOGIN" then
        if hooksecurefunc and C_AuctionHouse then
            for _, name in ipairs({ "SendBrowseQuery", "SearchForItemKeys", "SearchForFavorites" }) do
                if C_AuctionHouse[name] then hooksecurefunc(C_AuctionHouse, name, CancelOnExternalBrowse) end
            end
            for _, name in ipairs({ "SendSearchQuery", "SendSellSearchQuery", "RequestMoreBrowseResults" }) do
                if C_AuctionHouse[name] then hooksecurefunc(C_AuctionHouse, name, CancelOnConcurrentQuery) end
            end
        end
    elseif event == "AUCTION_HOUSE_CLOSED" or event == "AUCTION_HOUSE_DISABLED" then
        Scanner.priority, Scanner.flight, Scanner.draining = nil, nil, nil
        Scanner:Finish("Auction House closed", false)
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" and Scanner.flight and not Scanner.flight.key then
        Scanner.flight = nil
        Scanner:Finish("Browse failed", false)
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" and Scanner.draining and not Scanner.draining.key then
        Scanner.draining = nil
        Scanner:Resume()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" or event == "PLAYER_REGEN_ENABLED" then
        Scanner:Resume()
    else
        Scanner:Read(event, value)
    end
end)
