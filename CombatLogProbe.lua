-- CombatLogProbe.lua
-- TEMPORARY: Two-panel probe window for evaluating auto-mark approaches.
--
-- Panel A  (left)  — COMBAT_LOG_EVENT_UNFILTERED
--   Records every event where a hostile NPC is the destination.
--   Throttled: one line per unique (subevent + destGUID) pair.
--   Also notes whether the mob's GUID matches the current target
--   or any visible nameplate at the moment the event fires.
--
-- Panel B  (right) — CHAT_MSG_MONSTER_YELL / CHAT_MSG_MONSTER_EMOTE / CHAT_MSG_RAID_BOSS_EMOTE
--   Records every monster yell and emote with a timestamp.
--   This is how DBM/BigWigs detect wave starts in Mount Hyjal.
--   We want to see the exact yell text and timing relative to
--   the first mob appearing in Panel A.
--
-- HOW TO USE:
--   1. /reload — both panels open automatically.
--   2. Trigger a Hyjal wave.
--   3. Click inside either box, Ctrl-A, Ctrl-C, paste back here.
--   4. Use the individual Clear buttons or "Clear All" to reset.
--
-- DISABLING: comment out CombatLogProbe.lua in the .toc.

-- ── Layout constants ──────────────────────────────────────────────────────────

local WIN_W     = 1100
local WIN_H     = 440
local PAD       = 8
local BTN_H     = 22
local HDR_H     = 54
local PANEL_GAP = 6

-- ── Main window ───────────────────────────────────────────────────────────────

local win = CreateFrame("Frame", "PugRaidProbeWindow", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(WIN_W, WIN_H)
win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop",  win.StopMovingOrSizing)
win:SetFrameStrata("HIGH")
win:SetToplevel(true)
if win.TitleText then
    win.TitleText:SetText("PugRaid Probe  |cffaaaaaa[A] Combat Log     [B] Monster Yells / Emotes|r")
end

local btnClearAll = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
btnClearAll:SetSize(80, BTN_H)
btnClearAll:SetText("Clear All")
btnClearAll:SetPoint("TOPRIGHT", win, "TOPRIGHT", -28, -28)

-- ── Panel factory ─────────────────────────────────────────────────────────────

local function MakePanel(label, anchorLeft, anchorRight)
    local hdr = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT",  anchorLeft,  "TOPLEFT",  0, 0)
    hdr:SetPoint("TOPRIGHT", anchorRight, "TOPRIGHT", 0, 0)
    hdr:SetJustifyH("LEFT")
    hdr:SetText(label)

    local btnClear = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    btnClear:SetSize(60, BTN_H)
    btnClear:SetText("Clear")
    btnClear:SetPoint("TOPRIGHT", anchorRight, "TOPRIGHT", 0, 0)

    local bg = CreateFrame("Frame", nil, win, "BackdropTemplate")
    bg:SetPoint("TOPLEFT",     anchorLeft,  "TOPLEFT",     0, -(BTN_H + 2))
    bg:SetPoint("BOTTOMRIGHT", anchorRight, "BOTTOMRIGHT", 0, 0)
    bg:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.85)
    bg:SetBackdropBorderColor(0.4, 0.6, 1.0, 1)

    local sf = CreateFrame("ScrollFrame", nil, bg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     bg, "TOPLEFT",     4,   -4)
    sf:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -22,  4)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:EnableMouse(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(1)
    eb:SetHeight(1)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    sf:SetScrollChild(eb)

    sf:SetScript("OnSizeChanged", function(self, w)
        eb:SetWidth(math.max(1, w))
    end)

    local lineCount = 0
    local MAX_LINES = 600

    local function AppendLine(text)
        if lineCount >= MAX_LINES then return end
        lineCount = lineCount + 1
        local cur = eb:GetText()
        eb:SetText(cur == "" and text or (cur .. "\n" .. text))
        sf:SetVerticalScroll(sf:GetVerticalScrollRange())
    end

    local function ClearPanel()
        eb:SetText("")
        lineCount = 0
    end

    btnClear:SetScript("OnClick", ClearPanel)
    return AppendLine, ClearPanel
end

-- ── Anchor frames ─────────────────────────────────────────────────────────────

local panelH = WIN_H - HDR_H - PAD
local halfW  = math.floor((WIN_W - PAD * 2 - PANEL_GAP) / 2)

local anchorAL = CreateFrame("Frame", nil, win)
anchorAL:SetSize(halfW, panelH)
anchorAL:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -HDR_H)

