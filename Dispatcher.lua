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
        -- PERSONAL_BLOCK_GROUP is a synthetic presenter-mode-only message;
        -- individual PERSONAL messages already cover these whispers.
        if msg.kind ~= "LONG" and msg.kind ~= "PERSONAL_BLOCK_GROUP" then
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
    local blockNum = 0
    local inBlockMode = false

    -- Determine if the message set uses blocks at all.
    for _, msg in ipairs(messages) do
        if msg.blocks or msg.kind == "PERSONAL_BLOCK_GROUP" then
            inBlockMode = true
            break
        end
    end

    for _, msg in ipairs(messages) do
        if msg.kind == "LONG" then
            print("|cffaaaaaa[LONG]|r")
            for _, ln in ipairs(msg.lines) do print("  " .. ln) end
        elseif msg.kind == "SHORT" then
            if msg.blocks then
                for _, blk in ipairs(msg.blocks) do
                    blockNum = blockNum + 1
                    print("|cff888800── Block " .. blockNum .. " ──|r")
                    for _, ln in ipairs(blk.lines) do
                        for _, chunk in ipairs(ChunkText(ln)) do
                            print("|cffffffff[RAID]|r " .. chunk)
                        end
                    end
                end
            else
                for _, ln in ipairs(msg.lines) do
                    for _, chunk in ipairs(ChunkText(ln)) do
                        print("|cffffffff[RAID]|r " .. chunk)
                    end
                end
            end
        elseif msg.kind == "ASSIGNMENT" then
            if msg.blocks then
                for _, blk in ipairs(msg.blocks) do
                    blockNum = blockNum + 1
                    print("|cff888800── Block " .. blockNum .. " ──|r")
                    for _, ln in ipairs(blk.lines) do
                        for _, chunk in ipairs(ChunkText(ln)) do
                            print("|cffff8800[RAID WARNING]|r " .. chunk)
                        end
                    end
                end
            else
                for _, ln in ipairs(msg.lines) do
                    for _, chunk in ipairs(ChunkText(ln)) do
                        print("|cffff8800[RAID WARNING]|r " .. chunk)
                    end
                end
            end
        elseif msg.kind == "PERSONAL" then
            for _, chunk in ipairs(ChunkText(msg.text)) do
                print("|cff00ccff[WHISPER -> " .. (msg.target or "?") .. "]|r " .. chunk)
            end
        elseif msg.kind == "PERSONAL_BLOCK_GROUP" then
            -- Expand whisper blocks with block markers.
            for _, blk in ipairs(msg.blocks) do
                blockNum = blockNum + 1
                print("|cff888800── Block " .. blockNum .. " ──|r")
                for _, w in ipairs(blk.whispers) do
                    for _, chunk in ipairs(ChunkText(w.text)) do
                        print("|cff00ccff[WHISPER -> " .. (w.target or "?") .. "]|r " .. chunk)
                    end
                end
            end
        end
    end
end

