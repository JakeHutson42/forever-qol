local _, Addon = ...
local listener = CreateFrame("Frame")
local prefix = "FQOL_POPUP"
local maxBytes = 160
local channels = { PARTY = "party", WHISPER = "whisper" }
local outlines = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local fadeIn, fadeOut, settleTime = 0.15, 0.28, 0.36
local available, lastSent
local popup
local pending = {}
local lastReceived = {}
local lastWhisper, audioHandle, audioTimer
local audioFile = "Interface\\AddOns\\SmallerUI\\Media\\Popup.mp3"
local defaults = { enabled = true, party = true, whisper = false, style = "bounce",
    size = 38, intensity = 65, thickness = "thick", sound = "off", soundLength = 4,
    r = 1, g = 0.79, b = 0.4, recipient = "" }
local choices = {
    style = { bounce = true, pop = true, cascade = true },
    thickness = { none = true, thin = true, thick = true },
    sound = { off = true, chime = true, mp3 = true },
}
Addon.partyAlertLimits = { size = { 18, 76 }, intensity = { 0, 100 }, soundLength = { 1, 10 },
    r = { 0, 1 }, g = { 0, 1 }, b = { 0, 1 } }

local function Public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function CleanText(text)
    if not Public(text) or type(text) ~= "string" then return end
    return (text:gsub("%c", " "):match("^%s*(.-)%s*$"))
end

local function ValidRecipient(name)
    if name == "" then return true end
    if #name > 64 then return false end
    if name:match("^[^%s%p%d]+$") then return true end
    return name:match("^[^%s%p%d]+%-[%w\128-\255][%w'%-\128-\255]*$") ~= nil
end

local function ValidOption(key, value)
    if type(value) ~= type(defaults[key]) then return false end
    local range = Addon.partyAlertLimits[key]
    if range then return value >= range[1] and value <= range[2] end
    if choices[key] then return choices[key][value] == true end
    return key ~= "recipient" or ValidRecipient(value)
end

function Addon:ValidatePartyAlerts()
    if type(self.db.partyAlerts) ~= "table" then
        self.db.partyAlerts = { enabled = self.db.partyAlerts ~= false }
    end
    local cfg = self.db.partyAlerts
    for key, value in pairs(defaults) do
        if cfg[key] == nil or not ValidOption(key, cfg[key]) then cfg[key] = value end
    end
end

function Addon:GetPartyAlertSettings() return self.db.partyAlerts end

local function StopAudio()
    if audioTimer then audioTimer:Cancel(); audioTimer = nil end
    if audioHandle and StopSound then StopSound(audioHandle) end
    audioHandle = nil
end

function Addon:SetPartyAlertOption(key, value)
    if defaults[key] == nil or not ValidOption(key, value) then return false end
    self.db.partyAlerts[key] = value
    if key == "sound" then StopAudio() end
    if key == "enabled" and not value then
        pending = {}
        StopAudio()
        if popup then popup:SetScript("OnUpdate", nil); popup:Hide() end
    end
    return true
end

function Addon:GetPartyAlertRecipient()
    local recipient = self.db.partyAlerts.recipient
    return recipient ~= "" and recipient or lastWhisper
end

local function PlayAlertSound(cfg)
    if cfg.sound == "off" then return end
    StopAudio()
    local played, handle
    if cfg.sound == "chime" then
        if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
            played, handle = PlaySound(SOUNDKIT.TELL_MESSAGE, "SFX")
        end
    elseif PlaySoundFile then
        played, handle = PlaySoundFile(audioFile, "SFX")
    end
    if played and handle and StopSound and C_Timer and C_Timer.NewTimer then
        audioHandle = handle
        audioTimer = C_Timer.NewTimer(cfg.soundLength, StopAudio)
    end
    return played
end

function Addon:TestPartyAlertSound()
    local cfg = self:GetPartyAlertSettings()
    if cfg.sound ~= "off" and not PlayAlertSound(cfg) then
        self:Print("Could not play the selected sound.")
    end
end

