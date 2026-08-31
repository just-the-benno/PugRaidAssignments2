-- CombatLogProbe.lua
-- TEMPORARY: Two-panel probe window for evaluating auto-mark approaches.
--
-- Panel A  (left)  — COMBAT_LOG_EVENT_UNFILTERED
--   Records every event where a hostile NPC is the destination.
--   Throttled: one line per unique (subevent + destGUID) pair.
--   Also notes whether the mob's GUID already matches the current target
--   or any visible nameplate at the moment the event fires.
--
-- Panel B  (right) — NAME_PLATE_UNIT_ADDED / NAME_PLATE_UNIT_REMOVED
--   Records every nameplate appearance / disappearance.
--   Shows unit name, GUID, and whether it is a hostile NPC.
--   This lets us see whether nameplates appear *before* the combat log
--   picks up the mob (important for mobs like Shadowy Necromancers that
--   don't self-buff on spawn).
--
-- HOW TO USE:
--   1. /reload — both panels open automatically.
--   2. Trigger a Hyjal wave.
--   3. Click inside either box, Ctrl-A, Ctrl-C, paste back here.
--   4. Use the individual Clear buttons or "Clear All" to reset.
--
-- DISABLING: comment out CombatLogProbe.lua in the .toc.

-- ── Layout constants ──────────────────────────────────────────────────────────

local WIN_W  = 1100
local WIN_H  = 440
local PAD    = 8
local BTN_H  = 22
local HDR_H  = 54   -- space at top for title bar + buttons
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
if win.TitleText then win.TitleText:SetText("PugRaid Probe  |cffaaaaaa[A] Combat Log     [B] Nameplate Events|r") end

-- "Clear All" button (top-right)
local btnClearAll = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
btnClearAll:SetSize(80, BTN_H)
btnClearAll:SetText("Clear All")
btnClearAll:SetPoint("TOPRIGHT", win, "TOPRIGHT", -28, -28)

-- ── Panel factory ─────────────────────────────────────────────────────────────
-- Returns: AppendLine(text), ClearPanel()

local function MakePanel(label, anchorLeft, anchorRight, clearBtn)
    -- Header label
    local hdr = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT",  anchorLeft,  "TOPLEFT",  0,  0)
    hdr:SetPoint("TOPRIGHT", anchorRight, "TOPRIGHT", 0,  0)
    hdr:SetJustifyH("LEFT")
    hdr:SetText(label)

    -- Clear button for this panel
    local btnClear = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    btnClear:SetSize(60, BTN_H)
    btnClear:SetText("Clear")
    btnClear:SetPoint("TOPRIGHT", anchorRight, "TOPRIGHT", 0, 0)

    -- Backdrop
    local bg = CreateFrame("Frame", nil, win, "BackdropTemplate")
    bg:SetPoint("TOPLEFT",     anchorLeft,  "TOPLEFT",  0, -(BTN_H + 2))
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
    eb:SetWidth(1)   -- will be set after layout via OnSizeChanged
    eb:SetHeight(1)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    sf:SetScrollChild(eb)

    -- Keep EditBox width in sync with scroll frame
    sf:SetScript("OnSizeChanged", function(self, w, h)
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

-- ── Anchor frames for the two panels ─────────────────────────────────────────
-- We use invisible anchor frames to define the left/right columns.

local panelH = WIN_H - HDR_H - PAD
local halfW  = math.floor((WIN_W - PAD * 2 - PANEL_GAP) / 2)

local anchorAL = CreateFrame("Frame", nil, win)
anchorAL:SetSize(halfW, panelH)
anchorAL:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -HDR_H)

local anchorAR = CreateFrame("Frame", nil, win)
anchorAR:SetSize(halfW, panelH)
anchorAR:SetPoint("TOPLEFT", anchorAL, "TOPLEFT", 0, 0)
anchorAR:SetPoint("BOTTOMRIGHT", anchorAL, "BOTTOMRIGHT", 0, 0)

local anchorBL = CreateFrame("Frame", nil, win)
anchorBL:SetSize(halfW, panelH)
anchorBL:SetPoint("TOPLEFT", anchorAL, "TOPRIGHT", PANEL_GAP, 0)

local anchorBR = CreateFrame("Frame", nil, win)
anchorBR:SetSize(halfW, panelH)
anchorBR:SetPoint("TOPLEFT", anchorBL, "TOPLEFT", 0, 0)
anchorBR:SetPoint("BOTTOMRIGHT", anchorBL, "BOTTOMRIGHT", 0, 0)

local AppendA, ClearA = MakePanel("|cffffff00[A] COMBAT_LOG_EVENT_UNFILTERED  (hostile NPC dest, throttled)|r", anchorAL, anchorAR)
local AppendB, ClearB = MakePanel("|cff00ccff[B] NAME_PLATE_UNIT_ADDED / REMOVED|r",                           anchorBL, anchorBR)

btnClearAll:SetScript("OnClick", function() ClearA() ClearB() end)

-- ── Panel A — Combat log listener ────────────────────────────────────────────

local seenCL = {}  -- [subevent.."::"..destGUID] = true

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

    -- target match
    if UnitGUID("target") == destGUID then
        AppendA(string.format("  >> target match: %s", tostring(UnitName("target"))))
    end

    -- nameplate match
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == destGUID then
            AppendA(string.format("  >> nameplate%d match: %s", i, tostring(UnitName(unit))))
        end
    end
end)

-- ── Panel B — Nameplate event listener ───────────────────────────────────────

local npFrame = CreateFrame("Frame", "PugRaidNameplateProbeFrame")

-- Register events — NAME_PLATE_UNIT_ADDED fires when a nameplate appears in range.
-- If it doesn't exist in this client, we catch the error and note it.
local npEventsOK = pcall(function()
    npFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    npFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end)

if not npEventsOK then
    AppendB("|cffff4444NAME_PLATE_UNIT_ADDED is NOT supported by this client.|r")
    AppendB("TBC Classic may not expose nameplate unit events.")
else
    AppendB("NAME_PLATE_UNIT_ADDED registered OK — waiting for nameplates...")
end

npFrame:SetScript("OnEvent", function(self, event, unitToken)
    -- unitToken is e.g. "nameplate1"
    local name  = UnitName(unitToken)
    local guid  = UnitGUID(unitToken)
    local flags = UnitFlags and UnitFlags(unitToken)   -- may be nil in TBC

    local hostile = ""
    if guid then
        -- Check reaction via UnitReaction (player vs unit): 1-2 = hostile, 3 = neutral, 4+ = friendly
        local reaction = UnitReaction and UnitReaction("player", unitToken)
        if reaction and reaction <= 2 then
            hostile = "  [HOSTILE]"
        elseif reaction then
            hostile = "  [reaction=" .. reaction .. "]"
        end
    end

    local tag = (event == "NAME_PLATE_UNIT_ADDED") and "|cff00ff00+ADD |r" or "|cffff6666-REM |r"
    AppendB(string.format("%s unit=%-12s  name=%-22s  guid=%s%s",
        tag, tostring(unitToken), tostring(name), tostring(guid), hostile))
end)

-- ── Show ──────────────────────────────────────────────────────────────────────

AppendA("=== Panel A ready — trigger a Hyjal wave ===")
AppendB("=== Panel B ready — nameplate events will appear here ===")
win:Show()
