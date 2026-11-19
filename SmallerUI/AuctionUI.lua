local _, Addon = ...
local features = {}
local tabRoot
local rail, railTabs = nil, {}
local RAIL_PADDING, RAIL_GAP, RAIL_TOP = 24, 10, 54

-- Keep the library's buttons as invisible controllers. Copy their native art
-- into real, vertical hit targets so library selection and late tab additions
-- continue to work without a horizontal mouse region over neighbouring UI.
local function RailTab(source)
    if source.qolSideTab then return end
    local button = CreateFrame("Button", nil, rail)
    source.qolSideTab = button
    button.source, button.art = source, {}
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("CENTER")
    button.label:SetWordWrap(false)
    button.label:SetRotation(-math.pi / 2)
    button:SetScript("OnClick", function(_, mouseButton)
        local click = source:GetScript("OnClick")
        if click then click(source, mouseButton) end
        Addon:LayoutAuctionTabs()
    end)
    button:SetScript("OnEnter", function()
        button.hover = true
        Addon:LayoutAuctionTabs()
    end)
    button:SetScript("OnLeave", function()
        button.hover = false
        Addon:LayoutAuctionTabs()
    end)
    source:SetAlpha(0)
    source:EnableMouse(false)
    source:HookScript("OnShow", function() Addon:LayoutAuctionTabs() end)
    source:HookScript("OnHide", function() Addon:LayoutAuctionTabs() end)
    railTabs[#railTabs + 1] = button
end

local function CopyTabArt(button)
    local source = button.source
    local sx, sy, sw, sh = source:GetRect()
    if not sx then return button:GetWidth(), button:GetHeight() end
    local regions = source.GetRegions and { source:GetRegions() } or {}
    local minX, minY, maxX, maxY = 0, 0, sw, sh
    local textures = {}
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "Texture" then
            local x, y, w, h = region:GetRect()
            if x and y then
                textures[#textures + 1] = { region, x - sx, y - sy, w, h }
                minX, minY = math.min(minX, x - sx), math.min(minY, y - sy)
                maxX, maxY = math.max(maxX, x - sx + w), math.max(maxY, y - sy + h)
            end
        end
    end
    local width, height = maxY - minY, maxX - minX
    button:SetSize(width, height)
    for index, entry in ipairs(textures) do
        local region, x, y, w, h = unpack(entry)
        local copy = button.art[index]
        if not copy then
            copy = button:CreateTexture(nil, "ARTWORK")
            button.art[index] = copy
        end
        local layer, sublevel = region:GetDrawLayer()
        copy:SetDrawLayer(layer == "HIGHLIGHT" and "OVERLAY" or layer, sublevel)
        copy:SetTexture(region:GetTexture())
        local ulx, uly, llx, lly, urx, ury, lrx, lry = region:GetTexCoord()
        copy:SetTexCoord(llx, lly, lrx, lry, ulx, uly, urx, ury)
        copy:SetVertexColor(region:GetVertexColor())
        copy:SetAlpha(region:GetAlpha())
        copy:ClearAllPoints()
        copy:SetPoint("TOPLEFT", button, "TOPLEFT", y - minY, -(x - minX))
        copy:SetSize(h, w)
        copy:SetShown(region:IsShown() and (layer ~= "HIGHLIGHT" or button.hover == true))
    end
    for index = #textures + 1, #button.art do button.art[index]:Hide() end
    local text = source.GetFontString and source:GetFontString()
    button.label:SetText(source:GetText())
    if text then
        button.label:SetFont(text:GetFont())
        button.label:SetTextColor(text:GetTextColor())
        local tx, ty = text:GetCenter()
        if tx then
            button.label:ClearAllPoints()
            button.label:SetPoint("CENTER", button, "TOPLEFT", ty - sy - minY, -(tx - sx - minX))
        end
    end
    button.label:SetWidth(math.max(1, height - 24))
    button:SetEnabled(source:IsEnabled())
    return width, height
end

local function RootRect(frame)
    local x, y, w, h = frame:GetRect()
    if not x or not y then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * scale, y * scale, w * scale, h * scale
end

function Addon:LayoutAuctionTabs()
    if not rail or not AuctionHouseFrame:IsShown() then return end
    local house = AuctionHouseFrame
    local library = LibStub and LibStub("LibAHTab-1-0", true)
    for _, source in ipairs(library and library.internalState and library.internalState.Tabs or {}) do RailTab(source) end
    local width, height, visible = 0, 0, {}
    for _, button in ipairs(railTabs) do
        button:SetShown(button.source:IsVisible())
        if button:IsShown() then
            local w, h = CopyTabArt(button)
            width, height = math.max(width, w), height + h + RAIL_GAP
            visible[#visible + 1] = button
        end
    end
    if #visible == 0 then rail:SetSize(1, 1); return end
    rail:Show()
    height = height - RAIL_GAP
    local hx, hy, hw, hh = RootRect(house)
    if not hx then return end
    local houseScale = house:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local padding = RAIL_PADDING * houseScale
    local top = math.min(screenHeight - padding, hy + hh - RAIL_TOP * houseScale)
    local scale = houseScale * math.min(1, math.max(1, math.min(hh - RAIL_TOP * houseScale - padding, top - padding)) / height)
    local right, level = hx + hw, house:GetFrameLevel() + 30
    local bottom = top - height * scale
    local candidates = {}
    local function Collect(parent, depth)
        if not parent.GetChildren then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= rail and child ~= house and not child:IsForbidden() and child:IsVisible() then
                local x, y, w, h = RootRect(child)
                -- Exclude fullscreen managers, and join only adjacent windows
                -- crossing the rail's vertical span. Work in UIParent units.
                if x and w > 0 and w < screenWidth * 0.75 and y < top and y + h > bottom then
                    candidates[#candidates + 1] = { x, x + w, child:GetFrameLevel() }
                end
                if depth > 0 then Collect(child, depth - 1) end
            end
        end
    end
    Collect(house, 2)
    Collect(UIParent, 0)
    for _ = 1, #candidates do
        local previous = right
        for _, rect in ipairs(candidates) do
            if rect[1] >= hx and rect[1] <= right + padding * 2 and rect[2] > right then
                right, level = rect[2], math.max(level, rect[3] + 10)
            end
        end
        if right == previous then break end
    end
    -- On a cramped viewport keep the complete rail on screen above adjacent
    -- panels, rather than letting the last column disappear past the edge.
    local left = math.max(padding, math.min(right + padding, screenWidth - padding - width * scale))
    rail:SetScale(scale / houseScale)
    rail:SetFrameLevel(level)
    rail:ClearAllPoints()
    rail:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
    rail:SetSize(width, height)
    local offset = 0
    for _, button in ipairs(visible) do
        button:ClearAllPoints()
        button:SetPoint("TOP", rail, "TOP", 0, -offset)
        button:SetFrameLevel(level + 1)
        offset = offset + button:GetHeight() + RAIL_GAP
    end
end

local function EnsureRail(house)
    if rail then return end
    rail = CreateFrame("Frame", "SmallerUIAuctionTabRail", house)
    rail:SetSize(1, 1)
    rail:SetFrameStrata("DIALOG")
    local elapsed = 0
    rail:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.15 then return end
        elapsed = 0
        Addon:LayoutAuctionTabs()
    end)
    house:HookScript("OnShow", function() Addon:LayoutAuctionTabs() end)
end

function Addon:AuctionSurface(frame)
    local UI = self.OptionsUI
    UI.Backdrop(frame, { 0.07, 0.035, 0.015, 1 }, { 0.60, 0.43, 0.23, 1 })
    local art = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetPoint("TOPLEFT", 1, -1)
    art:SetPoint("BOTTOMRIGHT", -1, 1)
    art:SetTexture("Interface\\AddOns\\SmallerUI\\Media\\AuctionTavern.tga")
    art:SetVertexColor(0.65, 0.56, 0.45)
    local shade = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    shade:SetAllPoints(art)
    shade:SetColorTexture(0.035, 0.017, 0.007, 0.40)
    local function Crop()
        local ratio = frame:GetWidth() / math.max(1, frame:GetHeight())
        if ratio < 1.5 then
            local span = ratio / 1.5
            art:SetTexCoord((1 - span) / 2, (1 + span) / 2, 0, 1)
        else
            local span = 1.5 / ratio
            art:SetTexCoord(0, 1, 0, span)
        end
    end
    frame:HookScript("OnSizeChanged", Crop)
    Crop()
end

function Addon:CreateAuctionFeatureTab(id, panel, text)
    local house = AuctionHouseFrame
    EnsureRail(house)
    local library = LibStub and LibStub("LibAHTab-1-0", true)
    local button
    if library then
        library:CreateTab(id, panel, text)
        button = library:GetButton(id)
    else
        local previous = features[#features] and features[#features].button
            or house.Tabs and house.Tabs[#house.Tabs] or house.AuctionsTab
        if not tabRoot then
            tabRoot = CreateFrame("Frame", nil, house)
            tabRoot:SetSize(1, 1)
            tabRoot:SetPoint("TOPLEFT")
        end
        button = CreateFrame("Button", id, tabRoot, "AuctionHouseFrameDisplayModeTabTemplate")
        button:SetText(text)
        if PanelTemplates_TabResize then PanelTemplates_TabResize(button, 20, nil, 70) end
        if previous then
            button:SetPoint("TOPLEFT", previous, "TOPRIGHT", 3, 0)
        else
            button:SetPoint("BOTTOMLEFT", house, "BOTTOMLEFT", 18, -30)
        end
        button:SetScript("OnClick", function()
            if house.SetDisplayMode then house:SetDisplayMode({}) end
            house.displayMode = nil
            for _, entry in ipairs(features) do
                entry.panel:Hide()
                if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(entry.button) end
            end
            for _, native in ipairs(house.Tabs or {}) do
                if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(native) end
            end
            if PanelTemplates_SelectTab then PanelTemplates_SelectTab(button) end
            if house.SetTitle then house:SetTitle(text) end
            panel:Show()
        end)
        if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(button) end
    end
    button:SetFrameLevel(house:GetFrameLevel() + 30)
    panel:SetFrameLevel(house:GetFrameLevel() + 5)
    panel:EnableMouse(true)
    features[#features + 1] = { button = button, panel = panel }
    local function Close()
        panel:Hide()
        if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(button) end
    end
    for _, native in ipairs(house.Tabs or { house.BuyTab, house.SellTab, house.AuctionsTab }) do
        native:HookScript("OnClick", Close)
    end
    if not library and house.SetDisplayMode and hooksecurefunc then hooksecurefunc(house, "SetDisplayMode", Close) end
    house:HookScript("OnHide", Close)
    RailTab(button)
    self:LayoutAuctionTabs()
    return button
end

function Addon:AuctionModeTab(parent, name, label, previous, callback)
    local button = CreateFrame("Button", name, parent, "PanelTabButtonTemplate")
    button:SetText(label)
    if previous then button:SetPoint("TOPLEFT", previous, "TOPRIGHT", 4, 0)
    else button:SetPoint("TOPLEFT", 0, 0) end
    if PanelTemplates_TabResize then PanelTemplates_TabResize(button, 18, nil, 95) end
    button:SetScript("OnClick", callback)
    return button
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
    if AuctionHouseFrame then
        EnsureRail(AuctionHouseFrame)
        Addon:LayoutAuctionTabs()
    end
end)
