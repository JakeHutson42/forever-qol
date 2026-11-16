local _, Addon = ...
local driver = CreateFrame("Frame")
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DOT = "Interface\\AddOns\\SmallerUI\\Media\\SwingDot.tga"
local TRACK = "Interface\\AddOns\\SmallerUI\\Media\\Foundry.tga"
local events = { "PLAYER_SWING", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "WEAPON_SLOT_CHANGED" }
local timer, dragging, duration, deadline
local listening = false
local themes = {
    { 1, "Amber", 1, 0.78, 0.32 },
    { 2, "Ice", 0.48, 0.81, 1 },
    { 3, "Emerald", 0.39, 0.9, 0.63 },
    { 4, "White", 0.95, 0.95, 0.95 },
}
Addon.swingThemes = themes
local sizes = { width = { 80, 480 }, height = { 4, 24 } }
Addon.swingSizeLimits = sizes
local ranges = {
    width = sizes.width, height = sizes.height, weapon = { 1, 3 }, shape = { 1, 2 },
    theme = { 1, #themes }, texture = { 1, #Addon.resourceTextures },
}

local function Number(value)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

function Addon:DefaultSwingSettings()
    return { enabled = false, x = 0, y = -216, width = 164, height = 10,
        weapon = 1, shape = 1, theme = 1, texture = 1 }
end

function Addon:ValidateSwingSettings()
    local settings = self:GetResourceSettings().swing
    local defaults = self:DefaultSwingSettings()
    for key, range in pairs(ranges) do
        local value = settings[key]
        if not Number(value) or value ~= math.floor(value) or value < range[1] or value > range[2] then
            settings[key] = defaults[key]
        end
    end
end

function Addon:SupportsSwingTimer()
    return Enum and Enum.PlayerSwingType and C_EventUtils and C_EventUtils.IsEventValid
        and C_EventUtils.IsCallbackEvent and C_EventUtils.IsEventValid("PLAYER_SWING")
        and not C_EventUtils.IsCallbackEvent("PLAYER_SWING")
end

function Addon:CreateSwingDisplay(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:EnableMouse(false)
    local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rail:EnableMouse(false)
    frame.rail = rail
    local bar = CreateFrame("StatusBar", nil, frame)
    frame.bar = bar
    bar:SetFrameLevel(rail:GetFrameLevel() + 1)
    bar:SetPoint("CENTER")
    rail:SetPoint("CENTER", bar, "CENTER")
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture(WHITE)
    local fill = bar:GetStatusBarTexture()
    if fill.SetDrawLayer then fill:SetDrawLayer("ARTWORK") end
    bar:EnableMouse(false)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetTexture(TRACK)
    bar.track:SetVertexColor(0.27, 0.32, 0.34, 1)
    bar.stop = bar:CreateTexture(nil, "ARTWORK")
    bar.stop:SetColorTexture(0.57, 0.65, 0.64, 1)
    bar.dot = bar:CreateTexture(nil, "OVERLAY")
    bar.dot:SetTexture(DOT)
    bar.dot:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    if bar.dot.SetTexelSnappingBias then bar.dot:SetTexelSnappingBias(0) end
    if bar.dot.SetSnapToPixelGrid then bar.dot:SetSnapToPixelGrid(false) end
    return frame
end

function Addon:StyleSwingDisplay(frame, settings)
    local line = settings.shape == 1
    local color = themes[settings.theme]
    local bar, rail = frame.bar, frame.rail
    local pixel = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor() or 1) / frame:GetEffectiveScale()
    local height = line and 2 * pixel or math.max(pixel, math.floor(settings.height / pixel + 0.5) * pixel)
    local dot = math.max(4 * pixel, settings.height)
    local capHeight = line and 4 * pixel or height
    frame:SetSize(settings.width, math.max(16, line and dot or height + 4 * pixel))
    bar:SetSize(settings.width, height)
    rail:SetSize(settings.width + 4 * pixel, capHeight + 4 * pixel)
    if rail.pixel ~= pixel then
        rail:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = pixel })
        rail:SetBackdropColor(0.035, 0.055, 0.064, 1)
        rail:SetBackdropBorderColor(0.016, 0.023, 0.027, 1)
        rail.pixel = pixel
    end
    bar:GetStatusBarTexture():SetTexture(line and WHITE or self.resourceTextures[settings.texture][3])
    bar:SetStatusBarColor(color[3], color[4], color[5])
    bar.stop:ClearAllPoints()
    bar.stop:SetPoint("LEFT", bar, "RIGHT", 0, 0)
    bar.stop:SetSize(pixel, capHeight)
    bar.stop:SetShown(line)
    bar.dot:SetSize(dot, dot)
    bar.dot:SetVertexColor(color[3], color[4], color[5])
    bar.dot:SetShown(line)
