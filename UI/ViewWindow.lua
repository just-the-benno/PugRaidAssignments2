-- UI/ViewWindow.lua
-- Read-only viewer for a document version's text.

local W = PugRaidAssignmentsWidgets
local S = PugRaidAssignmentsStorage

local frame
local textDisplay

local function Build()
    frame = W.MakeWindow("PugRaidViewWindow", "View Document", 520, 500)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)

    local _, bgFrame = W.MakeEditBox(frame, 480, 420, true)
    bgFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -40)

    -- Get the inner editBox from bgFrame's children
    textDisplay = nil
    for _, child in ipairs({ bgFrame:GetChildren() }) do
        if child:GetObjectType() == "ScrollFrame" then
            textDisplay = child:GetScrollChild()
            break
        end
    end

    if textDisplay then
        textDisplay:SetEnabled(false)
    end

    local closeBtn = W.MakeButton(frame, "Close", 80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
end

function PugRaidAssignmentsViewWindow_Open(versionText, docName)
    if not frame then Build() end
    if frame.TitleText then
        frame.TitleText:SetText("View: " .. (docName or "Document"))
    end
    if textDisplay then
        textDisplay:SetText(versionText or "")
    end
    frame:Show()
    frame:Raise()
end
