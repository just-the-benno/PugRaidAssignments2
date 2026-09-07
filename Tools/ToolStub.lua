-- Tools/ToolStub.lua
-- Minimal example tool, used to validate the tool infrastructure end-to-end
-- before any "real" tool (mana watch, health monitor, etc.) is built.
--
-- Behavior:
--   - Spawns a small, draggable window showing a label from its config.
--   - When dragged, the new position is saved back into the tool's config
--     (document-scoped, via Storage.lua) so it's restored next time.
--
-- Config shape: { label = "some text", pos = { point, relPoint, x, y } }

local S = PugRaidAssignmentsStorage
local W = PugRaidAssignmentsWidgets
local ToolBase = PugRaidAssignmentsToolBase

PugRaidAssignmentsToolStub = setmetatable({}, { __index = ToolBase })
local ToolStub = PugRaidAssignmentsToolStub
ToolStub.__index = ToolStub

function ToolStub.New()
    return setmetatable({}, ToolStub)
end

function ToolStub:OnStart()
    if not self.frame then
        self.frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        self.frame:SetSize(200, 60)
        self.frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        self.frame:SetBackdropColor(0, 0, 0, 0.85)
        self.frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        self.frame:SetMovable(true)
        self.frame:EnableMouse(true)
        self.frame:RegisterForDrag("LeftButton")
        self.frame:SetFrameStrata("MEDIUM")
        self.frame:SetToplevel(true)

        self.label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        self.label:SetPoint("CENTER", self.frame, "CENTER", 0, 0)

        self.frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
        self.frame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            local point, _, relPoint, x, y = f:GetPoint()
            self.config = self.config or {}
            self.config.pos = { point = point, relPoint = relPoint, x = x, y = y }
            S.SetToolConfig(self.raidId, self.docId, self.toolId, "ToolStub", self.config)
        end)
    end

    local pos = self.config and self.config.pos
    self.frame:ClearAllPoints()
    if pos then
        self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    self.label:SetText((self.config and self.config.label) or "Tool Stub")
    self.frame:Show()
end

function ToolStub:OnStop()
    if self.frame then self.frame:Hide() end
end

function ToolStub:OnConfigChanged(newConfig)
    self.config = newConfig or self.config
    if self.label then
        self.label:SetText((self.config and self.config.label) or "Tool Stub")
    end
end

function ToolStub:GetFrame()
    return self.frame
end

PugRaidAssignmentsToolManager.RegisterToolType("ToolStub", ToolStub)
