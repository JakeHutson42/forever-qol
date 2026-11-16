local _, Addon = ...
local overlay, selection, drag, selected, selectedName
local toolbar, activeScope, activeKind
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ENAMEL = "Interface\\AddOns\\SmallerUI\\Media\\Foundry.tga"
local JEWEL = "Interface\\AddOns\\SmallerUI\\Media\\TrimJewel.tga"
local WIDTH, HEIGHT = 568, 135
local snapHint = "Hold Shift to bypass snapping"
local function Number(value)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end
local function Pixel()
    local size = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor()
    return Number(size) and size > 0 and size or 1
end
local function Rect(frame)
    if not frame then return end
    local x, y, width, height = frame:GetRect()
    local scale = frame:GetEffectiveScale()
    if not Number(x) or not Number(y) or not Number(width) or not Number(height) or not Number(scale) or scale <= 0 then return end
    return { x = x * scale, y = y * scale, width = width * scale, height = height * scale }
end

local function DrawGrid(grid)
    local screen = Rect(UIParent)
    if not screen then return end
    local spacing, pixel = 32, Pixel()
    local used = 0
    local function Axis(vertical, span, length)
        local count = math.floor((span - pixel) / (2 * spacing))
        for step = -count, count do
            used = used + 1
            local line = grid.lines[used]
            if not line then
                line = grid:CreateTexture(nil, "ARTWORK")
                grid.lines[used] = line
            end
            local offset = math.floor((span / 2 + step * spacing) / pixel + 0.5) * pixel
            line:ClearAllPoints()
            line:SetPoint("BOTTOMLEFT", vertical and offset or 0, vertical and 0 or offset)
            line:SetSize(vertical and pixel or length, vertical and length or pixel)
            line:SetColorTexture(0.85, 0.79, 0.64, step == 0 and 0.50 or step % 4 == 0 and 0.32 or 0.17)
            line:Show()
        end
    end
    Axis(true, screen.width, screen.height)
    Axis(false, screen.height, screen.width)
    for index = used + 1, #grid.lines do grid.lines[index]:Hide() end
end
local function Descendant(frame, parent)
    while frame do
        if frame == parent then return true end
        frame = frame:GetParent()
    end
    return false
end
local function EnsureOverlay()
    if overlay then return end
    overlay = CreateFrame("Frame", "SmallerUIMoveOverlay", UIParent)
    overlay:SetIgnoreParentScale(true)
    overlay:SetScale(1)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:EnableMouse(false)
    local grid = CreateFrame("Frame", "SmallerUIMoveGrid", overlay)
    grid:SetAllPoints()
    grid:SetFrameStrata("LOW")
    grid:EnableMouse(false)
    grid.lines = {}
    grid:Hide()
    overlay.grid = grid
    local function Guide(name, vertical)
        local line = CreateFrame("Frame", name, overlay)
        line:EnableMouse(false)
        local shadow = line:CreateTexture(nil, "BACKGROUND")
        shadow:SetAllPoints()
        shadow:SetColorTexture(0.05, 0.06, 0.07, 0.60)
        line.texture = line:CreateTexture(nil, "OVERLAY")
        line.texture:SetPoint(vertical and "TOP" or "LEFT")
        line.texture:SetPoint(vertical and "BOTTOM" or "RIGHT")
        line.texture:SetColorTexture(1, 0.78, 0.40, 0.92)
        line:Hide()
        return line
    end
    overlay.vertical = Guide("SmallerUIMoveVerticalGuide", true)
    overlay.horizontal = Guide("SmallerUIMoveHorizontalGuide", false)
    selection = CreateFrame("Frame", "SmallerUIMoveSelection", overlay, "BackdropTemplate")
    selection:SetFrameLevel(100)
    selection:EnableMouse(false)
    local UI = Addon.OptionsUI
    selection.outline = CreateFrame("Frame", nil, selection, "BackdropTemplate")
    selection.outline:EnableMouse(false)
    local tag = CreateFrame("Frame", nil, selection, "BackdropTemplate")
    tag:EnableMouse(false)
    UI.Plate(tag, { 0.10, 0.14, 0.15, 1 })
    tag:SetBackdropBorderColor(0.63, 0.50, 0.31, 1)
    selection.tag = tag
    selection.label = UI.Label(tag, "", 8, -5, "GameFontNormalSmall")
    selection.label:SetWordWrap(false)
    selection.size = tag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selection.size:SetPoint("RIGHT", -8, 0)
    selection.size:SetTextColor(0.80, 0.85, 0.86)
    selection:Hide()
