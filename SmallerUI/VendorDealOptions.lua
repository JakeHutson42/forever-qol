local _, Addon = ...
local Deals = Addon.VendorDeals
local Gaps = Addon.AuctionPriceGaps
local Scanner = Addon.AuctionScanner
local Market = Addon.VendorResaleMarket
local TAB_ID = "SmallerUIVendorDeals"
local PAGE_SIZE = 8
local ROW_HEIGHT, ROW_TOP = 40, 176
local queueActions = {
    search = "Checking…",
    quoteReady = "Get Quote",
    quote = "Waiting…",
    confirmItem = "Confirm Buy",
    confirmCommodity = "Confirm Buy",
}
local tab, tabButton

local function UpdateQueueKeyboard()
    local active = tab:IsVisible() and Deals.queue ~= nil and not InCombatLockdown()
    if tab.queueKeyboard == active then return end
    tab.queueKeyboard, tab.spaceDown = active, nil
    tab:EnableKeyboard(active)
    if active then tab:SetPropagateKeyboardInput(true) end
end

local function Money(copper)
    return GetMoneyString(math.floor(copper), true)
end

local function PerUnit(copper)
    if copper % 1 == 0 then return Money(copper) end
    if copper < 0.01 then return "<0.01c" end
    return ("%.2fc"):format(copper)
end

local function AuctionCategories()
    local classes = Enum.ItemClass or {}
    return { { classes.Tradegoods or 7, "Trade Goods" }, { classes.Consumable or 0, "Consumables" },
        { classes.Weapon or 2, "Weapons" }, { classes.Armor or 4, "Armor" }, { classes.Recipe or 9, "Recipes" },
        { classes.Miscellaneous or 15, "Miscellaneous" } }
end

