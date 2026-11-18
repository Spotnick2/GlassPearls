-- Core/Compass.lua: the compass ring any pearl points with (#93, shared by
-- #139). A ring under the character points at one target: NodeRadar's
-- compass (its Compass.lua and art, MIT, the same owner): the lens with an
-- icon or a label, the rim (bronze in WoW Forever's look, pearl under Glass
-- UI), an arrow outside the rim with an arc beneath it, the distance in a
-- capsule below, a tooltip on hover (mouse motion only: clicks reach the
-- world), Alt-drag to move (saved per character), clamped to the screen.
--
-- Owners: a pearl registers once (`Register(owner, spec)`) and asks for the
-- ring (`Want`) or stops asking (`Drop`, which touches only its own request).
-- The ring shows the highest-priority owner with a request, even while that
-- owner's own frame keeps it hidden (a hidden owner reserves the ring: never
-- a lower one's stale target flashing in). `Changed(owner)` re-dresses the
-- icon, label and tooltip on the next frame, never synchronously.
--
-- spec = { priority, Point(continent, north, west) -> the target's north, west | nil (given the player's), Icon() -> texture
-- | nil, Label() -> text | nil, Tooltip(tooltip) (sets its lines; false: no
-- tooltip), Hidden() -> bool, near?, Arrive()? }. Only an owner with `near`
-- arrives in the ring: within it, `Arrive()` is called once and the frame
-- returns. An owner without (a route) is drawn at any distance and advances
-- on its own.
--
-- NodeRadar measured on 70450: GetPlayerFacing is counter-clockwise from
-- north, 0 to 2pi; a point's bearing from (north, west) is atan2(-east,
-- north); an arrow at bearing - facing points true. HereBeDragons' world
-- position is (west, north, continent).
--
-- Built on its first show. Its OnUpdate runs only while shown: each frame it
-- hides at once (the owner hidden, a read failing, another continent);
-- the owner's own ticker asks again (`Want`), which shows it again.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local C = {}
GP.Compass = C

C.MEDIA = "Interface\\AddOns\\GlassPearls\\Media\\"
C.DISC = 52            -- NodeRadar's medium diameter
C.ICON = 0.58          -- the icon, a share of the diameter
C.ARROW = 16
-- CompassArrow's art: the apex 0.375 of its size above its centre, the base 0.3125 below; the base 1 unit
-- outside the rim.
C.ORBIT = C.DISC / 2 + 1 + 0.3125 * C.ARROW
C.REACH = C.ORBIT + 0.375 * C.ARROW
C.PILL_TOP = C.REACH + 3
C.PILL = { 56, 18 }
C.FOOT = C.PILL_TOP + C.PILL[2]
C.HOME = { 0, -160 }   -- under the character
C.TINTS = { forever = { 0.80, 0.62, 0.38 }, glass = { 0.97, 0.97, 1 } }   -- bronze, pearl
-- The saved spot keeps the books' key (#93): renaming it would lose every placement.
C.SAVE_KEY = "booksCompass"

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAU = 2 * math.pi

local root, body, disc, icon, label, rim, arc, arrow, text, hit, grip
local specs, wanted = {}, {}
local shownOwner              -- the owner the ring is dressed for
local dirty = {}              -- [owner] = true: re-dress on the next frame
local shownDist
local dragging = false

local function num(v)
    if API.IsSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
C.Num = num
local function wrap(a) return (a + math.pi) % TAU - math.pi end
C.Wrap = wrap

local function facing()
    local ok, f = pcall(GetPlayerFacing)
    return ok and num(f) or nil
end
C.Facing = facing

local function lib(name)
    local stub = rawget(_G, "LibStub")
    return stub and stub(name, true)
end

-- The player's world position: continent, north, west; nil when unreadable.
function C.Position()
    local HBD = lib("HereBeDragons-2.0")
    if not (HBD and HBD.GetPlayerWorldPosition) then return nil end
    local ok, west, north, continent = pcall(HBD.GetPlayerWorldPosition, HBD)
    if not ok then return nil end
    west, north, continent = num(west), num(north), num(continent)
    if not (west and north and continent) then return nil end
    return continent, north, west
