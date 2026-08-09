-- UI/RaidListWindow.lua
-- Main window: list of raids with actions, + New Raid button.

local W = PugRaidAssignmentsWidgets
local S = PugRaidAssignmentsStorage

local frame
local contentFrame
local _raidRows = {}

local RAID_TYPES = {
    "Karazhan",
    "Gruul's Lair",
    "Magtheridon's Lair",
    "Serpentshrine Cavern",
    "The Eye (Tempest Keep)",
    "Mount Hyjal",
    "Black Temple",
    "Zul'Aman",
    "Sunwell Plateau",
    "Unknown/Other",
}

local ROW_H = 36
local ROW_PAD = 4

local function ClearRows()
    for _, r in ipairs(_raidRows) do
        if r.Hide then r:Hide() end
    end
    _raidRows = {}
end

local function RebuildList()
    ClearRows()
    local raids = S.GetAllRaids()
    -- Sort raids by name for stable display
    local sorted = {}
    for _, raid in pairs(raids) do sorted[#sorted + 1] = raid end
    table.sort(sorted, function(a, b) return (a.name or "") < (b.name or "") end)

    local y = 0
    for _, raid in ipairs(sorted) do
        local row = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
        row:SetSize(460, ROW_H)
        row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -y)
        row:SetBackdrop({
            bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left=2, right=2, top=2, bottom=2 },
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
        row:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        _raidRows[#_raidRows + 1] = row

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 8, 0)
        lbl:SetWidth(160)
        lbl:SetText((raid.name or "?") .. " |cffaaaaaa(" .. (raid.raidType or "?") .. ")|r")

        local capturedRaid = raid

        local btnDocs = W.MakeButton(row, "Documents", 80, 22)
        btnDocs:SetPoint("LEFT", row, "LEFT", 174, 0)
        btnDocs:SetScript("OnClick", function()
            PugRaidAssignmentsDocumentsWindow_Open(capturedRaid.id)
        end)
        _raidRows[#_raidRows + 1] = btnDocs

        local btnSession = W.MakeButton(row, "Last Session", 90, 22)
        btnSession:SetPoint("LEFT", btnDocs, "RIGHT", 4, 0)
        btnSession:SetScript("OnClick", function()
            local sess = S.GetLastSession(capturedRaid.id)
            PugRaidAssignmentsSessionViewWindow_Open(capturedRaid, sess)
        end)
        _raidRows[#_raidRows + 1] = btnSession

        local btnStart = W.MakeButton(row, "Start Session", 90, 22)
        btnStart:SetPoint("LEFT", btnSession, "RIGHT", 4, 0)
        btnStart:SetScript("OnClick", function()
            -- Check for existing active session
            local active = S.GetActiveSession()
            if active and active.id then
                local activeRaid = S.GetRaid(active.raidId)
                local activeRaidName = activeRaid and activeRaid.name or "Unknown"
                StaticPopup_Show("PUGRAID_CONFIRM_START_SESSION", activeRaidName, nil,
                    { newRaidId = capturedRaid.id, activeSession = active })
            else
                S.CreateSession(capturedRaid.id)
                PugRaidPlayerBar_Open()
            end
        end)
        _raidRows[#_raidRows + 1] = btnStart

        local btnDel = W.MakeButton(row, "Delete", 60, 22)
        btnDel:SetPoint("LEFT", btnStart, "RIGHT", 4, 0)
        btnDel:SetScript("OnClick", function()
            StaticPopup_Show("PUGRAID_CONFIRM_DELETE_RAID", capturedRaid.name, nil, { raidId = capturedRaid.id })
        end)
        _raidRows[#_raidRows + 1] = btnDel

        y = y + ROW_H + ROW_PAD
    end
    contentFrame:SetHeight(math.max(1, y))
end

-- ── New Raid dialog ───────────────────────────────────────────────────────────
local newRaidFrame
local newRaidNameEB, newRaidNameBg
local _selectedRaidType = RAID_TYPES[1]

local function OpenNewRaidDialog()
    if not newRaidFrame then
        newRaidFrame = W.MakeWindow("PugRaidNewRaidDialog", "New Raid", 340, 180)
        newRaidFrame:SetFrameStrata("HIGH")
        newRaidFrame:SetToplevel(true)

        local lblName = newRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblName:SetPoint("TOPLEFT", newRaidFrame, "TOPLEFT", 14, -44)
        lblName:SetText("Name:")

        newRaidNameEB, newRaidNameBg = W.MakeEditBox(newRaidFrame, 230, 22, false)
        newRaidNameBg:SetPoint("TOPLEFT", newRaidFrame, "TOPLEFT", 60, -42)

        local lblType = newRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblType:SetPoint("TOPLEFT", newRaidFrame, "TOPLEFT", 14, -74)
        lblType:SetText("Type:")

        local btnTypeDropdown = W.MakeButton(newRaidFrame, _selectedRaidType, 220, 22)
        btnTypeDropdown:SetPoint("TOPLEFT", newRaidFrame, "TOPLEFT", 60, -72)
        btnTypeDropdown:SetScript("OnClick", function(self)
            local items = {}
            for _, rt in ipairs(RAID_TYPES) do
                items[#items + 1] = { text = rt, value = rt }
            end
            W.OpenDropdown(self, items, function(value)
                _selectedRaidType = value
                btnTypeDropdown:SetText(value)
            end)
        end)

        local btnCreate = W.MakeButton(newRaidFrame, "Create", 80, 22)
        btnCreate:SetPoint("BOTTOMLEFT", newRaidFrame, "BOTTOMLEFT", 14, 10)
        btnCreate:SetScript("OnClick", function()
            local name = newRaidNameEB:GetText()
            if name == "" then
                print("|cffff0000PugRaid:|r Raid name is required.")
                return
            end
            S.CreateRaid(name, _selectedRaidType)
            newRaidFrame:Hide()
            RebuildList()
        end)

        local btnCancel = W.MakeButton(newRaidFrame, "Cancel", 80, 22)
        btnCancel:SetPoint("LEFT", btnCreate, "RIGHT", 8, 0)
        btnCancel:SetScript("OnClick", function() newRaidFrame:Hide() end)
    end
    _selectedRaidType = RAID_TYPES[1]
    newRaidNameEB:SetText("")
    newRaidFrame:Show()
    newRaidFrame:Raise()
end

-- ── Static Popups ─────────────────────────────────────────────────────────────
StaticPopupDialogs["PUGRAID_CONFIRM_DELETE_RAID"] = {
    text           = "Delete raid \"%s\" and ALL its documents, versions, and session history? This cannot be undone.",
    button1        = "Delete",
    button2        = "Cancel",
    OnAccept       = function(self, data)
        S.DeleteRaid(data.raidId)
        RebuildList()
    end,
    timeout        = 0,
    whileDead      = true,
    hideOnEscape   = true,
    preferredIndex = 3,
}

StaticPopupDialogs["PUGRAID_CONFIRM_START_SESSION"] = {
    text           = "A session for \"%s\" is still active. End it and start a new one?",
    button1        = "Yes",
    button2        = "Cancel",
    OnAccept       = function(self, data)
        S.EndSession(data.activeSession)
        S.CreateSession(data.newRaidId)
        PugRaidPlayerBar_Open()
    end,
    timeout        = 0,
    whileDead      = true,
    hideOnEscape   = true,
    preferredIndex = 3,
}

-- ── Main window ───────────────────────────────────────────────────────────────
local function Build()
    frame = W.MakeWindow("PugRaidListWindow", "Raid Assignments", 500, 480)

    local btnNew = W.MakeButton(frame, "+ New Raid", 100, 24)
    btnNew:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -36)
    btnNew:SetScript("OnClick", OpenNewRaidDialog)

    local sf, cf = W.MakeScrollPane(frame, 480, 400)
    sf:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -68)
    contentFrame = cf
end

function PugRaidAssignmentsRaidListWindow_Open()
    if not frame then Build() end
    RebuildList()
    frame:Show()
    frame:Raise()
end

function PugRaidAssignmentsRaidListWindow_Toggle()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        RebuildList()
        frame:Show()
        frame:Raise()
    end
end
