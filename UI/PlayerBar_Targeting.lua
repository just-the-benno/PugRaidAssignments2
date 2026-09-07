-- UI/PlayerBar_Targeting.lua
-- Target-marking logic for the Player Bar.
-- Handles both hard-target (UnitName("target")) and mouseover (UnitName("mouseover"))
-- marking flows, shared by buttons and keybindings.

local S = PugRaidAssignmentsStorage
local P = PugRaidAssignmentsParser
local D = PugRaidAssignmentsDispatcher
local F = PugRaidAssignmentsFriendlyTargeting

-- ── Helpers (duplicated from PlayerBar.lua via upvalue) ────────────────────────

local function GetActiveSessionAndRaid()
    local sess = S.GetActiveSession()
    if not sess then return nil, nil end
    local raid = S.GetRaid(sess.raidId)
    return sess, raid
end

local function GetCurrentDoc(sess, raid)
    if not sess or not raid then return nil end
    local docs = S.GetDocumentsSorted(sess.raidId)
    local idx = math.max(1, math.min(sess.currentDocIndex or 1, #docs))
    sess.currentDocIndex = idx
    return docs[idx], idx, #docs
end

-- ── Core marking logic ─────────────────────────────────────────────────────────

-- Attempts to mark the unit identified by `unitToken` ("target" or "mouseover")
-- against the current document's target list.
--
-- Logic:
--   1. If the unit already carries an icon that matches one of its entries in
--      the target list, record that assignment and stop (don't re-mark).
--   2. Otherwise, assign the next unassigned icon for that mob name.
--
-- Returns true if all targets are now done (caller may close the checklist).
local function TryMarkUnit(unitToken, sess, doc)
    local unitName = UnitName(unitToken)
    if not unitName then return false end

    local ver      = S.GetLatestVersion(sess.raidId, doc.id)
    local sections = ver and P.Parse(ver.text) or {}
    local targets  = P.GetMobTargets(sections)
    local tp       = S.GetTargetProgress(sess, doc.id)

    -- Step 1: check if this unit already wears a valid icon from the list.
    local currentIcon = GetRaidTargetIndex(unitToken)
    if currentIcon and currentIcon > 0 then
        for _, entry in ipairs(targets) do
            if entry.mobName:lower() == unitName:lower()
               and entry.iconIndex == currentIcon
               and not tp.assignedIcons[currentIcon] then
                -- Unit already has the right mark; just record it.
                S.MarkIconAssigned(sess, doc.id, currentIcon)
                break
            end
        end
    end

    -- Refresh tp after potential early-record above.
    tp = S.GetTargetProgress(sess, doc.id)

    -- Step 2: if the unit still has no recorded assignment, assign the next
    -- unassigned icon for this mob name.
    -- First check: does this unit already have a recorded icon? (avoid double-mark)
    local alreadyRecorded = false
    if currentIcon and currentIcon > 0 then
        alreadyRecorded = tp.assignedIcons[currentIcon] == true
    end

    if not alreadyRecorded then
        for _, entry in ipairs(targets) do
            if entry.mobName:lower() == unitName:lower() and not tp.assignedIcons[entry.iconIndex] then
                if D.MarkTarget(unitToken, entry.iconIndex) then
                    S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
                end
                break
            end
        end
    end

    -- Check if all targets are now marked.
    local tp2 = S.GetTargetProgress(sess, doc.id)
    for _, entry in ipairs(targets) do
        if not tp2.assignedIcons[entry.iconIndex] then
            return false
        end
    end
    return #targets > 0
end

-- Attempts to mark the unit identified by `unitToken` against the current
-- document's friendly-target list, matching by the unit's live name against
-- the player name currently assigned to each friendly target's variable.
-- Mirrors TryMarkUnit's step-1/step-2 record-then-assign flow.
--
-- Returns true if all friendly targets are now done.
local function TryMarkFriendlyUnit(unitToken, sess, doc)
    local unitName = UnitName(unitToken)
    if not unitName then return false end

    local ver             = S.GetLatestVersion(sess.raidId, doc.id)
    local sections        = ver and P.Parse(ver.text) or {}
    local friendlyTargets = P.GetFriendlyTargets(sections)
    local tp              = S.GetTargetProgress(sess, doc.id)

    local function assignedNameFor(entry)
        return S.GetLastValue(sess.raidId, doc.id, entry.varName)
    end

    -- Step 1: check if this unit already wears a valid icon from the list.
    local currentIcon = GetRaidTargetIndex(unitToken)
    if currentIcon and currentIcon > 0 then
        for _, entry in ipairs(friendlyTargets) do
            local assignedName = assignedNameFor(entry)
            if assignedName and assignedName ~= "" and assignedName:lower() == unitName:lower()
               and entry.iconIndex == currentIcon
               and not tp.assignedIcons[currentIcon] then
                S.MarkIconAssigned(sess, doc.id, currentIcon)
                break
            end
        end
    end

    -- Refresh tp after potential early-record above.
    tp = S.GetTargetProgress(sess, doc.id)

    local alreadyRecorded = false
    if currentIcon and currentIcon > 0 then
        alreadyRecorded = tp.assignedIcons[currentIcon] == true
    end

    if not alreadyRecorded then
        for _, entry in ipairs(friendlyTargets) do
            local assignedName = assignedNameFor(entry)
            if assignedName and assignedName ~= "" and assignedName:lower() == unitName:lower()
               and not tp.assignedIcons[entry.iconIndex] then
                if D.MarkTarget(unitToken, entry.iconIndex) then
                    S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
                end
                break
            end
        end
    end

    local tp2 = S.GetTargetProgress(sess, doc.id)
    for _, entry in ipairs(friendlyTargets) do
        if not tp2.assignedIcons[entry.iconIndex] then
            return false
        end
    end
    return #friendlyTargets > 0
end

-- Returns true if every mob AND friendly target in the doc's current
-- version has been assigned.
local function AllTargetsAssigned(sess, doc)
    local ver      = S.GetLatestVersion(sess.raidId, doc.id)
    local sections = ver and P.Parse(ver.text) or {}
    local targets  = P.GetTargets(sections)
    if #targets == 0 then return false end
    local tp = S.GetTargetProgress(sess, doc.id)
    for _, entry in ipairs(targets) do
        if not tp.assignedIcons[entry.iconIndex] then
            return false
        end
    end
    return true
end

-- ── Public helpers ───────────────────────────────────────────────────────────────

-- Mark a specific target-list entry against the given unit token.
-- Used by checklist [Mark] buttons.
function PugRaidTargeting_MarkEntry(unitToken, sess, doc, entry)
    local currentIcon = GetRaidTargetIndex(unitToken)
    if currentIcon == entry.iconIndex then
        S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
    else
        if D.MarkTarget(unitToken, entry.iconIndex) then
            S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
        end
    end
end

-- Called automatically on PLAYER_TARGET_CHANGED.
-- Runs TryMarkUnit silently for "target" (mob match) plus a friendly-unit
-- resolution pass (both name-match against the current target and a full
-- roster-based resolve/mark of any still-unassigned friendly targets).
-- Refreshes the checklist if it is already open, but does NOT open it on
-- its own.
function PugRaidTargeting_MarkCurrentTarget(sess, doc, callbacks)
    TryMarkUnit("target", sess, doc)
    TryMarkFriendlyUnit("target", sess, doc)
    if F then F.MarkAll(sess, doc) end

    if callbacks.IsExpanded() then
        if AllTargetsAssigned(sess, doc) then
            callbacks.ShowChecklist(false)
        else
            callbacks.RebuildChecklist(sess, doc)
        end
    end
end

-- ── Public action functions ────────────────────────────────────────────────────

-- Both functions below share the same state machine:
--   Always attempt to mark the unit AND show/refresh the checklist.

-- `callbacks` table expected to contain:
--   callbacks.IsExpanded()          → bool
--   callbacks.ShowChecklist(show)   → nil
--   callbacks.RebuildChecklist(sess, doc) → nil

function PugRaidTargeting_ExecuteManualTarget(callbacks)
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not doc then
        callbacks.ShowChecklist(true)
        return
    end

    -- Always attempt to mark, then reliably show/refresh the checklist —
    -- this is an explicit user action, so it should never silently no-op.
    TryMarkUnit("target", sess, doc)
    callbacks.ShowChecklist(true)
    callbacks.RebuildChecklist(sess, doc)
end

function PugRaidTargeting_ExecuteMouseoverTarget(callbacks)
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not doc then
        callbacks.ShowChecklist(true)
        return
    end

    -- Always attempt to mark, then reliably show/refresh the checklist.
    TryMarkUnit("mouseover", sess, doc)
    callbacks.ShowChecklist(true)
    callbacks.RebuildChecklist(sess, doc)
end

-- Resolves the current target as a friendly unit (matches its name against
-- the player currently assigned to each friendly target's variable) and
-- marks it if found. Bound to the "Assign Friendly Target" keybinding.
function PugRaidTargeting_ExecuteFriendlyTarget(callbacks)
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not doc then
        callbacks.ShowChecklist(true)
        return
    end

    TryMarkFriendlyUnit("target", sess, doc)
    callbacks.ShowChecklist(true)
    callbacks.RebuildChecklist(sess, doc)
end
