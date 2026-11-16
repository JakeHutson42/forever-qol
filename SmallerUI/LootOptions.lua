local _, Addon = ...
local ledger, launcher
local WIDTH, HEIGHT, PAGE_SIZE = 792, 578, 10
local BAG = "INV_Misc_Bag_10"
local DICE = "INV_Misc_Dice_02"
local ART = "Interface\\AddOns\\SmallerUI\\Media\\LootLedgerHeader.tga"
local CHROME = { 0.048, 0.061, 0.068, 1 }
local BRASS = { 0.65, 0.49, 0.31, 1 }
local filters = { { 0, "All activity" }, { 1, "Loot" }, { 2, "Group rolls" }, { 3, "Random rolls" } }

local function RecordIcon(row)
    local id = row[3] and tonumber(row[3]:match("|Hitem:(%d+)"))
    local icon = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return icon or "Interface\\Icons\\" .. (row[2] == 3 and DICE or BAG)
end

local function SetTitle(label, row, title)
    local red, green, blue
    if row[3] then red, green, blue = row[3]:match("|c%x%x(%x%x)(%x%x)(%x%x)") end
    if red then
        label:SetTextColor(0.22 + 0.78 * tonumber(red, 16) / 255,
            0.22 + 0.78 * tonumber(green, 16) / 255, 0.22 + 0.78 * tonumber(blue, 16) / 255)
    else label:SetTextColor(0.96, 0.84, 0.62) end
    label:SetText(title)
end

