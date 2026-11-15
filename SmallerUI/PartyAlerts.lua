local _, Addon = ...
local listener = CreateFrame("Frame")
local prefix = "FQOL_POPUP"
local maxBytes = 160
local channels = { PARTY = "party", WHISPER = "whisper" }
local available, lastSent
local popup, elapsed
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

local function SetPopupText(frame, text)
    local cfg = Addon:GetPartyAlertSettings()
    local screenWidth = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    local width = math.max(140, math.min(720, (screenWidth - 32) / 1.15))
    frame.cfg = cfg
    frame.label:SetWidth(width)
    frame.label:SetTextColor(cfg.r, cfg.g, cfg.b)
    local font = STANDARD_TEXT_FONT or frame.label.GetFont and frame.label:GetFont()
    if font then
        local outlines = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
        frame.label:SetFont(font, cfg.size, outlines[cfg.thickness])
    end
    frame.label:SetText((text:gsub("|", "||")))
    frame.glow:SetWidth(width)
    frame.glow:SetVertexColor(cfg.r, cfg.g, cfg.b, 0.6)
    frame.topRule:SetColorTexture(cfg.r, cfg.g, cfg.b, 1)
    frame.bottomRule:SetColorTexture(cfg.r, cfg.g, cfg.b, 1)
    local height = math.max(40, frame.label:GetStringHeight() / 2 + 11)
    frame.topRule:ClearAllPoints()
    frame.topRule:SetPoint("CENTER", 0, height)
    frame.bottomRule:ClearAllPoints()
    frame.bottomRule:SetPoint("CENTER", 0, -height)
    PlayAlertSound(cfg)
end

local function CreatePopup()
    local frame = CreateFrame("Frame", "SmallerUIPartyAlert", UIParent)
    frame:Hide()
    frame:SetSize(620, 108)
    frame:SetIgnoreParentScale(true)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(false)

    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\Cooldown\\star4")
    glow:SetPoint("CENTER", 0, 0)
    glow:SetSize(610, 150)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.65, 0.24, 0.07, 0.5)
    frame.glow = glow

    local function Rule(y)
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.9, 0.57, 0.24, 0.85)
        line:SetPoint("CENTER", 0, y)
        line:SetSize(220, 1)
        return line
    end
    frame.topRule, frame.bottomRule = Rule(40), Rule(-40)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    label:SetPoint("CENTER")
    label:SetWidth(600)
    label:SetWordWrap(true)
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(true) end
    label:SetTextColor(1, 0.79, 0.4)
    if STANDARD_TEXT_FONT then label:SetFont(STANDARD_TEXT_FONT, 38, "THICKOUTLINE") end
    frame.label = label
    return frame
end

local function Animate(frame, delta)
    elapsed = elapsed + delta
    if elapsed >= 1.85 then
        local nextText = table.remove(pending, 1)
        if not nextText then
            frame:Hide()
            frame:SetScript("OnUpdate", nil)
            return
        end
        SetPopupText(frame, nextText)
        elapsed = 0
    end
    local rise = math.min(1, elapsed / 0.19)
    local settle = math.min(1, elapsed / 0.42)
    local fade = math.min(1, (1.85 - elapsed) / 0.42)
    local cfg = frame.cfg
    local intensity = cfg.intensity / 100
    local scale, y, entrance = 1, 130, rise * 3
    if cfg.style == "bounce" then
        scale = 1 + intensity * (-0.34 + 0.52 * (1 - (1 - rise) ^ 2) - 0.18 * settle)
        y = y - 36 * intensity * (1 - settle)
    elseif cfg.style == "pop" then
        scale = 1 - 0.38 * intensity * (1 - rise) ^ 2
    else
        y = y + 96 * intensity * (1 - settle) ^ 2
        entrance = math.min(1, elapsed / 0.3)
    end
    frame:SetScale(scale)
    frame:SetAlpha(math.min(entrance, fade))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, y + 18 * intensity * (1 - fade))
    frame.glow:SetAlpha(intensity * (0.2 + 0.8 * (1 - settle)))
    frame.topRule:SetAlpha(0.85 * intensity)
    frame.bottomRule:SetAlpha(0.85 * intensity)
    local width = 80 + 240 * (1 - (1 - settle) ^ 2)
    frame.topRule:SetWidth(width)
    frame.bottomRule:SetWidth(width)
end

local function Present(text)
    popup = popup or CreatePopup()
    if popup:IsShown() then
        if #pending < 4 then pending[#pending + 1] = text end
        return
    end
    elapsed = 0
    SetPopupText(popup, text)
    Animate(popup, 0)
    popup:SetScript("OnUpdate", Animate)
    popup:Show()
end

function Addon:PreviewPartyAlert()
    Present("chickenNuggies")
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
        else Present(text) end
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
    local sent = false
    if party then
        if send(prefix, text, "PARTY") == success then sent = true
        else Addon:Print("WoW did not deliver the Party pop-up.") end
    end
    if cfg.whisper then
        if not recipient then Addon:Print("No whisper recipient is set.")
        elseif send(prefix, text, "WHISPER", recipient) == success then sent = true
        else Addon:Print("WoW did not deliver the Whisper pop-up.") end
    end
    lastSent = now
    if sent then Present(text) end
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
    Present(text)
end)
