-- ToolManaWatch.lua
-- ManaWatch tool implementation for raid tools infrastructure.
-- Real-time monitoring of raid members' mana with alerts when falling below thresholds.

local W = PugRaidAssignmentsWidgets
local D = PugRaidAssignmentsDispatcher
local S = PugRaidAssignmentsStorage

PugRaidAssignmentsToolManaWatch = {}
local ToolManaWatch = PugRaidAssignmentsToolManaWatch
ToolManaWatch.__index = ToolManaWatch

local DEFAULT_CONFIG = {
    type = "ManaWatch",
    scanInterval = 150,
    redThreshold = 1200,
    amberThreshold = 2000,
    redMessage = "CRITICAL MANA",
    amberMessage = "Mana running low",
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

function ToolManaWatch:New(config, sessionId, docId)
    local instance = setmetatable({}, ToolManaWatch)
    instance:OnInit(config, sessionId, docId)
    return instance
end

function ToolManaWatch:OnInit(config, sessionId, docId)
    self.config = CopyTable(DEFAULT_CONFIG)
    if type(config) == "table" then
        for k, v in pairs(config) do
            self.config[k] = CopyTable(v)
        end
    end

    self.sessionId = sessionId
    self.docId = docId

    self.playerStates = {} -- { [playerName] = { inRed = false, inAmber = false } }
    self.redPlayers = {}
    self.amberPlayers = {}

    self.running = false
    self.timeSinceLastScan = 0
    self.redCollapsed = false
    self.amberCollapsed = false

    self.rowPool = {}
    self.activeRows = {}
end

function ToolManaWatch:GetFrame()
    if not self.frame then
        self:BuildFrame()
    end
    return self.frame
end

function ToolManaWatch:BuildFrame()
    local f = W.MakeWindow("PugRaidManaWatchFrame", "ManaWatch", 320, 420)
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

    -- Scroll pane for content
    local sf, cf = W.MakeScrollPane(f, 295, 330)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -32)
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
    redHeaderText:SetText("RED (Critical)")
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
    amberHeaderText:SetText("AMBER (Low)")
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
    local btnConfig = W.MakeButton(f, "Config", 90, 22)
    btnConfig:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
    btnConfig:SetScript("OnClick", function()
        self:ShowConfigUI()
    end)

    local btnReset = W.MakeButton(f, "Reset", 90, 22)
    btnReset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
    btnReset:SetScript("OnClick", function()
        self:ResetPlayerState()
        self:UpdateUI()
    end)
end

function ToolManaWatch:OnStart()
    self.running = true
    self.timeSinceLastScan = 0
    local f = self:GetFrame()
    f:Show()
    f:Raise()

    f:SetScript("OnUpdate", function(_, elapsed)
        if not self.running then return end
        self.timeSinceLastScan = self.timeSinceLastScan + elapsed
        local intervalSec = (tonumber(self.config.scanInterval) or 150) / 1000
        if self.timeSinceLastScan >= intervalSec then
            self.timeSinceLastScan = 0
            self:ScanRaid()
            self:CheckAndAlertPlayers()
            self:UpdateUI()
        end
    end)

    self:ScanRaid()
    self:CheckAndAlertPlayers()
    self:UpdateUI()
end

function ToolManaWatch:OnStop()
    self.running = false
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    if self.configFrame then
        self.configFrame:Hide()
    end
end

function ToolManaWatch:OnConfigChanged(newConfig)
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

function ToolManaWatch:ScanRaid()
    self.redPlayers = {}
    self.amberPlayers = {}

    local redThresh = tonumber(self.config.redThreshold) or 1200
    local amberThresh = tonumber(self.config.amberThreshold) or 2000

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

                local powerType = UnitPowerType and UnitPowerType(unit)
                -- 0 is MANA power type in WoW
                if powerType == 0 then
                    local mana = 0
                    if UnitMana then
                        mana = UnitMana(unit)
                    elseif UnitPower then
                        mana = UnitPower(unit, 0)
                    end

                    local locClass, engClass = UnitClass(unit)
                    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"

                    local playerObj = {
                        unit = unit,
                        name = name,
                        class = engClass or locClass or "WARRIOR",
                        role = role,
                        mana = mana,
                    }

                    if mana < redThresh then
                        table.insert(self.redPlayers, playerObj)
                    elseif mana < amberThresh then
                        table.insert(self.amberPlayers, playerObj)
                    end
                end
            end
        end
    end

    table.sort(self.redPlayers, function(a, b) return a.mana < b.mana end)
    table.sort(self.amberPlayers, function(a, b) return a.mana < b.mana end)
end

