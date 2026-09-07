-- Tools/ToolBase.lua
-- Base "class" that every raid tool inherits from. A tool is a lightweight
-- object, instantiated by ToolManager for the duration a document is
-- active, that can present a UI window and react to game events.
--
-- Lifecycle (driven entirely by ToolManager, see ToolManager.lua):
--   ToolClass.New()                  -- construct a fresh instance
--   instance:OnInit(config, sessionId, docId)
--                                     -- store config/state; no UI yet
--   instance:OnStart()               -- create/show the frame, register events
--   instance:OnStop()                -- hide the frame, unregister events
--   instance:OnConfigChanged(newConfig)
--                                     -- optional: react to a config edit
--                                     -- made while still in preparation
--   instance:GetFrame()              -- return the tool's main frame (used
--                                     -- for positioning/anchoring)
--
-- Before OnInit is called, ToolManager stamps the instance with:
--   self.toolId  -- the tool config's id (for S.SetToolConfig, etc.)
--   self.raidId  -- the owning raid's id
--   self.docId   -- the owning document's id (same as the docId argument)
--
-- To create a new tool type: build a table of functions, inherit from this
-- base via `setmetatable(YourTool, { __index = ToolBase })`, override what
-- you need, then call `PugRaidAssignmentsToolManager.RegisterToolType(...)`.
-- See Tools/ToolStub.lua for a full example.

PugRaidAssignmentsToolBase = {}
local ToolBase = PugRaidAssignmentsToolBase
ToolBase.__index = ToolBase

function ToolBase.New()
    return setmetatable({}, ToolBase)
end

function ToolBase:OnInit(config, sessionId, docId)
    self.config    = config or {}
    self.sessionId = sessionId
    self.docId     = docId
end

-- Override: create/show the frame, register for WoW events, etc.
function ToolBase:OnStart()
end

-- Override: hide the frame, unregister events, clean up.
function ToolBase:OnStop()
end

-- Override if the tool needs to react to a config edit made while the
-- document is being prepared (before OnStart runs during a raid).
function ToolBase:OnConfigChanged(newConfig)
    self.config = newConfig or self.config
end

-- Override: return the tool's main UI frame, or nil if it has none.
function ToolBase:GetFrame()
    return nil
end
