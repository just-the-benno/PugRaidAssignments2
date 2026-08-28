-- UI/PlayerBar.lua
-- Floating, movable Session Player Bar.
-- Layout: [<< Prev]  DocName (N/Total)  [Next >>]  [View][Sim][Send][Target][Close][End]
-- Expands downward to show the target checklist.
--
-- Target button:
--   Left-click       -> open checklist (if closed) or mark current target (if open); stays open.
--   Shift+left-click -> nameplate auto-scan: marks all visible matching living enemies.
--
-- Public functions for keybinding (register in Core.lua):
--   PugRaidPlayerBar_KeybindTarget()     -> same as left-clicking Target
--   PugRaidPlayerBar_KeybindAutoTarget() -> same as Shift+clicking Target

local W = PugRaidAssignmentsWidgets
local S = PugRaidAssignmentsStorage
local P = PugRaidAssignmentsParser
local T = PugRaidAssignmentsTemplate
local D = PugRaidAssignmentsDispatcher

local bar
local checklistPanel
local lblDocName
local checklistRows = {}
local _isExpanded   = false

-- ── Session helpers ──────────────────────────────────────────────────────────

local function GetActiveSessionAndRaid()
    local sess = S.GetActiveSession()
    if not sess then return nil, nil end
    local raid = S.GetRaid(sess.raidId)
    return sess, raid
end

