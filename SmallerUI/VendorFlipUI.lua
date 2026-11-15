local _, Addon = ...
local Flips = Addon.VendorFlipInventory
local dialog, merchantButton
local PAGE_SIZE = 8
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
    dialog.summary:SetText(("%d stack(s) selected · %s"):format(selected, Money(value)))
    for index, widget in ipairs(dialog.rows) do
        local item = rows[(dialog.page - 1) * PAGE_SIZE + index]
        widget.item = item
        widget:SetShown(item ~= nil)
        if item then
            widget.toggle:SetChecked(dialog.selected[item.guid] == true)
            widget.icon:SetTexture(item.icon)
            widget.name:SetText(item.name)
            widget.quantity:SetText(("×%d"):format(item.count))
            widget.value:SetText(Money(item.value))
        end
    end
end

local function MakeDialog()
    if dialog then return end
    local UI = Addon.OptionsUI
    dialog = CreateFrame("Frame", "SmallerUIVendorFlipReview", UIParent, "BackdropTemplate")
    dialog:SetSize(540, 490)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    UI.Backdrop(dialog, { 0.07, 0.10, 0.13, 1 })
    dialog:Hide()
    table.insert(UISpecialFrames, dialog:GetName())
    UI.Label(dialog, "Review Vendor Deals", 16, -14, "GameFontNormalLarge")
    UI.Label(dialog, "Uncheck any stack you want to keep.", 16, -40, "GameFontHighlightSmall")
    UI.Button(dialog, nil, "×", 494, -12, 29, function() dialog:Hide() end)

    local search = CreateFrame("EditBox", "SmallerUIVendorFlipSearch", dialog, "InputBoxTemplate")
    search:SetSize(245, 26)
    search:SetPoint("TOPLEFT", 20, -64)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    local placeholder = UI.Label(search, "Search item names", 4, -7, "GameFontDisableSmall")
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        dialog.page = 1
        Render()
    end)
    dialog.search, dialog.sort = search, "value"
    UI.Select(dialog, "SmallerUIVendorFlipSort", 282, -64, 160, sortChoices, function() return dialog.sort end, function(value)
        dialog.sort, dialog.page = value, 1
        Render()
    end)
    dialog.selectAll = UI.Button(dialog, nil, "Select All", 16, -102, 100, function()
        for guid in pairs(dialog.items) do dialog.selected[guid] = true end
        Render()
    end)
    dialog.selectNone = UI.Button(dialog, nil, "Deselect All", 124, -102, 106, function()
        dialog.selected = {}
        Render()
    end)
    dialog.empty = UI.Label(dialog, "", 18, -151, "GameFontHighlightSmall")
    dialog.rows = {}
    for index = 1, PAGE_SIZE do
        local row = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 16, -139 - (index - 1) * 33)
        row:SetSize(508, 30)
        UI.Backdrop(row, { 0.10, 0.14, 0.18, 1 })
        row.toggle = UI.Switch(row, nil, "", 7, -1, function(enabled)
            if row.item then dialog.selected[row.item.guid] = enabled end
            Render()
        end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(25, 25)
        row.icon:SetPoint("LEFT", 51, 0)
        row.name = UI.Label(row, "", 85, -9, "GameFontHighlightSmall", 222)
        row.name:SetWordWrap(false)
        row.quantity = UI.Label(row, "", 318, -9, "GameFontHighlightSmall")
        row.value = UI.Label(row, "", 382, -9, "GameFontNormalSmall")
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
    dialog.prev = UI.Button(dialog, nil, "<", 16, -407, 36, function() dialog.page = dialog.page - 1; Render() end)
    dialog.next = UI.Button(dialog, nil, ">", 111, -407, 36, function() dialog.page = dialog.page + 1; Render() end)
    dialog.pageLabel = UI.Label(dialog, "", 65, -414, "GameFontHighlightSmall")
    dialog.summary = UI.Label(dialog, "", 16, -455, "GameFontNormalSmall", 285)
    dialog.cancel = UI.Button(dialog, nil, "Cancel", 310, -446, 89, function() dialog:Hide() end)
    dialog.sell = UI.Button(dialog, nil, "Sell Selected", 409, -446, 114, function()
        local reviewed = {}
        for guid, item in pairs(dialog.items) do
            if dialog.selected[guid] then reviewed[#reviewed + 1] = item end
        end
        table.sort(reviewed, function(a, b) return a.guid < b.guid end)
        if #reviewed > 0 and Flips:Sell(reviewed) then dialog:Hide() end
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