local function ShowDetails(row)
    ledger.selected = row
    for _, button in ipairs(ledger.rows) do button.selected:SetShown(row ~= nil and button.record == row) end
    for _, entry in ipairs(ledger.rollRows) do entry:Hide() end
    ledger.rollScroll:SetVerticalScroll(0)
    ledger.detail:SetShown(row ~= nil)
    ledger.emptyDetail:SetShown(row == nil)
    if not row then return end
    local title, result = Addon:DescribeLootRecord(row)
    ledger.detail.icon:SetTexture(RecordIcon(row))
    SetTitle(ledger.detail.title, row, title)
    ledger.detail.kind:SetText(({ "Loot received", "Group roll", "Random roll" })[row[2]])
    ledger.detail.result:SetText(result)
    ledger.detail.stamp:SetText(date("%d/%m/%Y  %H:%M", row[1]))
    local rolls = row[7]
    local hasRolls = rolls ~= nil and #rolls > 0
    ledger.rollScroll:SetShown(hasRolls)
    ledger.rollSection:SetShown(hasRolls)
    ledger.rollContent:SetHeight(math.max(1, rolls and #rolls * 30 or 0))
    for index, roll in ipairs(rolls or {}) do
        local entry = ledger.rollRows[index]
        if not entry then
            local UI = Addon.OptionsUI
            entry = CreateFrame("Frame", nil, ledger.rollContent, "BackdropTemplate")
            entry:SetPoint("TOPLEFT", 0, -(index - 1) * 30)
            entry:SetSize(214, 26)
            UI.Backdrop(entry, { 0.066, 0.085, 0.092, 1 }, { 0.18, 0.21, 0.21, 1 })
            entry.name = UI.Label(entry, "", 7, -7, "GameFontHighlightSmall", 119)
            entry.name:SetWordWrap(false)
            entry.roll = entry:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            entry.roll:SetPoint("RIGHT", -7, 0)
            ledger.rollRows[index] = entry
        end
        entry.name:SetText((roll[1]:gsub("|", "||")))
        entry.roll:SetText(roll[2] .. (roll[3] and ("  " .. roll[3]) or ""))
        entry:Show()
    end
end

local function Draw()
    local records, first = Addon:GetLootRecords()
    local results = ledger.results
    local total = results and #results or #records - first + 1
    ledger.offset = math.max(0, math.min(ledger.offset, math.floor(math.max(0, total - 1) / PAGE_SIZE) * PAGE_SIZE))
    local selected
    for index, button in ipairs(ledger.rows) do
        local position = ledger.offset + index
        local row = position <= total and (results and results[position] or records[#records - position + 1]) or nil
        button.record = row
        button:SetShown(row ~= nil)
        if row then
            local title, detail = Addon:DescribeLootRecord(row)
            button.icon:SetTexture(RecordIcon(row))
            SetTitle(button.label, row, title)
            button.detail:SetText(detail)
            button.stamp:SetText(date("%d/%m  %H:%M", row[1]))
            if row == ledger.selected then selected = row end
        end
    end
    ShowDetails(selected or ledger.rows[1].record)
    ledger.previous:SetEnabled(ledger.offset > 0)
    ledger.next:SetEnabled(ledger.offset + PAGE_SIZE < total)
    ledger.empty:SetShown(total == 0)
    local empty = Addon:GetLootSettings().enabled and "Loot and roll results will appear here."
        or "Loot recording is paused. Turn it on in Loot settings."
    ledger.empty:SetText(#records < first and empty or "No activity matches these filters.")
    ledger.status:SetText(total > 0 and string.format("%d-%d of %d", ledger.offset + 1,
        math.min(total, ledger.offset + PAGE_SIZE), total) or "")
end

local function Search()
    Addon:CancelHistorySearch(ledger.driver)
    local records, first = Addon:GetLootRecords()
    local terms = Addon:HistoryTerms(ledger.search:GetText())
    local filter = ledger.filter
    if filter == 0 and #terms == 0 then
        ledger.results = nil
        Draw()
        return
    end
    local selected = ledger.selected
    ledger.status:SetText("Searching...")
    for _, button in ipairs(ledger.rows) do button:Hide() end
    ledger.previous:SetEnabled(false)
    ledger.next:SetEnabled(false)
    ledger.empty:Hide()
    ShowDetails(nil)
    local cursor, matches = #records, {}
    Addon:RunHistorySearch(ledger.driver, function()
        if cursor < first then return false end
        local row = records[cursor]
        if Addon:LootMatches(row, filter, terms) then matches[#matches + 1] = row end
        cursor = cursor - 1
        return true
    end, function()
        ledger.results = matches
        ledger.selected = selected
        Draw()
        if ledger.dirty then ledger.refresh:Show() end
    end)
end

function Addon:RefreshLootLedger()
    if not ledger then return end
    ledger.dirty = true
    if ledger:IsVisible() and not ledger.driver:IsShown() then ledger.refresh:Show() end
end

local function OfferTooltip(widget)
    local row = widget.record
    if not row or not row[3] or not GameTooltip.SetHyperlink then return end
    GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(row[3])
    GameTooltip:Show()
end

local function CreateLedger()
    local UI = Addon.OptionsUI
    local window = CreateFrame("Frame", "SmallerUILootLedger", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetIgnoreParentScale(true)
    window:SetClampedToScreen(true)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    UI.Backdrop(window, CHROME, BRASS)
    window.header = UI.Header(window, "Loot Ledger", BAG, function() window:Hide() end, ART)
    table.insert(UISpecialFrames, window:GetName())

    window.offset, window.filter, window.rows, window.rollRows = 0, 0, {}, {}
    window.driver = CreateFrame("Frame", nil, window)
    window.driver:Hide()
    window.refresh = CreateFrame("Frame", nil, window)
    window.refresh:Hide()
    window.refresh:SetScript("OnUpdate", function(frame)
        frame:Hide()
        if window.dirty then window.dirty = nil; Search() end
    end)

    local search = CreateFrame("EditBox", "SmallerUILootSearch", window, "BackdropTemplate")
    search:SetSize(322, 28)
    search:SetPoint("TOPLEFT", 16, -88)
    search:SetAutoFocus(false)
    search:SetMaxLetters(160)
    search:SetFontObject(GameFontHighlight)
    search:SetTextInsets(28, 8, 0, 0)
    UI.Backdrop(search, { 0.032, 0.046, 0.052, 1 })
    local icon = search:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 7, 0)
    local placeholder = UI.Label(search, "Search items, players, rolls, or dates", 28, -7, "GameFontDisableSmall")
    search:SetScript("OnTextChanged", function(field)
        placeholder:SetShown(field:GetText() == "")
        window.offset, window.selected = 0, nil
        Addon:CancelHistorySearch(window.driver)
        Addon:RefreshLootLedger()
    end)
    search:SetScript("OnEscapePressed", function(field) field:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(field) field:ClearFocus() end)
    window.search = search
    local filter = UI.Select(window, "SmallerUILootFilter", 346, -88, 148, filters, function() return window.filter end,
        function(value) window.filter, window.offset, window.selected = value, 0, nil; Search() end)

    local list = CreateFrame("Frame", nil, window, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 16, -125)
    list:SetSize(478, 408)
    UI.Backdrop(list, { 0.037, 0.050, 0.055, 1 })
    UI.Label(list, "Activity", 12, -8, "GameFontNormalSmall")
    UI.Label(list, "Date / time", 397, -8, "GameFontNormalSmall")
    window.empty = UI.Label(list, "", 18, -52, "GameFontHighlight", 432)
    for index = 1, PAGE_SIZE do
        local button = UI.Button(list, nil, "", 5, -28 - (index - 1) * 37, 468, function(self)
            local row = self.record
            if row and row[3] and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                HandleModifiedItemClick(row[3])
            elseif row then ShowDetails(row) end
        end)
        button:SetHeight(35)
        button:SetBackdropColor(0.10, 0.13, 0.14, index % 2 == 0 and 0.55 or 0.88)
        button:SetBackdropBorderColor(0.19, 0.21, 0.20, 0.55)
        button.selected = button:CreateTexture(nil, "BACKGROUND")
        button.selected:SetAllPoints()
        button.selected:SetColorTexture(0.44, 0.33, 0.16, 0.33)
        button.selected:Hide()
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(25, 25)
        button.icon:SetPoint("LEFT", 7, 0)
        button.label:ClearAllPoints()
        button.label:SetPoint("TOPLEFT", 41, -4)
        button.label:SetPoint("TOPRIGHT", -114, -4)
        button.label:SetJustifyH("LEFT")
        button.label:SetWordWrap(false)
        button.detail = UI.Label(button, "", 41, -19, "GameFontHighlightSmall", 311)
        button.detail:SetWordWrap(false)
        button.stamp = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        button.stamp:SetPoint("RIGHT", -9, 0)
        button:SetScript("OnEnter", OfferTooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        window.rows[index] = button
    end

    local card = CreateFrame("Frame", nil, window, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 507, -88)
    card:SetSize(269, 445)
    UI.Plate(card, { 0.11, 0.14, 0.16, 1 })
    local detail = CreateFrame("Frame", nil, card)
    detail:SetAllPoints()
    detail.kind = UI.Label(detail, "", 14, -13, "GameFontNormalSmall")
    detail.icon = detail:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(38, 38)
    detail.icon:SetPoint("TOPLEFT", 14, -37)
    detail.title = UI.Label(detail, "", 61, -38, "GameFontNormal", 193)
    detail.title:SetHeight(44)
    detail.result = UI.Label(detail, "", 14, -89, "GameFontHighlight", 236)
    detail.stamp = UI.Label(detail, "", 14, -120, "GameFontDisableSmall")
    window.rollSection = CreateFrame("Frame", nil, detail)
    window.rollSection:SetAllPoints()
    UI.Section(window.rollSection, "Roll details", -151)
    local scroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -185)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(214, 1)
    scroll:SetScrollChild(content)
    window.detail, window.rollScroll, window.rollContent = detail, scroll, content
    window.emptyDetail = UI.Label(card, "Select an entry to inspect its details.", 14, -16, "GameFontHighlightSmall", 230)

    window.previous = UI.Button(window, nil, "Previous", 16, -542, 82, function()
        window.offset = window.offset - PAGE_SIZE
        Draw()
    end)
    window.next = UI.Button(window, nil, "Next", 106, -542, 70, function()
        window.offset = window.offset + PAGE_SIZE
        Draw()
    end)
    window.status = UI.Label(window, "", 192, -550, "GameFontHighlightSmall")
    UI.Button(window, nil, "Loot settings", 644, -542, 132, function()
        if Addon:ShowOptions("loot") then window:Hide() end
    end)

    local function Fit()
        local width, height = UIParent:GetSize()
        local scale = UIParent:GetEffectiveScale()
        window:SetScale(math.min(scale, math.max(0.1, math.min((width * scale - 24) / WIDTH, (height * scale - 24) / HEIGHT))))
    end
    window:RegisterEvent("DISPLAY_SIZE_CHANGED")
    window:RegisterEvent("UI_SCALE_CHANGED")
    window:SetScript("OnEvent", function(self) if self:IsShown() then Fit() end end)
    window:SetScript("OnShow", function()
        Fit()
        filter:GenerateMenu()
        window.dirty = nil
        Search()
    end)
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing()
        Addon:CancelHistorySearch(window.driver)
        window.refresh:Hide()
        search:ClearFocus()
        GameTooltip:Hide()
    end)
    return window
end

function Addon:ShowLootLedger()
    ledger = ledger or CreateLedger()
    ledger:Show()
end

function Addon:ToggleLootLedger()
    if ledger and ledger:IsShown() then ledger:Hide() else self:ShowLootLedger() end
end

function Addon:GetLootLauncher() return launcher end

function Addon:UpdateLootLauncher()
    local cfg = self:GetLootSettings()
    if not cfg.showLauncher then
        if launcher then launcher:Hide() end
        return
    end
    if not launcher then
        local UI = self.OptionsUI
        launcher = UI.Button(UIParent, "SmallerUILootLauncher", "", 0, 0, 34, function()
            if not Addon:IsEditingResources() then Addon:ToggleLootLedger() end
        end)
        launcher:SetHeight(34)
        launcher:SetIgnoreParentScale(true)
        launcher:SetClampedToScreen(true)
        launcher:SetMovable(true)
        local icon = launcher:CreateTexture(nil, "ARTWORK")
        icon:SetTexture("Interface\\Icons\\" .. BAG)
        icon:SetSize(26, 26)
        icon:SetPoint("CENTER")
        launcher:RegisterForDrag("LeftButton")
        launcher:SetScript("OnDragStart", function(self)
            Addon:StartResourceMove(self, self, "lootLauncher", "Loot Ledger launcher", "lootLauncher")
        end)
        launcher:SetScript("OnDragStop", function() Addon:EndLootLauncherDrag() end)
        UI.Tooltip(launcher, "Loot Ledger\nDrag in Move Mode to reposition.")
    end
    local drag = self:GetResourceMoveState()
    if not drag or drag.target ~= launcher then
        local layout = self:GetResourceSettings().lootLauncher
        launcher:SetScale(layout.scale)
        launcher:ClearAllPoints()
        launcher:SetPoint("CENTER", UIParent, "CENTER", layout.x / layout.scale, layout.y / layout.scale)
    end
    launcher:Show()
end

function Addon:BuildLootOptions()
    local UI = self.OptionsUI
    local page = UI.Page("SmallerUILootOptions", "Loot & Rolls", 330)
    local content, cfg = page.content, self:GetLootSettings()
    UI.Section(content, "Loot Ledger", 0)
    UI.Button(content, "SmallerUIOpenLootLedger", "Open Loot Ledger", 12, -34, 172, function()
        Addon:HideOptions()
        Addon:ShowLootLedger()
    end)
    UI.Label(content, "/fqol loot or Shift-left-click the minimap button", 204, -40, "GameFontHighlightSmall")
    local show = UI.Switch(content, "SmallerUIShowLootLauncher", "Show Loot Ledger launcher", 4, -72, function(enabled)
        cfg.showLauncher = enabled
        Addon:UpdateLootLauncher()
        page.move:SetEnabled(enabled)
    end)
    page.move = UI.Button(content, nil, "Move launcher", 328, -73, 132, function() Addon:BeginResourceEdit() end)
    UI.Section(content, "Recording", -125)
    local enabled = UI.Switch(content, nil, "Record loot and rolls", 4, -156, function(value) cfg.enabled = value end)
    UI.Label(content, "Entries to keep", 12, -210)
    local limit = UI.EditBox(content, "SmallerUILootLimit")
    limit:SetPoint("TOPLEFT", 135, -203)
    limit:SetSize(92, 27)
    limit:SetAutoFocus(false)
    limit:SetMaxLetters(6)
    UI.Label(content, "Applies per character. Reducing the limit removes the oldest entries.",
        12, -247, "GameFontHighlightSmall", 532)
    local function Restore(field)
        field:SetText(tostring(cfg.limit))
        field:ClearFocus()
    end
    limit:SetScript("OnEscapePressed", Restore)
    limit:SetScript("OnEnterPressed", function(field)
        local ok = Addon:SetLootLimit(tonumber(field:GetText()))
        Addon:OptionsFeedback(ok and "History limit saved." or "Enter a limit from 1,000 to 100,000.", not ok, "loot")
        Restore(field)
    end)
    page:SetScript("OnShow", function()
        enabled:SetChecked(cfg.enabled)
        show:SetChecked(cfg.showLauncher)
        page.move:SetEnabled(cfg.showLauncher)
        Restore(limit)
    end)
    page:SetScript("OnHide", function() limit:ClearFocus() end)
    return page
end