end

function Addon:GetSwingTimerFrame() return timer end

function Addon:EndSwingTimerDrag()
    if not dragging then return end
    self:FinishResourceMove()
    dragging = nil
    if not InCombatLockdown() then
        local x, y = timer:GetCenter()
        local cx, cy = UIParent:GetCenter()
        local scale, parentScale = timer:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if Number(x) and Number(y) and Number(cx) and Number(cy) then
            local settings = self:GetResourceSettings().swing
            settings.x, settings.y = x * scale - cx * parentScale, y * scale - cy * parentScale
        end
    end
end

local function EnsureTimer()
    if timer then return end
    timer = Addon:CreateSwingDisplay(UIParent, "SmallerUISwingTimer")
    timer:SetIgnoreParentScale(true)
    timer:SetScale(1)
    timer:SetMovable(true)
    timer:SetClampedToScreen(true)
    timer:RegisterForDrag("LeftButton")
    timer:SetScript("OnDragStart", function()
        dragging = Addon:StartResourceMove(timer, timer, "swing", "Swing timer", "swing", false)
    end)
    timer:SetScript("OnDragStop", function() Addon:EndSwingTimerDrag() end)
    timer:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then Addon:SelectMoveElement("swing", "swing") end
    end)
    timer:Hide()
end

local function Tick()
    local remaining = deadline - GetTime()
    if remaining <= 0 then
        deadline = nil
        driver:SetScript("OnUpdate", nil)
        timer:Hide()
        return
    end
    timer.bar:SetValue(1 - remaining / duration)
end

local function Present(preview)
    driver:SetScript("OnUpdate", nil)
    if not timer then return end
    timer:EnableMouse(preview)
    if preview then
        timer.bar:SetValue(0.56)
        timer:Show()
    elseif deadline and deadline > GetTime() then
        timer:Show()
        driver:SetScript("OnUpdate", Tick)
        Tick()
    else
        deadline = nil
        timer:Hide()
    end
end

function Addon:ApplySwingTimer()
    local settings = self:GetResourceSettings().swing
    local enabled = settings.enabled and self:SupportsSwingTimer() and true or false
    if listening ~= enabled then
        for _, event in ipairs(events) do
            if enabled then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
        end
        listening = enabled
    end
    if not enabled then deadline = nil end
    local preview = Addon:IsEditingResources()
    if enabled or preview then EnsureTimer() end
    if timer and not dragging then
        timer:ClearAllPoints()
        timer:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
        self:StyleSwingDisplay(timer, settings)
    end
    Present(preview)
end

function Addon:SetSwingTimerOption(key, value)
    if key == "enabled" then
        if type(value) ~= "boolean" then return false end
    else
        local range = ranges[key]
        if not range or not Number(value) or value ~= math.floor(value) or value < range[1] or value > range[2] then return false end
    end
    local settings = self:GetResourceSettings().swing
    if key == "weapon" and settings.weapon ~= value then deadline = nil end
    settings[key] = value
    self:ApplySwingTimer()
    self:RefreshSwingOptions()
    return true
end

driver:SetScript("OnEvent", function(_, event, interval, swingType)
    if not listening then return end
    local settings = Addon:GetResourceSettings().swing
    if event == "PLAYER_SWING" then
        local types = Enum.PlayerSwingType
        local trackedType = settings.weapon == 1 and types.MainHand or settings.weapon == 2 and types.OffHand or types.Ranged
        if not Number(swingType) or swingType ~= trackedType then return end
        if not Number(interval) or interval <= 0 then
            deadline = nil
        else
            duration, deadline = interval, GetTime() + interval
        end
    else
        deadline = nil
    end
    Present(Addon:IsEditingResources())
end)
