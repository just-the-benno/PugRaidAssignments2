-- ToolHPWatcher.lua
-- HPWatcher tool implementation for raid tools infrastructure.
-- Real-time monitoring of raid members' health, plus a raid-leader-triggered
-- countdown mechanic used to coordinate emergency heals with a raid-wide
-- damage phase.

local W = PugRaidAssignmentsWidgets
local D = PugRaidAssignmentsDispatcher
local S = PugRaidAssignmentsStorage

PugRaidAssignmentsToolHPWatcher = {}
local ToolHPWatcher = PugRaidAssignmentsToolHPWatcher
ToolHPWatcher.__index = ToolHPWatcher

local DEFAULT_CONFIG = {
    type = "HPWatcher",
    scanInterval = 150,
    amberThreshold = 50,
    redThreshold = 25,
    countdownDuration = 3,
    preCountdownMessage = "Heal yourself. Spine in 3",
    finalMessage = "Throw",
    whisperMessage = "Heal yourself, inc dmg in 3 seconds",
}

local CLASS_ICON_TCOORDS = _G.CLASS_ICON_TCOORDS or {
    ["WARRIOR"]     = {0, 0.25, 0, 0.25},
    ["PALADIN"]     = {0.25, 0.5, 0, 0.25},
    ["HUNTER"]      = {0.5, 0.75, 0, 0.25},
    ["ROGUE"]       = {0.75, 1, 0, 0.25},
    ["PRIEST"]      = {0, 0.25, 0.25, 0.5},
    ["DEATHKNIGHT"] = {0.25, 0.5, 0.25, 0.5},
    ["SHAMAN"]      = {0.5, 0.75, 0.25, 0.5},
    ["MAGE"]        = {0.75, 1, 0.25, 0.5},
    ["WARLOCK"]     = {0, 0.25, 0.5, 0.75},
    ["MONK"]        = {0.25, 0.5, 0.5, 0.75},
    ["DRUID"]       = {0.5, 0.75, 0.5, 0.75},
    ["DEMONHUNTER"] = {0.75, 1, 0.5, 0.75},
}

local ROLE_TCOORDS = {
    TANK    = {0, 0.296875, 0.34375, 0.640625},
    HEALER  = {0.3125, 0.609375, 0.015625, 0.3125},
    DAMAGER = {0.3125, 0.609375, 0.34375, 0.640625},
}

local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
    ["WARRIOR"]     = { r = 0.78, g = 0.61, b = 0.43 },
    ["PALADIN"]     = { r = 0.96, g = 0.55, b = 0.73 },
    ["HUNTER"]      = { r = 0.67, g = 0.83, b = 0.45 },
    ["ROGUE"]       = { r = 1.00, g = 0.96, b = 0.41 },
    ["PRIEST"]      = { r = 1.00, g = 1.00, b = 1.00 },
    ["DEATHKNIGHT"] = { r = 0.77, g = 0.12, b = 0.23 },
    ["SHAMAN"]      = { r = 0.00, g = 0.44, b = 0.87 },
    ["MAGE"]        = { r = 0.25, g = 0.78, b = 0.92 },
    ["WARLOCK"]     = { r = 0.53, g = 0.53, b = 0.93 },
    ["MONK"]        = { r = 0.00, g = 1.00, b = 0.59 },
    ["DRUID"]       = { r = 1.00, g = 0.49, b = 0.04 },
    ["DEMONHUNTER"] = { r = 0.64, g = 0.19, b = 0.79 },
}

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = CopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Raid warnings are time-critical for the countdown mechanic, so they bypass
-- the Dispatcher's throttled queue entirely and fire immediately.
local function SendRaidWarning(text)
    if text and text ~= "" then
        C_ChatInfo.SendChatMessage(text, "RAID_WARNING")
    end
end

function ToolHPWatcher:New(config, sessionId, docId)
    local instance = setmetatable({}, ToolHPWatcher)
    instance:OnInit(config, sessionId, docId)
    return instance
