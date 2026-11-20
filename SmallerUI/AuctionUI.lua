local _, Addon = ...
local features = {}
local tabRoot
local TAVERN_ASPECT = 1 -- The shipped tavern texture is square.

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
        local ratio = math.max(1, frame:GetWidth() - 2) / math.max(1, frame:GetHeight() - 2)
        local uSpan, vSpan = math.min(1, ratio / TAVERN_ASPECT), math.min(1, TAVERN_ASPECT / ratio)
        art:SetTexCoord((1 - uSpan) / 2, (1 + uSpan) / 2, (1 - vSpan) / 2, (1 + vSpan) / 2)
    end
    frame:HookScript("OnSizeChanged", Crop)
    Crop()
end

function Addon:CreateAuctionFeatureTab(id, panel, text)
    local house = AuctionHouseFrame
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
