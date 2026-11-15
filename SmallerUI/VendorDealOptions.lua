local _, Addon = ...
local Deals = Addon.VendorDeals
local TAB_ID = "SmallerUIVendorDeals"
local PAGE_SIZE = 9
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

function Addon:BuildVendorDealOptions()
    local UI = self.OptionsUI
    local page = UI.Page("SmallerUIVendorDealOptions", "Vendor Deals", 350)
    local content, settings = page.content, self:GetVendorDealSettings()
    local enabled = UI.Switch(content, nil, "Show Vendor Deals at the Auction House", 12, 0, function(value)
        settings.enabled = value
        if value then
            Addon:CreateVendorDealsTab()
        else
            Deals.snapshot, Deals.scanning, Deals.rows = nil, false, {}
            Deals:Cancel("Run a Full Scan from the Auctionator tab.")
            if tab and tab:IsShown() and AuctionHouseFrame.BuyTab then AuctionHouseFrame.BuyTab:Click() end
        end
        if tabButton then tabButton:SetShown(value) end
        Addon:RefreshVendorFlipUI()
    end)
    UI.Section(content, "Purchase budget", -52)
    UI.Label(content, "Gold to keep when using Queue Affordable", 12, -92)
    local reserve = CreateFrame("EditBox", "SmallerUIVendorReserve", content, "InputBoxTemplate")
    reserve:SetPoint("TOPLEFT", 378, -85)
    reserve:SetSize(110, 26)
    reserve:SetAutoFocus(false)
    reserve:SetMaxLetters(12)
    local function Restore(field)
        field:SetText(tostring(settings.reserve / 10000))
        field:ClearFocus()
    end
    reserve:SetScript("OnEscapePressed", Restore)
    reserve:SetScript("OnEnterPressed", function(field)
        local value = tonumber(field:GetText())
        if not value or value ~= value or value < 0 or value > 999999999 then
            Addon:OptionsFeedback("Enter a gold amount from 0 to 999,999,999.", true, "vendorDeals")
        else
            settings.reserve = math.floor(value * 10000 + 0.5)
            if Deals.mode == "budget" then Deals:Cancel("The gold reserve changed. Build a new queue.") end
            Addon:OptionsFeedback("Gold reserve saved.", false, "vendorDeals")
        end
        Restore(field)
    end)
    UI.Label(content, "Queue Affordable keeps this much gold in reserve when you confirm each purchase.", 12, -125,
        "GameFontHighlightSmall", 540)
    UI.Section(content, "Auction House", -166)
    local status = UI.Label(content, "", 12, -202, "GameFontHighlightSmall", 535)
    UI.Label(content, "Run Full Scan in Auctionator, then open Vendor Deals. Review and confirm each purchase in the queue.",
        12, -232, "GameFontHighlightSmall", 535)
    UI.Label(content, "Collect auction mail as usual. At a vendor, Review Vendor Deals shows purchases verified in your bags.",
        12, -268, "GameFontHighlightSmall", 535)
    page:SetScript("OnShow", function()
        enabled:SetChecked(settings.enabled)
        Restore(reserve)
        status:SetText(Deals:ConnectAuctionator() and "Auctionator is available." or "Enable Auctionator to use Vendor Deals.")
    end)
    return page
end