end

function ToolHPWatcher:OnInit(config, sessionId, docId)
    self.config = CopyTable(DEFAULT_CONFIG)
    if type(config) == "table" then
        for k, v in pairs(config) do
            self.config[k] = CopyTable(v)
        end
    end

    self.sessionId = sessionId
    self.docId = docId

    self.redPlayers = {}
    self.amberPlayers = {}

    self.running = false
    self.timeSinceLastScan = 0
    self.redCollapsed = false
    self.amberCollapsed = false

    self.rowPool = {}
    self.activeRows = {}

    self:ResetCountdownState()
end

function ToolHPWatcher:GetFrame()
    if not self.frame then
        self:BuildFrame()
    end
    return self.frame
end

function ToolHPWatcher:BuildFrame()
    local f = W.MakeWindow("PugRaidHPWatcherFrame", "HP Watcher", 320, 440)
    self.frame = f
    f.tool = self

    -- Intercept close button if basic frame template added one
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function()
            self:OnStop()
        end)
    end

    -- Restore window position from config if set
    if self.config and self.config.windowPosition and self.config.windowPosition.x then
        local wp = self.config.windowPosition
        f:ClearAllPoints()
        f:SetPoint(wp.point or "CENTER", UIParent, wp.relativePoint or "CENTER", wp.x or 0, wp.y or 0)
    end

    f:SetScript("OnDragStop", function(sf)
        sf:StopMovingOrSizing()
        self:SavePosition()
    end)

    -- Countdown timer display (only visible during an active countdown)
    local countdownText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    countdownText:SetPoint("TOP", f, "TOP", 0, -30)
    countdownText:SetTextColor(1, 0.4, 0.1)
    countdownText:Hide()
    self.countdownText = countdownText

    -- Scroll pane for content
    local sf, cf = W.MakeScrollPane(f, 295, 300)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -50)
    self.scrollFrame = sf
    self.contentFrame = cf

    -- Red group header
    local redHeader = CreateFrame("Button", nil, cf, "BackdropTemplate")
    redHeader:SetSize(270, 24)
    redHeader:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 },
    })
    redHeader:SetBackdropColor(0.5, 0.1, 0.1, 0.85)
    redHeader:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    self.redHeader = redHeader

    local redHeaderText = redHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    redHeaderText:SetPoint("LEFT", redHeader, "LEFT", 8, 0)
    redHeaderText:SetText("RED (Danger Zone)")
    self.redHeaderText = redHeaderText

    redHeader:SetScript("OnClick", function()
        self.redCollapsed = not self.redCollapsed
        self:UpdateUI()
    end)

    -- Red status message
    local redStatus = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    redStatus:SetText("All above red threshold")
    redStatus:SetTextColor(0.2, 0.9, 0.2)
    self.redStatus = redStatus

    -- Amber group header
    local amberHeader = CreateFrame("Button", nil, cf, "BackdropTemplate")
    amberHeader:SetSize(270, 24)
    amberHeader:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 },
    })
    amberHeader:SetBackdropColor(0.5, 0.3, 0.0, 0.85)
    amberHeader:SetBackdropBorderColor(0.9, 0.5, 0.1, 1)
    self.amberHeader = amberHeader

    local amberHeaderText = amberHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    amberHeaderText:SetPoint("LEFT", amberHeader, "LEFT", 8, 0)
    amberHeaderText:SetText("AMBER (Under Watch)")
    self.amberHeaderText = amberHeaderText

    amberHeader:SetScript("OnClick", function()
        self.amberCollapsed = not self.amberCollapsed
        self:UpdateUI()
    end)

    -- Amber status message
    local amberStatus = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    amberStatus:SetText("All above amber threshold")
    amberStatus:SetTextColor(0.2, 0.9, 0.2)
    self.amberStatus = amberStatus

    -- Bottom controls
    local btnCountdown = W.MakeButton(f, "Start Countdown", 130, 22)
    btnCountdown:SetPoint("BOTTOM", f, "BOTTOM", 0, 38)
    btnCountdown:SetScript("OnClick", function()
        self:StartCountdown()
    end)
    self.btnCountdown = btnCountdown

    local btnConfig = W.MakeButton(f, "Config", 90, 22)
    btnConfig:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
    btnConfig:SetScript("OnClick", function()
        self:ShowConfigUI()
    end)

    local btnReset = W.MakeButton(f, "Reset", 90, 22)
    btnReset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
    btnReset:SetScript("OnClick", function()
        self:ResetCountdownState()
        self:UpdateUI()
    end)

    self:UpdateButtonState()
