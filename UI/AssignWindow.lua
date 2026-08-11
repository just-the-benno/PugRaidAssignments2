-- UI/AssignWindow.lua
-- Variable assignment form: shows {{var}} rows, Send/Simulate/SaveDraft buttons.
-- mode: "AUTHOR" (no roster validation on Simulate) or "SESSION" (roster validation on Simulate)

local W  = PugRaidAssignmentsWidgets
local S  = PugRaidAssignmentsStorage
local P  = PugRaidAssignmentsParser
local T  = PugRaidAssignmentsTemplate
local D  = PugRaidAssignmentsDispatcher
local R  = PugRaidAssignmentsRoster

local frame
local varRows       = {}  -- { label, editBox, bgFrame, varName, skipCheck, pickBtn }
local sectionChecks = {}  -- { kind -> checkbox }
local sectionsData  = {}
local currentRaidId, currentDocId, currentMode

local ROW_H = 26
local LABEL_W = 180

local function ClearVarRows()
    for _, row in ipairs(varRows) do
        row.label:Hide()
        row.bgFrame:Hide()
        if row.pickBtn  then row.pickBtn:Hide()  end
        if row.skipCheck then row.skipCheck:Hide() end
    end
    varRows = {}
end

local function CollectValues()
    local values = {}
    for _, row in ipairs(varRows) do
        values[row.varName] = row.editBox:GetText()
    end
    return values
end

local function CollectSkippedVars()
    local skipped = {}
    for _, row in ipairs(varRows) do
        if row.skipCheck and row.skipCheck:GetChecked() then
            skipped[row.varName] = true
        end
    end
    return skipped
end

local function PersistValues(values)
    for var, val in pairs(values) do
        S.SetLastValue(currentRaidId, currentDocId, var, val)
    end
end