end
local function HideGuides()
    if overlay then overlay.vertical:Hide(); overlay.horizontal:Hide() end
end
local function DrawSelection()
    if not selected or not selected:IsVisible() then selection:Hide(); return end
    local bounds, screen = Rect(selected), Rect(UIParent)
    if not bounds or not screen then selection:Hide(); return end
    local pixel = Pixel()
    if selection.pixel ~= pixel then
        selection:SetBackdrop({ edgeFile = WHITE, edgeSize = 3 * pixel })
        selection:SetBackdropBorderColor(0.035, 0.044, 0.047, 0.90)
        local outline = selection.outline
        outline:SetBackdrop({ edgeFile = WHITE, edgeSize = pixel })
        outline:SetBackdropBorderColor(1, 0.80, 0.43, 1)
        outline:ClearAllPoints()
        outline:SetPoint("TOPLEFT", pixel, -pixel)
        outline:SetPoint("BOTTOMRIGHT", -pixel, pixel)
        selection.pixel = pixel
    end
    selection:SetSize(bounds.width + 6 * pixel, bounds.height + 6 * pixel)
    selection:ClearAllPoints()
    selection:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bounds.x - screen.x - 3 * pixel, bounds.y - screen.y - 3 * pixel)
    local width, height = math.floor(bounds.width / pixel + 0.5), math.floor(bounds.height / pixel + 0.5)
    if selection.name ~= selectedName or selection.widthPx ~= width or selection.heightPx ~= height then
        selection.name, selection.widthPx, selection.heightPx = selectedName, width, height
        selection.label:SetText(selectedName)
        selection.size:SetText(("%d × %d px"):format(width, height))
        local nameWidth = selection.label.GetUnboundedStringWidth
            and selection.label:GetUnboundedStringWidth() or #selectedName * 7
        selection.sizeWidth = selection.size.GetUnboundedStringWidth
            and selection.size:GetUnboundedStringWidth() or #selection.size:GetText() * 6
        selection.tagWidth = math.ceil(nameWidth + selection.sizeWidth + 30)
    end
    local tagWidth = math.max(1, math.min(selection.tagWidth, screen.width - 8))
    local x = math.max(4, math.min(screen.width - tagWidth - 4, bounds.x - screen.x))
    local above, below = bounds.y + bounds.height - screen.y + 27, bounds.y - screen.y - 5
    local view, kind = selected.view, selected.resourceKind
    local sibling = view and kind and view[kind == "health" and "power" or "health"]
    local nearby = sibling and sibling:IsVisible() and Rect(sibling)
    if nearby and x + screen.x < nearby.x + nearby.width and x + screen.x + tagWidth > nearby.x then
        local siblingBottom, siblingTop = nearby.y - screen.y, nearby.y + nearby.height - screen.y
        if below > siblingBottom and below - 22 < siblingTop then below = siblingBottom - 5 end
        if above > siblingBottom and above - 22 < siblingTop then above = below >= 26 and below or siblingTop + 27 end
    end
    local top = above <= screen.height - 4 and above or below
    top = math.max(25, math.min(screen.height - 4, top))
    selection.tag:SetSize(tagWidth, 22)
    selection.label:SetWidth(math.max(1, tagWidth - selection.sizeWidth - 20))
    selection.tag:ClearAllPoints()
    selection.tag:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
    selection:Show()
