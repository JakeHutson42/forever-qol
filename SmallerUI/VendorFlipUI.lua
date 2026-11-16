local _, Addon = ...
local Flips = Addon.VendorFlipInventory
local dialog, merchantButton
local PAGE_SIZE = 8
local WIDTH, HEIGHT = 590, 567
local gold = { 0.83, 0.66, 0.35, 1 }
local sortChoices = { { "value", "Highest value" }, { "name", "Item name" } }

local function Money(value)
    return GetMoneyString(value, true)
end

local function Render()
    if not dialog or not dialog:IsShown() then return end
    local query = dialog.search:GetText():lower():match("^%s*(.-)%s*$")
    local rows, selected, value = {}, 0, 0
    for _, item in pairs(dialog.items) do
        if dialog.selected[item.guid] then selected, value = selected + 1, value + item.value end
        if item.name:lower():find(query, 1, true) then rows[#rows + 1] = item end
    end
    table.sort(rows, function(a, b)
        if dialog.sort == "value" and a.value ~= b.value then return a.value > b.value end
        if a.name ~= b.name then return a.name < b.name end
        return a.guid < b.guid
    end)
    local pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
    dialog.page = math.max(1, math.min(dialog.page, pages))
    dialog.pageLabel:SetText(("%d / %d"):format(dialog.page, pages))
    dialog.empty:SetShown(#rows == 0)
    dialog.empty:SetText(next(dialog.items) and "No items match this search." or "No verified stacks remain in your bags.")
    dialog.prev:SetEnabled(dialog.page > 1)
    dialog.next:SetEnabled(dialog.page < pages)
    dialog.selectAll:SetEnabled(next(dialog.items) ~= nil)
    dialog.selectNone:SetEnabled(selected > 0)
    dialog.sell:SetEnabled(selected > 0 and Flips:CanSell() and not Flips.selling)
    dialog.summary:SetText(("%d stack%s selected"):format(selected, selected == 1 and "" or "s"))
    dialog.total:SetText("Vendor total: " .. Money(value))
    for index, widget in ipairs(dialog.rows) do
        local item = rows[(dialog.page - 1) * PAGE_SIZE + index]
        widget.item = item
        widget:SetShown(item ~= nil)
        if item then
            local checked = dialog.selected[item.guid] == true
            widget.toggle:SetChecked(checked)
            widget:SetBackdropColor(checked and 0.14 or 0.09, checked and 0.20 or 0.12, checked and 0.20 or 0.14, 1)
            widget:SetBackdropBorderColor(checked and 0.35 or 0.22, checked and 0.33 or 0.23, checked and 0.27 or 0.23, 1)
            widget.icon:SetTexture(item.icon)
            widget.name:SetText(item.name)
            widget.quantity:SetText(("×%d"):format(item.count))
            widget.value:SetText(Money(item.value))
        end
    end
end

local function FitDialog()
    local scale = UIParent:GetEffectiveScale()
    local width, height = UIParent:GetSize()
    dialog:SetScale(math.max(0.1, math.min(1, (width - 24 / scale) / WIDTH, (height - 24 / scale) / HEIGHT)))
end

local function MakeDialog()
    if dialog then return end
    local UI = Addon.OptionsUI
    dialog = CreateFrame("Frame", "SmallerUIVendorFlipReview", UIParent, "BackdropTemplate")
    dialog:SetSize(WIDTH, HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    UI.Backdrop(dialog, { 0.052, 0.073, 0.080, 1 }, gold)
    dialog:Hide()
    table.insert(UISpecialFrames, dialog:GetName())
    UI.Header(dialog, "Review Vendor Deals", "INV_Misc_Coin_01", function() dialog:Hide() end)
    dialog:RegisterEvent("UI_SCALE_CHANGED")
    dialog:RegisterEvent("DISPLAY_SIZE_CHANGED")
    dialog:SetScript("OnEvent", FitDialog)

    local search = CreateFrame("EditBox", "SmallerUIVendorFlipSearch", dialog, "BackdropTemplate")
    search:SetSize(364, 28)
    search:SetPoint("TOPLEFT", 16, -87)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetFontObject(GameFontHighlightSmall)
    search:SetTextInsets(28, 8, 0, 0)
    UI.Backdrop(search, { 0.036, 0.052, 0.060, 1 })
    local lens = search:CreateTexture(nil, "ARTWORK")
    lens:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    lens:SetPoint("LEFT", 7, 0)
    lens:SetSize(14, 14)
    local placeholder = UI.Label(search, "Search item names", 28, -7, "GameFontDisableSmall")
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        dialog.page = 1
        Render()
    end)
    dialog.search, dialog.sort = search, "value"
    UI.Select(dialog, "SmallerUIVendorFlipSort", 396, -87, 178, sortChoices, function() return dialog.sort end, function(value)
        dialog.sort, dialog.page = value, 1
        Render()
    end)
    dialog.selectAll = UI.Button(dialog, nil, "Select All", 16, -124, 96, function()
        for guid in pairs(dialog.items) do dialog.selected[guid] = true end
        Render()
    end)
    dialog.selectNone = UI.Button(dialog, nil, "Deselect All", 120, -124, 102, function()
        dialog.selected = {}
        Render()
    end)
    UI.Label(dialog, "Uncheck any stack you want to keep.", 247, -131, "GameFontHighlightSmall")
    local headings = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    headings:SetPoint("TOPLEFT", 16, -160)
    headings:SetSize(WIDTH - 32, 23)
    UI.Plate(headings, { 0.19, 0.17, 0.13, 1 })
    UI.Label(headings, "Sell", 13, -5, "GameFontNormalSmall")
    UI.Label(headings, "Item", 89, -5, "GameFontNormalSmall")
    local function RightLabel(parent, text, inset, y, font)
        local label = parent:CreateFontString(nil, "ARTWORK", font)
        label:SetPoint("TOPRIGHT", -inset, y)
        label:SetText(text)
        return label
    end
    RightLabel(headings, "Qty", 146, -5, "GameFontNormalSmall")
    RightLabel(headings, "Vendor value", 11, -5, "GameFontNormalSmall")
    dialog.empty = UI.Label(dialog, "", 26, -200, "GameFontHighlightSmall")
    dialog.rows = {}
    for index = 1, PAGE_SIZE do
        local row = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 16, -187 - (index - 1) * 37)
        row:SetSize(WIDTH - 32, 33)
        UI.Plate(row)
        row.toggle = UI.Switch(row, nil, "", 7, -3, function(enabled)
            if row.item then dialog.selected[row.item.guid] = enabled end
            Render()
        end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(26, 26)
        row.icon:SetPoint("LEFT", 53, 0)
        row.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        row.name = UI.Label(row, "", 89, -9, "GameFontHighlight", 269)
        row.name:SetWordWrap(false)
        row.quantity = RightLabel(row, "", 146, -10, "GameFontHighlightSmall")
        row.value = RightLabel(row, "", 11, -10, "GameFontNormalSmall")
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.item.info.hyperlink)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dialog.rows[index] = row
    end
    dialog.prev = UI.Button(dialog, nil, "‹", 16, -487, 34, function() dialog.page = dialog.page - 1; Render() end)
    dialog.next = UI.Button(dialog, nil, "›", 111, -487, 34, function() dialog.page = dialog.page + 1; Render() end)
    UI.Tooltip(dialog.prev, "Previous page")
    UI.Tooltip(dialog.next, "Next page")
    dialog.pageLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dialog.pageLabel:SetPoint("CENTER", dialog.prev, "RIGHT", 30, 0)
    local footer = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(44)
    UI.Plate(footer, { 0.12, 0.15, 0.16, 1 })
    dialog.summary = UI.Label(footer, "", 15, -8, "GameFontHighlightSmall")
    dialog.total = UI.Label(footer, "", 15, -24, "GameFontNormalSmall")
    dialog.cancel = UI.Button(footer, nil, "Cancel", 345, -9, 95, function() dialog:Hide() end)
    dialog.sell = UI.Button(footer, nil, "Sell Selected", 448, -9, 124, function()
        local reviewed = {}
        for guid, item in pairs(dialog.items) do
            if dialog.selected[guid] then reviewed[#reviewed + 1] = item end
        end
        table.sort(reviewed, function(a, b) return a.guid < b.guid end)
        if #reviewed > 0 and Flips:Sell(reviewed) then dialog:Hide() end
    end)
    dialog.sell:SetBackdropColor(0.25, 0.20, 0.13, 1)
    dialog.sell:SetBackdropBorderColor(unpack(gold))
    dialog:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        search:ClearFocus()
    end)
end

local function OpenReview()
    local items = Flips:SellableStacks()
    if not next(items) or not Flips:CanSell() or Flips.selling then return end
    MakeDialog()
    dialog.items, dialog.selected, dialog.page = items, {}, 1
    for guid in pairs(items) do dialog.selected[guid] = true end
    dialog.search:SetText("")
    dialog.search:ClearFocus()
    FitDialog()
    dialog:Show()
    Render()
end

function Addon:RefreshVendorFlipUI()
    local UI = self.OptionsUI
    local enabled = self:GetVendorDealSettings().enabled
    local items = {}
    if Flips.merchantOpen and MerchantFrame and UI and enabled then
        items = self.VendorFlipInventory:SellableStacks()
        if next(items) and not merchantButton then
            merchantButton = UI.Button(MerchantFrame, "SmallerUIReviewVendorFlips", "Review Vendor Deals", 63, -30, 133, OpenReview)
            UI.Tooltip(merchantButton, "Review the items you bought through Vendor Deals before selling them to this vendor.")
        end
    end
    if merchantButton then
        merchantButton:SetShown(next(items) ~= nil and Flips.merchantOpen and MerchantFrame.selectedTab == 1)
        merchantButton:SetEnabled(not Flips.selling and Flips:CanSell())
    end
    if dialog and dialog:IsShown() then
        if not Flips.merchantOpen or not enabled then dialog:Hide(); return end
        for guid, item in pairs(dialog.items) do
            if not items[guid] or items[guid].value ~= item.value or items[guid].count ~= item.count then
                dialog.items[guid], dialog.selected[guid] = nil, nil
            end
        end
        Render()
    end
end
