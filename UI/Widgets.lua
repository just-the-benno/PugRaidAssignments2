-- UI/Widgets.lua
-- Shared widget factories used across all UI windows.

PugRaidAssignmentsWidgets = {}
local W = PugRaidAssignmentsWidgets

-- ── Checkbox ─────────────────────────────────────────────────────────────────
-- Template requires a unique global name for each CheckButton.
local _checkboxCounter = 0

function W.MakeCheckbox(parent, labelText)
    _checkboxCounter = _checkboxCounter + 1
    local name = "PugRaidCB_" .. _checkboxCounter
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    -- _G[name .. "Text"] is set by the template; assign label
    local label = _G[name .. "Text"]
    if label then label:SetText(labelText or "") end
    return cb
end

-- ── EditBox ───────────────────────────────────────────────────────────────────
-- Returns editBox, bgFrame.  Always anchor bgFrame, never editBox.
function W.MakeEditBox(parent, width, height, multiline)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(width or 300, height or 24)
    bg:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.6)
    bg:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)


    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetMultiLine(multiline)
    eb:SetAutoFocus(false)
    eb:EnableMouse(true)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)

    if multiline then
        local sf = CreateFrame("ScrollFrame", nil, bg, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -20, 4)
        eb:SetParent(sf)
        eb:SetSize(width - 10, height)
        eb:SetFontObject(ChatFontNormal)
        sf:SetScrollChild(eb)
        eb.scrollFrame = sf
    else
        eb:SetPoint("LEFT", bg, "LEFT", 4, 0)
        eb:SetPoint("RIGHT", bg, "RIGHT", -4, 0)
        eb:SetSize(width, height)
        eb:SetFontObject(GameFontNormal)
    end
    return eb, bg
end

-- ── Button helper ─────────────────────────────────────────────────────────────
function W.MakeButton(parent, label, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 80, height or 22)
    btn:SetText(label)
    return btn
end

-- ── Dropdown (lazy-load Blizzard_UIDropDownMenu) ──────────────────────────────
local _sharedDropdownFrame = nil

local function EnsureDropdown()
    if not _sharedDropdownFrame then
        if C_AddOns then
            C_AddOns.LoadAddOn("Blizzard_UIDropDownMenu")
        elseif UIParentLoadAddOn then
            UIParentLoadAddOn("Blizzard_UIDropDownMenu")
        end
        _sharedDropdownFrame = CreateFrame("Frame", "PugRaidSharedDropdown", UIParent, "UIDropDownMenuTemplate")
    end
    return _sharedDropdownFrame
end

-- Open a simple dropdown list at (anchorFrame).
-- items: { { text, value } }
-- onSelect: function(value, text)
function W.OpenDropdown(anchorFrame, items, onSelect)
    local dd = EnsureDropdown()
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = item.text
            info.value = item.value
            info.func  = function(btn)
                onSelect(btn.value, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, dd, anchorFrame, 0, 0)
end

-- ── Titled window frame ───────────────────────────────────────────────────────
function W.MakeWindow(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(width or 500, height or 400)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:Hide()
    if f.TitleText then f.TitleText:SetText(title) end
    return f
end

-- ── Scroll pane helper ────────────────────────────────────────────────────────
-- Returns (scrollFrame, content) where content is a plain Frame you put children on.
function W.MakeScrollPane(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(width, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(width - 20)
    content:SetHeight(1) -- grows dynamically
    sf:SetScrollChild(content)
    return sf, content
end
