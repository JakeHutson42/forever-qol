local _, Addon = ...
local button, menu
local COMPASS = "Interface\\AddOns\\SmallerUI\\Media\\MinimapCompass.tga"
local MENU_WIDTH, MENU_HEIGHT = 233, 139
local actions = {
    { "Settings", "Left-click", function() Addon:ShowOptions() end, "INV_Misc_Gear_01" },
    { "Loot Ledger", "Shift + left", function() Addon:ToggleLootLedger() end, "INV_Misc_Bag_10" },
    { "Chat search", "Right-click", function() Addon:ShowChatSearch() end, "INV_Letter_15" },
    { "Toggle chat menu", "Shift + right", function() Addon:ToggleWhisperBar() end, "INV_Misc_GroupLooking" },
}

local function CloseMenu()
    if menu then menu:Hide() end
end

local function RunAction(index)
    CloseMenu()
    actions[index][3]()
end

local function Bounds(frame)
    if not frame or not frame:IsVisible() then return end
    local x, y, width, height = frame:GetRect()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y) or issecretvalue(width) or issecretvalue(height)) then return end
    if not (x and y and width and height) then return end
    local scale = frame:GetEffectiveScale()
    return x * scale, y * scale, width * scale, height * scale
end

local function PlaceMenu()
    local scale = Addon.OptionsUI.FitScale(menu, MENU_WIDTH, MENU_HEIGHT)
    local x, y, bw, bh = Bounds(button)
    local ox, oy, sw, sh = Bounds(UIParent)
    if not (x and ox) then return false end
    local width, height = MENU_WIDTH * scale, MENU_HEIGHT * scale
    local left, right = x - width - 4, x + bw + 4
    local centeredY = y + (bh - height) * 0.5
    local centeredX = x + (bw - width) * 0.5
    local candidates = { { left, centeredY }, { right, centeredY },
        { centeredX, y - height - 4 }, { centeredX, y + bh + 4 } }
    if x + bw * 0.5 < ox + sw * 0.5 then candidates[1], candidates[2] = candidates[2], candidates[1] end
    local trackers = {}
    for _, frame in pairs({ ObjectiveTrackerFrame, QuestWatchFrame, Questie_BaseFrame }) do
        local tx, ty, tw, th = Bounds(frame)
        if tx then
            trackers[#trackers + 1] = { tx, ty, tw, th }
            candidates[#candidates + 1] = { tx - width - 5, centeredY }
            candidates[#candidates + 1] = { tx + tw + 5, centeredY }
            candidates[#candidates + 1] = { centeredX, ty + th + 5 }
            candidates[#candidates + 1] = { centeredX, ty - height - 5 }
        end
    end
    local function Overlap(px, py, tx, ty, tw, th)
        return math.max(0, math.min(px + width, tx + tw) - math.max(px, tx))
            * math.max(0, math.min(py + height, ty + th) - math.max(py, ty))
    end
    local best, lx, ly, distance
    for _, point in ipairs(candidates) do
        local px = math.max(ox + 5, math.min(ox + sw - width - 5, point[1]))
        local py = math.max(oy + 5, math.min(oy + sh - height - 5, point[2]))
        local gap = math.max(0, x - px - width, px - x - bw) + math.max(0, y - py - height, py - y - bh)
        local score = gap + 8 * Overlap(px, py, x, y, bw, bh)
        for _, tracker in ipairs(trackers) do
            score = score + 2 * Overlap(px, py, unpack(tracker))
        end
        if not best or score < best then best, lx, ly, distance = score, px, py, gap end
    end
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (lx - ox) / scale, (ly - oy) / scale)
    menu.linger = 0.22 + math.min(0.30, math.max(0, distance - 4) / 380)
    return true
end

local function ShowMenu()
    if button.dragging then return end
    if not menu then
        local UI = Addon.OptionsUI
        menu = CreateFrame("Frame", "SmallerUIMinimapMenu", UIParent, "BackdropTemplate")
        menu:Hide()
        menu:SetSize(MENU_WIDTH, MENU_HEIGHT)
        menu:SetIgnoreParentScale(true)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetFrameLevel(900)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        UI.WindowSurface(menu)
        local crest = menu:CreateTexture(nil, "ARTWORK")
        crest:SetSize(17, 17)
        crest:SetPoint("TOPLEFT", 11, -9)
        crest:SetTexture(COMPASS)
        crest:SetVertexColor(1, 0.84, 0.56)
        local title = UI.Label(menu, Addon.displayName, 35, -10, "GameFontNormal")
        title:SetTextColor(0.96, 0.80, 0.53)
        for index, action in ipairs(actions) do
            local row = UI.Button(menu, nil, action[1], 8, -31 - (index - 1) * 25, MENU_WIDTH - 16,
                function() RunAction(index) end, true)
            row:SetHeight(23)
            row:SetBackdropBorderColor(0, 0, 0, 0)
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("LEFT", 5, 0)
            icon:SetTexture("Interface\\Icons\\" .. action[4])
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", 24, 0)
            row.label:SetTextColor(0.94, 0.90, 0.82)
            local shortcut = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            shortcut:SetPoint("RIGHT", -6, 0)
            shortcut:SetText(action[2])
            shortcut:SetTextColor(0.78, 0.68, 0.54)
        end
        menu:RegisterEvent("UI_SCALE_CHANGED")
        menu:RegisterEvent("DISPLAY_SIZE_CHANGED")
        menu:SetScript("OnEvent", function(self) if self:IsShown() then PlaceMenu() end end)
        menu:SetScript("OnUpdate", function(self, elapsed)
            self.outside = (button:IsMouseOver() or self:IsMouseOver()) and 0 or self.outside + elapsed
            if not button:IsVisible() or self.outside >= self.linger then self:Hide() end
        end)
    end
    if not PlaceMenu() then return end
    menu.outside = 0
    menu:Show()
end

function Addon:ValidateMinimap()
    self.db.showMinimap = self.db.showMinimap ~= false
    local angle = self.db.minimapAngle
    if type(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = 225 end
    self.db.minimapAngle = angle % 360
end

local function Position()
    local angle = math.rad(Addon.db.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 8
    local x, y = math.cos(angle), math.sin(angle)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        radius = radius / math.max(math.abs(x), math.abs(y))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

function Addon:UpdateMinimap()
    if not self.db or not Minimap or InCombatLockdown() then return end
    if not button then
        button = CreateFrame("Button", "SmallerUIMinimapButton", Minimap)
        button:SetSize(32, 32)
        button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(COMPASS)
        icon:SetAllPoints()
        icon:SetVertexColor(1, 0.84, 0.56)
        button:SetHighlightTexture(COMPASS, "ADD")
        button:GetHighlightTexture():SetVertexColor(0.40, 0.30, 0.17, 0.46)
        button:SetScript("OnClick", function(_, mouseButton)
            local shift = IsShiftKeyDown and IsShiftKeyDown()
            RunAction((mouseButton == "RightButton" and 3 or 1) + (shift and 1 or 0))
        end)
        button:SetScript("OnEnter", ShowMenu)
        button:SetScript("OnHide", function(self)
            CloseMenu()
            self.dragging = nil
            self:SetScript("OnUpdate", nil)
        end)
        button:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            self.dragging = true
            CloseMenu()
            self:SetScript("OnUpdate", function()
                if InCombatLockdown() then self.dragging = nil; self:SetScript("OnUpdate", nil); return end
                local x, y = GetCursorPosition()
                local centerX, centerY = Minimap:GetCenter()
                local scale = Minimap:GetEffectiveScale()
                Addon.db.minimapAngle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX)) % 360
                Position()
            end)
        end)
        button:SetScript("OnDragStop", function(self) self.dragging = nil; self:SetScript("OnUpdate", nil) end)
    end
    Position()
    button:SetShown(self.db.showMinimap)
end
