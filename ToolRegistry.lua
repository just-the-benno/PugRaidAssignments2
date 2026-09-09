-- ToolRegistry.lua
-- Central registry of all available raid tools

PugRaidAssignmentsToolRegistry = {}
local TR = PugRaidAssignmentsToolRegistry

TR.TOOLS = {
    ManaWatch = {
        name = "ManaWatch",
        type = "ManaWatch",
        defaults = {
            type = "ManaWatch",
            scanInterval = 150,
            redThreshold = 1200,
            amberThreshold = 2000,
            redMessage = "CRITICAL MANA",
            amberMessage = "Mana running low",
        }
    },
    HPWatcher = {
        name = "HP Watcher",
        type = "HPWatcher",
        defaults = {
            type = "HPWatcher",
            amberThreshold = 50,
            redThreshold = 25,
            countdownDuration = 3,
            preCountdownMessage = "Heal yourself. Spine in 3",
            finalMessage = "Throw",
            whisperMessage = "Heal yourself, inc dmg in 3 seconds",
        }
    }
}

function TR.GetAllToolTypes()
    local list = {}
    for _, tool in pairs(TR.TOOLS) do
        list[#list + 1] = tool
    end
    return list
end

function TR.GetToolDefaults(toolType)
    local tool = TR.TOOLS[toolType]
    return tool and tool.defaults or {}
end