end

function Addon:SelectResourceMoveTarget(target, name, scope, kind)
    if not self:IsEditingResources() or InCombatLockdown() or not target then return false end
    if drag and drag.target ~= target then return false end
    EnsureOverlay()
    if scope and scope ~= "element" then self:HideElementMoveTarget() end
    selected, selectedName = target, name
    overlay:Show()
    if scope then
        activeScope, activeKind = scope, kind
        if toolbar then toolbar:RefreshSelection() end
    end
    DrawSelection()
    return true
end

function Addon:StartResourceMove(target, anchor, scope, name, kind, linked)
    if not self:IsEditingResources() or InCombatLockdown() or drag then return false end
    local bounds, anchorBounds = Rect(target), Rect(anchor)
    local x, y = GetCursorPosition()
    if not bounds or not anchorBounds or not Number(x) or not Number(y) then return false end
    if name then self:SelectResourceMoveTarget(target, name, scope, kind) end
    target:StopMovingOrSizing()
    target:SetClampedToScreen(false) -- The raw cursor and our screen clamp stay independent of snapping.
    drag = { target = target, anchor = anchor, scope = scope, kind = kind, linked = linked,
        bounds = bounds, anchorBounds = anchorBounds, cursorX = x, cursorY = y,
        sawHeld = IsMouseButtonDown("LeftButton") }
    if toolbar then toolbar:RefreshSelection() end
    return true
end

