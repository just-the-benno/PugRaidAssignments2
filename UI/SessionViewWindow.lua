-- UI/SessionViewWindow.lua
-- Read-only session viewer showing start/end timestamps.

local W = PugRaidAssignmentsWidgets
local S = PugRaidAssignmentsStorage

local frame
local lblTitle, lblStart, lblEnd

local function Build()
    frame = W.MakeWindow("PugRaidSessionViewWindow", "Session Info", 360, 180)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)

    lblTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lblTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -44)
    lblTitle:SetWidth(330)

    lblStart = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblStart:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -70)

    lblEnd = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblEnd:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -90)

    local closeBtn = W.MakeButton(frame, "Close", 80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
end

local function FormatTime(t)
    if not t then return nil end
    return date("%Y-%m-%d %H:%M", t)
end

function PugRaidAssignmentsSessionViewWindow_Open(raid, session)
    if not frame then Build() end

    if session then
        lblTitle:SetText((raid and raid.name or "?") .. " — Session")
        lblStart:SetText("Started:  " .. (FormatTime(session.startedAt) or "unknown"))

        local endTime = session.endedAt or session.lastSeenAt
        local endLabel
        if session.endedAt then
            endLabel = "Ended:    " .. FormatTime(session.endedAt)
        elseif session.lastSeenAt then
            endLabel = "Last seen: " .. FormatTime(session.lastSeenAt) .. " (not explicitly ended)"
        else
            endLabel = "Ended:    still active / unknown"
        end
        lblEnd:SetText(endLabel)
    else
        lblTitle:SetText((raid and raid.name or "?") .. " — No session recorded")
        lblStart:SetText("")
        lblEnd:SetText("")
    end

    frame:Show()
    frame:Raise()
end
