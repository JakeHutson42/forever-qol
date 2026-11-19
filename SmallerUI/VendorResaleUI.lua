local _, Addon = ...
local Resale, Market = Addon.VendorResale, Addon.VendorResaleMarket
local panel, button
local WIDTH, HEIGHT, PAGE_SIZE = 526, 494, 5

local function MerchantTabState()
    if not button then return end
    -- This opens an auxiliary review window; leave the merchant's buy/buyback
    -- selection alone so reading and buying stock retains native behaviour.
    if panel and panel:IsShown() then
        if PanelTemplates_SelectTab then PanelTemplates_SelectTab(button) end
        button:SetEnabled(true)
    elseif PanelTemplates_DeselectTab then
        PanelTemplates_DeselectTab(button)
    end
end

local function PositionMerchantTab()
    local tabs = MerchantFrame.Tabs and #MerchantFrame.Tabs > 0 and MerchantFrame.Tabs
        or { MerchantFrameTab1, MerchantFrameTab2 }
    local previous = tabs[#tabs]
    button:ClearAllPoints()
    local width = 120
    if previous then
        button:SetPoint("TOPLEFT", previous, "TOPRIGHT", 3, 0)
        local mx, _, mw = MerchantFrame:GetRect()
        local tx, _, tw = previous:GetRect()
        if mx and tx then
            local room = mx + mw - tx - tw - 20
            if room < 40 and PanelTemplates_TabResize then
                -- Long localized labels or another addon's merchant tab must
                -- share the available row rather than push this tab outside it.
                local share = math.max(40, (mw - 32 - 3 * #tabs) / (#tabs + 1))
                for index, tab in ipairs(tabs) do
                    PanelTemplates_TabResize(tab, 0, share, 40, share)
                    tab:ClearAllPoints()
                    if index == 1 then tab:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 12, 2)
                    else tab:SetPoint("TOPLEFT", tabs[index - 1], "TOPRIGHT", 3, 0) end
                end
                width = math.min(width, share)
            else
                width = math.max(40, math.min(width, room))
            end
        end
    else
        button:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 12, 2)
        width = math.max(40, math.min(width, MerchantFrame:GetWidth() - 32))
    end
    if PanelTemplates_TabResize then PanelTemplates_TabResize(button, 0, width, 40, width) end
    MerchantTabState()
end

local function Money(value)
    return GetMoneyString(math.floor(value), true)
end

local function Close()
    Resale.dismissed = true
    panel.selected = nil
    panel:Hide()
    MerchantTabState()
end

local function Position()
    local rootScale = UIParent:GetEffectiveScale()
    local ratio = MerchantFrame:GetEffectiveScale() / rootScale
    local right = UIParent:GetWidth() - (MerchantFrame:GetRight() or 0) * ratio
    local left = (MerchantFrame:GetLeft() or 0) * ratio
    local room = math.max(right, left)
    panel:ClearAllPoints()
    panel:SetScale(math.min(1, math.max(0.72, (room - 18) / WIDTH),
        (UIParent:GetHeight() - 20) / HEIGHT))
    if room < WIDTH * 0.72 + 18 then
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    elseif right >= left then
        panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, 0)
    else
        panel:SetPoint("TOPRIGHT", MerchantFrame, "TOPLEFT", -8, 0)
    end
end

local Sales = Addon.VendorResaleAuctions
local Scanner = Addon.AuctionScanner
local auctionPanel, auctionButton