local function GetPersonalVarNames()
    local names = {}
    for _, sec in ipairs(sectionsData) do
        if sec.kind == "PERSONAL" then
            for _, ln in ipairs(sec.lines) do
                local target = ln:match("^%s*(.-)%s*:")
                if target then
                    local var = target:match("{{(%w+)}}")
                    if var then names[#names + 1] = var end
                end
            end
        end
    end
    return names
end

local function BuildFilteredSections()
    local filtered = {}
    for _, sec in ipairs(sectionsData) do
        local cb = sectionChecks[sec.kind]
        if not cb or cb:GetChecked() then
            filtered[#filtered + 1] = sec
        end
    end
    return filtered
end

local function ValidateOrWarn(values, skippedVars)
    local personalVars = GetPersonalVarNames()
    local invalid = D.ValidateRoster(values, personalVars, skippedVars)
    if #invalid > 0 then
        print("|cffff0000PugRaid:|r Invalid roster assignments:")
        for _, pair in ipairs(invalid) do
            print("  {{" .. pair.var .. "}} = " .. pair.value)
        end
        return false
    end
    return true
end

local function Rebuild(raidId, docId, sections, mode, highlightVars)
    currentRaidId = raidId
    currentDocId  = docId
    currentMode   = mode or "AUTHOR"
    sectionsData  = sections

    -- In SESSION mode, retrieve the persisted skip state for this doc.
    local sess = (currentMode == "SESSION") and S.GetActiveSession() or nil

    -- Section checkboxes
    for _, cb in pairs(sectionChecks) do cb:Hide() end
    sectionChecks = {}
    local cbX, cbY = 10, -40
    local kindSeen = {}
    for _, sec in ipairs(sections) do
        if not kindSeen[sec.kind] and sec.kind ~= "TARGETS" then
            kindSeen[sec.kind] = true
            local cb = W.MakeCheckbox(frame, sec.kind)
            cb:SetChecked(sec.kind ~= "LONG") -- default: all except LONG
            cb:SetPoint("TOPLEFT", frame, "TOPLEFT", cbX, cbY)
            sectionChecks[sec.kind] = cb
            cbX = cbX + 120
        end
    end

    -- Variable rows
    ClearVarRows()
    local allVars = P.GetVariables(table.concat((function()
        local lines = {}
        for _, sec in ipairs(sections) do
            for _, ln in ipairs(sec.lines) do lines[#lines + 1] = ln end
        end
        return lines
    end)(), "\n"))

    -- Normalize highlightVars to a set for O(1) lookup.
    local highlightSet = {}
    if highlightVars then
        for _, v in ipairs(highlightVars) do highlightSet[v] = true end
    end

    local startY = -80
    for i, var in ipairs(allVars) do
        local y = startY - (i - 1) * ROW_H
        -- Reuse or create label
        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetText("{{" .. var .. "}}")
        lbl:SetWidth(LABEL_W)
        lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)

        local eb, bg = W.MakeEditBox(frame, 190, 22, false)
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", LABEL_W + 16, y + 1)

        -- Highlight rows for variables that just failed validation.
        if highlightSet[var] then
            bg:SetBackdropBorderColor(1, 0.2, 0.2, 1)
            bg:SetBackdropColor(0.4, 0.05, 0.05, 0.9)
        end

        -- Prefill from lastValues
        local lastVal = S.GetLastValue(raidId, docId, var)
        if lastVal then eb:SetText(lastVal) end

        -- Roster-select dropdown button
        local btnPick = W.MakeButton(frame, "Select...", 70, 22)
        btnPick:SetPoint("LEFT", bg, "RIGHT", 6, 0)
        local capturedEb = eb
        btnPick:SetScript("OnClick", function(self)
            local members = R.GetMembers()
            local items = {}
            for _, name in ipairs(members) do
                items[#items + 1] = { text = name, value = name }
            end
            W.OpenDropdown(self, items, function(value)
                capturedEb:SetText(value)
            end)
        end)

        -- Skip checkbox: in SESSION mode, initialize from persisted state and
        -- persist any change immediately.  In AUTHOR mode, ephemeral/local only.
        local skipCb = W.MakeCheckbox(frame, "Skip")
        skipCb:SetPoint("LEFT", btnPick, "RIGHT", 6, 0)

        if sess then
            -- SESSION mode: load initial state from session.
            local skipped = S.GetSkippedVars(sess, docId)
            skipCb:SetChecked(skipped[var] == true)
            local capturedVar = var
            skipCb:SetScript("OnClick", function(self)
                S.SetVarSkipped(sess, docId, capturedVar, self:GetChecked())
            end)
        end

        varRows[#varRows + 1] = { label = lbl, editBox = eb, bgFrame = bg, varName = var, pickBtn = btnPick, skipCheck = skipCb }
    end

    local totalH = math.max(200, 100 + #allVars * ROW_H + 40)
    frame:SetHeight(totalH)
end

local function Build()
    frame = W.MakeWindow("PugRaidAssignWindow", "Assign", 500, 300)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)

    -- Bottom buttons
    local btnSend = W.MakeButton(frame, "Send", 70, 22)
    btnSend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    btnSend:SetScript("OnClick", function()
        local values     = CollectValues()
        local skipped    = CollectSkippedVars()
        if not ValidateOrWarn(values, skipped) then return end
        local filtered   = BuildFilteredSections()
        local messages   = T.BuildMessages(filtered, values, skipped)
        PersistValues(values)

        if P.HasBlocks(filtered) then
            -- Presenter mode: build block queue and open the Presenter Bar.
            local queue = D.BuildPresenterQueue(messages)
            PugRaidPresenterBar_Open(queue)
        else
            D.SendAll(messages)
            print("|cff00ff00PugRaid:|r Sent.")
        end
    end)

    local btnSim = W.MakeButton(frame, "Simulate", 80, 22)
    btnSim:SetPoint("LEFT", btnSend, "RIGHT", 6, 0)
    btnSim:SetScript("OnClick", function()
        local values  = CollectValues()
        local skipped = CollectSkippedVars()
        if currentMode == "SESSION" then
            if not ValidateOrWarn(values, skipped) then return end
        end
        local filtered = BuildFilteredSections()
        local messages = T.BuildMessages(filtered, values, skipped)
        D.Simulate(messages)
    end)

    local btnDraft = W.MakeButton(frame, "Save Draft", 90, 22)
    btnDraft:SetPoint("LEFT", btnSim, "RIGHT", 6, 0)
    btnDraft:SetScript("OnClick", function()
        local values = CollectValues()
        PersistValues(values)
        print("|cffffff00PugRaid:|r Draft saved.")
    end)

    local btnClose = W.MakeButton(frame, "Close", 70, 22)
    btnClose:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    btnClose:SetScript("OnClick", function() frame:Hide() end)
end

-- Open the Assign window.
-- mode: "AUTHOR" or "SESSION"
-- highlightVars: optional list of variable names to visually highlight (e.g. failed validation)
function PugRaidAssignmentsAssignWindow_Open(raidId, docId, sections, mode, highlightVars)
    if not frame then Build() end
    Rebuild(raidId, docId, sections, mode, highlightVars)
    frame:Show()
    frame:Raise()
end