local anchorAR = CreateFrame("Frame", nil, win)
anchorAR:SetPoint("TOPLEFT",     anchorAL, "TOPLEFT",     0, 0)
anchorAR:SetPoint("BOTTOMRIGHT", anchorAL, "BOTTOMRIGHT", 0, 0)

local anchorBL = CreateFrame("Frame", nil, win)
anchorBL:SetSize(halfW, panelH)
anchorBL:SetPoint("TOPLEFT", anchorAL, "TOPRIGHT", PANEL_GAP, 0)

local anchorBR = CreateFrame("Frame", nil, win)
anchorBR:SetPoint("TOPLEFT",     anchorBL, "TOPLEFT",     0, 0)
anchorBR:SetPoint("BOTTOMRIGHT", anchorBL, "BOTTOMRIGHT", 0, 0)

local AppendA, ClearA = MakePanel("|cffffff00[A] COMBAT_LOG_EVENT_UNFILTERED  (hostile NPC dest, throttled)|r", anchorAL, anchorAR)
local AppendB, ClearB = MakePanel("|cff00ccff[B] Monster Yells / Emotes  (wave-start detection)|r",            anchorBL, anchorBR)

btnClearAll:SetScript("OnClick", function() ClearA() ClearB() end)

-- ── Panel A — Combat log ──────────────────────────────────────────────────────

local seenCL = {}

local clFrame = CreateFrame("Frame", "PugRaidCombatLogProbeFrame")
clFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
clFrame:SetScript("OnEvent", function(self, event)
    local timestamp, subevent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID,   destName,   destFlags,   destRaidFlags
        = CombatLogGetCurrentEventInfo()

    if not destFlags then return end
    local isHostileNPC = bit.band(destFlags, COMBATLOG_OBJECT_TYPE_NPC) ~= 0
                      and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
    if not isHostileNPC then return end

    local key = subevent .. "::" .. (destGUID or "nil")
    if seenCL[key] then return end
    seenCL[key] = true

    AppendA(string.format("sub=%-26s  dName=%-22s  dGUID=%s",
        subevent, tostring(destName), tostring(destGUID)))

    if UnitGUID("target") == destGUID then
        AppendA(string.format("  >> target match: %s", tostring(UnitName("target"))))
    end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == destGUID then
            AppendA(string.format("  >> nameplate%d match: %s", i, tostring(UnitName(unit))))
        end
    end
end)

-- ── Panel B — Monster yells / emotes ─────────────────────────────────────────
-- These are the events DBM/BigWigs use to detect wave starts.
-- CHAT_MSG_MONSTER_YELL      — boss yells (e.g. Rage Winterchill before wave 1)
-- CHAT_MSG_MONSTER_EMOTE     — boss emotes
-- CHAT_MSG_RAID_BOSS_EMOTE   — raid boss emotes (sometimes used instead)
--
-- For each event we record:
--   [time]  event-type  sender: "message text"
--
-- The wall-clock time lets us compare against Panel A to see how many
-- seconds before the first mob appears in the combat log.

local yellFrame = CreateFrame("Frame", "PugRaidYellProbeFrame")

local yellEventsOK = pcall(function()
    yellFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
    yellFrame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
    yellFrame:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
end)

if not yellEventsOK then
    AppendB("|cffff4444Failed to register monster chat events — unexpected in TBC Classic.|r")
else
    AppendB("Listening for MONSTER_YELL, MONSTER_EMOTE, RAID_BOSS_EMOTE...")
end

yellFrame:SetScript("OnEvent", function(self, event, msg, sender)
    -- arg1 = message text, arg2 = sender name
    local t     = date("%H:%M:%S")
    local etype = event:gsub("CHAT_MSG_", "")   -- shorten for display
    AppendB(string.format("[%s] %-22s  %s: \"%s\"",
        t, etype, tostring(sender), tostring(msg)))
end)

-- ── Show ──────────────────────────────────────────────────────────────────────

AppendA("=== Panel A ready — trigger a Hyjal wave ===")
AppendB("=== Panel B ready — waiting for boss yells/emotes ===")
win:Show()
