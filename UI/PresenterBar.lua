-- UI/PresenterBar.lua
-- Presenter Bar — appears when a document contains "!! END OF BLOCK !!" tokens
-- and the user clicks Send.  Lets the presenter step through blocks one at a
-- time rather than dumping everything at once.
--
-- Controls:
--   Play   — send the next block in the queue; advance the pointer forward.
--   Repeat — re-send the block at the current pointer (no pointer movement).
--   Back   — move the pointer back by one (clamp at block 1).
--   Eject  — send all remaining blocks immediately, then close the bar.
--   Cancel — close the bar immediately without sending anything further.
--   Label  — shows "Block N / Total" position indicator.
--
-- The bar closes automatically once Play advances past the last block or
-- Eject is triggered.  No SavedVariables state is stored for block position,
-- but the bar's on-screen POSITION is persisted (same pattern as PlayerBar's
-- playerBarPos) so it reopens in the same place next time.

local W = PugRaidAssignmentsWidgets
local D = PugRaidAssignmentsDispatcher

local presBar            -- the frame
local lblPos             -- "Block N / Total" label
local presQueue = {}     -- flat list of block items from D.BuildPresenterQueue
local presIndex = 0      -- current pointer (0 = nothing sent yet; 1 = first block sent)

-- ── Helpers ──────────────────────────────────────────────────────────────

local function UpdateLabel()
    if lblPos then
        if #presQueue == 0 then
            lblPos:SetText("Block - / -")
        else
            lblPos:SetText("Block " .. presIndex .. " / " .. #presQueue)
        end
    end
end

local function ClosePresenterBar()
    presQueue = {}
    presIndex = 0
    if presBar then presBar:Hide() end
end

-- ── Button handlers ────────────────────────────────────────────────────────

local function OnPlay()
    if #presQueue == 0 then return end
    local nextIndex = presIndex + 1
    if nextIndex > #presQueue then
        -- Already at the end; nothing more to send.
        ClosePresenterBar()
        return
    end
    presIndex = nextIndex
    D.SendBlock(presQueue[presIndex])
    UpdateLabel()
    if presIndex >= #presQueue then
        -- Sent the last block; close the bar.
        ClosePresenterBar()
    end
end

local function OnRepeat()
    if presIndex < 1 or presIndex > #presQueue then return end
    D.SendBlock(presQueue[presIndex])
    -- Pointer does not move.
end

local function OnBack()
    if presIndex <= 1 then return end -- clamp at start
    presIndex = presIndex - 1
    UpdateLabel()
    -- Back moves the pointer back so the *next* Play will re-send presIndex+1.
    -- It does not fire a send by itself.
end

local function OnEject()
    -- Send all remaining blocks (from presIndex+1 to end).
    for i = presIndex + 1, #presQueue do
        D.SendBlock(presQueue[i])
    end
    ClosePresenterBar()
end

local function OnCancel()
    ClosePresenterBar()
end

-- ── Build ────────────────────────────────────────────────────────────────

local function Build()
    presBar = CreateFrame("Frame", "PugRaidPresenterBar", UIParent, "BackdropTemplate")
    presBar:SetSize(500, 34)
    presBar:SetPoint("TOP", UIParent, "TOP", 0, -240)
    presBar:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 },
    })
    presBar:SetBackdropColor(0, 0.1, 0.2, 0.90)
    presBar:SetBackdropBorderColor(0.4, 0.6, 1.0, 1)
    presBar:SetMovable(true)
    presBar:EnableMouse(true)
    presBar:RegisterForDrag("LeftButton")
    presBar:SetScript("OnDragStart", presBar.StartMoving)
    presBar:SetFrameStrata("HIGH")
    presBar:SetToplevel(true)
    presBar:Hide()

    -- Restore saved position (same pattern as PlayerBar's playerBarPos).
    if PugRaidAssignmentsDB and PugRaidAssignmentsDB.presenterBarPos then
        local pos = PugRaidAssignmentsDB.presenterBarPos
        presBar:ClearAllPoints()
        presBar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    presBar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if PugRaidAssignmentsDB then
            PugRaidAssignmentsDB.presenterBarPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- NOTE: WoW's default UI font does not render most Unicode symbol
    -- glyphs (▶ ◀ ↺ ⏩ ✕ show up blank/missing in-game). Use plain ASCII
    -- button labels instead.
    local btnPlay = W.MakeButton(presBar, "Play", 60, 24)
    btnPlay:SetPoint("LEFT", presBar, "LEFT", 4, 0)
    btnPlay:SetScript("OnClick", OnPlay)

    local btnRepeat = W.MakeButton(presBar, "Repeat", 70, 24)
    btnRepeat:SetPoint("LEFT", btnPlay, "RIGHT", 4, 0)
    btnRepeat:SetScript("OnClick", OnRepeat)

    local btnBack = W.MakeButton(presBar, "Back", 60, 24)
    btnBack:SetPoint("LEFT", btnRepeat, "RIGHT", 4, 0)
    btnBack:SetScript("OnClick", OnBack)

    lblPos = presBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblPos:SetPoint("LEFT", btnBack, "RIGHT", 10, 0)
    lblPos:SetWidth(100)
    lblPos:SetText("Block - / -")

    local btnEject = W.MakeButton(presBar, "Eject", 60, 24)
    btnEject:SetPoint("LEFT", lblPos, "RIGHT", 10, 0)
    btnEject:SetScript("OnClick", OnEject)

    local btnCancel = W.MakeButton(presBar, "Cancel", 70, 24)
    btnCancel:SetPoint("LEFT", btnEject, "RIGHT", 4, 0)
    btnCancel:SetScript("OnClick", OnCancel)
end

-- ── Public API ──────────────────────────────────────────────────────────

-- Open the Presenter Bar with a block queue from D.BuildPresenterQueue.
-- If the queue is empty (no blocks to send) the bar is not shown.
function PugRaidPresenterBar_Open(queue)
    if not queue or #queue == 0 then return end
    if not presBar then Build() end

    presQueue = queue
    presIndex = 0  -- nothing sent yet; first Play will send block 1
    UpdateLabel()
    presBar:Show()
    presBar:Raise()

    print("|cffffff00PugRaid Presenter:|r " .. #presQueue .. " block(s) queued. Click Play to begin.")
end

function PugRaidPresenterBar_Close()
    ClosePresenterBar()
end