local function LayoutPopup(frame)
    local cfg = Addon:GetPartyAlertSettings()
    local scale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * scale, UIParent:GetHeight() * scale
    local width = math.max(120, math.min(560, screenWidth - 40))
    local label = frame.label
    label:SetTextColor(cfg.r, cfg.g, cfg.b)
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local size = math.min(cfg.size, math.max(12, math.floor((width - 32) / 3)))
    local limit = math.max(44, math.floor(screenHeight * 0.45) - 55)
    label:SetFont(font, size, outlines[cfg.thickness])
    if label.GetUnboundedStringWidth then
        local preferred = math.ceil((label:GetUnboundedStringWidth() or 0) + 32)
        width = math.min(width, math.max(320, preferred))
    end
    label:SetWidth(width - 32)
    local height = label:GetStringHeight()
    while height > limit and size > 12 do
        size = math.max(12, math.min(size - 1, math.floor(size * math.sqrt(limit / height))))
        label:SetFont(font, size, outlines[cfg.thickness])
        height = label:GetStringHeight()
    end
    frame:SetSize(width, math.max(size, height) + 55)
    frame.card:SetSize(frame:GetSize())
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -math.floor(screenHeight * 0.31))
end

local function CreatePopup()
    local UI = Addon.OptionsUI
    local frame = CreateFrame("Frame", "SmallerUIPartyAlert", UIParent)
    frame:Hide()
    frame:SetIgnoreParentScale(true)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(false)
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:SetScript("OnEvent", function(self) if self:IsShown() then LayoutPopup(self) end end)

    local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    card:SetPoint("TOP")
    card:EnableMouse(false)
    UI.Plate(card, { 0.071, 0.098, 0.11, 0.98 })
    card:SetBackdropBorderColor(0.57, 0.45, 0.28, 1)
    frame.card = card
    local crest = card:CreateTexture(nil, "ARTWORK")
    crest:SetSize(16, 16)
    crest:SetPoint("TOPLEFT", 13, -9)
    crest:SetTexture("Interface\\AddOns\\SmallerUI\\Media\\TrimJewel.tga")
    crest:SetVertexColor(1, 0.84, 0.55)
    frame.source = UI.Label(card, "", 36, -10, "GameFontNormal")
    frame.source:SetPoint("TOPRIGHT", -16, -10)
    frame.source:SetWordWrap(false)
    frame.source:SetTextColor(0.92, 0.76, 0.49)
    local rule = card:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", 16, -33)
    rule:SetPoint("TOPRIGHT", -16, -33)
    rule:SetHeight(1)
    rule:SetColorTexture(0.66, 0.54, 0.36, 0.52)
    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    label:SetPoint("TOPLEFT", 16, -42)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(true) end
    frame.label = label
    return frame
end

local function StartAlert(frame, alert)
    frame.alert, frame.elapsed = alert, 0
    local characters = #alert.text:gsub("[\128-\191]", "")
    frame.duration = 1.85 + math.min(3.1, math.max(0, (characters - 30) / 40))
    frame.source:SetText((alert.source:gsub("|", "||")))
    frame.label:SetText((alert.text:gsub("|", "||")))
    LayoutPopup(frame)
    PlayAlertSound(Addon:GetPartyAlertSettings())
end

local function Animate(frame, delta)
    local elapsed = frame.elapsed + delta
    if elapsed >= frame.duration then
        local nextAlert = table.remove(pending, 1)
        if not nextAlert then
            frame:Hide()
            frame:SetScript("OnUpdate", nil)
            return
        end
        StartAlert(frame, nextAlert)
        elapsed = 0
    end
    frame:SetAlpha(math.min(1, elapsed / fadeIn, (frame.duration - elapsed) / fadeOut))
    if elapsed <= settleTime or frame.elapsed < settleTime then
        local progress = math.min(1, elapsed / settleTime)
        local tail = (1 - progress) ^ 3
        local cfg = Addon:GetPartyAlertSettings()
        local intensity = cfg.intensity / 100
        local scale, y = 1, 0
        if cfg.style == "bounce" then
            scale = 1 + intensity * (-0.10 * tail + 0.019 * math.sin(progress * math.pi) ^ 2)
            y = -9 * intensity * tail
        elseif cfg.style == "pop" then
            scale = 1 - 0.14 * intensity * tail
        else
            y = 20 * intensity * tail
        end
        frame.card:SetScale(scale)
        frame.card:ClearAllPoints()
        frame.card:SetPoint("TOP", frame, "TOP", 0, y)
    end
    frame.elapsed = elapsed
