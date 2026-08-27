-- UI/RaidAssignWindow.lua
-- Raid-wide variable assignment form: collects {{var}} rows from all documents
-- in a raid, shows Send/Simulate/SaveDraft buttons. Mirrors UI/AssignWindow.lua.

local W  = PugRaidAssignmentsWidgets
local S  = PugRaidAssignmentsStorage
local P  = PugRaidAssignmentsParser
local T  = PugRaidAssignmentsTemplate
local D  = PugRaidAssignmentsDispatcher
local R  = PugRaidAssignmentsRoster

local frame
local varRows       = {}  -- { label, editBox, bgFrame, varName, skipCheck, pickBtn }
local sectionChecks = {}  -- { kind -> checkbox }
local docsData      = {}  -- { { docId = docId, sections = sections }, ... }
local currentRaidId

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
        for _, doc in ipairs(docsData) do
            if doc.vars[var] then
                S.SetLastValue(currentRaidId, doc.docId, var, val)
            end
        end
    end
end

local function GetPersonalVarNames()
    local names = {}
    local seen = {}
    for _, doc in ipairs(docsData) do
        for _, sec in ipairs(doc.sections) do
            if sec.kind == "PERSONAL" then
                for _, ln in ipairs(sec.lines) do
                    local target = ln:match("^%s*(.-)%s*:")
                    if target then
                        local var = target:match("{{(%w+)}}")
                        if var and not seen[var] then
                            seen[var] = true
                            names[#names + 1] = var
                        end
                    end
                end
            end
        end
    end
    return names
end

local function BuildFilteredSections(sections)
    local filtered = {}
    for _, sec in ipairs(sections) do
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

local function Rebuild(raidId)
    currentRaidId = raidId

    -- Collect all documents, their parsed sections, and unique variables/kinds.
    docsData = {}
    local allVars = {}
    local seenVars = {}
    local kindOrder = {}
    local kindSeen = {}

    local docs = S.GetDocumentsSorted(raidId)
    for _, doc in ipairs(docs) do
        local ver = S.GetLatestVersion(raidId, doc.id)
        if ver then
            local sections = P.Parse(ver.text)
            local lines = {}
            for _, sec in ipairs(sections) do
                if sec.kind ~= "TARGETS" and not kindSeen[sec.kind] then
                    kindSeen[sec.kind] = true
                    kindOrder[#kindOrder + 1] = sec.kind
                end
                for _, ln in ipairs(sec.lines) do lines[#lines + 1] = ln end
            end

            local docVarList = P.GetVariables(table.concat(lines, "\n"))
            local docVars = {}
            for _, var in ipairs(docVarList) do
                docVars[var] = true
                if not seenVars[var] then
                    seenVars[var] = true
                    allVars[#allVars + 1] = var
                end
            end

            docsData[#docsData + 1] = { docId = doc.id, sections = sections, vars = docVars }
        end
    end

    -- Section checkboxes
    for _, cb in pairs(sectionChecks) do cb:Hide() end
    sectionChecks = {}
    local cbX, cbY = 10, -40
    for _, kind in ipairs(kindOrder) do
        local cb = W.MakeCheckbox(frame, kind)
        cb:SetChecked(kind ~= "LONG") -- default: all except LONG
        cb:SetPoint("TOPLEFT", frame, "TOPLEFT", cbX, cbY)
        sectionChecks[kind] = cb
        cbX = cbX + 120
    end

    -- Variable rows
    ClearVarRows()

    local startY = -80
    for i, var in ipairs(allVars) do
        local y = startY - (i - 1) * ROW_H
        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetText("{{" .. var .. "}}")
        lbl:SetWidth(LABEL_W)
        lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)

        local eb, bg = W.MakeEditBox(frame, 190, 22, false)
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", LABEL_W + 16, y + 1)

        -- Prefill from lastValues: first non-nil value across all documents.
        local lastVal
        for _, doc in ipairs(docsData) do
            local v = S.GetLastValue(raidId, doc.docId, var)
            if v then
                lastVal = v
                break
            end
        end
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

        -- Skip checkbox — always visible, unchecked by default.
        local skipCb = W.MakeCheckbox(frame, "Skip")
        skipCb:SetPoint("LEFT", btnPick, "RIGHT", 6, 0)

        varRows[#varRows + 1] = { label = lbl, editBox = eb, bgFrame = bg, varName = var, pickBtn = btnPick, skipCheck = skipCb }
    end

    local totalH = math.max(200, 100 + #allVars * ROW_H + 40)
    frame:SetHeight(totalH)
end

local function Build()
    frame = W.MakeWindow("PugRaidRaidAssignWindow", "Assign All", 500, 300)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)

    -- Bottom buttons
    local btnSend = W.MakeButton(frame, "Send", 70, 22)
    btnSend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    btnSend:SetScript("OnClick", function()
        local values  = CollectValues()
        local skipped = CollectSkippedVars()
        if not ValidateOrWarn(values, skipped) then return end
        PersistValues(values)

        local presenterQueue = {}
        for _, doc in ipairs(docsData) do
            local filtered = BuildFilteredSections(doc.sections)
            local messages = T.BuildMessages(filtered, values, skipped)

            if P.HasBlocks(filtered) then
                -- Presenter mode: accumulate block queues across documents.
                local queue = D.BuildPresenterQueue(messages)
                for _, item in ipairs(queue) do
                    presenterQueue[#presenterQueue + 1] = item
                end
            else
                D.SendAll(messages)
            end
        end
        if #presenterQueue > 0 then
            PugRaidPresenterBar_Open(presenterQueue)
        end
        print("|cff00ff00PugRaid:|r Sent.")
    end)

    local btnSim = W.MakeButton(frame, "Simulate", 80, 22)
    btnSim:SetPoint("LEFT", btnSend, "RIGHT", 6, 0)
    btnSim:SetScript("OnClick", function()
        local values  = CollectValues()
        local skipped = CollectSkippedVars()

        for _, doc in ipairs(docsData) do
            local filtered = BuildFilteredSections(doc.sections)
            local messages = T.BuildMessages(filtered, values, skipped)
            D.Simulate(messages)
        end
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

-- Open the Raid Assign window for the given raid.
function PugRaidAssignmentsRaidAssignWindow_Open(raidId)
    if not frame then Build() end
    Rebuild(raidId)
    frame:Show()
    frame:Raise()
end
