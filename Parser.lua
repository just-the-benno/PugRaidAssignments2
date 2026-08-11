-- Parser.lua
-- Parses assignment document text into sections.
--
-- Document format:
--   ## SectionTitle
--   line1
--   line2
--   ...
--
-- Section kinds (determined by title, case-insensitive):
--   LONG       — free-form long text (e.g. "## Overview")
--   SHORT      — short broadcast text sent to RAID chat
--   ASSIGNMENT — sent to RAID_WARNING
--   PERSONAL   — whisper lines; format: "PlayerVar: message text"
--   TARGETS    — ordered target marks; format: "MobName: rt<N>"
--                rt1-rt8 map to SetRaidTarget indices:
--                  rt1 = 1 (Star), rt2 = 2 (Circle), rt3 = 3 (Diamond),
--                  rt4 = 4 (Triangle), rt5 = 5 (Moon), rt6 = 6 (Square),
--                  rt7 = 7 (Cross/X), rt8 = 8 (Skull)
--                These match SetRaidTarget(unit, index) exactly.

PugRaidAssignmentsParser = {}
local P = PugRaidAssignmentsParser
P.REGEX = "{{%s*([%w_]+)%s*}}"

-- Map from section title keywords to kinds
local TITLE_TO_KIND = {
    ["long"]        = "LONG",
    ["overview"]    = "LONG",
    ["short"]       = "SHORT",
    ["assignment"]  = "ASSIGNMENT",
    ["assignments"] = "ASSIGNMENT",
    ["personal"]    = "PERSONAL",
    ["whisper"]     = "PERSONAL",
    ["whispers"]    = "PERSONAL",
    ["targets"]     = "TARGETS",
    ["target"]      = "TARGETS",
}

-- Map rt<N> token to SetRaidTarget numeric index.
-- Star=1, Circle=2, Diamond=3, Triangle=4, Moon=5, Square=6, Cross=7, Skull=8
local RT_TOKEN_TO_INDEX = {
    rt1 = 1,
    rt2 = 2,
    rt3 = 3,
    rt4 = 4,
    rt5 = 5,
    rt6 = 6,
    rt7 = 7,
    rt8 = 8,
}

-- Icon index to display name (for UI labels)
P.ICON_NAMES = {
    [1] = "Star",
    [2] = "Circle",
    [3] = "Diamond",
    [4] = "Triangle",
    [5] = "Moon",
    [6] = "Square",
    [7] = "Cross",
    [8] = "Skull",
}

-- Block-splitting: a document may contain lines with exactly "!! END OF BLOCK !!"
-- (after trimming whitespace) inside any sendable section (SHORT, ASSIGNMENT,
-- PERSONAL).  This token divides the section's content into named "blocks" that
-- the Presenter Bar can send one at a time (Play, Repeat, Back, Eject).
--
-- Rules:
--  • If the token does NOT appear anywhere in the document, behavior is
--    100% unchanged — no blocks, no presenter bar.
--  • Each section is split into sub-lists of lines by the token.  A section
--    with N tokens produces N+1 blocks (the last block may be empty and is
--    trimmed away if so).
--  • For PERSONAL sections the token is its own line among the
--    "{{var}}: message" lines, splitting *groups* of whisper lines.
--  • Block information is stored as sec.blocks = { {lines={}}, ... } when
--    the token is present, in addition to the flat sec.lines list which
--    remains unchanged for callers that do not need block awareness.
--  • P.HasBlocks(sections) returns true if any section carries blocks.
--  • TARGETS and LONG sections ignore the token entirely.
P.END_OF_BLOCK_TOKEN = "!! END OF BLOCK !!"

-- Forward-declare ApplyBlockSplitting so P.Parse can call it even though
-- the function body is defined after P.Parse below.
local ApplyBlockSplitting

