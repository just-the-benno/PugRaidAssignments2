-- CombatLogProbe.lua
-- TEMPORARY: Two-panel probe window for evaluating auto-mark approaches.
--
-- Panel A  (left)  — COMBAT_LOG_EVENT_UNFILTERED
--   Records every event where a hostile NPC is the destination.
--   Throttled: one line per unique (subevent + destGUID) pair.
--
-- Panel B  (right) — CHAT_MSG_ADDON (ALL channels, ALL prefixes)
--   No channel filter this run — we want to see everything BigWigs sends
--   at the moment a wave actually starts, including WHISPER-to-self and
--   any other channel we may have been filtering out.
--   Guild/officer noise is still a lot, but we need the full picture once
--   to identify the exact message and channel, then we can filter again.
--
-- HOW TO USE:
--   1. /reload — both panels open automatically.
--   2. Run BigWigs. Trigger a Hyjal wave (talk to NPC AND confirm).
--   3. Click inside Panel B, Ctrl-A, Ctrl-C, paste back here.
--   4. Use the individual Clear buttons or "Clear All" to reset between waves.
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
    win.TitleText:SetText("PugRaid Probe  |cffaaaaaa[A] Combat Log     [B] ALL addon messages (no filter)|r")
end

local btnClearAll = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
btnClearAll:SetSize(80, BTN_H)
btnClearAll:SetText("Clear All")
btnClearAll:SetPoint("TOPRIGHT", win, "TOPRIGHT", -28, -28)

-- ── Panel factory ─────────────────────────────────────────────────────────────

local function MakePanel(label, anchorLeft, anchorRight)
    local hdr = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", anchorLeft, "TOPLEFT", 0, 0)
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

    local ebWidth = math.floor((WIN_W - PAD * 2 - PANEL_GAP) / 2) - 30
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:EnableMouse(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(ebWidth)
    eb:SetHeight(2000)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    sf:SetScrollChild(eb)

    local lineCount = 0
    local MAX_LINES = 600

    local function AppendLine(text)
        if lineCount >= MAX_LINES then return end
        lineCount = lineCount + 1
        local cur = eb:GetText()
        eb:SetText(cur == "" and text or (cur .. "\n" .. text))
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
local AppendB, ClearB = MakePanel("|cff00ccff[B] ALL CHAT_MSG_ADDON traffic  (no channel filter)|r",            anchorBL, anchorBR)

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

-- ── Panel B — ALL addon messages, no channel filter ──────────────────────────
-- We saw "B^SummitNext^Azgalor" on RAID when talking to the NPC, but nothing
-- when the wave actually started. Removing the channel filter to catch anything
-- BigWigs may send on WHISPER, SAY, or other channels at wave-start time.

local addonFrame = CreateFrame("Frame", "PugRaidAddonMsgProbeFrame")
addonFrame:RegisterEvent("CHAT_MSG_ADDON")

local registerFn = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
                or RegisterAddonMessagePrefix

local prefixesToRegister = {
    "BigWigs", "BigWigs3", "BigWigs4", "BigWigsRez",
    "DBM", "DBM-Core", "DBMv4",
    "BWPVE", "BWPVP",
}

local registered = {}
for _, prefix in ipairs(prefixesToRegister) do
    local ok = pcall(function()
        if registerFn then registerFn(prefix) end
    end)
    if ok then registered[#registered + 1] = prefix end
end

AppendB("Registered: " .. table.concat(registered, ", "))
AppendB("No channel filter — showing everything. Clear before confirming the wave dialog.")
AppendB("----------------------------------------------------------------------")

addonFrame:SetScript("OnEvent", function(self, event, prefix, payload, channel, sender)
    local t = date("%H:%M:%S")
    AppendB(string.format("[%s]  pfx=%-14s  ch=%-14s  from=%-20s  msg=\"%s\"",
        t, tostring(prefix), tostring(channel), tostring(sender), tostring(payload)))
end)

-- ── Show ──────────────────────────────────────────────────────────────────────

AppendA("=== Panel A ready — trigger a Hyjal wave ===")
AppendB("=== Panel B ready — ALL addon messages, no filter ===")
win:Show()