end

-- The angle of an arrow pointing from (north, west) to (tn, tw), counter-
-- clockwise from straight ahead for a facing f.
function C.Angle(north, west, tn, tw, f)
    local dn, east = tn - north, -(tw - west)
    return wrap(math.atan2(-east, dn) - f)
end

local function saved()
    local c = GP.charDB
    local s = type(c) == "table" and c[C.SAVE_KEY]
    return type(s) == "table" and s or nil
end

--------------------------------------------------------------------------------
-- Owners

function C.Register(owner, spec)
    specs[owner] = spec
end

local function top()
    local best, bestP
    for owner in pairs(wanted) do
        local p = specs[owner] and specs[owner].priority or 0
        if not best or p > bestP then best, bestP = owner, p end
    end
    return best
end
C.Top = top

--------------------------------------------------------------------------------
-- Moving it

-- An offset from UIParent's centre keeping the whole footprint on UIParent.
local function clamp(x, y)
    local w, h = num(UIParent:GetWidth()), num(UIParent:GetHeight())
    if not (w and h) then return x, y end
    return math.max(-w / 2 + C.REACH, math.min(w / 2 - C.REACH, x)),
        math.max(-h / 2 + C.FOOT, math.min(h / 2 - C.REACH, y))
end

local function place()
    if dragging or not root then return end
    local s = saved()
    local x, y = s and num(s.x), s and num(s.y)
    if not (x and y) then x, y = C.HOME[1], C.HOME[2] end
    x, y = clamp(x, y)
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
C.Place = place

