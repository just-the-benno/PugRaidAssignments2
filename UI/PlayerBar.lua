-- UI/PlayerBar.lua
-- Floating, movable Session Player Bar.
-- Layout: [<< Prev]  DocName (N/Total)  [Next >>]  [View][Sim][Send][Target][End]
-- Expands downward to show the target checklist.

local W = PugRaidAssignmentsWidgets
local S = PugRaidAssignmentsStorage
local P = PugRaidAssignmentsParser
local T = PugRaidAssignmentsTemplate
local D = PugRaidAssignmentsDispatcher

local bar                  -- main bar frame
local checklistPanel       -- expanded sub-frame
local lblDocName
local checklistRows = {}
local _isExpanded = false

local function GetActiveSessionAndRaid()
    local sess = S.GetActiveSession()
    if not sess then return nil, nil end
    local raid = S.GetRaid(sess.raidId)
    return sess, raid
end

local function GetCurrentDoc(sess, raid)
    if not sess or not raid then return nil end
    local docs = S.GetDocumentsSorted(sess.raidId)
    local idx = math.max(1, math.min(sess.currentDocIndex or 1, #docs))
    sess.currentDocIndex = idx
    return docs[idx], idx, #docs
end

-- ── Checklist ──────────────────────────────────────────────────────────────────

local function RebuildChecklist(sess, doc)
    -- Clear old rows
    for _, row in ipairs(checklistRows) do
        row.icon:Hide()
        row.status:Hide()
    end
    checklistRows = {}

    if not sess or not doc then return end
    local ver = S.GetLatestVersion(sess.raidId, doc.id)
    if not ver then return end

    local sections = P.Parse(ver.text)
    local targets  = P.GetTargets(sections)
    local tp       = S.GetTargetProgress(sess, doc.id)
    local rowH = 20
    local y = -4
    for i, entry in ipairs(targets) do

        local iconLbl = checklistPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        iconLbl:SetPoint("TOPLEFT", checklistPanel, "TOPLEFT", 6, y - (i-1)*rowH)
        local iconName = PugRaidAssignmentsParser.ICON_NAMES[entry.iconIndex] or ("rt"..entry.iconIndex)
        iconLbl:SetText(entry.mobName .. " --> " .. iconName)
        iconLbl:SetWidth(240)

        local statusLbl = checklistPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusLbl:SetPoint("TOPLEFT", checklistPanel, "TOPLEFT", 250, y - (i-1)*rowH)
        if tp.assignedIcons[entry.iconIndex] then
            statusLbl:SetText("|cff00ff00[Done]|r")
        else
            statusLbl:SetText("|cffff0000[Missing]|r")
        end

        checklistRows[#checklistRows + 1] = { icon = iconLbl, status = statusLbl }
    end

    local panelH = math.max(30, #targets * rowH + 30)
    checklistPanel:SetHeight(panelH)
end

local function ShowChecklist(show)
    _isExpanded = show
    if show then
        checklistPanel:Show()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        RebuildChecklist(sess, doc)
    else
        checklistPanel:Hide()
    end
end

-- ── Targeting callbacks ────────────────────────────────────────────────────────

-- Passed to the targeting module so it can drive checklist state
-- without needing direct access to this file's locals.
local TargetingCallbacks = {
    IsExpanded      = function() return _isExpanded end,
    ShowChecklist   = function(show) ShowChecklist(show) end,
    RebuildChecklist = function(sess, doc) RebuildChecklist(sess, doc) end,
}

-- ── Bar text update ────────────────────────────────────────────────────────────

local function RefreshBar()
    local sess, raid = GetActiveSessionAndRaid()
    if not sess or not raid then
        lblDocName:SetText("No active session")
        return
    end
    local doc, idx, total = GetCurrentDoc(sess, raid)
    if doc then
        lblDocName:SetText((doc.name or "?") .. " (" .. idx .. "/" .. total .. ")")
    else
        lblDocName:SetText("No documents")
    end
    if _isExpanded then
        ShowChecklist(true) -- refresh
    end
end

-- ── Build ──────────────────────────────────────────────────────────────────────

local function Build()
    bar = CreateFrame("Frame", "PugRaidPlayerBar", UIParent, "BackdropTemplate")
    bar:SetSize(680, 34)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -200)
    bar:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 },
    })
    bar:SetBackdropColor(0, 0, 0, 0.85)
    bar:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetFrameStrata("HIGH")
    bar:SetToplevel(true)
    bar:Hide()

    -- Restore saved position
    if PugRaidAssignmentsDB and PugRaidAssignmentsDB.playerBarPos then
        local pos = PugRaidAssignmentsDB.playerBarPos
        bar:ClearAllPoints()
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if PugRaidAssignmentsDB then
            PugRaidAssignmentsDB.playerBarPos = { point=point, relPoint=relPoint, x=x, y=y }
        end
    end)

    local btnPrev = W.MakeButton(bar, "<< Prev", 72, 24)
    btnPrev:SetPoint("LEFT", bar, "LEFT", 4, 0)
    btnPrev:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        if not sess then return end
        local docs = S.GetDocumentsSorted(sess.raidId)
        sess.currentDocIndex = math.max(1, (sess.currentDocIndex or 1) - 1)
        RefreshBar()
    end)

    lblDocName = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblDocName:SetPoint("LEFT", btnPrev, "RIGHT", 8, 0)
    lblDocName:SetWidth(200)
    lblDocName:SetText("—")

    local btnNext = W.MakeButton(bar, "Next >>", 72, 24)
    btnNext:SetPoint("LEFT", lblDocName, "RIGHT", 8, 0)
    btnNext:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        if not sess then return end
        local docs = S.GetDocumentsSorted(sess.raidId)
        sess.currentDocIndex = math.min(#docs, (sess.currentDocIndex or 1) + 1)
        RefreshBar()
    end)

    local btnView = W.MakeButton(bar, "View", 50, 24)
    btnView:SetPoint("LEFT", btnNext, "RIGHT", 8, 0)
    btnView:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not doc then return end
        local ver = S.GetLatestVersion(sess.raidId, doc.id)
        PugRaidAssignmentsViewWindow_Open(ver and ver.text or "", doc.name)
    end)

    local btnSim = W.MakeButton(bar, "Sim", 44, 24)
    btnSim:SetPoint("LEFT", btnView, "RIGHT", 4, 0)
    btnSim:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not doc then return end
        local ver = S.GetLatestVersion(sess.raidId, doc.id)
        if not ver then return end
        local sections = P.Parse(ver.text)
        -- Collect lastValues
        local values = {}
        for var in pairs(doc.lastValues or {}) do
            values[var] = S.GetLastValue(sess.raidId, doc.id, var)
        end
        local skippedVars = S.GetSkippedVars(sess, doc.id)
        local msgs = T.BuildMessages(sections, values, skippedVars)
        -- SESSION mode: validate first
        local personalVars = {}
        for _, sec in ipairs(sections) do
            if sec.kind == "PERSONAL" then
                for _, ln in ipairs(sec.lines) do
                    local target = ln:match("^%s*(.-)%s*:")
                    if target then
                        local v = target:match("{{(%w+)}}")
                        if v then personalVars[#personalVars+1] = v end
                    end
                end
            end
        end
        local invalid = D.ValidateRoster(values, personalVars, skippedVars)
        if #invalid > 0 then
            print("|cffff0000PugRaid:|r Invalid roster assignments:")
            for _, pair in ipairs(invalid) do
                print("  {{" .. pair.var .. "}} = " .. pair.value)
            end
            return
        end
        D.Simulate(msgs)
    end)

    local btnSend = W.MakeButton(bar, "Send", 50, 24)
    btnSend:SetPoint("LEFT", btnSim, "RIGHT", 4, 0)
    btnSend:SetScript("OnClick", function(self)
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not doc then return end
        local ver = S.GetLatestVersion(sess.raidId, doc.id)
        if not ver then return end
        local sections = P.Parse(ver.text)
        local values = {}
        for k, _ in pairs(doc.lastValues or {}) do
            values[k] = S.GetLastValue(sess.raidId, doc.id, k)
        end

        -- Shift+click opens assign window
        if IsShiftKeyDown() then
            PugRaidAssignmentsAssignWindow_Open(sess.raidId, doc.id, sections, "SESSION")
            return
        end

        -- Validate
        local skippedVars = S.GetSkippedVars(sess, doc.id)
        local personalVars = {}
        for _, sec in ipairs(sections) do
            if sec.kind == "PERSONAL" then
                for _, ln in ipairs(sec.lines) do
                    local target = ln:match("^%s*(.-)%s*:")
                    if target then
                        local v = target:match("{{(%w+)}}")
                        if v then personalVars[#personalVars+1] = v end
                    end
                end
            end
        end
        local invalid = D.ValidateRoster(values, personalVars, skippedVars)
        if #invalid > 0 then
            print("|cffff0000PugRaid:|r Can't send — invalid roster assignment(s):")
            local failingVars = {}
            for _, pair in ipairs(invalid) do
                print("  {{" .. pair.var .. "}} = \"" .. pair.value .. "\"")
                failingVars[#failingVars + 1] = pair.var
            end
            print("Opening Assign window so you can fix or skip them.")
            PugRaidAssignmentsAssignWindow_Open(sess.raidId, doc.id, sections, "SESSION", failingVars)
            return
        end

        -- Send everything except LONG
        local toSend = {}
        for _, sec in ipairs(sections) do
            if sec.kind ~= "LONG" and sec.kind ~= "TARGETS" then
                toSend[#toSend + 1] = sec
            end
        end
        local msgs = T.BuildMessages(toSend, values, skippedVars)
        -- Persist values
        for k, v in pairs(values) do
            S.SetLastValue(sess.raidId, doc.id, k, v)
        end

        if P.HasBlocks(toSend) then
            local queue = D.BuildPresenterQueue(msgs)
            PugRaidPresenterBar_Open(queue)
        else
            D.SendAll(msgs)
            print("|cff00ff00PugRaid:|r Sent.")
        end
    end)

    local btnTarget = W.MakeButton(bar, "Target", 56, 24)
    btnTarget:SetPoint("LEFT", btnSend, "RIGHT", 4, 0)
    btnTarget:SetScript("OnClick", function()
        PugRaidTargeting_ExecuteManualTarget(TargetingCallbacks)
    end)

    local btnEnd = W.MakeButton(bar, "End", 44, 24)
    btnEnd:SetPoint("LEFT", btnTarget, "RIGHT", 4, 0)
    btnEnd:SetScript("OnClick", function()
        local sess = S.GetActiveSession()
        if sess then
            S.EndSession(sess)
            print("|cffffff00PugRaid:|r Session ended.")
            LoggingCombat(false)
        end
        bar:Hide()
        ShowChecklist(false)
    end)

    -- Checklist panel
    checklistPanel = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    checklistPanel:SetPoint("TOPLEFT",  bar, "BOTTOMLEFT",  0, 0)
    checklistPanel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    checklistPanel:SetHeight(60)
    checklistPanel:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 },
    })
    checklistPanel:SetBackdropColor(0, 0, 0, 0.80)
    checklistPanel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    checklistPanel:Hide()

    local btnReset = W.MakeButton(checklistPanel, "Reset", 60, 20)
    btnReset:SetPoint("BOTTOMRIGHT", checklistPanel, "BOTTOMRIGHT", -4, 4)
    btnReset:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not sess or not doc then return end
        S.ResetTargetProgress(sess, doc.id)
        RebuildChecklist(sess, doc)
    end)

    local btnCloseChecklist = W.MakeButton(checklistPanel, "Close", 60, 20)
    btnCloseChecklist:SetPoint("RIGHT", btnReset, "LEFT", -4, 0)
    btnCloseChecklist:SetScript("OnClick", function()
        ShowChecklist(false)
    end)
end

-- ── Public API ─────────────────────────────────────────────────────────────────

function PugRaidPlayerBar_Open()
    if not bar then Build() end
    _isExpanded = false
    checklistPanel:Hide()
    RefreshBar()
    bar:Show()
    bar:Raise()
end

function PugRaidPlayerBar_Close()
    if bar then bar:Hide() end
    ShowChecklist(false)
end

function PugRaidPlayerBar_IsShown()
    return bar and bar:IsShown()
end

-- Called by the PUGRAID_TARGET_KEY keybinding.
function PugRaidPlayerBar_OnTargetKey()
    if not (bar and bar:IsShown()) then return end
    PugRaidTargeting_ExecuteManualTarget(TargetingCallbacks)
end

-- Called by the PUGRAID_MOUSEOVER_KEY keybinding.
function PugRaidPlayerBar_OnMouseoverKey()
    if not (bar and bar:IsShown()) then return end
    PugRaidTargeting_ExecuteMouseoverTarget(TargetingCallbacks)
end