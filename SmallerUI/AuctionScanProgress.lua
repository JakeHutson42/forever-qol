local _, Addon = ...
local Scanner = Addon.AuctionScanner
local Progress = {}
Addon.AuctionScanProgress = Progress

local INSET = 2
local colors = {
    running = { 0.39, 0.26, 0.13 },
    paused = { 0.27, 0.22, 0.16 },
    complete = { 0.24, 0.33, 0.16 },
    ended = { 0.35, 0.22, 0.15 },
}

local function Duration(seconds)
    seconds = math.floor(seconds)
    if seconds >= 60 then return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60) end
    return ("%ds"):format(seconds)
end

local function Paint(bar, data)
    local width = math.max(1, (bar:GetWidth() or 0) - INSET * 2)
    local offset, fill = 0, 0
    if data.fraction then
        fill = width * math.min(1, math.max(0, data.fraction))
    elseif data.state == "running" then
        fill = width * 0.22
        local phase = (data.elapsed / 1.6) % 2
        offset = (width - fill) * (1 - math.abs(phase - 1))
    end
    bar.fill:SetShown(fill >= 1)
    if fill >= 1 then
        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", INSET + offset, -INSET)
        bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", INSET + offset, INSET)
        bar.fill:SetWidth(fill)
        bar.fill:SetColorTexture(unpack(colors[data.state]))
    end

    local count = data.total and not data.estimated and ("%d / %d checked"):format(data.count, data.total)
        or ("%d items checked"):format(data.count)
    local time
    if data.state == "complete" then
        time = "Complete · " .. Duration(data.elapsed)
    elseif data.state == "ended" then
        time = data.message
    elseif data.state == "paused" then
        time = "Paused"
    else
        local progress = data.estimated and data.fraction and data.count > 0
            and ("~%d%% · "):format(math.floor(data.fraction * 100)) or ""
        time = progress .. (data.eta and ("~%s left"):format(Duration(data.eta)) or Duration(data.elapsed) .. " elapsed")
    end
    local label = data.label .. " · " .. count
    if bar.displayLabel ~= label then
        bar.displayLabel = label
        bar.label:SetText(label)
    end
    if bar.displayTime ~= time then
        bar.displayTime = time
        bar.time:SetText(time)
    end
end

local function Tick(bar, elapsed)
    bar.since = (bar.since or 0) + elapsed
    if bar.since < 0.05 then return end
    bar.since = 0
    bar:Refresh()
end

function Progress:Create(parent, labelFilter)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetHeight(18)
    Addon.OptionsUI.Plate(bar, { 0.11, 0.085, 0.065, 1 })
    bar.fill = bar:CreateTexture(nil, "BORDER")
    bar.label = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", 8, 0)
    bar.label:SetPoint("RIGHT", -184, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWordWrap(false)
    bar.time = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    bar.time:SetPoint("RIGHT", -8, 0)
    bar.time:SetWidth(172)
    bar.time:SetJustifyH("RIGHT")
    bar.time:SetWordWrap(false)
    bar.time:SetTextColor(0.96, 0.81, 0.56)

    function bar:Refresh()
        local settings = Addon:GetAuctionSettings()
        local data = Scanner:GetProgress()
        local visible = settings.scanBar ~= false and data and (not labelFilter or data.label == labelFilter)
        self:SetShown(visible == true)
        local active = visible and (data.state == "running" or data.state == "paused")
        self:SetScript("OnUpdate", active and Tick or nil)
        if visible then
            if settings.scanETA == false then data.eta = nil end
            Paint(self, data)
        end
    end
    bar:Hide()
    return bar
end