local function MakeAuctionPanel()
    local UI = Addon.OptionsUI
    auctionPanel = CreateFrame("Frame", "SmallerUIVendorResaleAuctions", AuctionHouseFrame, "BackdropTemplate")
    auctionPanel:SetPoint("TOPLEFT", 20, -65)
    auctionPanel:SetPoint("BOTTOMRIGHT", -20, 32)
    auctionPanel:SetClampedToScreen(true)
    auctionPanel:SetMovable(true)
    auctionPanel:EnableMouse(true)
    Addon:AuctionSurface(auctionPanel)
    auctionPanel:Hide()
    table.insert(UISpecialFrames, auctionPanel:GetName())
    auctionPanel.title = UI.Label(auctionPanel, "", 16, -70, "GameFontNormal", 307)
    auctionPanel.details = UI.Label(auctionPanel, "", 16, -99, "GameFontHighlightSmall", 405)
    auctionPanel.progress = Addon.AuctionScanProgress:Create(auctionPanel, "Vendor Stock")
    auctionPanel.progress:SetPoint("TOPLEFT", 16, -185)
    auctionPanel.progress:SetPoint("TOPRIGHT", -16, -185)
    auctionPanel.summary = UI.Label(auctionPanel, "", 16, -210, "GameFontHighlightSmall", 405)
    auctionPanel.index = 1
    auctionPanel.purchases = Addon:AuctionModeTab(auctionPanel, nil, "Purchases", nil, function()
        auctionPanel.showHistory, auctionPanel.index = false, 1
        Addon:RefreshVendorResaleAuctions()
    end)
    auctionPanel.history = Addon:AuctionModeTab(auctionPanel, nil, "Sale History", auctionPanel.purchases, function()
        auctionPanel.showHistory = true
        auctionPanel.index = 1
        Addon:RefreshVendorResaleAuctions()
    end)
    auctionPanel.refresh = UI.Button(auctionPanel, nil, "Refresh Vendor Stock", 16, -154, 145, function()
        if Scanner.job and Scanner.job.label == "Vendor Stock" then Scanner:Stop()
        else Scanner:Start("Vendor Stock", nil, Resale:KnownStock()) end
    end)
    auctionPanel.prev = UI.Button(auctionPanel, nil, "<", 16, -248, 25, function()
        auctionPanel.index = auctionPanel.index - 1
        Addon:RefreshVendorResaleAuctions()
    end)
    auctionPanel.pageText = UI.Label(auctionPanel, "", 50, -255, "GameFontHighlightSmall")
    auctionPanel.next = UI.Button(auctionPanel, nil, ">", 88, -248, 25, function()
        auctionPanel.index = auctionPanel.index + 1
        Addon:RefreshVendorResaleAuctions()
    end)
    auctionPanel.check = UI.Button(auctionPanel, nil, "Check price", 168, -248, 109, function()
        Sales:Review(auctionPanel.purchase)
        Addon:RefreshVendorResaleAuctions()
    end)
    auctionPanel.post = UI.Button(auctionPanel, nil, "Confirm Listing", 288, -248, 136, function()
        Sales:Post()
        Addon:RefreshVendorResaleAuctions()
    end)
end

