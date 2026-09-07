-- UI/PlayerBar_Targeting.lua
-- Target-marking logic for the Player Bar.
-- Handles both hard-target (UnitName("target")) and mouseover (UnitName("mouseover"))
-- marking flows, shared by buttons and keybindings.

local S = PugRaidAssignmentsStorage
local P = PugRaidAssignmentsParser
local D = PugRaidAssignmentsDispatcher
local R = PugRaidAssignmentsRoster

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

-- ── Friendly unit resolution ───────────────────────────────────────────────────
--
-- Friendly targets ("{{ VarName }}: rt<N>") are resolved on demand rather than
-- stored: the variable's current value (a roster player name, same as used
-- everywhere else {{var}} substitution happens) is looked up and matched
-- against the live raid/party roster to find a unit token.

-- Resolve a friendly-target variable name to a live unit token, or nil if the
-- variable has no assigned value or that value isn't currently in the group.
function PugRaidTargeting_ResolveFriendlyUnit(varName, sess, doc)
    local value = S.GetLastValue(sess.raidId, doc.id, varName)
    if not value or value == "" then return nil end
    return R.FindUnitByName(value)
end

-- Mark a single friendly-target entry ({ type="friendly", varName, iconIndex })
-- by resolving its variable to a unit token and applying the icon.
-- Returns true if the unit was resolved and marked, false otherwise (no-op).
function PugRaidTargeting_MarkFriendlyEntry(sess, doc, entry)
    local unit = PugRaidTargeting_ResolveFriendlyUnit(entry.varName, sess, doc)
    if not unit then return false end
    if D.MarkTarget(unit, entry.iconIndex) then
        S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
        return true
    end
    return false
end

-- Resolve and mark every friendly target in the document's TARGETS section.
-- Unresolvable entries are silently skipped (no error, no blocking).
-- Used both by the Send flow and by the "Assign Friendly" button/keybinding.
function PugRaidTargeting_MarkAllFriendlyTargets(sess, doc)
    local ver = S.GetLatestVersion(sess.raidId, doc.id)
    local sections = ver and P.Parse(ver.text) or {}
    local friendlyTargets = P.GetFriendlyTargets(sections)
    for _, entry in ipairs(friendlyTargets) do
        PugRaidTargeting_MarkFriendlyEntry(sess, doc, entry)
    end
end

-- Called automatically on PLAYER_TARGET_CHANGED.
-- Runs TryMarkUnit silently for "target"; refreshes the checklist if it is
-- already open, but does NOT open it on its own.
function PugRaidTargeting_MarkCurrentTarget(sess, doc, callbacks)
    local allDone = TryMarkUnit("target", sess, doc)
    if callbacks.IsExpanded() then
        if allDone then
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

    -- Always attempt to mark, then show/refresh checklist.
    local allDone = TryMarkUnit("target", sess, doc)
    if allDone then
        callbacks.ShowChecklist(false)
    else
        callbacks.ShowChecklist(true)
        callbacks.RebuildChecklist(sess, doc)
    end
end

function PugRaidTargeting_ExecuteMouseoverTarget(callbacks)
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not doc then
        callbacks.ShowChecklist(true)
        return
    end

    -- Always attempt to mark, then show/refresh checklist.
    local allDone = TryMarkUnit("mouseover", sess, doc)
    if allDone then
        callbacks.ShowChecklist(false)
    else
        callbacks.ShowChecklist(true)
        callbacks.RebuildChecklist(sess, doc)
    end
end

-- Resolves and marks every friendly target for the current document
-- (see PugRaidTargeting_MarkAllFriendlyTargets), then shows/refreshes the
-- checklist so the raid leader can see what got marked. Bound to the
-- "Assign Friendly Target" keybinding and the checklist's "Assign Friendly"
-- buttons.
function PugRaidTargeting_ExecuteAssignFriendly(callbacks)
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not doc then
        callbacks.ShowChecklist(true)
        return
    end

    PugRaidTargeting_MarkAllFriendlyTargets(sess, doc)
    callbacks.ShowChecklist(true)
    callbacks.RebuildChecklist(sess, doc)
end