local function Candidates()
    local result, display = {}, Addon:GetResourceDisplay()
    local function Add(frame, scope, kind)
        if not frame or not frame:IsVisible() or Descendant(frame, drag.target) then return end
        if drag.scope == "party" and scope == "party" and (drag.linked or kind == drag.kind or not kind) then return end
        if not kind and scope == drag.scope then return end
        -- The seal follows personal health, even when that health bar is unlinked.
        if kind == "seal" and Addon:GetResourceSettings().seal.linked and drag.scope == "player"
            and (drag.linked or drag.kind == "health") then return end
        local bounds = Rect(frame)
        if bounds then result[#result + 1] = bounds end
    end
    local function View(view)
        Add(view, view.scope)
        Add(view.health, view.scope, "health")
        Add(view.power, view.scope, "power")
    end
    View(display.player)
    View(display.pet)
    Add(display.partyRoot, "party")
    for _, view in ipairs(display.party) do View(view) end
    Add(display.player.seal, "player", "seal")
    Add(Addon:GetSwingTimerFrame(), "swing", "swing")
    Add(Addon:GetLootLauncher(), "lootLauncher")
    return result
end
local function ClampOrigin(value, size, low, high)
    if size > high - low then return math.max(high - size, math.min(low, value)) end
    return math.max(low, math.min(high - size, value))
end
local function Features(bounds, axis, delta)
    local low = bounds[axis] + delta
    local size = axis == "x" and bounds.width or bounds.height
    return { low, low + size / 2, low + size }
end
local function Snap(axis, delta, targets, screen)
    local best, guide, distance = 0, nil, 8 * Pixel() + 0.000001
    local source = Features(drag.bounds, axis, delta)
    if drag.anchor ~= drag.target then
        for _, value in ipairs(Features(drag.anchorBounds, axis, delta)) do source[#source + 1] = value end
    end
    local marks = Features(screen, axis, 0)
    for _, target in ipairs(targets) do
        for _, value in ipairs(Features(target, axis, 0)) do marks[#marks + 1] = value end
    end
    for _, mark in ipairs(marks) do
        for _, value in ipairs(source) do
            local offset = mark - value
            if math.abs(offset) < distance then best, guide, distance = offset, mark, math.abs(offset) end
        end
    end
    return best, guide
end
local function DrawGuides(screen, x, y, shift)
    HideGuides()
    local pixel = Pixel()
    if x then
        overlay.vertical:ClearAllPoints()
        overlay.vertical:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x - screen.x - pixel, 0)
        overlay.vertical:SetSize(3 * pixel, screen.height)
        overlay.vertical.texture:SetWidth(pixel)
        overlay.vertical:Show()
    end
    if y then
        overlay.horizontal:ClearAllPoints()
        overlay.horizontal:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, y - screen.y - pixel)
        overlay.horizontal:SetSize(screen.width, 3 * pixel)
        overlay.horizontal.texture:SetHeight(pixel)
        overlay.horizontal:Show()
    end
    if toolbar then
        local hint = shift and "Snapping paused" or (x or y) and "Snapped · Shift to release" or snapHint
        if toolbar.hint:GetText() ~= hint then toolbar.hint:SetText(hint) end
    end
end

function Addon:UpdateResourceMoveMode()
    if not overlay or not self:IsEditingResources() then return end
    if drag and not drag.finishing then
        if IsMouseButtonDown("LeftButton") then drag.sawHeld = true
        elseif drag.sawHeld then
            if drag.scope == "seal" then self:EndSealDrag()
            elseif drag.scope == "swing" then self:EndSwingTimerDrag()
            elseif drag.scope == "lootLauncher" then self:EndLootLauncherDrag()
            elseif drag.scope == "element" then self:EndElementDrag()
            else self:EndResourceDrag() end
            return
        end
    end
    if drag and not InCombatLockdown() then
        local x, y = GetCursorPosition()
        local screen = Rect(UIParent)
        if Number(x) and Number(y) and screen then
            local rawX, rawY = x - drag.cursorX, y - drag.cursorY
            local offsetX, offsetY, guideX, guideY = 0, 0, nil, nil
            local shift = IsShiftKeyDown and IsShiftKeyDown()
            if not shift then
                local targets = Candidates()
                offsetX, guideX = Snap("x", rawX, targets, screen)
                offsetY, guideY = Snap("y", rawY, targets, screen)
            end
            local left = ClampOrigin(drag.bounds.x + rawX + offsetX, drag.bounds.width, screen.x, screen.x + screen.width)
            local bottom = ClampOrigin(drag.bounds.y + rawY + offsetY, drag.bounds.height, screen.y, screen.y + screen.height)
            if math.abs(left - drag.bounds.x - rawX - offsetX) > 0.001 then guideX = nil end
            if math.abs(bottom - drag.bounds.y - rawY - offsetY) > 0.001 then guideY = nil end
            local scale = drag.target:GetEffectiveScale()
            drag.target:ClearAllPoints()
            drag.target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (left - screen.x) / scale, (bottom - screen.y) / scale)
            drag.snapX, drag.snapY, drag.shift = guideX, guideY, shift
            DrawGuides(screen, guideX, guideY, shift)
        end
    end
    DrawSelection()
end

function Addon:FinishResourceMove()
    if not drag then return end
    -- Re-evaluate modifiers and the final pointer position on release.
    drag.finishing = true
    self:UpdateResourceMoveMode()
    local previous = drag
    drag = nil
    previous.target:SetClampedToScreen(true)
    HideGuides()
    if toolbar then
        toolbar.hint:SetText(snapHint)
        toolbar:RefreshSelection()
    end
end

function Addon:CloseResourceMoveMode()
    if drag then drag.target:SetClampedToScreen(true) end
    drag, selected, selectedName = nil, nil, nil
    activeScope, activeKind = nil, nil
    if overlay then
        HideGuides()
        overlay.grid:Hide()
        selection:Hide()
        overlay:Hide()
    end
    if toolbar then toolbar.gridToggle:SetText("Show grid") end
end

function Addon:GetResourceMoveState() return drag end

local targets = {
    { "player:health", "Personal health", "player", "health" },
    { "player:power", "Personal power", "player", "power" },
    { "party:health", "Party health", "party", "health" },
    { "party:power", "Party power", "party", "power" },
    { "pet:health", "Pet health", "pet", "health" },
    { "pet:power", "Pet power", "pet", "power" },
    { "swing:swing", "Swing timer", "swing", "swing" },
}
local sealTarget = { "seal:seal", "Paladin seal", "seal", "seal" }
local lootTarget = { "lootLauncher:lootLauncher", "Loot Ledger launcher", "lootLauncher", "lootLauncher" }