function Addon:RefreshVendorResaleAuctions()
    if Resale:Settings().enabled == false or not Sales.open or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        if auctionButton then auctionButton:Hide() end
        if auctionPanel then auctionPanel:Hide() end
        return
    end
    local ledger = Resale:Ledger()
    local count = #ledger.purchases
    if not auctionButton then
        MakeAuctionPanel()
        auctionButton = self:CreateAuctionFeatureTab("SmallerUIResaleAuctionButton", auctionPanel, "Vendor Resale")
        auctionPanel:HookScript("OnShow", function() Addon:RefreshVendorResaleAuctions() end)
    end
    auctionButton:Show()
    if not auctionPanel or not auctionPanel:IsShown() then return end
    local panel = auctionPanel
    panel.progress:Refresh()
    local stock = Scanner.job and Scanner.job.label == "Vendor Stock" and Scanner.job
    panel.refresh:SetText(stock and "Stop Stock Scan" or "Refresh Vendor Stock")
    panel.refresh:SetEnabled(stock ~= nil or (not Scanner.job and not Scanner:HasFlight() and not Sales.pending
        and not Sales.query and not Sales.quote and not Addon.VendorDeals.queue and not InCombatLockdown()))
    if PanelTemplates_SelectTab then
        PanelTemplates_SelectTab(panel.showHistory and panel.history or panel.purchases)
        PanelTemplates_DeselectTab(panel.showHistory and panel.purchases or panel.history)
    end
    if panel.showHistory then
        local total = #ledger.outcomes
        panel.index = math.max(1, math.min(panel.index, total))
        local outcome = ledger.outcomes[total - panel.index + 1]
        panel.prev:SetEnabled(panel.index > 1)
        panel.next:SetEnabled(panel.index < total)
        panel.pageText:SetText(("%d / %d"):format(outcome and panel.index or 0, total))
        panel.check:Hide()
        panel.post:Hide()
        panel.title:SetText(outcome and ("%s × %d"):format(outcome.name, outcome.quantity) or "Sale History")
        local details = "Sales and expirations appear here when the Auction House mail can be matched."
        if outcome then
            local label = outcome.profit >= 0 and "Realized profit" or "Realized loss"
            details = ("%s · %s\nPurchase cost: %s\n%s: %s"):format(outcome.sold and "Sold" or "Expired",
                date("%d %b %H:%M", outcome.at), Money(outcome.cost), label, Money(math.abs(outcome.profit)))
        end
        panel.details:SetText(details)
        panel.summary:SetText(("%d listings awaiting Auction House mail."):format(#ledger.listings))
        return
    end
    panel.index = math.max(1, math.min(panel.index, count))
    local purchase = ledger.purchases[panel.index]
    panel.purchase = purchase
    panel.prev:SetEnabled(panel.index > 1)
    panel.next:SetEnabled(panel.index < count)
    panel.pageText:SetText(("%d / %d"):format(count > 0 and panel.index or 0, count))
    local assisted = Resale:Settings().assistedPosting == true
    panel.check:Show()
    panel.check:SetEnabled(purchase ~= nil and not Sales.pending and not Sales.query and not InCombatLockdown())
    panel.post:SetShown(assisted)
    local quote = Sales.quote and Sales.quote.purchase == purchase and Sales.quote
    panel.post:SetEnabled(quote ~= nil and Sales:CanPost() == true)
    panel.title:SetText(purchase and ("%s × %d"):format(purchase.name, purchase.quantity) or "Resale purchases")
    local detail = Sales.message
    if quote then
        local margin = (quote.profit < 0 and "−" or "") .. Money(math.abs(quote.profit))
        detail = ("Listing: %d at %s each\nDeposit due for %d hours: %s\nProfit if sold: %s"):format(
            quote.quantity, Money(quote.price), quote.hours, Money(quote.deposit), margin)
    elseif not detail then
        detail = purchase and ("Cost per item: %s\nCheck the current price before listing."):format(Money(purchase.unitCost))
            or "No purchases waiting to list."
        if purchase and purchase.target then detail = detail .. "\nEarlier resale target: " .. Money(purchase.target) .. " per item." end
    end
    panel.details:SetText(detail)
    local latest = ledger.outcomes[#ledger.outcomes]
    if latest then
        panel.summary:SetText(("Latest outcome: %s · %s\n%s %s · %d awaiting mail"):format(latest.name,
            latest.sold and "Sold" or "Expired", latest.profit >= 0 and "Profit" or "Loss", Money(math.abs(latest.profit)), #ledger.listings))
    elseif #ledger.listings > 0 then
        panel.summary:SetText(("%d listings awaiting Auction House mail."):format(#ledger.listings))
    else
        panel.summary:SetText("")
    end
    if Scanner.last and not panel.progress:IsShown() and Scanner.last:find("^Vendor Stock") then
        panel.summary:SetText(Scanner.last)
    end
end

local function Column(UI, parent, text, x, y, width, right, font)
    local label = UI.Label(parent, text, x, y, font or "GameFontHighlightSmall")
    label:SetWidth(width)
    label:SetWordWrap(false)
    if right then label:SetJustifyH("RIGHT") end
    return label
end

local function MakePanel()
    local UI = Addon.OptionsUI
    panel = CreateFrame("Frame", "SmallerUIVendorResale", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    Addon:AuctionSurface(panel)
    UI.Header(panel, "Vendor Resale", "INV_Misc_Coin_01", Close, nil, 53)
    panel:Hide()
    table.insert(UISpecialFrames, panel:GetName())
    panel:SetScript("OnHide", function()
        Resale.dismissed = true
        panel.selected, panel.confirming, panel.quoted = nil, false, nil
        MerchantTabState()
    end)
    panel:HookScript("OnShow", MerchantTabState)
    panel:RegisterEvent("UI_SCALE_CHANGED")
    panel:RegisterEvent("DISPLAY_SIZE_CHANGED")
    panel:SetScript("OnEvent", function() if panel:IsShown() then Position() end end)
    panel.status = UI.Label(panel, "", 16, -64, "GameFontHighlightSmall", WIDTH - 32)
    local heading = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    heading:SetPoint("TOPLEFT", 14, -88)
    heading:SetSize(WIDTH - 28, 23)
    UI.Plate(heading)
    Column(UI, heading, "Item", 9, -5, 180, false, "GameFontNormalSmall")
    Column(UI, heading, "Vendor / pack", 210, -5, 72, true, "GameFontNormalSmall")
    Column(UI, heading, "AH / unit", 285, -5, 74, true, "GameFontNormalSmall")
    Column(UI, heading, "Profit / pack", 364, -5, 85, true, "GameFontNormalSmall")
    panel.rows, panel.page, panel.packs = {}, 1, 1
    for index = 1, PAGE_SIZE do
        local row = CreateFrame("Button", nil, panel, "BackdropTemplate")
        row:SetSize(WIDTH - 28, 41)
        row:SetPoint("TOPLEFT", 14, -113 - (index - 1) * 44)
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
        row:GetHighlightTexture():SetVertexColor(0.48, 0.34, 0.13, 0.24)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetSize(28, 28)
        row.item = Column(UI, row, "", 42, -5, 163)
        row.stock = Column(UI, row, "", 42, -23, 163)
        row.stock:SetTextColor(0.82, 0.73, 0.57)
        row.cost = Column(UI, row, "", 208, -8, 74, true)
        row.ask = Column(UI, row, "", 285, -8, 74, true)
        row.profit = Column(UI, row, "", 364, -8, 85, true)
        row.profit:SetTextColor(0.59, 0.85, 0.53)
        row:SetScript("OnClick", function(self)
            panel.selected, panel.packs, panel.confirming = self.offer.index, 1, false
            Addon:RefreshVendorResale()
        end)
        row:SetScript("OnEnter", function(self)
            if not self.offer then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.offer.link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.rows[index] = row
    end
    panel.prev = UI.Button(panel, nil, "<", 16, -338, 25, function()
        panel.page, panel.selected = panel.page - 1, nil
        Addon:RefreshVendorResale()
    end)
    panel.pageText = UI.Label(panel, "", 50, -345, "GameFontHighlightSmall")
    panel.next = UI.Button(panel, nil, ">", 91, -338, 25, function()
        panel.page, panel.selected = panel.page + 1, nil
        Addon:RefreshVendorResale()
    end)
    UI.Button(panel, nil, "Settings", WIDTH - 96, -338, 80, function() Addon:ShowOptions("vendorDeals") end)
    panel.details = UI.Label(panel, "", 16, -376, "GameFontHighlightSmall", WIDTH - 34)
    panel.total = UI.Label(panel, "", 16, -441, "GameFontHighlightSmall", 248)
    panel.minus = UI.Button(panel, nil, "−", 270, -439, 24, function()
        panel.packs, panel.confirming = panel.packs - 1, false
        Addon:RefreshVendorResale()
    end)
    panel.count = UI.Label(panel, "", 301, -447, "GameFontHighlightSmall")
    panel.plus = UI.Button(panel, nil, "+", 338, -439, 24, function()
        panel.packs, panel.confirming = panel.packs + 1, false
        Addon:RefreshVendorResale()
    end)
    panel.buy = UI.Button(panel, nil, "Buy…", 382, -439, 128, function()
        if not panel.offer then return end
        if panel.confirming then
            panel.confirming = false
            Resale.message = Resale:Buy(panel.quoted, panel.packs)
            panel.quoted = nil
        else
            panel.confirming = true
            panel.quoted, panel.quotedPacks = panel.offer, panel.packs
        end
        Addon:RefreshVendorResale()
    end)
end

function Addon:RefreshVendorResale()
    if not Resale:CanReadMerchant() then
        if button then button:Hide() end
        if panel and panel:IsShown() then
            local dismissed = Resale.dismissed
            panel:Hide()
            Resale.dismissed = dismissed
        end
        return
    end
    local offers, emptyMessage = Resale:Offers()
    if not button then
        button = CreateFrame("Button", "SmallerUIResaleDealsButton", MerchantFrame, "PanelTabButtonTemplate")
        button:SetScript("OnClick", function()
            if panel and panel:IsShown() then Close(); return end
            if not panel then MakePanel() end
            Resale.dismissed, panel.page = false, 1
            Position()
            panel:Show()
            Addon:RefreshVendorResale()
        end)
        button:RegisterEvent("UI_SCALE_CHANGED")
        button:RegisterEvent("DISPLAY_SIZE_CHANGED")
        button:SetScript("OnEvent", PositionMerchantTab)
        MerchantFrame:HookScript("OnShow", PositionMerchantTab)
    end
    button:SetText(#offers > 0 and ("Resale Deals (%d)"):format(#offers) or "Resale Deals")
    button:Show()
    PositionMerchantTab()
    if #offers > 0 and Resale:Settings().autoOpen ~= false and not Resale.dismissed and (not panel or not panel:IsShown()) then
        if not panel then MakePanel() end
        panel.page = 1
        Position()
        panel:Show()
    end
    if not panel or not panel:IsShown() then return end
    local pages = math.max(1, math.ceil(#offers / PAGE_SIZE))
    panel.page = math.max(1, math.min(panel.page, pages))
    panel.prev:SetEnabled(panel.page > 1)
    panel.next:SetEnabled(panel.page < pages)
    panel.pageText:SetText(("%d / %d"):format(panel.page, pages))
    local snapshot = Market:GetLatest()
    local minutes = snapshot and math.max(0, math.floor((Market:Now() - snapshot.at) / 60))
    local venue = snapshot and snapshot.venue and " · " .. snapshot.venue or ""
    panel.status:SetText(Resale.message or emptyMessage or ("%d matches · scan %d min ago%s"):format(#offers, minutes or 0, venue))
    local selected
    for _, offer in ipairs(offers) do
        if panel.selected == offer.index then selected = offer; break end
    end
    if not selected and offers[(panel.page - 1) * PAGE_SIZE + 1] then
        selected = offers[(panel.page - 1) * PAGE_SIZE + 1]
        panel.selected, panel.packs, panel.confirming = selected.index, 1, false
    end
    for i, row in ipairs(panel.rows) do
        local offer = offers[(panel.page - 1) * PAGE_SIZE + i]
        row.offer = offer
        row:SetShown(offer ~= nil)
        if offer then
            self.OptionsUI.Plate(row, offer == selected and { 0.27, 0.19, 0.09, 1 } or { 0.12, 0.09, 0.06, 0.9 })
            row.icon:SetTexture(offer.icon)
            row.item:SetText(offer.name)
            row.stock:SetText(offer.available and offer.available >= 0
                and ("%d packs available · %d each"):format(offer.available, offer.pack)
                or ("Unlimited · %d per pack"):format(offer.pack))
            row.cost:SetText(Money(offer.price))
            row.ask:SetText(Money(offer.ask))
            row.profit:SetText(Money(offer.profit))
        end
    end
    panel.offer = selected
    panel.minus:SetShown(selected ~= nil)
    panel.plus:SetShown(selected ~= nil)
    panel.buy:SetShown(selected ~= nil)
    panel.count:SetShown(selected ~= nil)
    if not selected then panel.details:SetText(""); panel.total:SetText(""); return end
    local limit = Resale:PurchaseLimit(selected)
    panel.packs = math.max(1, math.min(panel.packs, limit))
    if panel.confirming and (panel.quotedPacks ~= panel.packs or not panel.quoted
        or panel.quoted.link ~= selected.link or panel.quoted.at ~= selected.at
        or panel.quoted.price ~= selected.price or panel.quoted.pack ~= selected.pack or panel.quoted.ask ~= selected.ask) then
        panel.confirming, panel.quoted = false, nil
    end
    local competing = selected.observation.atFloor
    local stock = competing and ("%d at this price"):format(competing) or ("%d listed at all prices"):format(selected.observation.quantity)
    local typical = selected.typical and ("%s (%d scans)"):format(Money(selected.typical), selected.scans) or "—"
    local marketNote = competing == 1 or selected.observation.quantity == 1
    local deposit = Resale:DepositEstimate(selected, panel.packs)
    local hours = Resale.durationHours[Resale:Settings().duration]
    local depositText = deposit and ("Estimated %d-hour deposit: %s"):format(hours, Money(deposit))
        or "Deposit checked at the Auction House."
    panel.details:SetText(("Pack of %d · %s%s\n%d-day typical %s · estimated cut %d%%\n%s"):format(
        selected.pack, stock, marketNote and " · Thin market" or "", Addon:GetAuctionSettings().typicalDays,
        typical, selected.cutRate * 100, depositText))
    panel.total:SetText(("%s%s\nProfit if sold  %s"):format(panel.confirming and "Confirm cost  " or "Purchase cost  ",
        Money(selected.price * panel.packs), Money(selected.profit * panel.packs)))
    panel.minus:SetEnabled(panel.packs > 1 and limit > 0)
    panel.plus:SetEnabled(panel.packs < limit)
    panel.count:SetText(tostring(panel.packs))
    panel.buy:SetText(panel.confirming and "Confirm Buy" or "Buy…")
    panel.buy:SetEnabled(limit > 0)
end
