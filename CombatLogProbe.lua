-- CombatLogProbe.lua
-- TEMPORARY: Data-gathering probe for evaluating the combat log / auto-mark
-- approach for gauntlet waves (e.g. Mount Hyjal).
--
-- What this does:
--   1. Listens to COMBAT_LOG_EVENT_UNFILTERED and prints every event where
--      the *destination* is a hostile NPC. This lets us see:
--        - Which event subtypes fire when a wave mob appears
--        - destName (must match your target list entries exactly)
--        - destGUID (contains the NPC ID — key for GUID->unit resolution)
--        - Timing relative to the wave start
--
--   2. On each hostile-NPC event, immediately scans:
--        - UnitGUID("target") to see if the current target matches
--        - All nameplate units (nameplate1..40) to see if the GUID is
--          already visible on a nameplate and therefore addressable
--
-- HOW TO USE:
--   Load the addon normally. Trigger a Hyjal wave. After it ends (or during
--   it), copy everything from your chat log / WoW logs and paste it back.
--
-- DISABLING:
--   Either remove CombatLogProbe.lua from the .toc, or set
--   PUGRAID_PROBE_ENABLED = false before reloading the UI.
--
-- This file is intentionally NOT wired into any permanent addon state.
-- Delete / abandon this branch once data is gathered.

PUGRAID_PROBE_ENABLED = true

if not PUGRAID_PROBE_ENABLED then return end

local PREFIX = "|cff00ff99[PugRaidProbe]|r"

-- Throttle: only print a given destGUID once per event subtype to avoid
-- chat spam when the same mob generates dozens of SWING_DAMAGE lines.
local seen = {}  -- [subevent.."::"..destGUID] = true

local probeFrame = CreateFrame("Frame", "PugRaidCombatLogProbeFrame")
probeFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

probeFrame:SetScript("OnEvent", function(self, event)
    local timestamp, subevent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID,   destName,   destFlags,   destRaidFlags
        = CombatLogGetCurrentEventInfo()

    -- Only care about hostile units as destination
    if not destFlags then return end
    local isHostileNPC = bit.band(destFlags, COMBATLOG_OBJECT_TYPE_NPC) ~= 0
                      and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
    if not isHostileNPC then return end

    -- Throttle duplicate (subevent, GUID) pairs
    local key = subevent .. "::" .. (destGUID or "nil")
    if seen[key] then return end
    seen[key] = true

    -- ── 1. Print the raw combat log fields ──────────────────────────────────
    print(string.format("%s sub=%-30s  dName=%-25s  dGUID=%s",
        PREFIX, subevent, tostring(destName), tostring(destGUID)))

    -- ── 2. Check if current target matches ──────────────────────────────────
    local targetGUID = UnitGUID("target")
    local targetName = UnitName("target")
    if targetGUID == destGUID then
        print(string.format("%s   >> MATCH on 'target': name=%s guid=%s",
            PREFIX, tostring(targetName), tostring(targetGUID)))
    end

    -- ── 3. Scan nameplates for this GUID ────────────────────────────────────
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local npGUID = UnitGUID(unit)
            local npName = UnitName(unit)
            if npGUID == destGUID then
                print(string.format("%s   >> MATCH on nameplate%d: name=%s guid=%s",
                    PREFIX, i, tostring(npName), tostring(npGUID)))
            end
        end
    end
end)

print(PREFIX .. " Combat log probe loaded. Trigger a Hyjal wave to gather data.")
print(PREFIX .. " Set PUGRAID_PROBE_ENABLED = false and /reload to disable.")