-- Validate: returns a list of invalid {{var}}=value pairs where value is not a current group member.
-- `values` is { [varName] = resolvedName }
-- `usedVars` is the list of variable names used in PERSONAL sections (these must be roster members)
-- `skippedVars` is an optional set { [varName] = true } — skipped vars are excluded from validation.
function D.ValidateRoster(values, usedVars, skippedVars)
    skippedVars = skippedVars or {}
    local invalid = {}
    for temp, var in ipairs(usedVars) do
        if not skippedVars[var] then
            local val = values[var]
            if val and val ~= "" and not PugRaidAssignmentsRoster.IsMember(val) then
                invalid[#invalid + 1] = { var = var, value = val }
            end
        end
    end

    for var, value in pairs(usedVars) do
        if not skippedVars[var] then
            local val = value
            if val == nil or val == "" then
                invalid[#invalid + 1] = { var = var, value = "<EMPTY>" }
            elseif val and val ~= "" and not PugRaidAssignmentsRoster.IsMember(val) then
                invalid[#invalid + 1] = { var = var, value = val }
            end
        end
    end

    for var, value in pairs(values) do
        if not skippedVars[var] then
            local val = value
            if val == nil or val == "" then
                invalid[#invalid + 1] = { var = var, value = "<EMPTY>" }
            elseif val and val ~= "" and not PugRaidAssignmentsRoster.IsMember(val) then
                invalid[#invalid + 1] = { var = var, value = val }
            end
        end
    end
    return invalid
end

-- ── Presenter / block queue ───────────────────────────────────────────────────
--
-- BuildPresenterQueue takes a list of messages (from Template.BuildMessages)
-- that already contain .blocks information (set by Parser.ApplyBlockSplitting)
-- and returns a flat, ordered list of "block items".  Each block item is a
-- small list of messages (or whispers) that should be sent together when the
-- user clicks Play.  The queue is ordered by section/document order.
--
-- A block item has the shape:
--   { messages = { msg, ... } }
-- where each `msg` is something D.SendMessage understands (kind, lines/target/text).
--
-- Sections without .blocks get a single implicit block containing all their content.
-- PERSONAL_BLOCK_GROUP pseudo-messages (emitted by Template when sec.blocks exists)
-- are expanded into per-block whisper groups here.  Plain PERSONAL messages
-- (emitted when sec.blocks is absent) fall into the single implicit block.
function D.BuildPresenterQueue(messages)
    local queue = {} -- list of { messages = {} }

    -- We process in document order.  We need to group by "block index" per
    -- section, then flatten across sections.  The approach: collect all block
    -- contributions per section, then concatenate across sections.

    -- Temporary per-section block accumulators.
    local sectionBlocks = {} -- list of lists-of-msgs

    -- State for accumulating plain (non-block) PERSONAL messages
    -- into the section they belong to.
    local pendingPlain = {} -- plain messages since last PERSONAL_BLOCK_GROUP

    for _, msg in ipairs(messages) do
        if msg.kind == "PERSONAL_BLOCK_GROUP" then
            -- Flush any preceding plain PERSONAL messages (shouldn't happen if
            -- blocks are consistent, but be defensive).
            pendingPlain = {}
            -- Each block in the group becomes one block-item for this section.
            local secBlks = {}
            for _, blk in ipairs(msg.blocks) do
                secBlks[#secBlks + 1] = blk.whispers -- list of PERSONAL msgs
            end
            sectionBlocks[#sectionBlocks + 1] = secBlks
        elseif msg.kind == "PERSONAL" then
            -- Plain (non-block) PERSONAL: accumulate for a single block.
            pendingPlain[#pendingPlain + 1] = msg
        elseif msg.kind == "LONG" then
            -- LONG is never sent; skip.
        else
            -- SHORT or ASSIGNMENT
            if msg.blocks then
                -- Flush any accumulated plain PERSONAL into a prior single-block section.
                if #pendingPlain > 0 then
                    sectionBlocks[#sectionBlocks + 1] = { pendingPlain }
                    pendingPlain = {}
                end
                -- Expand blocks into per-block messages.
                local secBlks = {}
                for _, blk in ipairs(msg.blocks) do
                    -- Build a sendable message for just this block's lines.
                    secBlks[#secBlks + 1] = { { kind = msg.kind, lines = blk.lines } }
                end
                sectionBlocks[#sectionBlocks + 1] = secBlks
            else
                -- No blocks: single implicit block.
                if #pendingPlain > 0 then
                    sectionBlocks[#sectionBlocks + 1] = { pendingPlain }
                    pendingPlain = {}
                end
                sectionBlocks[#sectionBlocks + 1] = { { msg } }
            end
        end
    end
    -- Flush any trailing plain PERSONAL.
    if #pendingPlain > 0 then
        sectionBlocks[#sectionBlocks + 1] = { pendingPlain }
    end

    -- Flatten: iterate block index across all sections.
    -- Because sections can have different numbers of blocks we zip across them
    -- sequentially, appending all section-blocks at their natural positions into
    -- the flat queue.
    for _, secBlks in ipairs(sectionBlocks) do
        for _, blkMsgs in ipairs(secBlks) do
            queue[#queue + 1] = { messages = blkMsgs }
        end
    end

    return queue
end

-- Send all messages in a single block item from BuildPresenterQueue.
-- Uses the same chunking+throttled pipeline as SendAll.
function D.SendBlock(blockItem)
    for _, msg in ipairs(blockItem.messages) do
        D.SendMessage(msg)
    end
end