-- A drag ends: its spot read, clamped, saved, placed. Idempotent (the grip's OnHide too).
local function stopDrag()
    if not dragging then return end
    dragging = false
    root:StopMovingOrSizing()
    local rx, ry = root:GetCenter()
    local ux, uy = UIParent:GetCenter()
    rx, ry, ux, uy = num(rx), num(ry), num(ux), num(uy)
    if rx and ry and ux and uy and type(GP.charDB) == "table" then
        local x, y = clamp(rx - ux, ry - uy)
        GP.charDB[C.SAVE_KEY] = { x = x, y = y }
    end
    place()
end

local function altDown()
    local ok, down = pcall(IsAltKeyDown)
    return ok and not API.IsSecret(down) and down == true
end

-- The grip from live input: Alt held over the shown compass. A drag ends when Alt is let go.
local function updateGrip()
    if not grip then return end
    if dragging then
        if not altDown() then stopDrag(); grip:Hide() end
        return
    end
    local over = hit:IsMouseOver()
    grip:SetShown((altDown() and root:IsVisible() and not API.IsSecret(over) and over == true) and true or false)
end

--------------------------------------------------------------------------------
-- The tooltip

local function ownsTooltip()
    local ok, owner = pcall(GameTooltip.GetOwner, GameTooltip)
    return ok and disc ~= nil and owner == disc
end

local function setTooltip()
    local spec = shownOwner and specs[shownOwner]
    if not (spec and spec.Tooltip) then
        if ownsTooltip() then GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(disc, "ANCHOR_TOP")
    local ok, shown = pcall(spec.Tooltip, GameTooltip)
    if not ok then
        API.Fail("compass tooltip " .. tostring(shownOwner), shown)
        GameTooltip:Hide()
        return
    end
    if shown == false then return GameTooltip:Hide() end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Showing

-- Hidden for now: the requests stay (an owner's Want shows it again).
local function hide()
    if not root then return end
    if grip then grip:Hide() end                       -- its OnHide ends a drag under way
    root:Hide()
    shownDist = nil
    if ownsTooltip() then GameTooltip:Hide() end
end

-- Dress the ring for `owner`: the rim's tint, the icon or label, the tooltip under a still cursor.
local function dress(owner)
    local spec = specs[owner]
    shownOwner = owner
    dirty[owner] = nil
    local tint = C.TINTS[GP.Theme and GP.Theme.Active and GP.Theme.Active() or "forever"] or C.TINTS.forever
    rim:SetVertexColor(tint[1], tint[2], tint[3])
    local tex = spec.Icon and spec.Icon() or nil
    local words = spec.Label and spec.Label() or nil
    icon:SetTexture(tex)
    icon:SetShown(tex ~= nil)
    label:SetText(words or "")
    label:SetShown(words ~= nil)
    shownDist = nil
    if ownsTooltip() then setTooltip() end
end

-- Each frame while shown: the top owner, hidden at once when it says so or a
-- read fails; its arrival; else the arrow and arc at bearing - facing, the distance.
local function frame()
    local owner = top()
    if not owner then return hide() end
    local spec = specs[owner]
    if owner ~= shownOwner or dirty[owner] then dress(owner) end
    local okH, hidden = pcall(spec.Hidden)
    if not okH or hidden ~= false then return hide() end
    local continent, north, west = C.Position()
    local f = facing()
    if not (continent and f) then return hide() end
    local okP, tn, tw = pcall(spec.Point, continent, north, west)
    if not okP then tn, tw = nil, nil end
    tn, tw = num(tn), num(tw)
    if not (tn and tw) then return hide() end
    local d = math.sqrt((north - tn) ^ 2 + (west - tw) ^ 2)
    if spec.near and d <= spec.near then return spec.Arrive() end
    local a = C.Angle(north, west, tn, tw, f)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", body, "CENTER", -C.ORBIT * math.sin(a), C.ORBIT * math.cos(a))
    arrow:SetRotation(a)
    arc:SetRotation(a)
    local whole = math.floor(d + 0.5)
    if whole ~= shownDist then
        shownDist = whole
        text:SetText(whole .. " yd")
    end
    updateGrip()
end
C.Frame = frame

local function layer(parent, file, size, drawLayer, sub)
    local t = parent:CreateTexture(nil, drawLayer, nil, sub)
    t:SetSize(size, size)
    t:SetPoint("CENTER", parent, "CENTER")
    t:SetTexture(C.MEDIA .. file)
    return t
end

local function build()
    root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(1, 1)
    root:EnableMouse(false)
    root:SetMovable(true)
    root:Hide()
    body = CreateFrame("Frame", nil, root)
    body:SetSize(C.DISC, C.DISC)
    body:SetPoint("CENTER", root, "CENTER")
    body:EnableMouse(false)
    local shadow = layer(body, "CompassShadow.tga", C.DISC * 1.25, "BACKGROUND", -8)
    shadow:ClearAllPoints()
    shadow:SetPoint("CENTER", body, "CENTER", 0, -2)
    disc = CreateFrame("Frame", nil, body)
    disc:SetSize(C.DISC, C.DISC)
    disc:SetPoint("CENTER", body, "CENTER")
    layer(disc, "CompassLens.tga", C.DISC, "BACKGROUND")
    icon = disc:CreateTexture(nil, "ARTWORK")
    icon:SetSize(C.DISC * C.ICON, C.DISC * C.ICON)
    icon:SetPoint("CENTER", disc, "CENTER")
    local mask = disc:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    label = disc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    label:SetPoint("CENTER", disc, "CENTER", 0, 1)
    label:Hide()
    rim = layer(disc, "CompassRim.tga", C.DISC, "OVERLAY", 1)
    arc = layer(disc, "CompassArc.tga", C.DISC, "OVERLAY", 2)
    local over = CreateFrame("Frame", nil, body)
    over:SetAllPoints(body)
    over:SetFrameLevel(disc:GetFrameLevel() + 2)
    over:EnableMouse(false)
    arrow = over:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(C.ARROW, C.ARROW)
    arrow:SetTexture(C.MEDIA .. "CompassArrow.tga")
    local pill = CreateFrame("Frame", nil, body)
    pill:SetSize(C.PILL[1], C.PILL[2])
    pill:SetPoint("TOP", body, "CENTER", 0, -C.PILL_TOP)
    pill:EnableMouse(false)
    local pillArt = pill:CreateTexture(nil, "BACKGROUND")
    pillArt:SetAllPoints(pill)
    pillArt:SetTexture(C.MEDIA .. "CompassPill.tga")
    pillArt:SetTexCoord(2 / 128, 126 / 128, 12 / 64, 52 / 64)
    text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", pill, "CENTER")
    -- Mouse motion only on the disc: the tooltip; clicks reach the world.
    disc:SetScript("OnEnter", setTooltip)
    disc:SetScript("OnLeave", function() if ownsTooltip() then GameTooltip:Hide() end end)
    disc:EnableMouse(false)
    disc:SetMouseMotionEnabled(true)
    disc:SetMouseClickEnabled(false)
    -- The footprint (asked IsMouseOver only) and the grip over it, shown while Alt is held.
    hit = CreateFrame("Frame", nil, body)
    hit:SetSize(2 * C.REACH, C.REACH + C.FOOT)
    hit:SetPoint("TOP", body, "CENTER", 0, C.REACH)
    hit:EnableMouse(false)
    grip = CreateFrame("Frame", nil, hit)
    grip:SetAllPoints(hit)
    grip:SetFrameLevel(over:GetFrameLevel() + 1)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:Hide()
    local fill = grip:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(grip)
    fill:SetColorTexture(0, 0, 0, 0.45)
    local gripText = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gripText:SetPoint("CENTER", body, "CENTER")
    gripText:SetText("Drag to move")
    grip:SetScript("OnDragStart", function()
        dragging = true
        root:StartMoving()
    end)
    grip:SetScript("OnDragStop", function() stopDrag(); updateGrip() end)
    grip:SetScript("OnHide", stopDrag)
    grip:SetScript("OnMouseDown", function() end)       -- a click on the grip stays on it
    root:SetScript("OnUpdate", frame)
    -- Alt pressed or let go; the UI's scale or the display's size changed (a drag ended, placed again).
    local input = CreateFrame("Frame")
    API.RegisterEvents(input, { "MODIFIER_STATE_CHANGED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" })
    input:SetScript("OnEvent", function(_, event, key)
        if event == "MODIFIER_STATE_CHANGED" then
            if not API.IsSecret(key) and (key == "LALT" or key == "RALT") then updateGrip() end
            return
        end
        stopDrag()
        grip:Hide()
        place()
    end)
    C._test.input = input
    place()
end

-- An owner asks for the ring: shown (built on the first), then one frame's work.
function C.Want(owner)
    if not specs[owner] then return end
    wanted[owner] = true
    if not root then build() end
    if not root:IsShown() then place() end
    root:Show()
    frame()
end

-- An owner stops asking: only its own request. The ring goes to the next
-- owner with a request, or hides.
function C.Drop(owner)
    if not wanted[owner] then return end
    wanted[owner] = nil
    if not root then return end
    if owner == shownOwner then
        shownOwner = nil
        if top() and root:IsShown() then frame() else hide() end
    end
end

function C.Changed(owner) dirty[owner] = true end

function C.Wants(owner) return wanted[owner] == true end
function C.IsShown() return root ~= nil and root:IsShown() end
function C.Shown() return C.IsShown() and shownOwner or nil end

-- Back under the character (/gpearls books compass reset), shown or not, any owner.
function C.ResetPosition()
    if type(GP.charDB) == "table" then GP.charDB[C.SAVE_KEY] = nil end
    if root then
        stopDrag()
        place()
    end
end

C._test = {
    root = function() return root end, arrow = function() return arrow end, arc = function() return arc end,
    text = function() return text end, icon = function() return icon end, rim = function() return rim end,
    disc = function() return disc end, grip = function() return grip end, hit = function() return hit end,
    label = function() return label end, dragging = function() return dragging end, clamp = clamp,
    wanted = wanted, reset = function() for k in pairs(wanted) do wanted[k] = nil end; shownOwner = nil end,
}