end

function ToolHPWatcher:OnStart()
    self.running = true
    self.timeSinceLastScan = 0
    local f = self:GetFrame()
    f:Show()
    f:Raise()

    f:SetScript("OnUpdate", function(_, elapsed)
        if not self.running then return end

        if self.countdownActive then
            self:UpdateCountdown(elapsed)
        end

        self.timeSinceLastScan = self.timeSinceLastScan + elapsed
        local intervalSec = (tonumber(self.config.scanInterval) or 150) / 1000
        if self.timeSinceLastScan >= intervalSec then
            self.timeSinceLastScan = 0
            self:ScanRaid()
            self:UpdateUI()
        end
    end)

    self:ScanRaid()
    self:UpdateUI()
end

function ToolHPWatcher:OnStop()
    self.running = false
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    if self.configFrame then
        self.configFrame:Hide()
    end
    self:ResetCountdownState()
end

function ToolHPWatcher:OnConfigChanged(newConfig)
    if type(newConfig) == "table" then
        for k, v in pairs(newConfig) do
            self.config[k] = CopyTable(v)
        end
    end
    if self.running then
        self:ScanRaid()
        self:UpdateUI()
    end
end

function ToolHPWatcher:ScanRaid()
    self.redPlayers = {}
    self.amberPlayers = {}

    local redThresh = tonumber(self.config.redThreshold) or 25
    local amberThresh = tonumber(self.config.amberThreshold) or 50

    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            units[#units + 1] = "raid" .. i
        end
    elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
        units[1] = "player"
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    else
        units[1] = "player"
        for i = 1, 40 do
            units[#units + 1] = "raid" .. i
        end
    end

    local scannedNames = {}

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name and name ~= "" and not scannedNames[name] then
                scannedNames[name] = true

                local health = UnitHealth(unit) or 0
                local maxHealth = UnitHealthMax(unit) or 0
                local pct = 0
                if maxHealth > 0 then
                    pct = (health / maxHealth) * 100
                end

                local locClass, engClass = UnitClass(unit)
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"

                local playerObj = {
                    unit = unit,
                    name = name,
                    class = engClass or locClass or "WARRIOR",
                    role = role,
                    hpPercent = pct,
                    health = health,
                    maxHealth = maxHealth,
                }

                if pct < redThresh then
                    table.insert(self.redPlayers, playerObj)
                elseif pct < amberThresh then
                    table.insert(self.amberPlayers, playerObj)
                end
            end
        end
    end

    table.sort(self.redPlayers, function(a, b) return a.hpPercent < b.hpPercent end)
    table.sort(self.amberPlayers, function(a, b) return a.hpPercent < b.hpPercent end)
end

-- Snapshot red-zone players and kick off the raid-warning/whisper countdown
-- sequence. Cannot be restarted mid-sequence.
function ToolHPWatcher:StartCountdown()
    if self.countdownActive then return end

    local duration = tonumber(self.config.countdownDuration) or 3
    if duration < 0 then duration = 0 end

    self.countdownRedSnapshot = {}
    for _, p in ipairs(self.redPlayers) do
        table.insert(self.countdownRedSnapshot, p.name)
    end

    self.countdownActive = true
    self.countdownDuration = duration
    self.countdownRemaining = duration
    self.countdownCounter = math.floor(duration)
    self.countdownTickAccumulator = 0
    self:UpdateButtonState()

    SendRaidWarning(self.config.preCountdownMessage or DEFAULT_CONFIG.preCountdownMessage)

    local whisperMessage = self.config.whisperMessage or DEFAULT_CONFIG.whisperMessage
    for _, name in ipairs(self.countdownRedSnapshot) do
        D.SendMessage({ kind = "PERSONAL", target = name, text = whisperMessage })
    end

    self:UpdateUI()
end

-- Ticks the active countdown forward by `elapsed` seconds, firing one raid
-- warning per whole second that passes, and the final message at zero.
function ToolHPWatcher:UpdateCountdown(elapsed)
    if not self.countdownActive then return end

    self.countdownRemaining = self.countdownRemaining - elapsed
    if self.countdownRemaining < 0 then self.countdownRemaining = 0 end

    self.countdownTickAccumulator = (self.countdownTickAccumulator or 0) + elapsed
    while self.countdownTickAccumulator >= 1 do
        self.countdownTickAccumulator = self.countdownTickAccumulator - 1

        if self.countdownCounter > 0 then
            SendRaidWarning(tostring(self.countdownCounter))
            self.countdownCounter = self.countdownCounter - 1
        else
            SendRaidWarning(self.config.finalMessage or DEFAULT_CONFIG.finalMessage)
            self:ResetCountdownState()
            break
        end
    end
end

-- Clears any active countdown state, re-enabling the Start Countdown button.
-- Used both when a countdown completes naturally and as the manual Reset
-- button handler (e.g. after a wipe).
function ToolHPWatcher:ResetCountdownState()
    self.countdownActive = false
    self.countdownDuration = 0
    self.countdownRemaining = 0
    self.countdownCounter = 0
    self.countdownTickAccumulator = 0
    self.countdownRedSnapshot = nil
    self:UpdateButtonState()
end

function ToolHPWatcher:UpdateButtonState()
    if not self.btnCountdown then return end
    if self.countdownActive then
        self.btnCountdown:Disable()
    else
        self.btnCountdown:Enable()
    end
end

local function GetRowFrame(self)
    local row = table.remove(self.rowPool)
    if not row then
        row = CreateFrame("Frame", nil, self.contentFrame)
        row:SetSize(270, 22)

        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetSize(16, 16)
        row.classIcon:SetPoint("LEFT", row, "LEFT", 4, 0)

        row.roleIcon = row:CreateTexture(nil, "ARTWORK")
        row.roleIcon:SetSize(16, 16)
        row.roleIcon:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", row.roleIcon, "RIGHT", 6, 0)
        row.nameText:SetWidth(130)
        row.nameText:SetJustifyH("LEFT")

        row.hpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.hpText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.hpText:SetJustifyH("RIGHT")
    end
    row:Show()
    self.activeRows[#self.activeRows + 1] = row
    return row
end

local function PopulateRow(row, p, hpColor)
    -- Class icon
    if p.class and CLASS_ICON_TCOORDS[p.class] then
        row.classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[p.class]))
        row.classIcon:Show()
    else
        row.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.classIcon:SetTexCoord(0, 1, 0, 1)
        row.classIcon:Show()
    end

    -- Role icon
    if p.role and ROLE_TCOORDS[p.role] then
        row.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        row.roleIcon:SetTexCoord(unpack(ROLE_TCOORDS[p.role]))
        row.roleIcon:Show()
    else
        row.roleIcon:Hide()
    end

    -- Player name
    row.nameText:SetText(p.name)
    local col = RAID_CLASS_COLORS[p.class]
    if col then
        row.nameText:SetTextColor(col.r, col.g, col.b)
    else
        row.nameText:SetTextColor(1, 1, 1)
    end

    -- HP text (percentage)
    row.hpText:SetText(string.format("| %.0f%%", p.hpPercent))
    row.hpText:SetTextColor(unpack(hpColor))
end

function ToolHPWatcher:UpdateUI()
    if not self.frame or not self.contentFrame then return end

    -- Countdown display
    if self.countdownText then
        if self.countdownActive then
            self.countdownText:SetText(string.format("%.1fs remaining", self.countdownRemaining))
            self.countdownText:Show()
        else
            self.countdownText:Hide()
        end
    end

    -- Recycle existing active rows
    for _, row in ipairs(self.activeRows) do
        row:Hide()
        self.rowPool[#self.rowPool + 1] = row
    end
    self.activeRows = {}

    local y = 0

    -- RED Section Header
    self.redHeader:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 0, -y)
    local redArrow = self.redCollapsed and "[+] " or "[-] "
    self.redHeaderText:SetText(redArrow .. "RED (Danger Zone) (" .. #self.redPlayers .. ")")
    self.redHeader:Show()
    y = y + 26

    if not self.redCollapsed then
        if #self.redPlayers == 0 then
            self.redStatus:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 8, -y)
            self.redStatus:SetText("All above red threshold")
            self.redStatus:Show()
            y = y + 20
        else
            self.redStatus:Hide()
            for _, p in ipairs(self.redPlayers) do
                local row = GetRowFrame(self)
                row:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 0, -y)
                PopulateRow(row, p, {1, 0.3, 0.3})
                y = y + 22
            end
        end
    else
        self.redStatus:Hide()
    end

    y = y + 6

    -- AMBER Section Header
    self.amberHeader:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 0, -y)
    local amberArrow = self.amberCollapsed and "[+] " or "[-] "
    self.amberHeaderText:SetText(amberArrow .. "AMBER (Under Watch) (" .. #self.amberPlayers .. ")")
    self.amberHeader:Show()
    y = y + 26

    if not self.amberCollapsed then
        if #self.amberPlayers == 0 then
            self.amberStatus:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 8, -y)
            self.amberStatus:SetText("All above amber threshold")
            self.amberStatus:Show()
            y = y + 20
        else
            self.amberStatus:Hide()
            for _, p in ipairs(self.amberPlayers) do
                local row = GetRowFrame(self)
                row:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 0, -y)
                PopulateRow(row, p, {1, 0.7, 0.2})
                y = y + 22
            end
        end
    else
        self.amberStatus:Hide()
    end

    self.contentFrame:SetHeight(math.max(1, y))