local function FitToolbar(self)
    local screen = Rect(UIParent)
    if not screen then return end
    self:SetScale(math.max(0.1, math.min(1, (screen.width - 24) / WIDTH, (screen.height - 48) / HEIGHT)))
end

function Addon:CreateResourceMoveToolbar()
    if toolbar then return toolbar end
    local UI = self.OptionsUI
    toolbar = CreateFrame("Frame", "SmallerUIResourceEditor", UIParent, "BackdropTemplate")
    toolbar:Hide()
    toolbar:SetIgnoreParentScale(true)
    toolbar:SetFrameStrata("DIALOG")
    toolbar:SetFrameLevel(110)
    toolbar:SetSize(WIDTH, HEIGHT)
    toolbar:SetPoint("TOP", 0, -22)
    toolbar:SetMovable(true)
    toolbar:SetClampedToScreen(true)
    toolbar:EnableMouse(true)
    toolbar:RegisterForDrag("LeftButton")
    toolbar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    toolbar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    UI.Backdrop(toolbar, { 0.053, 0.073, 0.080, 1 }, { 0.58, 0.46, 0.29, 1 })
    toolbar:RegisterEvent("UI_SCALE_CHANGED")
    toolbar:RegisterEvent("DISPLAY_SIZE_CHANGED")
    toolbar:SetScript("OnEvent", function(self)
        if self:IsShown() then FitToolbar(self) end
        if overlay and overlay.grid:IsVisible() then DrawGrid(overlay.grid) end
    end)
    toolbar:SetScript("OnShow", FitToolbar)
    local header = toolbar:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(35)
    header:SetTexture(ENAMEL)
    header:SetVertexColor(0.19, 0.25, 0.26)
    local edge = toolbar:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
    edge:SetHeight(1)
    edge:SetColorTexture(0.58, 0.45, 0.28, 0.8)
    local emblem = toolbar:CreateTexture(nil, "ARTWORK")
    emblem:SetPoint("TOPLEFT", 12, -10)
    emblem:SetSize(16, 16)
    emblem:SetTexture(JEWEL)
    emblem:SetVertexColor(1, 0.86, 0.55)
    local title = UI.Label(toolbar, "Move Mode", 35, -9, "GameFontNormalLarge")
    title:SetTextColor(0.96, 0.81, 0.54)
    toolbar.hint = toolbar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    toolbar.hint:SetPoint("TOPRIGHT", -14, -12)
    toolbar.hint:SetText(snapHint)
    toolbar.hint:SetTextColor(0.82, 0.85, 0.85)
    UI.Label(toolbar, "Element", 14, -43, "GameFontNormalSmall")
    UI.Label(toolbar, "Scale", 244, -43, "GameFontNormalSmall")
    UI.Label(toolbar, "Movement", 344, -43, "GameFontNormalSmall")
    local choices, byKey = {}, {}
    for _, entry in ipairs(targets) do choices[#choices + 1] = entry; byKey[entry[1]] = entry end
    if self:IsPaladin() then choices[#choices + 1] = sealTarget; byKey[sealTarget[1]] = sealTarget end
    local function Choices()
        local available = { unpack(choices) }
        if Addon:GetLootSettings().showLauncher then
            available[#available + 1] = lootTarget
            byKey[lootTarget[1]] = lootTarget
        end
        for _, entry in ipairs(Addon:GetElementMoveChoices()) do
            available[#available + 1] = entry
            byKey[entry[1]] = entry
        end
        return available
    end
    local select = UI.Select(toolbar, "SmallerUIMoveTarget", 14, -60, 211, Choices, function()
        return activeScope and activeScope .. ":" .. activeKind
    end, function(key)
        local entry = byKey[key]
        Addon:SelectMoveElement(entry[3], entry[4])
    end)
    local function Adjust(factor)
        if not activeScope or drag or InCombatLockdown() then return end
        local _, resize = Addon:GetMoveElementControls(activeScope, activeKind)
        resize(factor)
        DrawSelection()
    end
    local smaller = UI.Button(toolbar, "SmallerUIMoveScaleDown", "−", 244, -60, 37, function() Adjust(1 / 1.1) end)
    UI.Tooltip(smaller, "Scale the selected element down")
    local larger = UI.Button(toolbar, "SmallerUIMoveScaleUp", "+", 285, -60, 37, function() Adjust(1.1) end)
    UI.Tooltip(larger, "Scale the selected element up")
    local link = UI.Switch(toolbar, "SmallerUIMoveGroup", "", 342, -59, function(enabled)
        if not activeScope or drag then toolbar:RefreshSelection(); return end
        local _, _, setLinked = Addon:GetMoveElementControls(activeScope, activeKind)
        if setLinked then setLinked(enabled) end
        Addon:SelectMoveElement(activeScope, activeKind)
    end, "Move and scale related elements together. The seal groups with personal health.")
    link:SetWidth(132)
    toolbar.groupState = UI.Label(link, "", 46, -7, "GameFontHighlightSmall")
    local single = UI.Label(toolbar, "Single element", 344, -67, "GameFontHighlightSmall")
    single:SetTextColor(0.71, 0.76, 0.77)
    local reset = UI.Button(toolbar, nil, "Reset", 471, -60, 83, function()
        if activeScope ~= "element" or drag then return end
        Addon:ResetElementMoveTarget()
        DrawSelection()
    end)
    UI.Tooltip(reset, "Restore the selected Blizzard frame's position and family scale.")
    function toolbar:RefreshSelection()
        reset:SetShown(activeScope == "element")
        reset:SetEnabled(not drag)
        smaller:SetEnabled(not drag)
        larger:SetEnabled(not drag)
        select:GenerateMenu()
        local linked = Addon:GetMoveElementControls(activeScope, activeKind)
        link:SetShown(linked ~= nil)
        link:SetChecked(linked)
        link:SetEnabled(not drag)
        single:SetShown(linked == nil)
        self.groupState:SetText(linked and (activeScope == "seal" and "Linked to health" or "Grouped") or "Separate")
        self.groupState:SetTextColor(linked and 0.96 or 0.82, linked and 0.81 or 0.85, linked and 0.54 or 0.85)
    end
    UI.Button(toolbar, "SmallerUIResourceDemo", "Preview damage / heal", 14, -98, 169,
        function() Addon:TestResourceDamage() end)
    toolbar.gridToggle = UI.Button(toolbar, "SmallerUIMoveGridToggle", "Show grid", 192, -98, 108, function(button)
        EnsureOverlay()
        local grid = overlay.grid
        local show = not grid:IsShown()
        if show then
            overlay:Show()
            DrawGrid(grid)
        end
        grid:SetShown(show)
        button:SetText(show and "Hide grid" or "Show grid")
    end)
    UI.Tooltip(toolbar.gridToggle, "Show a screen-centred alignment grid")
    UI.Button(toolbar, "SmallerUIResourceCancel", "Cancel", 310, -98, 89,
        function() Addon:FinishResourceEdit(false) end)
    local done = UI.Button(toolbar, "SmallerUIResourceDone", "Done & Settings", 407, -98, 147,
        function() Addon:FinishResourceEdit(true) end)
    done:SetBackdropColor(0.26, 0.21, 0.14, 1)
    done:SetBackdropBorderColor(0.83, 0.66, 0.38, 1)
    toolbar:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if Addon:IsEditingResources() then Addon:FinishResourceEdit(false) end
    end)
    table.insert(UISpecialFrames, toolbar:GetName())
    return toolbar
end
