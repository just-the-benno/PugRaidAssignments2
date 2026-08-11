-- Template.lua
-- Substitutes {{variable}} placeholders in text using a provided values table.

PugRaidAssignmentsTemplate = {}
local T = PugRaidAssignmentsTemplate
local regex ="{{%s*([%w_]+)%s*}}"

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
function T.BuildMessages(sections, values)
    local messages = {}
    for _, sec in ipairs(sections) do
        if sec.kind == "LONG" or sec.kind == "SHORT" or sec.kind == "ASSIGNMENT" then
            local rendered = {}
            for _, ln in ipairs(sec.lines) do
                rendered[#rendered + 1] = T.Render(ln, values)
            end
            messages[#messages + 1] = { kind = sec.kind, lines = rendered }
        elseif sec.kind == "PERSONAL" then
            -- Each line: "{{PlayerVar}}: message text" or "PlayerName: message text"
            for _, ln in ipairs(sec.lines) do
                local target, msg = ln:match("^%s*(.-)%s*:%s*(.+)%s*$")
                if target and msg then
                    local resolvedTarget = T.Render(target, values)
                    local resolvedMsg    = T.Render(msg, values)
                    messages[#messages + 1] = { kind = "PERSONAL", target = resolvedTarget, text = resolvedMsg }
                end
            end
        end
        -- TARGETS sections are not broadcast as chat messages
    end
    return messages
end
