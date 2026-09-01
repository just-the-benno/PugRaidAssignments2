-- UI/PlayerBar_Targeting.lua
-- Target-marking logic for the Player Bar.
-- Handles both hard-target (UnitName("target")) and mouseover (UnitName("mouseover"))
-- marking flows, shared by buttons and keybindings.

local S = PugRaidAssignmentsStorage
local P = PugRaidAssignmentsParser
local D = PugRaidAssignmentsDispatcher

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
-- Skips marking if the unit already carries the correct icon.
-- Returns true if all targets are now done (caller may close the checklist).
local function TryMarkUnit(unitToken, sess, doc)
    local unitName = UnitName(unitToken)
    if not unitName then return false end

    local ver      = S.GetLatestVersion(sess.raidId, doc.id)
    local sections = ver and P.Parse(ver.text) or {}
    local targets  = P.GetTargets(sections)
    local tp       = S.GetTargetProgress(sess, doc.id)

    for _, entry in ipairs(targets) do
        if entry.mobName:lower() == unitName:lower() and not tp.assignedIcons[entry.iconIndex] then
            -- Check if the unit already has the correct icon in the world.
            local currentIcon = GetRaidTargetIndex(unitToken)
            if currentIcon == entry.iconIndex then
                -- Already marked correctly; just record it.
                S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
            else
                if D.MarkTarget(unitToken, entry.iconIndex) then
                    S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
                end
            end
            break
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

-- Public wrapper so PlayerBar.lua checklist rows can trigger a mark
-- for a specific entry without going through the full state-machine flow.
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

-- ── Public action functions ────────────────────────────────────────────────────

-- Both functions below share the same state machine:
--   1st activation  → open the checklist panel (via callback).
--   Subsequent activations while panel is open → attempt to mark the unit.

-- `callbacks` table expected to contain:
--   callbacks.IsExpanded()          → bool
--   callbacks.ShowChecklist(show)   → nil
--   callbacks.RebuildChecklist(sess, doc) → nil

function PugRaidTargeting_ExecuteManualTarget(callbacks)
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not doc then
        if not callbacks.IsExpanded() then callbacks.ShowChecklist(true) end
        return
    end

    if not callbacks.IsExpanded() then
        callbacks.ShowChecklist(true)
        return
    end

    local allDone = TryMarkUnit("target", sess, doc)
    if allDone then
        callbacks.ShowChecklist(false)
    else
        callbacks.RebuildChecklist(sess, doc)
    end
end

function PugRaidTargeting_ExecuteMouseoverTarget(callbacks)
    local sess, raid = GetActiveSessionAndRaid()
    local doc = GetCurrentDoc(sess, raid)

    if not doc then
        if not callbacks.IsExpanded() then callbacks.ShowChecklist(true) end
        return
    end

    if not callbacks.IsExpanded() then
        callbacks.ShowChecklist(true)
        return
    end

    local allDone = TryMarkUnit("mouseover", sess, doc)
    if allDone then
        callbacks.ShowChecklist(false)
    else
        callbacks.RebuildChecklist(sess, doc)
    end
end