-- Parse `text` into a list of sections.
-- Returns: { { kind, title, lines = {string,...} }, ... }
-- TARGETS sections additionally have .targets = { {mobName, iconIndex}, ... }
-- Sendable sections will have .blocks = { {lines={}}, ... } if the document
-- contains any END_OF_BLOCK tokens (see block-splitting comment above).
function P.Parse(text)
    local sections = {}
    local currentSection = nil

    local function flushSection()
        if currentSection then
            -- trim trailing blank lines
            while #currentSection.lines > 0 and currentSection.lines[#currentSection.lines]:match("^%s*$") do
                currentSection.lines[#currentSection.lines] = nil
            end
            sections[#sections + 1] = currentSection
        end
    end

    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local heading = line:match("^##%s*(.+)$")
        if heading then
            flushSection()
            local titleLower = heading:lower():gsub("^%s+", ""):gsub("%s+$", "")
            local kind = TITLE_TO_KIND[titleLower] or "LONG"
            currentSection = { kind = kind, title = heading, lines = {}, targets = {} }
        elseif currentSection then
            currentSection.lines[#currentSection.lines + 1] = line
        end
    end
    flushSection()

    -- Post-process TARGETS sections
    for _, sec in ipairs(sections) do
        if sec.kind == "TARGETS" then
            for _, ln in ipairs(sec.lines) do
                -- capture mob name and the rest (token list)
                local mob, tokenList = ln:match("^%s*(.-)%s*:%s*(.+)%s*$")
                if mob and mob ~= "" and tokenList then
                    for token in tokenList:gmatch("(rt%d+)") do
                        local idx = RT_TOKEN_TO_INDEX[token:lower()]
                        if idx then
                            sec.targets[#sec.targets + 1] = { mobName = mob, iconIndex = idx }
                        end
                    end
                end
            end
        end
    end

    -- Apply block-splitting when the document contains END_OF_BLOCK tokens.
    ApplyBlockSplitting(sections)

    return sections
end

-- Post-process all sections to populate .blocks when the document contains
-- at least one END_OF_BLOCK_TOKEN in any sendable section.
-- Sendable sections (SHORT, ASSIGNMENT, PERSONAL) get .blocks added.
-- LONG and TARGETS are untouched.
ApplyBlockSplitting = function(sections)
    -- First, check if ANY sendable section uses the token.
    local hasAny = false
    for _, sec in ipairs(sections) do
        if sec.kind == "SHORT" or sec.kind == "ASSIGNMENT" or sec.kind == "PERSONAL" then
            for _, ln in ipairs(sec.lines) do
                if ln:match("^%s*" .. P.END_OF_BLOCK_TOKEN:gsub("!", "%%!") .. "%s*$") then
                    hasAny = true
                    break
                end
            end
        end
        if hasAny then break end
    end

    if not hasAny then return end -- document-wide opt-in check

    -- Split each sendable section's .lines into .blocks.
    for _, sec in ipairs(sections) do
        if sec.kind == "SHORT" or sec.kind == "ASSIGNMENT" or sec.kind == "PERSONAL" then
            sec.blocks = {}
            local currentBlock = { lines = {} }
            for _, ln in ipairs(sec.lines) do
                if ln:match("^%s*" .. P.END_OF_BLOCK_TOKEN:gsub("!", "%%!") .. "%s*$") then
                    -- Token line itself is not included in any block's content.
                    -- Flush current block (even if empty — will be pruned below).
                    sec.blocks[#sec.blocks + 1] = currentBlock
                    currentBlock = { lines = {} }
                else
                    currentBlock.lines[#currentBlock.lines + 1] = ln
                end
            end
            -- Flush the trailing implicit block.
            sec.blocks[#sec.blocks + 1] = currentBlock

            -- Remove blocks that have no non-blank lines.
            local pruned = {}
            for _, blk in ipairs(sec.blocks) do
                local hasContent = false
                for _, ln in ipairs(blk.lines) do
                    if not ln:match("^%s*$") then
                        hasContent = true; break
                    end
                end
                if hasContent then pruned[#pruned + 1] = blk end
            end
            sec.blocks = pruned
        end
    end
end

-- Returns true if any section in the list has block data (i.e. the document
-- contained at least one END_OF_BLOCK_TOKEN in a sendable section).
function P.HasBlocks(sections)
    for _, sec in ipairs(sections) do
        if sec.blocks then return true end
    end
    return false
end

-- Collect all {{variable}} names from text.
function P.GetVariables(text)
    local vars = {}
    local seen = {}
    for var in text:gmatch(P.REGEX) do
        if not seen[var] then
            seen[var] = true
            vars[#vars + 1] = var
        end
    end
    return vars
end

-- Return the targets list from the TARGETS section, or {} if none.
function P.GetTargets(sections)
    for _, sec in ipairs(sections) do
        if sec.kind == "TARGETS" then
            return sec.targets
        end
    end
    return {}
end