end

local function Present(text, source, preview)
    popup = popup or CreatePopup()
    local alert = { text = text, source = source, preview = preview }
    if popup:IsShown() and not popup.alert.preview then
        if not preview and #pending < 4 then pending[#pending + 1] = alert end
        return
    end
    StartAlert(popup, alert)
    Animate(popup, 0)
    popup:SetScript("OnUpdate", Animate)
    popup:Show()
end

function Addon:PreviewPartyAlert()
    Present("Regroup at the entrance.", "Alert preview", true)
end

local function InParty()
    return IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid())
        and not (LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
end

local function IsOwnMessage(sender)
    if not UnitFullName then return false end
    local name, realm = UnitFullName("player")
    if not Public(name) or not name then return false end
    if sender == name then return true end
    if Public(realm) and realm and realm ~= "" then
        return sender == name .. "-" .. realm:gsub("%s", "")
    end
    return GetNormalizedRealmName and sender == name .. "-" .. GetNormalizedRealmName()
end

local function SendPopup(input)
    if not Addon.db then return end
    local cfg = Addon:GetPartyAlertSettings()
    if not cfg.enabled then Addon:Print("Pop-ups are off."); return end
    local text = CleanText(input)
    if not text then return end
    local quote = text:sub(1, 1)
    if (quote == '"' or quote == "'") and text:sub(-1) == quote then
        text = CleanText(text:sub(2, -2))
    end
    if text == "" then Addon:Print("Enter a phrase."); return end
    if #text > maxBytes then Addon:Print("That phrase is too long."); return end
    local party = cfg.party and InParty()
    local recipient = cfg.whisper and Addon:GetPartyAlertRecipient()
    if not party and not recipient then
        if cfg.whisper then Addon:Print("Choose a whisper recipient or send a character whisper first.")
        elseif cfg.party and IsInGroup and IsInGroup() then Addon:Print("Party pop-ups require a regular party.")
        else Present(text, "Chat alert") end
        return
    end
    local now = GetTime()
    if lastSent and now - lastSent < 2 then return end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessageLogged
    if not available or not send or C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        Addon:Print("Shared pop-ups are unavailable here.")
        return
    end
    local codes = Enum and Enum.SendAddonMessageResult
    local success = codes and codes.Success or 0
    local source
    if party then
        if send(prefix, text, "PARTY") == success then source = "Party"
        else Addon:Print("WoW did not deliver the Party pop-up.") end
    end
    if cfg.whisper then
        if not recipient then Addon:Print("No whisper recipient is set.")
        elseif send(prefix, text, "WHISPER", recipient) == success then source = source or "Whisper"
        else Addon:Print("WoW did not deliver the Whisper pop-up.") end
    end
    lastSent = now
    if source then Present(text, source) end
end

SLASH_SMALLERUIPOPUP1 = "/swear"
SlashCmdList.SMALLERUIPOPUP = SendPopup
listener:RegisterEvent("PLAYER_LOGIN")
listener:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
listener:RegisterEvent("CHAT_MSG_WHISPER")
listener:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
listener:SetScript("OnEvent", function(_, event, incomingPrefix, message, channel, sender)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            local result = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
            local codes = Enum and Enum.RegisterAddonMessagePrefixResult
            available = result == true or result == (codes and codes.Success or 0)
                or result == (codes and codes.DuplicatePrefix or 1)
        end
        return
    end
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        if Public(message) and type(message) == "string" and message ~= "" and ValidRecipient(message) then
            lastWhisper = message
        end
        return
    end
    if not available or not Addon.db or not Public(incomingPrefix) or incomingPrefix ~= prefix
        or not Public(channel) or not channels[channel]
        or not Public(sender) or type(sender) ~= "string" or IsOwnMessage(sender) then return end
    local cfg = Addon:GetPartyAlertSettings()
    if not cfg.enabled or not cfg[channels[channel]] then return end
    local text = CleanText(message)
    if not text or text == "" or #text > maxBytes then return end
    local now = GetTime()
    for name, previous in pairs(lastReceived) do
        if now - previous >= 2 then lastReceived[name] = nil end
    end
    if lastReceived[sender] then return end
    lastReceived[sender] = now
    Present(text, (channel == "PARTY" and "Party · " or "Whisper · ") .. sender)
end)