function Addon:BuildVendorDealOptions()
    local UI = self.OptionsUI
    local page = UI.Page("SmallerUIVendorDealOptions", "Auction House", 390)
    local content, vendor = page.content, self:GetVendorDealSettings()
    local settings, resale = self:GetAuctionSettings(), self.VendorResale:Settings()
    local fields = {}
    local panels = {}
    for index, height in ipairs({ 240, 350, 283, 390 }) do
        local panel = CreateFrame("Frame", nil, page.content)
        panel:SetPoint("TOPLEFT")
        panel:SetSize(620, height)
        panels[index] = panel
    end

    local function Feedback(message, failed)
        Addon:OptionsFeedback(message, failed, "vendorDeals")
    end

    local function Refresh()
        Addon:RefreshVendorDealsTab()
        Addon:RefreshVendorResale()
        Addon:RefreshVendorResaleAuctions()
    end

    local function SetSwitch(name, label, y, values, key, default, change)
        local widget = UI.Switch(content, name, label, 12, y, function(value)
            values[key] = value
            if change then change(value) end
            Refresh()
        end)
        fields[#fields + 1] = function()
            local value = values[key]
            if value == nil then value = default end
            widget:SetChecked(value)
        end
        return widget
    end

    local function Number(name, label, y, values, key, min, max, scale, change)
        UI.Label(content, label, 12, y - 7, nil, 365)
        local field = UI.EditBox(content, name)
        field:SetPoint("TOPLEFT", 378, y)
        field:SetSize(110, 26)
        field:SetAutoFocus(false)
        field:SetMaxLetters(12)
        scale = scale or 1
        local function Restore()
            field:SetText(tostring(values[key] / scale))
            field:ClearFocus()
        end
        fields[#fields + 1] = Restore
        field:SetScript("OnEscapePressed", Restore)
        field:SetScript("OnEnterPressed", function()
            local value = tonumber(field:GetText())
            if value and value >= min and value <= max and (scale ~= 1 or value % 1 == 0) then
                values[key] = math.floor(value * scale + 0.5)
                if change then change() end
                Refresh()
                Feedback("Setting saved.")
            else
                Feedback(("Enter %s from %s to %s."):format(scale == 1 and "a whole number" or "a number", min, max), true)
            end
            Restore()
        end)
    end

    local function ResetPurchaseCheck()
        if Deals.queue then Deals:Cancel("Settings changed. Check prices again.") end
    end
    local function ResetGapCheck()
        if Deals.mode == "gap" then ResetPurchaseCheck() end
    end

    content = panels[1]
    UI.Section(content, "Scanning and price history", 0)
    local importButton = SetSwitch("SmallerUIAuctionImport", "Import Auctionator scans", -32, settings, "importAuctionator", true,
        function(value)
            if value then Deals:ConnectAuctionator()
            elseif Deals.importing then
                Deals.importing, Deals.scanRun, Deals.snapshot = nil, nil, nil
                Deals.scanning, Gaps.scanning = false, false
            end
        end)
    UI.Tooltip(importButton, "Use Auctionator's completed scans alongside scans started in Forever QoL.")
    SetSwitch("SmallerUIAuctionProgressBar", "Show scan progress bar", -64, settings, "scanBar", true)
    SetSwitch("SmallerUIAuctionETA", "Show estimated time remaining", -96, settings, "scanETA", true)
    UI.Label(content, "Default scan category", 12, -138)
    UI.Select(content, "SmallerUIAuctionDefaultCategory", 378, -131, 176, AuctionCategories(),
        function() return settings.category end, function(value)
            settings.category = value
            if tab and tab.category.GenerateMenu then tab.category:GenerateMenu() end
            Feedback("Default category saved.")
        end)
    Number("SmallerUIAuctionTypicalDays", "Days used for typical resale prices", -165, settings, "typicalDays", 2, 14)
    Number("SmallerUIAuctionHistoryDays", "Days to keep scanned prices", -199, settings, "historyDays", 14, 90)

    content = panels[2]
    UI.Section(content, "Vendor Deals", 0)
    SetSwitch("SmallerUIAHVendorDealsEnabled", "Show Vendor Deals and Price Gaps at auctioneers", -32, vendor, "enabled", true,
        function(value)
            if value then Addon:CreateVendorDealsTab()
            else
                if Scanner.job and Scanner.job.label ~= "Vendor Stock" then Scanner:Stop() end
                Deals:Cancel("Scan the Auction House to find items below vendor value.")
                if tab then tab:Hide() end
            end
            if tabButton then tabButton:SetShown(value) end
            Addon:RefreshVendorFlipUI()
        end)
    Number("SmallerUIVendorReserve", "Gold reserve for Queue Affordable and Price Gaps", -66,
        vendor, "reserve", 0, 999999999, 10000, ResetPurchaseCheck)
    Number("SmallerUIVendorMinimum", "Minimum vendor flip profit per item (copper)", -100,
        settings, "vendorMinimum", 0, 100000000, 1, ResetPurchaseCheck)
    UI.Section(content, "Equipment shown in vendor flips", -146)
    for index, entry in ipairs({
        { "GreyWeapons", "Grey weapons (Poor)", "showGreyWeapons" },
        { "WhiteWeapons", "White weapons (Common)", "showWhiteWeapons" },
        { "GreyArmour", "Grey armour (Poor)", "showGreyArmour" },
        { "WhiteArmour", "White armour (Common)", "showWhiteArmour" },
    }) do
        local toggle = SetSwitch("SmallerUIVendor" .. entry[1], entry[2], -178 - (index - 1) * 32,
            vendor, entry[3], true, function()
                if Deals.mode ~= "gap" then ResetPurchaseCheck() end
            end)
        UI.Tooltip(toggle, "Show this equipment type in Vendor Deals. Hidden types are also excluded from Queue All and Queue Affordable.")
    end
    UI.Label(content, "Hidden types are also skipped by Queue All and Queue Affordable.",
        12, -314, "GameFontHighlightSmall", 535)

    content = panels[3]
    UI.Section(content, "Price Gaps", 0)
    SetSwitch("SmallerUIAuctionPriceGapsEnabled", "Show Price Gaps", -32, settings, "priceGaps", true, function(value)
        if not value and Scanner.job and Scanner.job.watchlist then Scanner:Stop() end
        ResetGapCheck()
    end)
    Number("SmallerUIAuctionGapDiscount", "Minimum discount from the resale price (%)", -65, settings, "gapDiscount", 1, 99, 1, ResetGapCheck)
    Number("SmallerUIAuctionGapUnits", "Maximum units per purchase", -99, settings, "gapUnits", 1, 10000, 1, ResetGapCheck)
    Number("SmallerUIAuctionGapSupport", "Minimum stock at the comparison price", -133, settings, "gapSupport", 1, 10000, 1, ResetGapCheck)
    Number("SmallerUIAuctionGapAge", "Maximum age of a scan lead (minutes)", -167, settings, "gapAge", 1, 120, 1, ResetGapCheck)
    UI.Label(content, "Watchlist item name, link, or ID", 12, -211)
    local entry = UI.EditBox(content, "SmallerUIAuctionWatchItem")
    entry:SetPoint("TOPLEFT", 304, -204)
    entry:SetSize(116, 26)
    entry:SetAutoFocus(false)
    entry:SetMaxLetters(220)
    local watchStatus = UI.Label(content, "", 12, -239, "GameFontHighlightSmall", 535)
    local function WatchCount() watchStatus:SetText(("%d items in the watchlist. Hover over Add / Remove to see the list."):format(#Scanner:Watchlist())) end
    local function ToggleWatch()
        local row = Gaps:ManualRow(entry:GetText(), true)
        if not row then Feedback("Enter a commodity name, link, or item ID.", true); return end
        local added = Scanner:ToggleWatch(row)
        entry:SetText("")
        entry:ClearFocus()
        WatchCount()
        Refresh()
        Feedback((added and "Added " or "Removed ") .. row.name .. ".")
    end
    local watch = UI.Button(content, "SmallerUIAuctionWatchToggle", "Add / Remove", 430, -204, 122, ToggleWatch)
    watch:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Watchlist")
        for _, item in ipairs(Scanner:Watchlist()) do GameTooltip:AddLine(item.name) end
        GameTooltip:Show()
    end)
    watch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    entry:SetScript("OnEnterPressed", ToggleWatch)
    entry:SetScript("OnEscapePressed", function(field) field:ClearFocus() end)

    content = panels[4]
    UI.Section(content, "Vendor Resale", 0)
    SetSwitch("SmallerUIAuctionResaleEnabled", "Show Vendor Resale", -32, resale, "enabled", true, function(value)
        if not value and Scanner.job and Scanner.job.label == "Vendor Stock" then Scanner:Stop() end
    end)
    SetSwitch("SmallerUIResaleAutoOpen", "Open resale deals automatically at merchants", -64, resale, "autoOpen", true)
    Number("SmallerUIResaleMinimumProfit", "Minimum profit per vendor pack (silver)", -97, resale, "minimum", 0, 1000000, 100)
    Number("SmallerUIResaleMaxAge", "Maximum age of a resale price (hours)", -131, resale, "maxAge", 1, 168)
    UI.Label(content, "Resale listing duration", 12, -172)
    UI.Select(content, "SmallerUIResaleDuration", 378, -165, 176, { { 1, "2 hours" }, { 2, "8 hours" }, { 3, "24 hours" } },
        function() return resale.duration end, function(value)
            resale.duration = value
            Addon.VendorResaleAuctions.quote = nil
            ResetGapCheck()
            Refresh()
            Feedback("Listing duration saved.")
        end)
    SetSwitch("SmallerUIResaleAssistedPosting", "Enable assisted resale posting", -204, resale, "assistedPosting", false)
    SetSwitch("SmallerUIResaleTrackSales", "Track sales and expirations from auction mail", -236, resale, "trackSales", true)
    local status = UI.Label(content, "", 12, -282, "GameFontHighlightSmall", 535)
    UI.Label(content, "Use Vendor Resale at the Auction House to refresh prices for merchants you have visited.",
        12, -314, "GameFontHighlightSmall", 535)

    UI.Tabs(page, {
        { "scanning", "Scanning", panels[1] }, { "vendor", "Vendor Deals", panels[2] },
        { "gaps", "Price Gaps", panels[3] }, { "resale", "Vendor Resale", panels[4] },
    })
    page:SetScript("OnShow", function()
        for _, update in ipairs(fields) do update() end
        WatchCount()
        status:SetText(Deals:ConnectAuctionator() and "Native scans and Auctionator import are available." or "Native scans are available.")
    end)
    return page
end

function Addon:RefreshVendorDealsTab()
    if not tab then return end
    UpdateQueueKeyboard()
    if not tab:IsVisible() then return end
    local preferences = Addon:GetAuctionSettings()
    if preferences.priceGaps == false then tab.showGaps = false end
    local gap = tab.showGaps
    local rows, queue = gap and Gaps:VisibleRows() or Deals:VisibleRows(), Deals.queue
    local scanning = gap and Gaps.scanning or not gap and Deals.scanning
    local busy = scanning or queue or Deals.pending
    local native = Scanner.job
    local rowBusy = (scanning and not native) or queue or Deals.pending
    local now, scope
    if gap then now, scope = Market:Now(), Market:ScanContext().scope end
    local current = not gap or Gaps:IsCurrent(nil, now, scope)
    local height = tab:GetHeight() or 0
    local pageSize = height >= 200 and math.max(1, math.min(PAGE_SIZE, math.floor((height - 278) / ROW_HEIGHT))) or PAGE_SIZE
    tab.page = math.max(1, math.min(tab.page, math.ceil(#rows / pageSize)))
    local status = gap and Gaps.status or Deals.status
    if gap and Gaps.at and not current and not busy then
        status = "Scan prices are stale. Run Full Scan again or check a commodity directly."
    end
    tab.progress:Refresh()
    if not queue and not Deals.pending then
        local progress = native or Scanner.last and Scanner.outcome
        if progress and tab.progress:IsShown() then
            local first = progress.first and (" · first results %.1fs"):format(progress.first) or ""
            status = ("%d %s%s"):format(progress.requests, progress.requests == 1 and "request" or "requests", first)
        elseif native then status = ("%s · %d items checked"):format(native.label, native.count)
        elseif Scanner.last and (current or not Gaps.at) then status = Scanner.last end
    end
    tab.status:SetText(status)
    tab.all:SetShown(not gap)
    tab.budget:SetShown(not gap)
    tab.gapInput:SetShown(gap == true)
    tab.gapCheck:SetShown(gap == true)
    tab.gapCheck:SetEnabled(not rowBusy)
    tab.scanAll:SetText(gap and "Scan Watchlist" or "Scan All")
    tab.scanAll:SetEnabled(not busy and not native and not Scanner:HasFlight())
    tab.category:SetShown(not gap)
    tab.scanCategory:SetShown(not gap)
    tab.scanCategory:SetEnabled(not busy and not native and not Scanner:HasFlight())
    tab.watch:SetShown(gap == true)
    tab.watch:SetText(("Edit Watchlist (%d)"):format(#Scanner:Watchlist()))
    tab.stopScan:SetEnabled(native ~= nil)
    tab.mode:SetShown(preferences.priceGaps ~= false)
    tab.mode:SetEnabled(not Deals.pending)
    tab.vendorMode:SetEnabled(not Deals.pending)
    if PanelTemplates_SelectTab then
        PanelTemplates_SelectTab(gap and tab.mode or tab.vendorMode)
        PanelTemplates_DeselectTab(gap and tab.vendorMode or tab.mode)
    end
    tab.cancel:SetText(gap and "Clear Check" or "Clear Queue")
    tab.skip:SetText(gap and "Cancel" or "Skip")
    tab.reference:SetText(gap and "Resale / unit" or "Vendor / unit")
    tab.all:SetEnabled(not busy and #rows > 0)
    tab.budget:SetEnabled(not busy and #rows > 0)
    tab.cancel:SetEnabled(queue ~= nil)
    tab.prev:SetEnabled(tab.page > 1)
    tab.nextPage:SetEnabled(tab.page * pageSize < #rows)
    tab.prev:SetShown(queue == nil)
    tab.nextPage:SetShown(queue == nil)
    tab.pageLabel:SetShown(queue == nil)
    if tab.visibleRows ~= pageSize then
        tab.visibleRows = pageSize
        local y = -ROW_TOP - pageSize * ROW_HEIGHT - 5
        tab.prev:ClearAllPoints()
        tab.prev:SetPoint("TOPLEFT", 0, y)
        tab.nextPage:ClearAllPoints()
        tab.nextPage:SetPoint("TOPLEFT", 88, y)
        tab.pageLabel:ClearAllPoints()
        tab.pageLabel:SetPoint("TOPLEFT", 39, y - 6)
    end
    tab.pageLabel:SetText(("%d / %d"):format(tab.page, math.max(1, math.ceil(#rows / pageSize))))
    for index, widgets in ipairs(tab.rows) do
        local row = index <= pageSize and rows[(tab.page - 1) * pageSize + index] or nil
        widgets.frame:SetShown(row ~= nil)
        widgets.buy.deal = row
        widgets.frame.deal = row
        if row then
            widgets.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            widgets.item:SetText(row.name)
            local quantity = row.quantity
            local stock = quantity and (row.quantityKnown and ("%d available"):format(quantity)
                or ("Up to %d in scan"):format(quantity)) or "Check live availability"
            widgets.stock:SetText(stock)
            local quality = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
            widgets.item:SetTextColor(quality and quality.r or 1, quality and quality.g or 1, quality and quality.b or 1)
            widgets.price:SetText(PerUnit(row.price))
            widgets.vendor:SetText(Money(gap and row.target or row.vendor))
            widgets.profit:SetText(PerUnit(gap and row.margin or row.vendor - row.price))
            widgets.buy:SetText(gap and "Check" or "Buy")
            widgets.buy:SetEnabled(not rowBusy and (not gap or Gaps:IsCurrent(row, now, scope)))
            widgets.selected:SetShown(queue ~= nil and queue[queue.index] == row)
        end
    end

    tab.footer:SetShown(queue ~= nil)
    if not queue then return end
    local remaining = #queue - queue.index + 1
    local available = Deals:AvailableGold()
    tab.queueInfo:SetText(gap and "Commodity price gap" or ("%d item type%s left"):format(remaining, remaining == 1 and "" or "s"))
    tab.available:SetText("Available: " .. Money(available))
    local purchase = Deals.purchase
    local row = queue[queue.index]
    local confirming = Deals.stage == "confirmItem" or Deals.stage == "confirmCommodity"
    local currentCost = purchase and (Deals.quote or purchase.cost)
    local overBudget = currentCost and currentCost > available
    local actionable = not Deals.pending and (not Deals.stage or confirming or Deals.stage == "quoteReady")
        and not overBudget
    tab.offerIcon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    tab.offer:SetText(row.name)
    if gap and purchase then
        local gross = purchase.quantity * purchase.target
        local expected = gross - math.ceil(gross * row.cut) - currentCost
        local deposit = purchase.deposit and " · Deposit " .. Money(purchase.deposit) or ""
        tab.cost:SetText(("×%d · Cost %s · Profit if sold %s%s"):format(purchase.quantity, Money(currentCost), Money(expected), deposit))
        tab.offer:SetText(row.name .. " · Resale " .. PerUnit(purchase.target) .. " / unit")
    else
        tab.cost:SetText(purchase and ("×%d   %s: %s"):format(
            purchase.quantity, (confirming or Deals.pending) and "Total" or "Estimate", Money(currentCost)) or "Live price not checked")
    end
    tab.purchase:SetText(Deals.pending and "Submitted" or queueActions[Deals.stage] or "Buy Next")
    tab.purchase:SetEnabled(actionable)
    tab.skip:SetEnabled(not Deals.pending)
    local showBudgetWarning = overBudget and not Deals.pending
    tab.hint:SetText(showBudgetWarning and "Over available gold" or "Space")
    tab.hint:SetShown(showBudgetWarning or tab.queueKeyboard and actionable)
end

local function AuctionButton(parent, text, x, y, width, callback, right)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint(right and "TOPRIGHT" or "TOPLEFT", x, y)
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function AuctionStripe(texture, atlas, r, g, b, a)
    if texture.SetAtlas and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(atlas)) then
        texture:SetAtlas(atlas)
    else
        texture:SetColorTexture(r, g, b, a)
    end
end

function Addon:CreateVendorDealsTab()
    if tab or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end
    Deals:ConnectAuctionator()
    local UI = self.OptionsUI
    tab = CreateFrame("Frame", "SmallerUIAuctionDeals", AuctionHouseFrame, "BackdropTemplate")
    tab:SetPoint("TOPLEFT", 20, -65)
    tab:SetPoint("BOTTOMRIGHT", -20, 32)
    tab:Hide()
    self:AuctionSurface(tab)
    tab.rows, tab.page = {}, 1
    local function Mode(gap)
        if Deals.pending then return end
        if Deals.queue then Deals:Cancel("Price check cleared.") end
        tab.showGaps, tab.page = gap, 1
        Addon:RefreshVendorDealsTab()
    end
    tab.vendorMode = self:AuctionModeTab(tab, "SmallerUIAuctionVendorMode", "Vendor Deals", nil, function() Mode(false) end)
    tab.mode = self:AuctionModeTab(tab, "SmallerUIAuctionGapMode", "Price Gaps", tab.vendorMode, function() Mode(true) end)
    tab.all = AuctionButton(tab, "Queue All", 10, -70, 96, function() Deals:Prepare("all") end)
    tab.budget = AuctionButton(tab, "Queue Affordable", 116, -70, 136, function() Deals:Prepare("budget") end)
    tab.cancel = AuctionButton(tab, "Clear Queue", 262, -70, 104, function()
        Deals:Cancel(Deals.pending and "Queue cleared. Waiting for the submitted purchase." or "Queue cleared.")
    end)
    tab.gapInput = UI.EditBox(tab, "SmallerUIPriceGapItem")
    tab.gapInput:SetPoint("TOPLEFT", 10, -70)
    tab.gapInput:SetSize(178, 24)
    tab.gapInput:SetAutoFocus(false)
    tab.gapInput:SetMaxLetters(220)
    UI.Tooltip(tab.gapInput, "Enter a commodity name, item link, or item ID.")
    local function CheckCommodity()
        if not tab.showGaps or (Gaps.scanning and not Scanner.job) or Deals.queue or Deals.pending then return end
        local row = Gaps:ManualRow(tab.gapInput:GetText())
        tab.gapInput:ClearFocus()
        if row then Deals:Prepare("gap", row)
        else
            Gaps.status = "Enter a known commodity name, item link, or item ID."
            Addon:RefreshVendorDealsTab()
        end
    end
    tab.gapInput:SetScript("OnEnterPressed", CheckCommodity)
    tab.gapInput:SetScript("OnEscapePressed", function(field) field:ClearFocus() end)
    tab.gapCheck = AuctionButton(tab, "Check Item", 198, -70, 96, CheckCommodity)
    tab.gapInput:Hide()
    tab.gapCheck:Hide()
    AuctionButton(tab, "Settings", -10, -4, 80, function() Addon:ShowOptions("vendorDeals") end, true)
    tab.scanAll = AuctionButton(tab, "Scan All", 10, -36, 116, function()
        if not tab.showGaps then Scanner:Start("All Categories"); return end
        local keys = {}
        for i, entry in ipairs(Scanner:Watchlist()) do keys[i] = entry.key end
        Scanner:Start("Watchlist", nil, keys, true)
    end)
    local categories = AuctionCategories()
    local preferences = self:GetAuctionSettings()
    tab.category = UI.Select(tab, nil, 136, -36, 147, categories, function() return preferences.category end,
        function(value) preferences.category = value end)
    tab.scanCategory = AuctionButton(tab, "Scan Category", 293, -36, 112, function()
        for _, category in ipairs(categories) do
            if category[1] == preferences.category then Scanner:Start(category[2], preferences.category); return end
        end
    end)
    tab.watch = AuctionButton(tab, "Edit Watchlist", 136, -36, 147, function()
        local row = Gaps:ManualRow(tab.gapInput:GetText())
        Scanner.last = nil
        if row then
            local added = Scanner:ToggleWatch(row)
            Gaps.status = (added and "Added to watchlist: " or "Removed from watchlist: ") .. row.name
        else
            Gaps.status = "Enter a commodity in the item field, then click Edit Watchlist to add or remove it."
        end
        Addon:RefreshVendorDealsTab()
    end)
    tab.watch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Watchlist")
        local list = Scanner:Watchlist()
        for _, entry in ipairs(list) do GameTooltip:AddLine(entry.name) end
        GameTooltip:AddLine("Enter an item above and click here to add or remove it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab.watch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab.stopScan = AuctionButton(tab, "Stop Scan", 415, -36, 87, function() Scanner:Stop() end)
    tab.progress = Addon.AuctionScanProgress:Create(tab)
    tab.progress:SetPoint("TOPLEFT", 10, -106)
    tab.progress:SetPoint("TOPRIGHT", -10, -106)
    tab.status = UI.Label(tab, "", 10, -130, "GameFontHighlightSmall")
    tab.status:SetPoint("TOPRIGHT", -10, -130)
    tab.status:SetWordWrap(false)
    local header = tab:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", 0, -150)
    header:SetPoint("TOPRIGHT", 0, -150)
    header:SetHeight(22)
    header:SetColorTexture(0.16, 0.12, 0.08, 0.94)
    local function Column(parent, text, offset, y, font)
        local label = parent:CreateFontString(nil, "ARTWORK", font)
        label:SetPoint("TOPRIGHT", offset, y)
        label:SetWidth(93)
        label:SetJustifyH("RIGHT")
        label:SetWordWrap(false)
        label:SetText(text)
        return label
    end
    UI.Label(tab, "Item / available stock", 42, -156, "GameFontNormalSmall")
    Column(tab, "Scan low / unit", -283, -156, "GameFontNormalSmall")
    tab.reference = Column(tab, "Vendor / unit", -180, -156, "GameFontNormalSmall")
    Column(tab, "Profit / unit", -77, -156, "GameFontNormalSmall")
    local function Tooltip(self)
        if not self.deal or not self.deal.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.deal.link)
        GameTooltip:Show()
    end
    for index = 1, PAGE_SIZE do
        local row = CreateFrame("Button", nil, tab)
        row:SetPoint("TOPLEFT", 0, -ROW_TOP - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -ROW_TOP - (index - 1) * ROW_HEIGHT)
        row:SetHeight(ROW_HEIGHT - 2)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(0.065, 0.032, 0.014, index % 2 == 0 and 0.88 or 0.74)
        local selected = row:CreateTexture(nil, "BORDER")
        selected:SetAllPoints()
        AuctionStripe(selected, "auctionhouse-ui-row-select", 0.65, 0.48, 0.18, 0.36)
        selected:SetAlpha(0.8)
        selected:Hide()
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
        row:GetHighlightTexture():SetVertexColor(0.28, 0.21, 0.13, 0.24)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", 6, 0)
        icon:SetSize(28, 28)
        local item = UI.Label(row, "", 42, -5, "GameFontHighlightSmall")
        item:SetPoint("TOPRIGHT", -386, -5)
        item:SetWordWrap(false)
        local stock = UI.Label(row, "", 42, -22, "GameFontHighlightSmall")
        stock:SetPoint("TOPRIGHT", -386, -22)
        stock:SetWordWrap(false)
        stock:SetTextColor(0.81, 0.72, 0.56)
        local buy = AuctionButton(row, "Buy", -4, -7, 62, function(button) Deals:Prepare("row", button.deal) end, true)
        row:SetScript("OnEnter", Tooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tab.rows[index] = { frame = row, item = item, stock = stock, buy = buy, icon = icon, selected = selected,
            price = Column(row, "", -283, -12, "GameFontHighlightSmall"),
            vendor = Column(row, "", -180, -12, "GameFontHighlightSmall"),
            profit = Column(row, "", -77, -12, "GameFontHighlightSmall") }
        tab.rows[index].profit:SetTextColor(0.50, 0.92, 0.44)
    end
    tab.prev = AuctionButton(tab, "<", 0, -312, 32, function()
        tab.page = tab.page - 1
        Addon:RefreshVendorDealsTab()
    end)
    tab.nextPage = AuctionButton(tab, ">", 88, -312, 32, function()
        tab.page = tab.page + 1
        Addon:RefreshVendorDealsTab()
    end)
    tab.pageLabel = UI.Label(tab, "", 39, -318, "GameFontHighlightSmall")
    local footer = CreateFrame("Frame", nil, tab, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(73)
    UI.Plate(footer, { 0.18, 0.14, 0.10, 1 })
    footer:SetBackdropBorderColor(0.52, 0.39, 0.24, 1)
    tab.footer = footer
    tab.queueInfo = UI.Label(footer, "", 10, -8, "GameFontNormalSmall")
    tab.available = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tab.available:SetPoint("TOPRIGHT", -10, -8)
    tab.offerIcon = footer:CreateTexture(nil, "ARTWORK")
    tab.offerIcon:SetPoint("TOPLEFT", 10, -31)
    tab.offerIcon:SetSize(28, 28)
    tab.offerIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    tab.offer = UI.Label(footer, "", 47, -30, "GameFontHighlight")
    tab.offer:SetPoint("TOPRIGHT", -205, -30)
    tab.offer:SetWordWrap(false)
    tab.cost = UI.Label(footer, "", 47, -49, "GameFontNormalSmall")
    tab.cost:SetPoint("TOPRIGHT", -205, -49)
    tab.cost:SetWordWrap(false)
    tab.purchase = AuctionButton(footer, "Buy Next", -77, -26, 116, function() Deals:BuyNext() end, true)
    tab.skip = AuctionButton(footer, "Skip", -10, -26, 60, function() Deals:Skip() end, true)
    tab.hint = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tab.hint:SetPoint("TOP", tab.purchase, "BOTTOM", 0, -3)
    tab.hint:SetTextColor(0.79, 0.73, 0.63)
    footer:Hide()
    tab:RegisterEvent("PLAYER_REGEN_DISABLED")
    tab:RegisterEvent("PLAYER_REGEN_ENABLED")
    tab:SetScript("OnEvent", function() Addon:RefreshVendorDealsTab() end)
    tab:SetScript("OnKeyDown", function(self, key)
        if not self.queueKeyboard or InCombatLockdown() then return end
        local useSpace = key == "SPACE" and not IsModifierKeyDown() and not GetCurrentKeyBoardFocus()
        if useSpace then self.spaceDown = true end
        self:SetPropagateKeyboardInput(not useSpace)
    end)
    tab:SetScript("OnKeyUp", function(self, key)
        if not self.queueKeyboard or InCombatLockdown() then return end
        local useSpace = key == "SPACE" and self.spaceDown
        self:SetPropagateKeyboardInput(not useSpace)
        if not useSpace then return end
        self.spaceDown = nil
        if self.purchase:IsEnabled() and not IsModifierKeyDown() and not GetCurrentKeyBoardFocus() then Deals:BuyNext() end
    end)
    tab:SetScript("OnShow", function() Addon:RefreshVendorDealsTab() end)
    tab:SetScript("OnSizeChanged", function() Addon:RefreshVendorDealsTab() end)
    tab:SetScript("OnHide", function()
        UpdateQueueKeyboard()
        if Deals.queue then
            Deals:Cancel("Queue cleared when you left Vendor Deals.")
        end
    end)
    tabButton = self:CreateAuctionFeatureTab(TAB_ID, tab, "Vendor Deals")
end
