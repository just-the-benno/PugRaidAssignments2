-- Roster.lua
-- Provides helpers for querying the current group/raid members.

PugRaidAssignmentsRoster = {}
local R = PugRaidAssignmentsRoster

-- Returns a sorted list of player names in the current group/raid.
function R.GetMembers()
    local members = {}
    local numMembers = GetNumGroupMembers()
    if numMembers > 0 then
        local isRaid = IsInRaid()
        for i = 1, numMembers do
            local unit = isRaid and ("raid" .. i) or ("party" .. i)
            local name = UnitName(unit)
            if name and name ~= "Unknown" then
                members[#members + 1] = name
            end
        end
    end
    -- Always include the player themselves
    local playerName = UnitName("player")
    if playerName then
        local found = false
        for _, n in ipairs(members) do
            if n == playerName then found = true break end
        end
        if not found then members[#members + 1] = playerName end
    end
    table.sort(members)
    return members
end

-- Returns true if the given name is a current group/raid member (case-sensitive unit name match).
function R.IsMember(name)
    local members = R.GetMembers()
    for _, m in ipairs(members) do
        if m == name then return true end
    end
    return false
end

-- Returns true if the player can send raid warnings.
function R.CanLead()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Returns the live unit token ("player", "partyN", "raidN") for the given
-- player name in the current group/raid, or nil if not found.
-- Used to resolve friendly-unit targets ({{ VarName }}) to an actual unit
-- that can be marked with SetRaidTarget.
function R.FindUnitByName(name)
    if not name or name == "" then return nil end
    local lowered = name:lower()

    local playerName = UnitName("player")
    if playerName and playerName:lower() == lowered then
        return "player"
    end

    local numMembers = GetNumGroupMembers()
    if numMembers > 0 then
        local isRaid = IsInRaid()
        for i = 1, numMembers do
            local unit = isRaid and ("raid" .. i) or ("party" .. i)
            local unitName = UnitName(unit)
            if unitName and unitName:lower() == lowered then
                return unit
            end
        end
    end
    return nil
end
