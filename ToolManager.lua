-- ToolManager.lua
-- Orchestrates the lifecycle of raid tools: keeps a registry of available
-- tool types, and spawns/closes tool instances as the active document
-- changes.
--
-- A "tool type" is a class table (see Tools/ToolBase.lua) registered under a
-- string name (e.g. "ToolStub"). A "tool config" is the per-document, saved
-- configuration created via Storage.lua (S.SetToolConfig / S.GetAllTools).
--
-- Lifecycle:
--   Session starts / first document becomes active
--     -> ActivateToolsForDocument(raidId, docId, sessionId)
--   Player switches documents
--     -> DeactivateAllTools() then ActivateToolsForDocument(...) for the new doc
--   Session ends
--     -> DeactivateAllTools()
--
-- Tools never talk to each other; ToolManager only manages their lifecycle.

PugRaidAssignmentsToolManager = {}
local TM = PugRaidAssignmentsToolManager
local S = PugRaidAssignmentsStorage

local toolTypes   = {} -- [toolTypeName] = toolClass
local activeTools = {} -- [toolId] = toolInstance
local activeRaidId, activeDocId

-- Registers a tool type (class) under a name so ToolManager can instantiate
-- it whenever a document has a tool config of that type. Call this once per
-- tool type, at load time (see Tools/ToolStub.lua for an example).
function TM.RegisterToolType(name, toolClass)
    toolTypes[name] = toolClass
end

-- Stops and discards every currently active tool instance. Safe to call
-- when nothing is active.
function TM.DeactivateAllTools()
    for _, instance in pairs(activeTools) do
        if instance.OnStop then instance:OnStop() end
    end
    activeTools   = {}
    activeRaidId  = nil
    activeDocId   = nil
end

-- Closes any currently active tools, then spawns one instance per tool
-- config found on the given document. Gracefully does nothing if the
-- document has no tools configured (or doesn't exist).
function TM.ActivateToolsForDocument(raidId, docId, sessionId)
    TM.DeactivateAllTools()
    if not raidId or not docId then return end

    local tools = S.GetAllTools(raidId, docId)
    for toolId, toolCfg in pairs(tools) do
        local toolClass = toolTypes[toolCfg.toolType]
        if toolClass and toolClass.New then
            local instance = toolClass.New()
            instance.toolId = toolId
            instance.raidId = raidId
            instance.docId  = docId
            instance:OnInit(toolCfg.config, sessionId, docId)
            instance:OnStart()
            activeTools[toolId] = instance
        end
    end

    activeRaidId = raidId
    activeDocId  = docId
end

-- Returns the live instance for a given tool id, or nil if it isn't active.
function TM.GetActiveTool(toolId)
    return activeTools[toolId]
end
