-- Dispatcher.lua
-- Sends built messages to the appropriate chat channels.

PugRaidAssignmentsDispatcher = {}
local D = PugRaidAssignmentsDispatcher

local Roster = PugRaidAssignmentsRoster

-- WoW chat messages are capped at 255 bytes; leave a little headroom for
-- safety since some server-side prefixes/escaping can eat into that budget.
local MAX_CHUNK_LEN = 240

-- WoW throttles outgoing chat messages; sending too many too fast gets some
-- silently dropped by the server or triggers a "message throttled" error.
-- We queue every outgoing message and drain the queue on a timer instead of
-- firing them all synchronously.
local SEND_INTERVAL = 0.8 -- seconds between messages, safely under the throttle

local sendQueue = {}
local queueFrame = CreateFrame("Frame")
local timeSinceLastSend = 0
local queueRunning = false

local function DrainQueue(self, elapsed)
    timeSinceLastSend = timeSinceLastSend + elapsed
    if timeSinceLastSend < SEND_INTERVAL then return end
    timeSinceLastSend = 0

    local item = table.remove(sendQueue, 1)
    if not item then
        queueRunning = false
        queueFrame:SetScript("OnUpdate", nil)
        return
    end
    C_ChatInfo.SendChatMessage(item.text, item.chatType, nil, item.target)
end

local function QueueSend(text, chatType, target)
    sendQueue[#sendQueue + 1] = { text = text, chatType = chatType, target = target }
    if not queueRunning then
        queueRunning = true
        timeSinceLastSend = SEND_INTERVAL -- send first one immediately on next tick
        queueFrame:SetScript("OnUpdate", DrainQueue)
    end
end

-- Splits `text` into a list of chunks no longer than MAX_CHUNK_LEN, breaking
-- on word boundaries where possible so words are never cut in half.
-- If a single "word" is itself longer than the limit (rare, e.g. a long URL),
-- it is hard-split as a last resort.
local function ChunkText(text)
    if not text or text == "" then return {} end
    if #text <= MAX_CHUNK_LEN then return { text } end

    local chunks = {}
    local current = ""

    for word in text:gmatch("%S+") do
        local candidate = (current == "") and word or (current .. " " .. word)
        if #candidate <= MAX_CHUNK_LEN then
            current = candidate
        else
            if current ~= "" then
                chunks[#chunks + 1] = current
                current = ""
            end
            -- Word itself too long for one chunk: hard-split it.
            while #word > MAX_CHUNK_LEN do
                chunks[#chunks + 1] = word:sub(1, MAX_CHUNK_LEN)
                word = word:sub(MAX_CHUNK_LEN + 1)
            end
            current = word
        end
    end
    if current ~= "" then
        chunks[#chunks + 1] = current
    end
    return chunks
end

-- Queues `text` to the given chat type/target, splitting into multiple
-- throttled messages if it exceeds the safe chat length.
local function SendChunked(text, chatType, target)
    for _, chunk in ipairs(ChunkText(text)) do
        QueueSend(chunk, chatType, target)
    end
end

-- Send a single built message (from Template.BuildMessages) to appropriate channel.
function D.SendMessage(msg)
    if msg.kind == "SHORT" then
        for _, line in ipairs(msg.lines) do
            if line ~= "" then
                SendChunked(line, "RAID")
            end
        end
    elseif msg.kind == "ASSIGNMENT" then
        local chatType = (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and "RAID_WARNING" or "RAID"
        for _, line in ipairs(msg.lines) do
            if line ~= "" then
                SendChunked(line, chatType)
            end
        end
    elseif msg.kind == "PERSONAL" then
        if msg.target and msg.target ~= "" then
            SendChunked(msg.text, "WHISPER", msg.target)
        end
    end
    -- LONG is not sent
end

-- Send all messages that are not LONG (i.e. SHORT, ASSIGNMENT, PERSONAL).
-- All lines/whispers across every message are funneled into the same
-- throttled queue, so e.g. a raid warning followed by ten whispers won't
-- all fire in the same instant.
function D.SendAll(messages)
    for _, msg in ipairs(messages) do
        if msg.kind ~= "LONG" then
            D.SendMessage(msg)
        end
    end
end

-- Returns true if there are still queued messages waiting to be sent.
-- Useful if UI wants to show "Sending... (N left)" feedback.
function D.IsSending()
    return queueRunning
end

function D.QueuedCount()
    return #sendQueue
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
-- Also shows how each line/whisper would be chunked, so the preview matches
-- what Send will actually produce. Simulate is not queued/throttled since
-- nothing actually goes out over the network.
function D.Simulate(messages)
    print("|cffffff00PugRaid Simulate:|r")
    for _, msg in ipairs(messages) do
        if msg.kind == "LONG" then
            print("|cffaaaaaa[LONG]|r")
            for _, ln in ipairs(msg.lines) do print("  " .. ln) end
        elseif msg.kind == "SHORT" then
            for _, ln in ipairs(msg.lines) do
                for _, chunk in ipairs(ChunkText(ln)) do
                    print("|cffffffff[RAID]|r " .. chunk)
                end
            end
        elseif msg.kind == "ASSIGNMENT" then
            for _, ln in ipairs(msg.lines) do
                for _, chunk in ipairs(ChunkText(ln)) do
                    print("|cffff8800[RAID WARNING]|r " .. chunk)
                end
            end
        elseif msg.kind == "PERSONAL" then
            for _, chunk in ipairs(ChunkText(msg.text)) do
                print("|cff00ccff[WHISPER -> " .. (msg.target or "?") .. "]|r " .. chunk)
            end
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