-- CombatLogProbe.lua
-- TEMPORARY: Data-gathering probe for evaluating the combat log / auto-mark
-- approach for gauntlet waves (e.g. Mount Hyjal).
--
-- Opens a window on load with a scrollable, selectable text area.
-- All combat log output is appended there so you can select-all and copy it.
--
-- HOW TO USE:
--   1. Load the addon. The probe window opens automatically.
--   2. Trigger a Hyjal wave.
--   3. Click inside the output box, Ctrl-A to select all, Ctrl-C to copy.
--   4. Paste the result back into the chat with the developer.
--
-- DISABLING: remove CombatLogProbe.lua from the .toc (or comment it out).
--
-- This file is intentionally NOT wired into any permanent addon state.
-- Delete / abandon this branch once data is gathered.

-- ── Window ────────────────────────────────────────────────────────────────────

local WIN_W, WIN_H = 720, 400
local PAD = 8

local win = CreateFrame("Frame", "PugRaidProbeWindow", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(WIN_W, WIN_H)
win:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop",  win.StopMovingOrSizing)
win:SetFrameStrata("HIGH")
win:SetToplevel(true)
if win.TitleText then win.TitleText:SetText("PugRaid Combat Log Probe") end

-- Clear button
local btnClear = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
btnClear:SetSize(70, 22)
btnClear:SetText("Clear")
btnClear:SetPoint("TOPRIGHT", win, "TOPRIGHT", -28, -28)

-- Scrollable output area — built manually so the EditBox is fully selectable
local scrollBg = CreateFrame("Frame", nil, win, "BackdropTemplate")
scrollBg:SetPoint("TOPLEFT",     win, "TOPLEFT",     PAD, -50)
scrollBg:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, PAD + 4)
scrollBg:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left=2, right=2, top=2, bottom=2 },
})
scrollBg:SetBackdropColor(0, 0, 0, 0.85)
scrollBg:SetBackdropBorderColor(0.4, 0.6, 1.0, 1)

local sf = CreateFrame("ScrollFrame", nil, scrollBg, "UIPanelScrollFrameTemplate")
sf:SetPoint("TOPLEFT",     scrollBg, "TOPLEFT",     4, -4)
sf:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -22, 4)

local eb = CreateFrame("EditBox", "PugRaidProbeEditBox", sf)
eb:SetMultiLine(true)
eb:SetAutoFocus(false)
eb:EnableMouse(true)
eb:SetFontObject(ChatFontNormal)
eb:SetWidth(sf:GetWidth() or (WIN_W - PAD * 2 - 26))
eb:SetHeight(1)   -- grows with content
eb:SetScript("OnEscapePressed", eb.ClearFocus)
sf:SetScrollChild(eb)

btnClear:SetScript("OnClick", function()
    eb:SetText("")
end)

-- ── Append helper ─────────────────────────────────────────────────────────────

local lineCount = 0
local MAX_LINES = 500   -- safety cap so the box doesn't grow forever

local function AppendLine(line)
    if lineCount >= MAX_LINES then return end
    lineCount = lineCount + 1
    local current = eb:GetText()
    if current == "" then
        eb:SetText(line)
    else
        eb:SetText(current .. "\n" .. line)
    end
    -- Scroll to bottom
    sf:SetVerticalScroll(sf:GetVerticalScrollRange())
end

-- ── Combat log listener ───────────────────────────────────────────────────────

-- Throttle: only record a given destGUID once per event subtype to avoid
-- flooding the box when the same mob generates dozens of SWING_DAMAGE lines.
local seen = {}  -- [subevent.."::"..destGUID] = true

local probeFrame = CreateFrame("Frame", "PugRaidCombatLogProbeFrame")
probeFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

probeFrame:SetScript("OnEvent", function(self, event)
    local timestamp, subevent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID,   destName,   destFlags,   destRaidFlags
        = CombatLogGetCurrentEventInfo()

    -- Only care about hostile NPCs as destination
    if not destFlags then return end
    local isHostileNPC = bit.band(destFlags, COMBATLOG_OBJECT_TYPE_NPC) ~= 0
                      and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
    if not isHostileNPC then return end

    -- Throttle duplicate (subevent, GUID) pairs
    local key = subevent .. "::" .. (destGUID or "nil")
    if seen[key] then return end
    seen[key] = true

    -- ── 1. Raw combat log fields ─────────────────────────────────────────────
    AppendLine(string.format("sub=%-28s  dName=%-24s  dGUID=%s",
        subevent, tostring(destName), tostring(destGUID)))

    -- ── 2. Current target match ──────────────────────────────────────────────
    local targetGUID = UnitGUID("target")
    local targetName = UnitName("target")
    if targetGUID == destGUID then
        AppendLine(string.format("  >> MATCH target: name=%s  guid=%s",
            tostring(targetName), tostring(targetGUID)))
    end

    -- ── 3. Nameplate scan ────────────────────────────────────────────────────
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local npGUID = UnitGUID(unit)
            if npGUID == destGUID then
                AppendLine(string.format("  >> MATCH nameplate%d: name=%s  guid=%s",
                    i, tostring(UnitName(unit)), tostring(npGUID)))
            end
        end
    end
end)

-- ── Show window on load ───────────────────────────────────────────────────────

AppendLine("=== PugRaid Combat Log Probe ready ===")
AppendLine("Trigger a Hyjal wave, then Ctrl-A / Ctrl-C this box to copy output.")
AppendLine("----------------------------------------------------------------------")
win:Show()