function Addon:RefreshVendorDealsTab()
    if not tab then return end
    UpdateQueueKeyboard()
    if not tab:IsVisible() then return end
    local rows, queue = Deals.rows, Deals.queue
    local busy = Deals.scanning or queue or Deals.pending
    tab.page = math.max(1, math.min(tab.page, math.ceil(#rows / PAGE_SIZE)))
    tab.status:SetText(Deals.status)
    tab.all:SetEnabled(not busy and #rows > 0)
    tab.budget:SetEnabled(not busy and #rows > 0)
    tab.cancel:SetEnabled(queue ~= nil)
    tab.prev:SetEnabled(tab.page > 1)
    tab.nextPage:SetEnabled(tab.page * PAGE_SIZE < #rows)
    tab.pageLabel:SetText(("%d / %d"):format(tab.page, math.max(1, math.ceil(#rows / PAGE_SIZE))))
    for index, widgets in ipairs(tab.rows) do
        local row = rows[(tab.page - 1) * PAGE_SIZE + index]
        widgets.frame:SetShown(row ~= nil)
        widgets.buy.deal = row
        widgets.frame.deal = row
        if row then
            widgets.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            widgets.item:SetText(row.name)
            local quality = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
            widgets.item:SetTextColor(quality and quality.r or 1, quality and quality.g or 1, quality and quality.b or 1)
            widgets.price:SetText(PerUnit(row.price))
            widgets.vendor:SetText(Money(row.vendor))
            widgets.profit:SetText(PerUnit(row.vendor - row.price))
            widgets.buy:SetEnabled(not busy)
            widgets.selected:SetShown(queue ~= nil and queue[queue.index] == row)
        end
    end

    tab.purchase:SetShown(queue ~= nil)
    tab.skip:SetShown(queue ~= nil)
    if not queue then tab.queueInfo:SetText(""); tab.offer:SetText(""); return end
    local remaining = #queue - queue.index + 1
    tab.queueInfo:SetText(("%d item type%s left   |   Available: %s%s"):format(
        remaining, remaining == 1 and "" or "s", Money(Deals:AvailableGold()),
        tab.queueKeyboard and "   |   Space: next action" or ""))
    local purchase = Deals.purchase
    local row = queue[queue.index]
    local confirming = Deals.stage == "confirmItem" or Deals.stage == "confirmCommodity"
    local currentCost = purchase and (Deals.quote or purchase.cost)
    tab.offer:SetText(purchase and ("%s x%d   %s"):format(purchase.link or row.name, purchase.quantity, Money(currentCost)) or row.name)
    local quoteReady = Deals.stage == "quoteReady"
    tab.purchase:SetText(confirming and "Confirm Buy" or quoteReady and "Get Quote" or "Buy Next")
    tab.purchase:SetEnabled(not Deals.pending and (not Deals.stage or confirming or quoteReady)
        and (not currentCost or currentCost <= Deals:AvailableGold()))
    tab.skip:SetEnabled(not Deals.pending)
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
    if tab or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() or not Deals:ConnectAuctionator() then return end
    local library = LibStub and LibStub("LibAHTab-1-0", true)
    if not library then return end
    local UI = self.OptionsUI
    tab = CreateFrame("Frame", nil, AuctionHouseFrame)
    tab:SetPoint("TOPLEFT", 20, -65)
    tab:SetPoint("BOTTOMRIGHT", -20, 12)
    tab:Hide()
    tab.rows, tab.page = {}, 1
    tab.all = AuctionButton(tab, "Queue All", 0, 0, 96, function() Deals:Prepare("all") end)
    tab.budget = AuctionButton(tab, "Queue Affordable", 102, 0, 125, function() Deals:Prepare("budget") end)
    tab.cancel = AuctionButton(tab, "Clear Queue", 233, 0, 96, function()
        Deals:Cancel(Deals.pending and "Queue cleared. Waiting for the submitted purchase." or "Queue cleared.")
    end)
    AuctionButton(tab, "Settings", 0, 0, 80, function() Addon:ShowOptions("vendorDeals") end, true)
    tab.status = UI.Label(tab, "", 0, -34, "GameFontHighlightSmall", 585)
    local header = tab:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", 0, -59)
    header:SetPoint("TOPRIGHT", 0, -59)
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
    UI.Label(tab, "Item", 36, -65, "GameFontNormalSmall")
    Column(tab, "Scan low / unit", -283, -65, "GameFontNormalSmall")
    Column(tab, "Vendor / unit", -180, -65, "GameFontNormalSmall")
    Column(tab, "Profit / unit", -77, -65, "GameFontNormalSmall")
    local function Tooltip(self)
        if not self.deal or not self.deal.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.deal.link)
        GameTooltip:Show()
    end
    for index = 1, PAGE_SIZE do
        local row = CreateFrame("Button", nil, tab)
        row:SetPoint("TOPLEFT", 0, -83 - (index - 1) * 25)
        row:SetPoint("TOPRIGHT", 0, -83 - (index - 1) * 25)
        row:SetHeight(24)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        AuctionStripe(stripe, index % 2 == 0 and "auctionhouse-rowstripe-1" or "auctionhouse-rowstripe-2",
            0.10, 0.08, 0.06, index % 2 == 0 and 0.85 or 0.50)
        local selected = row:CreateTexture(nil, "BORDER")
        selected:SetAllPoints()
        AuctionStripe(selected, "auctionhouse-ui-row-select", 0.65, 0.48, 0.18, 0.36)
        selected:SetAlpha(0.8)
        selected:Hide()
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", 6, 0)
        icon:SetSize(19, 19)
        local item = UI.Label(row, "", 36, -5, "GameFontHighlightSmall")
        item:SetPoint("TOPRIGHT", -386, -5)
        item:SetWordWrap(false)
        local buy = AuctionButton(row, "Buy", -4, 0, 62, function(button) Deals:Prepare("row", button.deal) end, true)
        buy:SetHeight(22)
        row:SetScript("OnEnter", Tooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tab.rows[index] = { frame = row, item = item, buy = buy, icon = icon, selected = selected,
            price = Column(row, "", -283, -5, "GameFontHighlightSmall"),
            vendor = Column(row, "", -180, -5, "GameFontHighlightSmall"),
            profit = Column(row, "", -77, -5, "GameFontHighlightSmall") }
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
    local footer = CreateFrame("Frame", nil, tab)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(66)
    tab.queueInfo = UI.Label(footer, "", 0, -4, "GameFontNormalSmall")
    tab.offer = UI.Label(footer, "", 0, -32, "GameFontHighlightSmall")
    tab.offer:SetPoint("TOPRIGHT", -185, -32)
    tab.offer:SetWordWrap(false)
    tab.purchase = AuctionButton(footer, "Buy Next", -69, -26, 108, function() Deals:BuyNext() end, true)
    tab.skip = AuctionButton(footer, "Skip", 0, -26, 62, function() Deals:Skip() end, true)
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
    tab:SetScript("OnHide", function()
        UpdateQueueKeyboard()
        if Deals.queue then
            Deals:Cancel("Queue cleared when you left Vendor Deals.")
        end
    end)
    library:CreateTab(TAB_ID, tab, "Vendor Deals")
    tabButton = library:GetButton(TAB_ID)
end
