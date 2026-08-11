-- Template.lua
-- Substitutes {{variable}} placeholders in text using a provided values table.

PugRaidAssignmentsTemplate = {}
local T = PugRaidAssignmentsTemplate
local P = PugRaidAssignmentsParser
local regex = "{{%s*([%w_]+)%s*}}"

-- Replace all {{var}} occurrences in `text` with values[var].
-- Missing vars are left as-is.
function T.Render(text, values)
    return (text:gsub(regex, function(var)
        return values[var] or ("{{" .. var .. "}}")
    end))
end

-- Build outgoing messages for each section kind given sections and values.
-- Returns a list of { kind, text } where kind is "LONG","SHORT","ASSIGNMENT","PERSONAL","TARGETS"
-- PERSONAL entries have { kind="PERSONAL", target=varValue, text=renderedText }
--
-- skippedVars: optional set of { [varName] = true } for variables whose Skip
--   checkbox is checked in the Assign window.
--   • For SHORT/ASSIGNMENT sections: a skipped variable's placeholder is
--     substituted with "NOT FOUND!" so the raid sees a deliberately jarring
--     marker rather than a raw {{var}} token.
--   • For PERSONAL sections: any whisper line whose target resolves to a
--     skipped variable is dropped entirely (to avoid a "no player found" error
--     from SendChatMessage with a literal "NOT FOUND!" as the target). Any
--     OTHER {{var}} reference inside a whisper's message body (not just its
--     target) is also substituted with "NOT FOUND!" if skipped, matching
--     SHORT/ASSIGNMENT behavior for consistency.
--
-- Block-aware: if sections carry .blocks (from Parser.ApplyBlockSplitting),
-- each returned message also carries .blocks = { {lines={}}, ... } (or
-- .blocks = { {whispers={}}, ... } for PERSONAL) so the Presenter Bar can
-- send one block at a time.
function T.BuildMessages(sections, values, skippedVars)
    skippedVars = skippedVars or {}

    -- Build an effective values table where skipped vars render as "NOT FOUND!"
    -- for non-PERSONAL sections (and for whisper message bodies below).
    local skippedValues = setmetatable({}, {
        __index = function(_, k)
            if skippedVars[k] then return "NOT FOUND!" end
            return values[k]
        end
    })

    local messages = {}
    for _, sec in ipairs(sections) do
        if sec.kind == "LONG" or sec.kind == "SHORT" or sec.kind == "ASSIGNMENT" then
            local rendered = {}
            for _, ln in ipairs(sec.lines) do
                rendered[#rendered + 1] = T.Render(ln, skippedValues)
            end
            local msg = { kind = sec.kind, lines = rendered }
            -- Propagate block structure if present.
            if sec.blocks then
                msg.blocks = {}
                for _, blk in ipairs(sec.blocks) do
                    local blkLines = {}
                    for _, ln in ipairs(blk.lines) do
                        blkLines[#blkLines + 1] = T.Render(ln, skippedValues)
                    end
                    msg.blocks[#msg.blocks + 1] = { lines = blkLines }
                end
            end
            messages[#messages + 1] = msg
        elseif sec.kind == "PERSONAL" then
            -- Each line: "{{PlayerVar}}: message text" or "PlayerName: message text"
            -- Collect whispers in block-aware fashion if blocks are present.
            local allWhispers = {}
            for _, ln in ipairs(sec.lines) do
                local target, msg = ln:match("^%s*(.-)%s*:%s*(.+)%s*$")
                if target and msg then
                    -- Check if this line's target variable is skipped.
                    -- Use the shared PugRaidAssignmentsParser regex so
                    -- "{{ tank3 }}" (with internal whitespace, as authors
                    -- commonly write it) is recognized the same way
                    -- everywhere else in the codebase.
                    local rawVar = target:match(P.REGEX)
                    if rawVar and skippedVars[rawVar] then
                        -- Omit: do not whisper a "NOT FOUND!" target.
                    else
                        local resolvedTarget = T.Render(target, skippedValues)
                        local resolvedMsg    = T.Render(msg, skippedValues)
                        allWhispers[#allWhispers + 1] = { kind = "PERSONAL", target = resolvedTarget, text = resolvedMsg }
                    end
                end
            end
            -- Add individual whisper messages to the output.
            for _, w in ipairs(allWhispers) do
                messages[#messages + 1] = w
            end

            -- Also propagate block structure for PERSONAL if present.
            if sec.blocks then
                -- Build a block-level whisper grouping message (used by Presenter Bar).
                -- We emit a synthetic "PERSONAL_BLOCK_GROUP" so the bar knows which
                -- whispers belong to which block.  The individual messages above are
                -- used by the non-presenter send path; the block group is only used
                -- by the presenter path.
                local blockGroups = {}
                for _, blk in ipairs(sec.blocks) do
                    local blkWhispers = {}
                    for _, ln in ipairs(blk.lines) do
                        local target, msg = ln:match("^%s*(.-)%s*:%s*(.+)%s*$")
                        if target and msg then
                            local rawVar = target:match(P.REGEX)
                            if not (rawVar and skippedVars[rawVar]) then
                                local rt = T.Render(target, skippedValues)
                                local rm = T.Render(msg, skippedValues)
                                blkWhispers[#blkWhispers + 1] = { kind = "PERSONAL", target = rt, text = rm }
                            end
                        end
                    end
                    blockGroups[#blockGroups + 1] = { whispers = blkWhispers }
                end
                messages[#messages + 1] = { kind = "PERSONAL_BLOCK_GROUP", blocks = blockGroups }
            end
        end
        -- TARGETS sections are not broadcast as chat messages
    end
    return messages
end