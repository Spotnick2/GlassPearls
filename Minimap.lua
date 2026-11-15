-- Minimap.lua: the glass pearl on the minimap ring (#121). A hand-made
-- button, no library: AltStable's recipe (the same owner's, MIT;
-- AltStable\SheetUI.lua). LibDBIcon needs LibDataBroker-1.1, which has no
-- published licence, and its copy at hand drew wrong on Forever (Codex
-- review, three rounds).
--
-- `GlassPearlsMinimapButton`, a plain Button child of Minimap: named,
-- square, clickable, so a minimap-button collector (the owner's
-- GlassMiniMapBar scans Minimap's named children) takes it like any other;
-- `btn.icon` is the pearl, the field such a collector reads for the icon.
-- Placed on the ellipse of the minimap's half width and height plus a
-- clearance, at the saved angle; it follows the minimap's size (a HookScript,
-- extending Blizzard's frame, never replacing). Left-drag moves it around
-- the ring; the drag stops when the button hides or is taken from Minimap
-- (a collector reparents it), before anything is written.
--
-- Left-click toggles the options window, right-click opens it on Settings.
-- Saved per account, never synced: GlassPearlsDB.minimap = { hide, angle }.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local M = {}
GP.Minimap = M

M.NAME = "GlassPearlsMinimapButton"
M.ICON = "Interface\\AddOns\\GlassPearls\\Media\\Pearl"
M.ANGLE = 200          -- the default: lower left
M.CLEARANCE = 10       -- past the minimap's edge (AltStable's, tuned by eye)
M.FALLBACK_RADIUS = 99 -- half of Forever's 198 px minimap, while its size reads 0

local btn

-- The saved table, each field checked (a junk value would throw in the
-- maths or hide the button by accident).
function M.Clean(t)
    if type(t) ~= "table" then return {} end
    if t.hide ~= nil and t.hide ~= true then t.hide = nil end
    local a = t.angle
    if a ~= nil and (type(a) ~= "number" or a ~= a or a == math.huge or a == -math.huge) then t.angle = nil end
    for k in pairs(t) do
        if k ~= "hide" and k ~= "angle" then t[k] = nil end
    end
    return t
end

local function db()
    local d = GP.db
    if not d then return {} end
    if type(rawget(d, "minimap")) ~= "table" then d.minimap = {} end
    return d.minimap
end

local function size(v, fallback)
    if API.IsSecret(v) or type(v) ~= "number" or v <= 0 then return fallback end
    return v / 2
end

-- On the ring at the saved angle.
function M.Place()
    if not btn or btn:GetParent() ~= Minimap then return end
    local rad = math.rad(db().angle or M.ANGLE)
    local rx = size(Minimap:GetWidth(), M.FALLBACK_RADIUS) + M.CLEARANCE
    local ry = size(Minimap:GetHeight(), M.FALLBACK_RADIUS) + M.CLEARANCE
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", rx * math.cos(rad), ry * math.sin(rad))
end

local function stopDrag(self)
    self.isDragging = nil
    self:SetScript("OnUpdate", nil)
end

local function dragUpdate(self)
    if self:GetParent() ~= Minimap then return stopDrag(self) end   -- taken by a collector
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if type(mx) ~= "number" or type(px) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
    db().angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    M.Place()
end

local function tooltip(self)
    if self.isDragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Glass Pearls")
    GameTooltip:AddLine("Left-click: the options", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function build()
    btn = CreateFrame("Button", M.NAME, Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 1)
    icon:SetTexture(M.ICON)
    btn.icon = icon
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", dragUpdate)
    end)
    btn:SetScript("OnDragStop", stopDrag)
    btn:SetScript("OnHide", stopDrag)
    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then GP.Options.Open("settings") else GP.Options.Toggle() end
    end)
    btn:SetScript("OnEnter", tooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local ok, err = pcall(Minimap.HookScript, Minimap, "OnSizeChanged", M.Place)
    if not ok then API.Fail("minimap size", err) end
    M.Place()
end

function M.Shown() return db().hide ~= true end

-- Shown or hidden, saved first (the button only follows).
function M.SetShown(on)
    db().hide = (on == false) or nil
    if btn then btn:SetShown(on ~= false) end
end

-- At PLAYER_LOGIN, from the bootstrap.
function M.Start()
    if btn or not rawget(_G, "Minimap") then return end
    GP.db.minimap = M.Clean(rawget(GP.db, "minimap"))
    build()
    btn:SetShown(M.Shown())
end

function M.Button() return btn end
