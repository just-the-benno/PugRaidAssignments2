-- Dispatcher.lua
-- Sends built messages to the appropriate chat channels.

PugRaidAssignmentsDispatcher = {}
local D = PugRaidAssignmentsDispatcher

local Roster = PugRaidAssignmentsRoster

-- Send a single built message (from Template.BuildMessages) to appropriate channel.
function D.SendMessage(msg)
    if msg.kind == "SHORT" then
        for _, line in ipairs(msg.lines) do
            if line ~= "" then
                SendChatMessage(line, "RAID")
            end
        end
    elseif msg.kind == "ASSIGNMENT" then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            for _, line in ipairs(msg.lines) do
                if line ~= "" then
                    SendChatMessage(line, "RAID_WARNING")
                end
            end
        else
            -- Fall back to RAID chat if no permission
            for _, line in ipairs(msg.lines) do
                if line ~= "" then
                    SendChatMessage(line, "RAID")
                end
            end
        end
    elseif msg.kind == "PERSONAL" then
        if msg.target and msg.target ~= "" then
            SendChatMessage(msg.text, "WHISPER", nil, msg.target)
        end
    end
    -- LONG is not sent
end

-- Send all messages that are not LONG (i.e. SHORT, ASSIGNMENT, PERSONAL).
function D.SendAll(messages)
    for _, msg in ipairs(messages) do
        if msg.kind ~= "LONG" then
            D.SendMessage(msg)
        end
    end
end

-- Mark a raid target icon on the current target unit.
-- iconIndex: 1-8 per SetRaidTarget API (1=Star ... 8=Skull)
-- Returns true on success, false if not leader/assist.
function D.MarkTarget(iconIndex)
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        print("|cffff8800PugRaid:|r You need to be leader or assist to mark targets.")
        return false
    end
    SetRaidTarget("target", iconIndex)
    return true
end

-- Simulate: print messages in colored chat-type style without sending.
function D.Simulate(messages)
    print("|cffffff00PugRaid Simulate:|r")
    for _, msg in ipairs(messages) do
        if msg.kind == "LONG" then
            print("|cffaaaaaa[LONG]|r")
            for _, ln in ipairs(msg.lines) do print("  " .. ln) end
        elseif msg.kind == "SHORT" then
            for _, ln in ipairs(msg.lines) do
                print("|cffffffff[RAID]|r " .. ln)
            end
        elseif msg.kind == "ASSIGNMENT" then
            for _, ln in ipairs(msg.lines) do
                print("|cffff8800[RAID WARNING]|r " .. ln)
            end
        elseif msg.kind == "PERSONAL" then
            print("|cff00ccff[WHISPER -> " .. (msg.target or "?") .. "]|r " .. (msg.text or ""))
        end
    end
end

-- Validate: returns a list of invalid {{var}}=value pairs where value is not a current group member.
-- `values` is { [varName] = resolvedName }
-- `usedVars` is the list of variable names used in PERSONAL sections (these must be roster members)
function D.ValidateRoster(values, usedVars)
    local invalid = {}
    for _, var in ipairs(usedVars) do
        local val = values[var]
        if val and val ~= "" and not PugRaidAssignmentsRoster.IsMember(val) then
            invalid[#invalid + 1] = { var = var, value = val }
        end
    end
    return invalid
end
