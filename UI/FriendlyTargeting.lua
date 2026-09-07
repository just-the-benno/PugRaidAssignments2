-- UI/FriendlyTargeting.lua
-- Resolution + marking logic for friendly-unit targets in the TARGETS
-- section, written as "{{ VarName }}: rt<N>".
--
-- Unlike mob targets (matched by name against the player's current target),
-- friendly targets reference a raid/party member indirectly through a
-- template variable. The actual player name assigned to that variable is
-- looked up the same way PERSONAL section variables are (S.GetLastValue),
-- then resolved to a live unit token via the current roster
-- (PugRaidAssignmentsRoster.FindUnitByName).
--
-- If a friendly unit can't be resolved (variable unassigned, or the
-- assigned player isn't currently in the group/raid) resolution/marking
-- silently no-ops — callers should not treat this as an error.

PugRaidAssignmentsFriendlyTargeting = {}
local F = PugRaidAssignmentsFriendlyTargeting

local S = PugRaidAssignmentsStorage
local P = PugRaidAssignmentsParser
local D = PugRaidAssignmentsDispatcher
local R = PugRaidAssignmentsRoster

-- Resolve a friendly-target entry's variable to a live unit token.
-- Returns nil if the variable has no assigned value, or the assigned
-- player isn't currently present in the group/raid.
function F.ResolveUnit(sess, doc, varName)
    if not (sess and doc and varName) then return nil end
    local playerName = S.GetLastValue(sess.raidId, doc.id, varName)
    if not playerName or playerName == "" then return nil end
    return R.FindUnitByName(playerName)
end

-- Attempt to resolve and mark a single friendly-target entry.
-- Returns true if the mark is (now, or already was) applied.
function F.MarkEntry(sess, doc, entry)
    if not (sess and doc and entry and entry.varName) then return false end
    local tp = S.GetTargetProgress(sess, doc.id)
    if tp.assignedIcons[entry.iconIndex] then return true end

    local unit = F.ResolveUnit(sess, doc, entry.varName)
    if not unit then return false end

    if D.MarkTarget(unit, entry.iconIndex) then
        S.MarkIconAssigned(sess, doc.id, entry.iconIndex)
        return true
    end
    return false
end

-- Resolve and mark every friendly target found in the doc's latest version.
-- Silently skips entries that can't be resolved.
-- Returns the number of entries newly marked during this call.
function F.MarkAll(sess, doc)
    if not (sess and doc) then return 0 end
    local ver = S.GetLatestVersion(sess.raidId, doc.id)
    if not ver then return 0 end

    local sections = P.Parse(ver.text)
    local friendlyTargets = P.GetFriendlyTargets(sections)
    local marked = 0
    for _, entry in ipairs(friendlyTargets) do
        local tp = S.GetTargetProgress(sess, doc.id)
        local wasAssigned = tp.assignedIcons[entry.iconIndex] == true
        if F.MarkEntry(sess, doc, entry) and not wasAssigned then
            marked = marked + 1
        end
    end
    return marked
end
