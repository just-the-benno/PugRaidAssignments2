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

-- Map from section title keywords to kinds
local TITLE_TO_KIND = {
    ["long"]        = "LONG",
    ["overview"]    = "LONG",
    ["short"]       = "SHORT",
    ["assignment"]  = "ASSIGNMENT",
    ["assignments"] = "ASSIGNMENT",
    ["personal"]    = "PERSONAL",
    ["targets"]     = "TARGETS",
    ["target"]      = "TARGETS",
}

-- Map rt<N> token to SetRaidTarget numeric index.
-- Star=1, Circle=2, Diamond=3, Triangle=4, Moon=5, Square=6, Cross=7, Skull=8
local RT_TOKEN_TO_INDEX = {
    rt1 = 1, rt2 = 2, rt3 = 3, rt4 = 4,
    rt5 = 5, rt6 = 6, rt7 = 7, rt8 = 8,
}

-- Icon index to display name (for UI labels)
P.ICON_NAMES = {
    [1] = "Star",    [2] = "Circle",   [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon",    [6] = "Square",   [7] = "Cross",   [8] = "Skull",
}

-- Parse `text` into a list of sections.
-- Returns: { { kind, title, lines = {string,...} }, ... }
-- TARGETS sections additionally have .targets = { {mobName, iconIndex}, ... }
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
                -- Format: "MobName: rt<N>"  (whitespace-forgiving)
                local mob, token = ln:match("^%s*(.-)%s*:%s*(rt%d+)%s*$")
                if mob and mob ~= "" and token then
                    local idx = RT_TOKEN_TO_INDEX[token:lower()]
                    if idx then
                        sec.targets[#sec.targets + 1] = { mobName = mob, iconIndex = idx }
                    end
                end
            end
        end
    end

    return sections
end

-- Collect all {{variable}} names from text.
function P.GetVariables(text)
    local vars = {}
    local seen = {}
    for var in text:gmatch("{{(%w+)}}") do
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
