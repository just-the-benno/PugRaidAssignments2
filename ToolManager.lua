-- ToolManager.lua
-- Orchestrates tool activation, deactivation, and lifecycle management as documents/sessions change.

PugRaidAssignmentsToolManager = {}
local TM = PugRaidAssignmentsToolManager
local S = PugRaidAssignmentsStorage

local activeTools = {}

-- Map tool type string to implementation class table
function TM.GetToolClass(toolType)
    if toolType == "ManaWatch" then
        return PugRaidAssignmentsToolManaWatch
    end
    if toolType == "HPWatcher" then
        return PugRaidAssignmentsToolHPWatcher
    end
    return nil
end

-- Start a tool with given config, sessionId, docId
function TM.StartTool(toolConfig, sessionId, docId)
    if not toolConfig or not toolConfig.type then return nil end
    local toolType = toolConfig.type

    -- If already running, stop it first
    TM.StopTool(toolType)

    local toolClass = TM.GetToolClass(toolType)
    if not toolClass then return nil end

    local tool = toolClass:New(toolConfig, sessionId, docId)
    tool:OnStart()
    activeTools[toolType] = tool
    return tool
end

-- Stop a specific running tool
function TM.StopTool(toolType)
    local tool = activeTools[toolType]
    if tool then
        tool:OnStop()
        activeTools[toolType] = nil
    end
end

-- Stop all currently running tools
function TM.StopAllTools()
    for toolType, tool in pairs(activeTools) do
        if tool and tool.OnStop then
            tool:OnStop()
        end
    end
    activeTools = {}
end

-- Retrieve a running tool instance by type
function TM.GetActiveTool(toolType)
    return activeTools[toolType]
end

-- Called when a document is activated in a session to start configured tools
-- sessionId: the current session ID
-- docId: the document ID to activate tools for
function TM.OnDocumentActivated(sessionId, docId)
    TM.StopAllTools()
    if not sessionId or not docId then return end

    local doc = nil
    local raidId = nil
    
    -- Find the raid and document by searching through all raids
    for _, raid in pairs(S.GetAllRaids()) do
        local d = S.GetDocument(raid.id, docId)
        if d then
            doc = d
            raidId = raid.id
            break
        end
    end
    
    if not doc or not doc.tools then return end

    for toolType, config in pairs(doc.tools) do
        TM.StartTool(config, sessionId, docId)
    end
end