function ToolManaWatch:CheckAndAlertPlayers()
    local redMessage = self.config.redMessage or "CRITICAL MANA"
    local amberMessage = self.config.amberMessage or "Mana running low"

    -- Alert Red players
    for _, p in ipairs(self.redPlayers) do
        local state = self.playerStates[p.name]
        if not state then
            state = { inRed = false, inAmber = false }
            self.playerStates[p.name] = state
        end

        if not state.inRed then
            state.inRed = true
            state.inAmber = true
            D.SendMessage({ kind = "PERSONAL", target = p.name, text = redMessage })
        end
    end

    -- Alert Amber players
    for _, p in ipairs(self.amberPlayers) do
        local state = self.playerStates[p.name]
        if not state then
            state = { inRed = false, inAmber = false }
            self.playerStates[p.name] = state
        end

        if not state.inAmber then
            state.inAmber = true
            D.SendMessage({ kind = "PERSONAL", target = p.name, text = amberMessage })
        end

        -- If player was in red and recovered to amber, reset inRed state
        if state.inRed then
            state.inRed = false
        end
    end

    -- Reset state for players above amber threshold
    local redThresh = tonumber(self.config.redThreshold) or 1200
    local amberThresh = tonumber(self.config.amberThreshold) or 2000

    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    end

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name and name ~= "" then
                local powerType = UnitPowerType and UnitPowerType(unit)
                if powerType == 0 then
                    local mana = UnitMana and UnitMana(unit) or (UnitPower and UnitPower(unit, 0) or 0)
                    if mana >= amberThresh then
                        local state = self.playerStates[name]
                        if state then
                            state.inRed = false
                            state.inAmber = false
                        end
                    end
                end
            end
        end
    end
end

function ToolManaWatch:ResetPlayerState()
    self.playerStates = {}
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

        row.manaText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.manaText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.manaText:SetJustifyH("RIGHT")
    end
    row:Show()
    self.activeRows[#self.activeRows + 1] = row
    return row
end

function ToolManaWatch:UpdateUI()
    if not self.frame or not self.contentFrame then return end

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
    self.redHeaderText:SetText(redArrow .. "RED (Critical) (" .. #self.redPlayers .. ")")
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

                -- Mana text
                row.manaText:SetText("| " .. p.mana)
                row.manaText:SetTextColor(1, 0.3, 0.3)

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
    self.amberHeaderText:SetText(amberArrow .. "AMBER (Low) (" .. #self.amberPlayers .. ")")
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

                -- Mana text
                row.manaText:SetText("| " .. p.mana)
                row.manaText:SetTextColor(1, 0.7, 0.2)

                y = y + 22
            end
        end
    else
        self.amberStatus:Hide()
    end

    self.contentFrame:SetHeight(math.max(1, y))
end

function ToolManaWatch:ShowConfigUI()
    if not self.configFrame then
        local cf = W.MakeWindow("PugRaidManaWatchConfigFrame", "ManaWatch Configuration", 360, 360)
        cf:SetFrameStrata("HIGH")
        cf:SetToplevel(true)
        self.configFrame = cf

        local y = -36

        -- Red Threshold
        local lblRed = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblRed:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblRed:SetText("Red Threshold (Critical Mana):")
        y = y - 20

        local ebRed, bgRed = W.MakeEditBox(cf, 320, 22, false)
        bgRed:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebRedThreshold = ebRed
        y = y - 30

        -- Amber Threshold
        local lblAmber = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblAmber:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblAmber:SetText("Amber Threshold (Low Mana):")
        y = y - 20

        local ebAmber, bgAmber = W.MakeEditBox(cf, 320, 22, false)
        bgAmber:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebAmberThreshold = ebAmber
        y = y - 30

        -- Scan Interval
        local lblInterval = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblInterval:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblInterval:SetText("Scan Interval (ms):")
        y = y - 20

        local ebInterval, bgInterval = W.MakeEditBox(cf, 320, 22, false)
        bgInterval:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebScanInterval = ebInterval
        y = y - 30

        -- Red Message
        local lblRedMsg = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblRedMsg:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblRedMsg:SetText("Red Message (Whisper):")
        y = y - 20

        local ebRedMsg, bgRedMsg = W.MakeEditBox(cf, 320, 44, true)
        bgRedMsg:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebRedMessage = ebRedMsg
        y = y - 52

        -- Amber Message
        local lblAmberMsg = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblAmberMsg:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        lblAmberMsg:SetText("Amber Message (Whisper):")
        y = y - 20

        local ebAmberMsg, bgAmberMsg = W.MakeEditBox(cf, 320, 44, true)
        bgAmberMsg:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, y)
        self.ebAmberMessage = ebAmberMsg
        y = y - 52

        -- Save / Cancel buttons
        local btnSave = W.MakeButton(cf, "Save", 90, 22)
        btnSave:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 14, 10)
        btnSave:SetScript("OnClick", function()
            local redVal = tonumber(self.ebRedThreshold:GetText()) or 1200
            local amberVal = tonumber(self.ebAmberThreshold:GetText()) or 2000
            local intervalVal = tonumber(self.ebScanInterval:GetText()) or 150
            local redMsg = self.ebRedMessage:GetText() or "CRITICAL MANA"
            local amberMsg = self.ebAmberMessage:GetText() or "Mana running low"

            self.config.redThreshold = redVal
            self.config.amberThreshold = amberVal
            self.config.scanInterval = intervalVal
            self.config.redMessage = redMsg
            self.config.amberMessage = amberMsg

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

    self.ebRedThreshold:SetText(tostring(self.config.redThreshold or 1200))
    self.ebAmberThreshold:SetText(tostring(self.config.amberThreshold or 2000))
    self.ebScanInterval:SetText(tostring(self.config.scanInterval or 150))
    self.ebRedMessage:SetText(tostring(self.config.redMessage or "CRITICAL MANA"))
    self.ebAmberMessage:SetText(tostring(self.config.amberMessage or "Mana running low"))

    self.configFrame:Show()
    self.configFrame:Raise()
end

function ToolManaWatch:SavePosition()
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

function ToolManaWatch:SaveConfigToStorage()
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
