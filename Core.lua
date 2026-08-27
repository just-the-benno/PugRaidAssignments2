-- Core.lua
-- Addon entry point: event handling, slash commands, minimap button.

-- ── Keybinding globals ────────────────────────────────────────────────────────
-- These must be set as globals so the Key Bindings UI can read them.
BINDING_HEADER_PUGRAID2    = "Pug Raid Assignments 2"
BINDING_NAME_PUGRAIDTARGET = "Mark/Open Target Checklist"

-- Global function invoked by the PUGRAIDTARGET keybinding.
function PUGRAIDTARGET()
    PugRaidPlayerBar_OnTargetKey()
end

local ADDON_NAME = "PugRaidAssignments2"

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_LOGOUT")

coreFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        PugRaidAssignmentsStorage.Init()
        PugRaidAssignmentsCore_BuildMinimapButton()
        local active = PugRaidAssignmentsStorage.GetActiveSession()
        if active then
            PugRaidPlayerBar_Open()
        end

    elseif event == "PLAYER_LOGOUT" then
        -- Touch the active session so "lastSeenAt" is set (used as fallback end time)
        local sess = PugRaidAssignmentsStorage.GetActiveSession()
        if sess then
            PugRaidAssignmentsStorage.TouchSession(sess)
        end
    end
end)

-- ── Minimap button ────────────────────────────────────────────────────────────
local minimapButton

function PugRaidAssignmentsCore_BuildMinimapButton()
    if minimapButton then return end

    minimapButton = CreateFrame("Button", "PugRaidMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetMovable(true)
    minimapButton:EnableMouse(true)

    -- Icon
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture("Interface/Icons/INV_Misc_Note_01")

    -- Border ring to match minimap style
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("CENTER")
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")

    -- Position on minimap edge
    local angle = math.rad(220) -- degrees around minimap
    local radius = 80
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)

    -- Dragging around minimap
    local dragging = false
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function(self)
        dragging = true
        self:SetScript("OnUpdate", function()
            local cx, cy = Minimap:GetCenter()
            local mx, my = GetCursorPosition()
            local scale  = UIParent:GetEffectiveScale()
            mx, my = mx / scale, my / scale
            local newAngle = math.atan2(my - cy, mx - cx)
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER",
                math.cos(newAngle) * radius, math.sin(newAngle) * radius)
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    minimapButton:SetScript("OnClick", function(self, btn)
        if not dragging then
            PugRaidAssignmentsRaidListWindow_Toggle()
        end
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Raid Assignments", 1, 1, 1)
        GameTooltip:AddLine("Click to open/close", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── Slash commands ────────────────────────────────────────────────────────────
SLASH_PUGRAID1 = "/pugraid"
SLASH_PUGRAID2 = "/pra"

SlashCmdList["PUGRAID"] = function(msg)
    msg = msg:lower():match("^%s*(.-)%s*$")
    if msg == "bar" then
        if PugRaidPlayerBar_IsShown and PugRaidPlayerBar_IsShown() then
            PugRaidPlayerBar_Close()
        else
            PugRaidPlayerBar_Open()
        end
    else
        PugRaidAssignmentsRaidListWindow_Toggle()
    end
end
