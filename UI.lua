-- UI.lua: the small widgets every GlassPearls page and pearl builds with (#3).
--
-- Blizzard's own templates and fonts in both looks (the Forever look is
-- exactly that; under glass only the window and surfaces change), titles in
-- the suite's accent while following Glass UI. Each control that shows a value
-- returns a `refresh` the page calls on every show, so a value changed
-- elsewhere (a slash command, a synced setting) is never shown stale.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local UI = {}
GP.UI = UI

-- Blizzard's gear button art (MenuVariants.GearButtonTexture, Blizzard_Menu).
UI.GEAR = "Interface\\WorldMap\\GEAR_64GREY"
local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

function UI.Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

-- A section or page title, in the suite's accent while following.
function UI.Header(parent, text, font)
    local fs = UI.Label(parent, text, font or "GameFontNormalLarge")
    GP.Theme.Accent(fs)
    return fs
end

-- Attach a hover tooltip: a title and an optional wrapped body.
function UI.Tooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if body and body ~= "" then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A plain Blizzard button.
function UI.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 120, 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- An on/off control: the template's box and our own label beside it.
-- get() and set(on) are the setting's; opts.tip (tooltip body), opts.title.
-- Returns the box and its refresh.
function UI.Check(parent, text, get, set, opts)
    opts = opts or {}
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local fs = UI.Label(parent, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label = fs
    local function refresh() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function()
        set(cb:GetChecked() == true)
        refresh()
        if opts.onChange then opts.onChange() end
    end)
    if opts.tip then UI.Tooltip(cb, opts.title or text, opts.tip) end
    return cb, refresh
end

-- A gear button that opens a pearl's configuration panel.
function UI.Gear(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b:SetNormalTexture(UI.GEAR)
    b:SetHighlightTexture(UI.GEAR)
    b:GetHighlightTexture():SetBlendMode("ADD")
    b:SetScript("OnClick", onClick)
    UI.Tooltip(b, "Click to configure the settings for this option.")
    return b
end

-- A labelled radio button: UIRadioButtonTemplate when the client has it (its
-- own label, rb.text), else the client's own radio art and a label of ours
-- (GlassMail's recipe).
local function radioButton(parent, text)
    local rb, templated = API.SafeFrame("CheckButton", parent, "UIRadioButtonTemplate", "text")
    if templated then
        rb.text:SetFontObject("GameFontHighlight")
        rb.text:SetText(text)
        return rb
    end
    rb:SetSize(16, 16)
    rb:SetNormalTexture(RADIO_ART)
    rb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
    rb:SetCheckedTexture(RADIO_ART)
    rb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
    rb:SetHighlightTexture(RADIO_ART)
    rb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    rb:GetHighlightTexture():SetBlendMode("ADD")
    local fs = UI.Label(parent, text)
    fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    rb.label = fs
    return rb
end

-- Mutually exclusive choices stacked under `anchor`: { {value, text}, ... }.
-- Returns the last button (to anchor what follows), the group and its refresh.
-- The whole group re-syncs after a click, so a refused choice snaps back.
function UI.Radios(parent, anchor, choices, get, set)
    local group = {}
    local function refresh()
        local current = get()
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
    end
    local prev = anchor
    for _, c in ipairs(choices) do
        local rb = radioButton(parent, c[2])
        rb.value = c[1]
        rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == anchor and 4 or 0, prev == anchor and -8 or -6)
        rb:SetScript("OnClick", function() set(c[1]); refresh() end)
        group[#group + 1] = rb
        prev = rb
    end
    return prev, group, refresh
end

-- The search box: SearchBoxTemplate (its clear button and instructions) when
-- the client has it, else a plain input box. onChange(text) on every edit.
function UI.Search(parent, width, instructions, onChange)
    local box, templated = API.SafeFrame("EditBox", parent, "SearchBoxTemplate", "Instructions")
    if not templated then
        box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        box:SetAutoFocus(false)
    elseif instructions then
        box.Instructions:SetText(instructions)
    end
    box:SetSize(width, 22)
    box:HookScript("OnTextChanged", function(self)
        local text = self:GetText()
        onChange(type(text) == "string" and text or "")
    end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end