end

function ToolHPWatcher:ShowConfigUI()
    if not self.configFrame then
        local cf = W.MakeWindow("PugRaidHPWatcherConfigFrame", "HP Watcher Configuration", 360, 460)
        cf:SetFrameStrata("HIGH")
        cf:SetToplevel(true)
        self.configFrame = cf

        local y = -36

        -- Amber Threshold
        local lblAmber = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblAmber:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblAmber:SetText("Amber Threshold (% HP):")
        y = y - 20

        local ebAmber, bgAmber = W.MakeEditBox(cf, 320, 22, false)
        bgAmber:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebAmberThreshold = ebAmber
        y = y - 30

        -- Red Threshold
        local lblRed = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblRed:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblRed:SetText("Red Threshold (% HP):")
        y = y - 20

        local ebRed, bgRed = W.MakeEditBox(cf, 320, 22, false)
        bgRed:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebRedThreshold = ebRed
        y = y - 30

        -- Countdown Duration
        local lblDuration = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblDuration:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblDuration:SetText("Countdown Duration (seconds):")
        y = y - 20

        local ebDuration, bgDuration = W.MakeEditBox(cf, 320, 22, false)
        bgDuration:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebCountdownDuration = ebDuration
        y = y - 30

        -- Pre-countdown Message
        local lblPre = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblPre:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblPre:SetText("Pre-countdown Message (Raid Warning):")
        y = y - 20

        local ebPre, bgPre = W.MakeEditBox(cf, 320, 36, true)
        bgPre:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebPreCountdownMessage = ebPre
        y = y - 44

        -- Final Message
        local lblFinal = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblFinal:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblFinal:SetText("Final Message (Raid Warning at zero):")
        y = y - 20

        local ebFinal, bgFinal = W.MakeEditBox(cf, 320, 36, true)
        bgFinal:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebFinalMessage = ebFinal
        y = y - 44

        -- Whisper Message
        local lblWhisper = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblWhisper:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblWhisper:SetText("Whisper Message (to Red-zone players):")
        y = y - 20

        local ebWhisper, bgWhisper = W.MakeEditBox(cf, 320, 36, true)
        bgWhisper:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebWhisperMessage = ebWhisper
        y = y - 44

        -- Save / Cancel buttons
        local btnSave = W.MakeButton(cf, "Save", 90, 22)
        btnSave:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 14, 10)
        btnSave:SetScript("OnClick", function()
            local amberVal = tonumber(self.ebAmberThreshold:GetText()) or DEFAULT_CONFIG.amberThreshold
            local redVal = tonumber(self.ebRedThreshold:GetText()) or DEFAULT_CONFIG.redThreshold
            local durationVal = tonumber(self.ebCountdownDuration:GetText()) or DEFAULT_CONFIG.countdownDuration
            local preMsg = self.ebPreCountdownMessage:GetText()
            if not preMsg or preMsg == "" then preMsg = DEFAULT_CONFIG.preCountdownMessage end
            local finalMsg = self.ebFinalMessage:GetText()
            if not finalMsg or finalMsg == "" then finalMsg = DEFAULT_CONFIG.finalMessage end
            local whisperMsg = self.ebWhisperMessage:GetText()
            if not whisperMsg or whisperMsg == "" then whisperMsg = DEFAULT_CONFIG.whisperMessage end

            self.config.amberThreshold = amberVal
            self.config.redThreshold = redVal
            self.config.countdownDuration = durationVal
            self.config.preCountdownMessage = preMsg
            self.config.finalMessage = finalMsg
            self.config.whisperMessage = whisperMsg

            self:SaveConfigToStorage()
            self:OnConfigChanged(self.config)
            self.configFrame:Hide()
        end)

        local btnCancel = W.MakeButton(cf, "Cancel", 90, 22)
        btnCancel:SetPoint("LEFT", btnSave, "RIGHT", 10, 0)
        btnCancel:SetScript("OnClick", function()
            self.configFrame:Hide()
        end)
    end

    self.ebAmberThreshold:SetText(tostring(self.config.amberThreshold or DEFAULT_CONFIG.amberThreshold))
    self.ebRedThreshold:SetText(tostring(self.config.redThreshold or DEFAULT_CONFIG.redThreshold))
    self.ebCountdownDuration:SetText(tostring(self.config.countdownDuration or DEFAULT_CONFIG.countdownDuration))
    self.ebPreCountdownMessage:SetText(tostring(self.config.preCountdownMessage or DEFAULT_CONFIG.preCountdownMessage))
    self.ebFinalMessage:SetText(tostring(self.config.finalMessage or DEFAULT_CONFIG.finalMessage))
    self.ebWhisperMessage:SetText(tostring(self.config.whisperMessage or DEFAULT_CONFIG.whisperMessage))

    self.configFrame:Show()
    self.configFrame:Raise()
end

function ToolHPWatcher:SavePosition()
    if not self.frame then return end
    local point, _, relPoint, x, y = self.frame:GetPoint()
    self.config.windowPosition = {
        point = point or "CENTER",
        relativePoint = relPoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
    self:SaveConfigToStorage()
end

function ToolHPWatcher:SaveConfigToStorage()
    if not self.docId then return end
    local raidId = nil
    if self.sessionId then
        local sess = S.GetSession(self.sessionId)
        if sess then raidId = sess.raidId end
    end
    if not raidId then
        local active = S.GetActiveSession()
        if active then raidId = active.raidId end
    end
    if raidId and self.docId then
        S.SetToolConfig(raidId, self.docId, self.config)
    end
end
