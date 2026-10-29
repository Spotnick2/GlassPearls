-- Pearls/MarkWheelFrame.lua: the raid mark wheel's art, its animations and its
-- Configuration Panel (#34). The logic, and the secure button that takes the
-- click, are Pearls/MarkWheel.lua.
--
-- The art is an ordinary frame of ours, never a parent or an anchor of the
-- secure button, so it never becomes protected: it can animate, and finish
-- fading after combat starts. Everything in it is click-through. It sits in
-- UISpecialFrames, so Esc hides it, and hiding it ends the wheel.
--
-- WoW Forever's look: the gamepad radial menu's art (Blizzard_Gamepad,
-- GamepadRadial.xml), the highlight placed and turned as Blizzard does
-- (GamepadRadial.lua:1111). Glass, only while following Glass UI: a LibGlass
-- disc with the highlight in the suite's accent. An atlas is used only when
-- the client has it (C_Texture.GetAtlasInfo, as Blizzard's CheckSetAtlas
-- does); without one, a plain disc and lines, never a bare frame.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.MarkWheelFrame = Frame

Frame.NAME = "GlassPearlsMarkWheel"
Frame.ATLAS = {
    wheel = "gamepad-radial-menu-wheelbg",
    selected = "gamepad-radial-menu-selected",
    label = "gamepad-radial-menu-bottomtext",
    clear = "Radial_Wheel_Icon_Close",          -- the centre of Blizzard's ping wheel
}
Frame.ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
Frame.CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
Frame.MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Frame.NATIVE = 400               -- the wheel atlas's width when the client gives none
Frame.HIGHLIGHT_DISTANCE = 150   -- GamepadRadial.lua:4, in the atlas's own pixels
Frame.ROTATION_CORRECTION = 270  -- GamepadRadial.lua:1
Frame.ICON_SIZE = 40
Frame.OPEN, Frame.CLOSE = 0.15, 0.12
-- English only when the client's RAID_TARGET_<i> can't be read.
Frame.NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
Frame.CLEAR = "Clear"

local f            -- built on first open
local token = 0    -- one per open; a close animation hides only its own

local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function atlasInfo(name)
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if ok and not API.IsSecret(info) and type(info) == "table" then return info end
end

-- SetAtlas returns nothing: ask the client first.
local function setAtlas(tex, name)
    if not atlasInfo(name) then return false end
    tex:SetAtlas(name)
    return true
end
Frame.SetAtlas = setAtlas

function Frame.MarkName(i)
    local v = rawget(_G, "RAID_TARGET_" .. i)
    if not API.IsSecret(v) and type(v) == "string" and v ~= "" then return v end
    return Frame.NAMES[i]
end

-- Segment g's highlight: its rotation (radians) and offset from the centre,
-- with the art scaled by k. GamepadRadial.lua:1111-1117.
function Frame.Geometry(g, k)
    local degrees = (g - 1) * 45
    local d = Frame.HIGHLIGHT_DISTANCE * k
    return math.rad(degrees - Frame.ROTATION_CORRECTION), d * math.cos(math.rad(degrees)), d * math.sin(math.rad(degrees))
end

-- The art's segment that shows marker i.
local function segmentOf(i)
    for g, m in ipairs(GP.MarkWheel.MARKERS) do
        if m == i then return g end
    end
end

local function circle(host, tex)
    local mask = host:CreateMaskTexture()
    mask:SetTexture(Frame.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    return mask
end

-- Lines between the segments, from the centre ring to the rim.
local function dividers(host, r, g, b, a)
    local M = GP.MarkWheel
    for i = 1, 8 do
        local angle = math.rad((i - 1) * 45 + 22.5)
        local c, s = math.cos(angle), math.sin(angle)
        local line = host:CreateLine(nil, "ARTWORK")
        line:SetThickness(1.5)
        line:SetColorTexture(r, g, b, a)
        line:SetStartPoint("CENTER", host, M.R_CLEAR * c, M.R_CLEAR * s)
        line:SetEndPoint("CENTER", host, (M.R_OUTER - 3) * c, (M.R_OUTER - 3) * s)
    end
end

local function buildForever(D)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    if setAtlas(bg, Frame.ATLAS.wheel) then
        f.art = "atlas"
    else
        f.art = "plain"
        bg:SetColorTexture(0.06, 0.05, 0.04, 0.92)
        circle(f, bg)
        dividers(f, 0.85, 0.68, 0.3, 0.7)
    end
    f.bg = bg
    local hl = f:CreateTexture(nil, "BORDER")
    if setAtlas(hl, Frame.ATLAS.selected) then
        local info = atlasInfo(Frame.ATLAS.selected)
        hl:SetSize((plainNumber(info.width) or 160) * f.k, (plainNumber(info.height) or 160) * f.k)
        f.highlight = hl
    end
    hl:Hide()
end

local function buildGlass(D)
    local G = GP.Theme.Glass()
    local host = CreateFrame("Frame", nil, f)
    host:SetSize(D, D)
    host:SetPoint("CENTER", f, "CENTER")
    local g = G.Disc(host, "disc")
    f.glass, f.art = g, "glass"
    dividers(f, 1, 1, 1, 0.28)
    local hl = f:CreateTexture(nil, "BORDER")
    if setAtlas(hl, Frame.ATLAS.selected) then
        local info = atlasInfo(Frame.ATLAS.selected)
        hl:SetSize((plainNumber(info.width) or 160) * f.k, (plainNumber(info.height) or 160) * f.k)
        hl:SetDesaturated(true)
        local r, gg, b = GP.Theme.AccentRGB()
        if r then hl:SetVertexColor(r, gg, b, 0.85) else hl:SetVertexColor(1, 1, 1, 0.6) end
        if g.mask then hl:AddMaskTexture(g.mask) end
        f.highlight = hl
    end
    hl:Hide()
end

local function animation(scaleFrom, scaleTo, alphaFrom, alphaTo, duration, smoothing)
    local ag = f:CreateAnimationGroup()
    local s = ag:CreateAnimation("Scale")
    s:SetScaleFrom(scaleFrom, scaleFrom)
    s:SetScaleTo(scaleTo, scaleTo)
    s:SetDuration(duration)
    s:SetSmoothing(smoothing)
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(alphaFrom)
    a:SetToAlpha(alphaTo)
    a:SetDuration(duration)
    a:SetSmoothing(smoothing)
    return ag
end

local function onUpdate()
    if f.closingNow then return end
    local M = GP.MarkWheel
    local dx, dy = M.Offset()
    local choice = dx and M.Choice(dx, dy)
    Frame.Hover(choice ~= "outside" and choice or nil)
end

local function build()
    local M = GP.MarkWheel
    local D = M.R_OUTER * 2
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(D, D)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(20)
    f:EnableMouse(false)
    f:Hide()
    table.insert(UISpecialFrames, Frame.NAME)
    f:SetScript("OnHide", function() GP.MarkWheel.OnArtHidden() end)
    local info = atlasInfo(Frame.ATLAS.wheel)
    f.k = D / (info and plainNumber(info.width) or Frame.NATIVE)
    f.look = (GP.Theme.Active() == "glass" and GP.Theme.Glass()) and "glass" or "forever"
    if f.look == "glass" then buildGlass(D) else buildForever(D) end

    -- The centre: Clear.
    local centre = f:CreateTexture(nil, "BORDER", nil, 1)
    centre:SetSize(M.R_CLEAR * 2, M.R_CLEAR * 2)
    centre:SetPoint("CENTER", f, "CENTER")
    centre:SetColorTexture(0, 0, 0, f.look == "glass" and 0.3 or 0.55)
    circle(f, centre)
    local clear = f:CreateTexture(nil, "ARTWORK")
    clear:SetSize(26, 26)
    clear:SetPoint("CENTER", f, "CENTER", 0, 7)
    if not setAtlas(clear, Frame.ATLAS.clear) then clear:SetTexture(Frame.CLEAR_ICON) end
    local clearText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clearText:SetPoint("TOP", clear, "BOTTOM", 0, -1)
    clearText:SetText(Frame.CLEAR)
    f.clear, f.clearText = clear, clearText

    -- The unit's current mark, ringed.
    local current = f:CreateTexture(nil, "BORDER", nil, 2)
    current:SetSize(Frame.ICON_SIZE + 14, Frame.ICON_SIZE + 14)
    current:SetColorTexture(1, 0.82, 0.2, 0.35)
    circle(f, current)
    current:Hide()
    f.current = current

    -- The marks.
    f.icons = {}
    for g, marker in ipairs(M.MARKERS) do
        local _, x, y = Frame.Geometry(g, f.k)
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(Frame.ICON_SIZE, Frame.ICON_SIZE)
        icon:SetPoint("CENTER", f, "CENTER", x, y)
        icon:SetTexture(Frame.ICON .. marker)
        icon.x, icon.y = x, y
        f.icons[marker] = icon
    end

    -- The label under the wheel: the hovered mark, and the unit.
    local label = CreateFrame("Frame", nil, f)
    label:SetSize(220, 52)
    label:SetPoint("TOP", f, "BOTTOM", 0, -6)
    label:EnableMouse(false)
    local labelArt = label:CreateTexture(nil, "BACKGROUND")
    labelArt:SetAllPoints(label)
    if f.look == "forever" and setAtlas(labelArt, Frame.ATLAS.label) then
        label.art = "atlas"
    else
        labelArt:Hide()
        label.art = GP.Theme.Window(label, { header = 0 })
    end
    label.name = label:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label.name:SetPoint("TOP", label, "TOP", 0, -9)
    label.unit = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label.unit:SetPoint("TOP", label.name, "BOTTOM", 0, -3)
    f.label = label

    f.opening = animation(0.7, 1, 0, 1, Frame.OPEN, "OUT")
    f.closing = animation(1, 0.85, 1, 0, Frame.CLOSE, "IN")
    f.closing:SetScript("OnFinished", function(ag)
        if ag.token == token then f:Hide() end
    end)
    f:SetScript("OnUpdate", onUpdate)
end

-- What the cursor is on: a marker, 0 (Clear) or nil.
function Frame.Hover(choice)
    if not f or choice == f.hover then return end
    f.hover = choice
    for marker, icon in pairs(f.icons) do
        local size = marker == choice and Frame.ICON_SIZE + 8 or Frame.ICON_SIZE
        icon:SetSize(size, size)
    end
    local hl = f.highlight
    if type(choice) == "number" and choice > 0 then
        if hl then
            local rotation, x, y = Frame.Geometry(segmentOf(choice), f.k)
            hl:ClearAllPoints()
            hl:SetPoint("CENTER", f, "CENTER", x, y)
            hl:SetRotation(rotation)
            hl:Show()
        end
        f.label.name:SetText(Frame.MarkName(choice))
    else
        if hl then hl:Hide() end
        f.label.name:SetText(choice == 0 and Frame.CLEAR or "")
    end
end

-- Open at (x, y), UIParent's bottom-left coordinates, on session `s`.
function Frame.Open(x, y, s)
    if not f then build() end
    token = token + 1
    f.closing:Stop()
    f.opening:Stop()
    f.closingNow = false
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    local ok, idx = pcall(GetRaidTargetIndex, s.token)
    idx = ok and plainNumber(idx)
    local icon = idx and f.icons[idx]
    if icon then
        f.current:ClearAllPoints()
        f.current:SetPoint("CENTER", f, "CENTER", icon.x, icon.y)
        f.current:Show()
    else
        f.current:Hide()
    end
    f.currentMark = icon and idx or nil
    local okName, name = pcall(UnitName, s.token)
    f.label.unit:SetText((okName and not API.IsSecret(name) and type(name) == "string") and name or "")
    f.hover = false
    Frame.Hover(nil)
    f:SetAlpha(1)
    f:Show()
    f.opening:Play()
end

-- Fade out, then hide (the secure button is already gone).
function Frame.Close()
    if not (f and f:IsShown()) or f.closingNow then return end
    f.closingNow = true
    f.opening:Stop()
    f.closing.token = token
    f.closing:Play()
end

function Frame.IsShown() return f ~= nil and f:IsShown() end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local KEY, P, M = "markwheel", GP.Pearls, GP.MarkWheel
    local head = GP.UI.Header(panel, "Raid marks at your cursor")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local key = GP.UI.Label(panel, "")
    key:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    key:SetWidth(380)
    key:SetWordWrap(true)
    refreshers[#refreshers + 1] = function()
        local k = M.BindingText()
        key:SetText(k and ("Key: " .. k)
            or "No key yet: Esc > Options > Key Bindings > Glass Pearls > Raid mark wheel.")
    end
    local menu, refresh = GP.UI.Check(panel, "Add it to units' right-click menus",
        function() return P.Setting(KEY, "menu") end, function(on) P.SetSetting(KEY, "menu", on) end,
        { tip = "A Raid mark wheel entry in the menu of yourself, your target, focus, group members and pets." })
    menu:SetPoint("TOPLEFT", key, "BOTTOMLEFT", -4, -8)
    refreshers[#refreshers + 1] = refresh
    local test = GP.UI.Button(panel, "Test", 90, function() M.Test() end)
    test:SetPoint("TOPLEFT", menu, "BOTTOMLEFT", 4, -12)
    GP.UI.Tooltip(test, "Open the wheel on yourself", "Click a mark to set it on yourself, the centre to clear it.")
    local note = GP.UI.Label(panel,
        "Pings are the game's own: its Ping key, in Key Bindings. The wheel opens out of combat only; in a raid, "
            .. "only the leader or an assistant can set marks. Unverified until the game is live.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
    panel.test, panel.key = test, key
end

Frame._test = { frame = function() return f end }