local function GetCurrentDoc(sess, raid)
    if not sess or not raid then return nil end
    local docs = S.GetDocumentsSorted(sess.raidId)
    local idx  = math.max(1, math.min(sess.currentDocIndex or 1, #docs))
    sess.currentDocIndex = idx
    return docs[idx], idx, #docs
end

-- ── Checklist ────────────────────────────────────────────────────────────────

local function RebuildChecklist(sess, doc)
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
    local rowH     = 20
    local y        = -4

    for i, entry in ipairs(targets) do
        local iconName = PugRaidAssignmentsParser.ICON_NAMES[entry.iconIndex] or ("rt" .. entry.iconIndex)

        local iconLbl = checklistPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        iconLbl:SetPoint("TOPLEFT", checklistPanel, "TOPLEFT", 6, y - (i - 1) * rowH)
        iconLbl:SetText(entry.mobName .. " -> " .. iconName)
        iconLbl:SetWidth(240)

        local statusLbl = checklistPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusLbl:SetPoint("TOPLEFT", checklistPanel, "TOPLEFT", 250, y - (i - 1) * rowH)
        if tp.assignedIcons[entry.iconIndex] then
            statusLbl:SetText("|cff00ff00[done]|r")
        else
            statusLbl:SetText("|cffff0000[open]|r")
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

-- ── Manual target action ─────────────────────────────────────────────────────
-- If the checklist is closed: open it and do nothing else.
-- If the checklist is open: attempt to mark the current target, then refresh
-- the checklist in place. Never closes the checklist.
local function ExecuteManualTarget()
    if not bar or not bar:IsShown() then return end
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not _isExpanded then
        -- First press: just open the checklist.
        ShowChecklist(true)
        return
    end

    -- Checklist already open: try to mark current target.
    if doc then
        local targetName = UnitName("target")
        if targetName then
            local ver      = S.GetLatestVersion(sess.raidId, doc.id)
            local sections = ver and P.Parse(ver.text) or {}
            local targets  = P.GetTargets(sections)
            local tp       = S.GetTargetProgress(sess, doc.id)

            for _, entry in ipairs(targets) do
                if entry.mobName:lower() == targetName:lower()
                    and not tp.assignedIcons[entry.iconIndex]
                then
                    if D.MarkTarget(entry.iconIndex) then
                        S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
                    end
                    break
                end
            end
        end
    end

    -- Refresh checklist to reflect any new marks; keep it open.
    ShowChecklist(true)
end

-- ── Nameplate auto-scan ──────────────────────────────────────────────────────
-- Iterates nameplate unit tokens (nameplate1..N), filters to living enemies,
-- and marks any whose name matches an unassigned entry in the target list.
-- Returns the number of targets still unassigned after the scan, or nil on
-- permission error.
--
-- Notes:
--   * SetCVar("nameplateShowEnemies", 1) is called each time to ensure
--     nameplates are visible. This is a persistent setting — accepted side effect.
--   * SetRaidTarget(token, iconIndex) is called directly so the player's current
--     target is never disturbed during the scan.
--   * Nameplate tokens are sequential from nameplate1 with no gaps; the loop
--     breaks on the first missing token so 40 is just a safety ceiling.
--   * When multiple mobs share a name, whichever nameplate is encountered first
--     receives the next available icon — pairing may differ between scans.
--   * Already-assigned icons are always skipped via tp.assignedIcons.
local function DoAutoTarget(sess, doc)
    -- if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
    --     print("|cffff8800PugRaid:|r You need to be leader or assist to mark targets.")
    --     return nil
    -- end

    SetCVar("nameplateShowEnemies", 1)

    local ver = S.GetLatestVersion(sess.raidId, doc.id)
    if not ver then return 0 end

    local sections = P.Parse(ver.text)
    local targets  = P.GetTargets(sections)
    if #targets == 0 then
        print("|cffffff00PugRaid:|r No targets defined for this document.")
        return 0
    end

    local tp = S.GetTargetProgress(sess, doc.id)

    -- Build a per-name queue of unassigned icon indices (document order).
    local unassigned = {}
    for _, entry in ipairs(targets) do
        if not tp.assignedIcons[entry.iconIndex] then
            local key = entry.mobName:lower()
            if not unassigned[key] then unassigned[key] = {} end
            unassigned[key][#unassigned[key] + 1] = entry.iconIndex
        end
    end

    -- Iterate nameplate unit tokens sequentially; break on first missing one.
    for i = 1, 40 do
        local token = "nameplate" .. i
        if not UnitExists(token) then break end
        if UnitIsEnemy("player", token) and not UnitIsDead(token) then
            local mobName = UnitName(token)
            if mobName then
                local key   = mobName:lower()
                local queue = unassigned[key]
                if queue and #queue > 0 then
                    local iconIndex = table.remove(queue, 1)
                    SetRaidTarget(token, iconIndex)
                    S.MarkIconAssigned(sess, doc.id, iconIndex)
                    if #queue == 0 then unassigned[key] = nil end
                end
            end
        end
    end

    -- Count remaining unassigned entries.
    local remaining = 0
    for _, entry in ipairs(targets) do
        if not tp.assignedIcons[entry.iconIndex] then
            remaining = remaining + 1
        end
    end
    return remaining
end

local function ExecuteAutoTarget()
    if not bar or not bar:IsShown() then return end
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)
    if not doc then
        ShowChecklist(true)
        return
    end

    local remaining = DoAutoTarget(sess, doc)
    if remaining == nil then
        -- Permission error already printed inside DoAutoTarget.
        return
    elseif remaining == 0 then
        print("|cff00ff00PugRaid:|r All targets marked.")
        ShowChecklist(false)
    else
        print("|cffffff00PugRaid:|r " .. remaining .. " target(s) still unassigned - scan again when they are in range.")
        ShowChecklist(true)
    end
end

-- ── Bar text update ──────────────────────────────────────────────────────────

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
        ShowChecklist(true)
    end
end

-- ── Build ────────────────────────────────────────────────────────────────────

local function Build()
    bar = CreateFrame("Frame", "PugRaidPlayerBar", UIParent, "BackdropTemplate")
    bar:SetSize(720, 34)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -200)
    bar:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
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
            PugRaidAssignmentsDB.playerBarPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- [<< Prev]
    local btnPrev = W.MakeButton(bar, "<< Prev", 72, 24)
    btnPrev:SetPoint("LEFT", bar, "LEFT", 4, 0)
    btnPrev:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        if not sess then return end
        sess.currentDocIndex = math.max(1, (sess.currentDocIndex or 1) - 1)
        RefreshBar()
    end)

    -- Doc name label
    lblDocName = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblDocName:SetPoint("LEFT", btnPrev, "RIGHT", 8, 0)
    lblDocName:SetWidth(200)
    lblDocName:SetText("-")

    -- [Next >>]
    local btnNext = W.MakeButton(bar, "Next >>", 72, 24)
    btnNext:SetPoint("LEFT", lblDocName, "RIGHT", 8, 0)
    btnNext:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        if not sess then return end
        local docs = S.GetDocumentsSorted(sess.raidId)
        sess.currentDocIndex = math.min(#docs, (sess.currentDocIndex or 1) + 1)
        RefreshBar()
    end)

    -- [View]
    local btnView = W.MakeButton(bar, "View", 50, 24)
    btnView:SetPoint("LEFT", btnNext, "RIGHT", 8, 0)
    btnView:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not doc then return end
        local ver = S.GetLatestVersion(sess.raidId, doc.id)
        PugRaidAssignmentsViewWindow_Open(ver and ver.text or "", doc.name)
    end)

    -- [Sim]
    local btnSim = W.MakeButton(bar, "Sim", 44, 24)
    btnSim:SetPoint("LEFT", btnView, "RIGHT", 4, 0)
    btnSim:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not doc then return end
        local ver = S.GetLatestVersion(sess.raidId, doc.id)
        if not ver then return end
        local sections = P.Parse(ver.text)
        local values   = {}
        for var in pairs(doc.lastValues or {}) do
            values[var] = S.GetLastValue(sess.raidId, doc.id, var)
        end
        local msgs = T.BuildMessages(sections, values)
        local personalVars = {}
        for _, sec in ipairs(sections) do
            if sec.kind == "PERSONAL" then
                for _, ln in ipairs(sec.lines) do
                    local target = ln:match("^%s*(.-)%s*:")
                    if target then
                        local v = target:match("{{(%w+)}}")
                        if v then personalVars[#personalVars + 1] = v end
                    end
                end
            end
        end
        local invalid = D.ValidateRoster(values, personalVars)
        if #invalid > 0 then
            print("|cffff0000PugRaid:|r Invalid roster assignments:")
            for _, pair in ipairs(invalid) do
                print("  {{" .. pair.var .. "}} = " .. pair.value)
            end
            return
        end
        D.Simulate(msgs)
    end)

    -- [Send]  Shift+click opens the assign window instead.
    local btnSend = W.MakeButton(bar, "Send", 50, 24)
    btnSend:SetPoint("LEFT", btnSim, "RIGHT", 4, 0)
    btnSend:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not doc then return end
        local ver = S.GetLatestVersion(sess.raidId, doc.id)
        if not ver then return end
        local sections = P.Parse(ver.text)
        local values   = {}
        for k in pairs(doc.lastValues or {}) do
            values[k] = S.GetLastValue(sess.raidId, doc.id, k)
        end

        if IsShiftKeyDown() then
            PugRaidAssignmentsAssignWindow_Open(sess.raidId, doc.id, sections, "SESSION")
            return
        end

        local personalVars = {}
        for _, sec in ipairs(sections) do
            if sec.kind == "PERSONAL" then
                for _, ln in ipairs(sec.lines) do
                    local target = ln:match("^%s*(.-)%s*:")
                    if target then
                        local v = target:match("{{(%w+)}}")
                        if v then personalVars[#personalVars + 1] = v end
                    end
                end
            end
        end
        local invalid = D.ValidateRoster(values, personalVars)
        if #invalid > 0 then
            print("|cffff0000PugRaid:|r Invalid roster assignments:")
            for _, pair in ipairs(invalid) do
                print("  {{" .. pair.var .. "}} = " .. pair.value)
            end
            return
        end

        local toSend = {}
        for _, sec in ipairs(sections) do
            if sec.kind ~= "LONG" and sec.kind ~= "TARGETS" then
                toSend[#toSend + 1] = sec
            end
        end
        local msgs = T.BuildMessages(toSend, values)
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

    -- [Target]  Left-click = open checklist / mark current target (stays open).
    --           Shift+click = nameplate auto-scan.
    local btnTarget = W.MakeButton(bar, "Target", 56, 24)
    btnTarget:SetPoint("LEFT", btnSend, "RIGHT", 4, 0)
    btnTarget:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            ExecuteAutoTarget()
        else
            ExecuteManualTarget()
        end
    end)

    -- [Close]  Hides bar and checklist without ending the session.
    local btnClose = W.MakeButton(bar, "Close", 52, 24)
    btnClose:SetPoint("LEFT", btnTarget, "RIGHT", 4, 0)
    btnClose:SetScript("OnClick", function()
        PugRaidPlayerBar_Close()
    end)

    -- [End]  Ends the active session and hides the bar.
    local btnEnd = W.MakeButton(bar, "End", 44, 24)
    btnEnd:SetPoint("LEFT", btnClose, "RIGHT", 4, 0)
    btnEnd:SetScript("OnClick", function()
        local sess = S.GetActiveSession()
        if sess then
            S.EndSession(sess)
            print("|cffffff00PugRaid:|r Session ended.")
        end
        bar:Hide()
        ShowChecklist(false)
    end)

    -- Checklist panel (anchored below the bar)
    checklistPanel = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    checklistPanel:SetPoint("TOPLEFT",  bar, "BOTTOMLEFT",  0, 0)
    checklistPanel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    checklistPanel:SetHeight(60)
    checklistPanel:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    checklistPanel:SetBackdropColor(0, 0, 0, 0.80)
    checklistPanel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    checklistPanel:Hide()

    -- [Reset] clears target progress for the current doc.
    local btnReset = W.MakeButton(checklistPanel, "Reset", 60, 20)
    btnReset:SetPoint("BOTTOMRIGHT", checklistPanel, "BOTTOMRIGHT", -68, 4)
    btnReset:SetScript("OnClick", function()
        local sess, raid = GetActiveSessionAndRaid()
        local doc = GetCurrentDoc(sess, raid)
        if not sess or not doc then return end
        S.ResetTargetProgress(sess, doc.id)
        RebuildChecklist(sess, doc)
    end)

    -- [Close] on the checklist panel itself — hides just the checklist.
    local btnChecklistClose = W.MakeButton(checklistPanel, "Close", 60, 20)
    btnChecklistClose:SetPoint("BOTTOMRIGHT", checklistPanel, "BOTTOMRIGHT", -4, 4)
    btnChecklistClose:SetScript("OnClick", function()
        ShowChecklist(false)
    end)
end

-- ── Public API ───────────────────────────────────────────────────────────────

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

function PugRaidPlayerBar_KeybindTarget()
    ExecuteManualTarget()
end

function PugRaidPlayerBar_KeybindAutoTarget()
    ExecuteAutoTarget()
end
