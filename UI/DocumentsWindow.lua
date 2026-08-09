-- UI/DocumentsWindow.lua
-- Card-based document list for a single raid.

local W = PugRaidAssignmentsWidgets
local S = PugRaidAssignmentsStorage
local P = PugRaidAssignmentsParser

local frame
local contentFrame
local currentRaidId

local CARD_W = 400
local CARD_H = 90
local CARD_PAD = 8

local function DateStr(ts)
    if not ts then return "?" end
    return date("%Y-%m-%d", ts)
end

local _docCards = {}

local function ClearCards()
    for _, card in ipairs(_docCards) do
        card:Hide()
        card:SetParent(nil)
    end
    _docCards = {}
end

local function RebuildCards()
    ClearCards()
    if not currentRaidId then return end

    local docs = S.GetDocumentsSorted(currentRaidId)
    local raid  = S.GetRaid(currentRaidId)

    local y = 0
    for i, doc in ipairs(docs) do
        local card = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
        card:SetSize(CARD_W, CARD_H)
        card:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -y)
        card:SetBackdrop({
            bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left=2, right=2, top=2, bottom=2 },
        })
        card:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        card:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        _docCards[#_docCards + 1] = card

        -- Name
        local nameLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        nameLabel:SetText(doc.name or "Untitled")

        -- Version info
        local versions = S.GetVersionsSorted(currentRaidId, doc.id)
        local verInfo  = "No versions"
        if #versions > 0 then
            local latest = versions[#versions]
            verInfo = "v" .. #versions .. " — " .. DateStr(latest.timestamp)
        end
        local verLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        verLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -26)
        verLabel:SetText(verInfo)

        -- Up / Down reorder buttons (left of card)
        local btnUp = W.MakeButton(contentFrame, "▲", 24, 22)
        btnUp:SetPoint("RIGHT", card, "LEFT", -4, 10)
        btnUp:SetEnabled(i > 1)
        local capturedDoc = doc
        local capturedI   = i
        btnUp:SetScript("OnClick", function()
            local sortedDocs = S.GetDocumentsSorted(currentRaidId)
            if capturedI > 1 then
                S.SwapDocumentOrder(currentRaidId, capturedDoc.id, sortedDocs[capturedI - 1].id)
                RebuildCards()
            end
        end)
        _docCards[#_docCards + 1] = btnUp

        local btnDown = W.MakeButton(contentFrame, "▼", 24, 22)
        btnDown:SetPoint("RIGHT", card, "LEFT", -4, -10)
        btnDown:SetEnabled(i < #docs)
        btnDown:SetScript("OnClick", function()
            local sortedDocs = S.GetDocumentsSorted(currentRaidId)
            if capturedI < #sortedDocs then
                S.SwapDocumentOrder(currentRaidId, capturedDoc.id, sortedDocs[capturedI + 1].id)
                RebuildCards()
            end
        end)
        _docCards[#_docCards + 1] = btnDown

        -- Action buttons
        local btnView = W.MakeButton(card, "View", 50, 22)
        btnView:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 8)
        btnView:SetScript("OnClick", function()
            local ver = S.GetLatestVersion(currentRaidId, capturedDoc.id)
            PugRaidAssignmentsViewWindow_Open(ver and ver.text or "", capturedDoc.name)
        end)
        _docCards[#_docCards + 1] = btnView

        local btnEdit = W.MakeButton(card, "Edit", 50, 22)
        btnEdit:SetPoint("LEFT", btnView, "RIGHT", 4, 0)
        btnEdit:SetScript("OnClick", function()
            PugRaidAssignmentsDocumentsWindow_OpenEdit(currentRaidId, capturedDoc.id)
        end)
        _docCards[#_docCards + 1] = btnEdit

        local btnAssign = W.MakeButton(card, "Assign", 60, 22)
        btnAssign:SetPoint("LEFT", btnEdit, "RIGHT", 4, 0)
        btnAssign:SetScript("OnClick", function()
            local ver = S.GetLatestVersion(currentRaidId, capturedDoc.id)
            if not ver then return end
            local sections = P.Parse(ver.text)
            PugRaidAssignmentsAssignWindow_Open(currentRaidId, capturedDoc.id, sections, "AUTHOR")
        end)
        _docCards[#_docCards + 1] = btnAssign

        local btnDel = W.MakeButton(card, "Delete", 60, 22)
        btnDel:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 8)
        btnDel:SetScript("OnClick", function()
            StaticPopup_Show("PUGRAID_CONFIRM_DELETE_DOC", capturedDoc.name, nil, { raidId = currentRaidId, docId = capturedDoc.id })
        end)
        _docCards[#_docCards + 1] = btnDel

        y = y + CARD_H + CARD_PAD
    end

    contentFrame:SetHeight(math.max(1, y))
end

-- ── Edit / New document form ──────────────────────────────────────────────────
local editFrame, editNameEB, editNameBg, editTextEB, editTextBg
local editRaidId, editDocId  -- nil docId = new document

local function CloseEditFrame()
    if editFrame then editFrame:Hide() end
end

local function OpenEditFrame(raidId, docId)
    editRaidId = raidId
    editDocId  = docId

    if not editFrame then
        editFrame = W.MakeWindow("PugRaidDocEditFrame", "Document", 460, 420)
        editFrame:SetFrameStrata("HIGH")
        editFrame:SetToplevel(true)

        local lblName = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblName:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 14, -44)
        lblName:SetText("Name:")

        editNameEB, editNameBg = W.MakeEditBox(editFrame, 280, 22, false)
        editNameBg:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 60, -42)

        local lblText = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lblText:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 14, -72)
        lblText:SetText("Text:")

        editTextEB, editTextBg = W.MakeEditBox(editFrame, 430, 280, true)
        editTextBg:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 14, -90)

        local btnSave = W.MakeButton(editFrame, "Save", 80, 22)
        btnSave:SetPoint("BOTTOMLEFT", editFrame, "BOTTOMLEFT", 14, 10)
        btnSave:SetScript("OnClick", function()
            local name = editNameEB:GetText()
            local text = editTextEB:GetText()
            if name == "" then
                print("|cffff0000PugRaid:|r Document name is required.")
                return
            end
            if editDocId then
                -- Save as new version
                S.AddVersion(editRaidId, editDocId, text)
            else
                -- Create new document
                S.CreateDocument(editRaidId, name, text)
            end
            CloseEditFrame()
            RebuildCards()
        end)

        local btnCancel = W.MakeButton(editFrame, "Cancel", 80, 22)
        btnCancel:SetPoint("LEFT", btnSave, "RIGHT", 8, 0)
        btnCancel:SetScript("OnClick", CloseEditFrame)
    end

    -- Pre-fill
    if docId then
        local doc = S.GetDocument(raidId, docId)
        editNameEB:SetText(doc and doc.name or "")
        editNameEB:SetEnabled(false)
        local ver = S.GetLatestVersion(raidId, docId)
        editTextEB:SetText(ver and ver.text or "")
        if editFrame.TitleText then editFrame.TitleText:SetText("Edit Document") end
    else
        editNameEB:SetText("")
        editNameEB:SetEnabled(true)
        editTextEB:SetText("")
        if editFrame.TitleText then editFrame.TitleText:SetText("New Document") end
    end
    editFrame:Show()
    editFrame:Raise()
end

-- ── Static Popups ─────────────────────────────────────────────────────────────
StaticPopupDialogs["PUGRAID_CONFIRM_DELETE_DOC"] = {
    text           = "Delete document \"%s\"? This removes all its versions.",
    button1        = "Delete",
    button2        = "Cancel",
    OnAccept       = function(self, data)
        S.DeleteDocument(data.raidId, data.docId)
        RebuildCards()
    end,
    timeout        = 0,
    whileDead      = true,
    hideOnEscape   = true,
    preferredIndex = 3,
}

-- ── Main window ───────────────────────────────────────────────────────────────
local function Build()
    frame = W.MakeWindow("PugRaidDocumentsWindow", "Documents", 500, 500)

    local btnNew = W.MakeButton(frame, "+ New Document", 130, 24)
    btnNew:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -36)
    btnNew:SetScript("OnClick", function()
        OpenEditFrame(currentRaidId, nil)
    end)

    local sf, cf = W.MakeScrollPane(frame, 460, 400)
    sf:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -68)
    contentFrame = cf
end

function PugRaidAssignmentsDocumentsWindow_Open(raidId)
    if not frame then Build() end
    currentRaidId = raidId
    local raid = S.GetRaid(raidId)
    if frame.TitleText then
        frame.TitleText:SetText("Documents — " .. (raid and raid.name or "?"))
    end
    RebuildCards()
    frame:Show()
    frame:Raise()
end

function PugRaidAssignmentsDocumentsWindow_OpenEdit(raidId, docId)
    OpenEditFrame(raidId, docId)
end
