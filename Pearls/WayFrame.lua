-- Pearls/WayFrame.lua: what waypoint routes (#139) draw: the step list, the
-- paste box, the numbered pins and the Configuration Panel. The route and its
-- progress are Pearls/Way.lua's; this file only shows them and passes clicks.
--
-- The step list: a movable window (per character), ROWS rows with the mouse
-- wheel; each row the step's number, an arrow at bearing - facing (the
-- compass's arrow art and convention), its distance (or its zone on another
-- continent, or "no position"), its coordinates and note; the current one
-- highlighted, done ones dimmed with a check. Repainted every REPAINT seconds
-- while shown; scrolled to the current step only when the current step
-- changes. Previous, Next, Paste, Clear; a click on a row makes it current.
-- The X only hides it (remembered: not shown again at login until a route is
-- loaded or it's opened).
--
-- The paste box: a multi-line edit box in a scroll frame, Load and Cancel.
--
-- Pins (HereBeDragons-Pins, ref Frame): every step with a position on the
-- world map (by its map) and on the minimap (by its map, near the player's
-- zone); the current step's minimap pin by its world position, floating on
-- the minimap's edge from anywhere on its continent. A small disc with the
-- number; current gold, done grey; tooltip on hover, clicks pass through.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.WayFrame = Frame

Frame.NAME = "GlassPearlsWayFrame"
Frame.PASTE_NAME = "GlassPearlsWayPaste"
Frame.ROWS = 8
Frame.ROW_H = 20
Frame.WIDTH = 360
Frame.REPAINT = 0.2
Frame.PIN = 16
Frame.SHOW_CONTINENT = 2   -- HBD_PINS_WORLDMAP_SHOW_CONTINENT (HereBeDragons-Pins-2.0.lua)
Frame.CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
Frame.COLORS = { current = { 1, 0.82, 0 }, step = { 0.35, 0.65, 1 }, done = { 0.5, 0.5, 0.5 } }

local PAD = 14
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local list, paste
local offset = 0           -- the first row's step index - 1
local lastCurrent          -- the current step the list last scrolled to
local lastRoute            -- the route it was for (a paste replaces the table)
local elapsed = 0

local function W() return GP.Way end

--------------------------------------------------------------------------------
-- The step list

local function savePos(frame, key)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not API.IsSecret(left) and not API.IsSecret(top) and type(GP.charDB) == "table"
        and type(left) == "number" and type(top) == "number" then
        GP.charDB[key] = { x = left, y = top }
    end
end

local function place(frame, key, x, y)
    frame:ClearAllPoints()
    local db = type(GP.charDB) == "table" and GP.charDB[key]
    if type(db) == "table" and type(db.x) == "number" and type(db.y) == "number" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

local function movable(frame, key)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePos(self, key)
    end)
end

-- What a row says about step i: the distance or where, and the arrow's angle (nil: no arrow).
function Frame.Where(i, continent, north, west, facing)
    local p = W().Position(i)
    if not p then return "no position", nil end
    if not (continent and p.c == continent) then
        local s = W().Route().steps[i]
        return W().ZoneName(s.map), nil
    end
    local d = math.sqrt((north - p.north) ^ 2 + (west - p.west) ^ 2)
    local angle = facing and GP.Compass.Angle(north, west, p.north, p.west, facing) or nil
    return ("%d yd"):format(math.floor(d + 0.5)), angle
end

local function paintRows()
    local r = W().Route()
    if not (list and r) then return end
    local continent, north, west = GP.Compass.Position()
    local facing = GP.Compass.Facing()
    for n, row in ipairs(list.rows) do
        local i = offset + n
        local s = r.steps[i]
        row.index = i
        if not s then
            row:Hide()
        else
            row:Show()
            row.num:SetText(i .. ".")
            local where, angle = Frame.Where(i, continent, north, west, facing)
            row.dist:SetText(where)
            if angle then
                row.arrow:SetRotation(angle)
                row.arrow:Show()
            else
                row.arrow:Hide()
            end
            local note = s.desc ~= "" and (" " .. s.desc) or ""
            row.text:SetText(("%.1f, %.1f%s"):format(s.x, s.y, note))
            local current = i == r.current
            row.current:SetShown(current)
            row.check:SetShown(s.done == true)
            row:SetAlpha((s.done and not current) and 0.5 or 1)
        end
    end
end

-- Keep the current step in view (only when it changed, or the route was
-- replaced: browsing isn't undone), and the rows always within the route.
local function follow()
    local r = W().Route()
    if not r then return end
    if r ~= lastRoute then lastRoute, lastCurrent, offset = r, nil, 0 end
    local cur = math.min(r.current, #r.steps)
    if cur ~= lastCurrent then
        lastCurrent = cur
        if cur <= offset then offset = cur - 1
        elseif cur > offset + Frame.ROWS then offset = cur - Frame.ROWS end
    end
    offset = math.max(0, math.min(offset, math.max(0, #r.steps - Frame.ROWS)))
end

function Frame.Scroll(delta)
    local r = W().Route()
    if not r then return end
    offset = math.max(0, math.min(offset - delta, math.max(0, #r.steps - Frame.ROWS)))
    paintRows()
end

local function header()
    local r = W().Route()
    if not r then return "" end
    if r.current > #r.steps then return ("Complete: %d steps"):format(#r.steps) end
    return ("Step %d of %d"):format(r.current, #r.steps)
end

local function buildRow(parent, n)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(Frame.WIDTH - 2 * PAD, Frame.ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -48 - (n - 1) * Frame.ROW_H)
    row.current = row:CreateTexture(nil, "BACKGROUND")
    row.current:SetAllPoints(row)
    row.current:SetColorTexture(1, 0.82, 0, 0.18)
    row.current:Hide()
    row.num = GP.UI.Label(row, "", "GameFontNormalSmall")
    row.num:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.num:SetWidth(28)
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetSize(14, 14)
    row.arrow:SetPoint("LEFT", row, "LEFT", 32, 0)
    row.arrow:SetTexture(GP.Compass.MEDIA .. "CompassArrow.tga")
    row.dist = GP.UI.Label(row, "", "GameFontHighlightSmall")
    row.dist:SetPoint("LEFT", row, "LEFT", 50, 0)
    row.dist:SetWidth(78)
    row.text = GP.UI.Label(row, "", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 130, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    row.text:SetWordWrap(false)
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(14, 14)
    row.check:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.check:SetTexture(Frame.CHECK)
    row.check:Hide()
    row:SetScript("OnClick", function(self) if self.index then W().Select(self.index) end end)
    return row
end

local function buildList()
    list = CreateFrame("Frame", Frame.NAME, UIParent)
    list:SetSize(Frame.WIDTH, 48 + Frame.ROWS * Frame.ROW_H + 44)
    list:SetFrameStrata("MEDIUM")
    movable(list, "wayList")
    list:Hide()
    GP.Theme.Window(list, { header = 40 })
    list.title = GP.UI.Header(list, "Waypoint route")
    list.title:SetPoint("TOPLEFT", list, "TOPLEFT", PAD, -14)
    list.count = GP.UI.Label(list, "", "GameFontHighlightSmall")
    list.count:SetPoint("TOPRIGHT", list, "TOPRIGHT", -34, -18)
    list.close = CreateFrame("Button", nil, list, "UIPanelCloseButton")
    list.close:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, -4)
    list.close:SetScript("OnClick", function() Frame.HideList(true) end)
    list.rows = {}
    for n = 1, Frame.ROWS do list.rows[n] = buildRow(list, n) end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Frame.Scroll(delta) end)
    local y = 12
    list.prev = GP.UI.Button(list, "Previous", 78, function() W().Previous() end)
    list.prev:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", PAD, y)
    list.next = GP.UI.Button(list, "Next", 78, function() W().Next() end)
    list.next:SetPoint("LEFT", list.prev, "RIGHT", 4, 0)
    list.clear = GP.UI.Button(list, "Clear", 70, function() W().Clear() end)
    list.clear:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -PAD, y)
    list.paste = GP.UI.Button(list, "Paste", 70, function() Frame.ShowPaste() end)
    list.paste:SetPoint("RIGHT", list.clear, "LEFT", -4, 0)
    list:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < Frame.REPAINT then return end
        elapsed = 0
        paintRows()
    end)
    place(list, "wayList", 380, 60)
end

-- The route changed: the header, the buttons, the rows (the current step brought into view).
function Frame.Refresh()
    if not list then return end
    local r = W().Route()
    if not r then
        lastRoute, lastCurrent, offset = nil, nil, 0
        list:Hide()
        return
    end
    follow()
    list.count:SetText(header())
    list.prev:SetEnabled(r.current > 1)
    list.next:SetEnabled(r.current <= #r.steps)
    paintRows()
end

function Frame.ShowList()
    local r = W().Route()
    if not r then return end
    r.closed = nil
    if not list then buildList() end
    list:Show()
    Frame.Refresh()
end

-- Hidden; `byPlayer`: remembered, so it doesn't come back at login.
function Frame.HideList(byPlayer)
    if byPlayer then
        local r = W().Route()
        if r then r.closed = true end
    end
    if list then list:Hide() end
end

function Frame.ToggleList()
    if list and list:IsShown() then Frame.HideList(true) else Frame.ShowList() end
end

function Frame.ListShown() return list ~= nil and list:IsShown() end

--------------------------------------------------------------------------------
-- The paste box

local function buildPaste()
    paste = CreateFrame("Frame", Frame.PASTE_NAME, UIParent)
    paste:SetSize(380, 320)
    paste:SetFrameStrata("DIALOG")
    movable(paste, "wayPaste")
    paste:Hide()
    GP.Theme.Window(paste, { header = 40 })
    local title = GP.UI.Header(paste, "Paste waypoints")
    title:SetPoint("TOPLEFT", paste, "TOPLEFT", PAD, -14)
    local hint = GP.UI.Label(paste, "One /way line per step, such as /way 66 34 or /way Zone name 66 34 note. "
        .. "A zone name alone on a line (Duskwood) sets the zone of the lines after it.", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", paste, "TOPLEFT", PAD, -40)
    hint:SetWidth(380 - 2 * PAD)
    hint:SetWordWrap(true)
    local area = CreateFrame("Frame", nil, paste)
    area:SetPoint("TOPLEFT", paste, "TOPLEFT", PAD, -84)
    area:SetPoint("BOTTOMRIGHT", paste, "BOTTOMRIGHT", -PAD, 44)
    GP.Theme.Reading(paste, area, 2)
    local scroll = CreateFrame("ScrollFrame", nil, paste, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", area, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -24, 4)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(380 - 2 * PAD - 32)
    edit:SetHeight(200)
    edit:SetMaxBytes(GP.Way.MAX_BYTES + 1)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
        -- Keep the cursor in view (the scroll frame doesn't follow an edit box by itself).
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -(y or 0)
        if type(view) ~= "number" or type(h) ~= "number" then return end
        if y < top then scroll:SetVerticalScroll(y)
        elseif y + h > top + view then scroll:SetVerticalScroll(y + h - view) end
    end)
    scroll:SetScrollChild(edit)
    area:EnableMouse(true)
    area:SetScript("OnMouseDown", function() edit:SetFocus() end)
    paste.edit = edit
    paste.load = GP.UI.Button(paste, "Load", 90, function()
        if GP.Way.Load(edit:GetText()) then
            edit:SetText("")
            paste:Hide()
        end
    end)
    paste.load:SetPoint("BOTTOMRIGHT", paste, "BOTTOMRIGHT", -PAD, 12)
    paste.cancel = GP.UI.Button(paste, "Cancel", 90, function() paste:Hide() end)
    paste.cancel:SetPoint("RIGHT", paste.load, "LEFT", -4, 0)
    place(paste, "wayPaste", 0, 120)
end

function Frame.ShowPaste()
    if not paste then buildPaste() end
    paste:Show()
    paste.edit:SetFocus()
end

function Frame.PasteShown() return paste ~= nil and paste:IsShown() end

function Frame.HideAll()
    if list then list:Hide() end
    if paste then paste:Hide() end
    Frame.ClearPins()
end

--------------------------------------------------------------------------------
-- Pins

local frames = { world = {}, mini = {} }
local used = { world = 0, mini = 0 }
Frame.placed = {}

local function pinsLib()
    local stub = rawget(_G, "LibStub")
    return stub and stub("HereBeDragons-Pins-2.0", true)
end

local function pinEnter(self)
    local r, i = W().Route(), self.index
    local s = r and i and r.steps[i]
    if not s then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(("Step %d of %d"):format(i, #r.steps))
    if s.desc ~= "" then GameTooltip:AddLine(s.desc, 1, 1, 1, true) end
    GameTooltip:AddLine(("%s %.1f, %.1f"):format(W().ZoneName(s.map), s.x, s.y), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function pinLeave(self)
    local ok, owner = pcall(GameTooltip.GetOwner, GameTooltip)
    if ok and owner == self then GameTooltip:Hide() end
end

local function acquire(display, i, kind)
    used[display] = used[display] + 1
    local f = frames[display][used[display]]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(Frame.PIN, Frame.PIN)
        f.disc = f:CreateTexture(nil, "ARTWORK")
        f.disc:SetAllPoints(f)
        f.disc:SetColorTexture(1, 1, 1, 1)
        local mask = f:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(f.disc)
        f.disc:AddMaskTexture(mask)
        f.num = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.num:SetPoint("CENTER", f, "CENTER", 0, 0)
        f:SetMouseClickEnabled(false)
        f:SetMouseMotionEnabled(true)
        f:SetScript("OnEnter", pinEnter)
        f:SetScript("OnLeave", pinLeave)
        frames[display][used[display]] = f
    end
    local c = Frame.COLORS[kind]
    f.disc:SetVertexColor(c[1], c[2], c[3])
    f.num:SetText(tostring(i))
    f.index, f.kind = i, kind
    -- Hidden, unanchored: HereBeDragons shows and places only what it draws (Landmarks, #95).
    f:Hide()
    f:ClearAllPoints()
    return f
end

function Frame.ClearPins()
    local P = pinsLib()
    if P then
        P:RemoveAllWorldMapIcons(Frame)
        P:RemoveAllMinimapIcons(Frame)
    end
    for _, display in ipairs({ "world", "mini" }) do
        for _, f in ipairs(frames[display]) do
            f.index = nil
            f:Hide()
        end
        used[display] = 0
    end
    Frame.placed = {}
end

-- Every pin again from the route (any change of it, of the settings, Enable).
function Frame.Pins()
    Frame.ClearPins()
    local P, way = pinsLib(), W()
    local r = way.enabled and way.Route()
    if not (P and r) then return end
    local worldOn = GP.Pearls.Setting(way.KEY, "worldmap")
    local miniOn = GP.Pearls.Setting(way.KEY, "minimap")
    for i, s in ipairs(r.steps) do
        local p = way.Position(i)
        if p then
            local kind = i == r.current and "current" or (s.done and "done" or "step")
            if worldOn then
                local f = acquire("world", i, kind)
                P:AddWorldMapIconMap(Frame, f, s.map, s.x / 100, s.y / 100, Frame.SHOW_CONTINENT)
                Frame.placed[#Frame.placed + 1] = { display = "world", index = i, kind = kind }
            end
            if miniOn then
                local f = acquire("mini", i, kind)
                if kind == "current" then
                    P:AddMinimapIconWorld(Frame, f, p.c, p.west, p.north, true)
                else
                    P:AddMinimapIconMap(Frame, f, s.map, s.x / 100, s.y / 100, true, false)
                end
                Frame.placed[#Frame.placed + 1] = { display = "mini", index = i, kind = kind }
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local KEY, P = GP.Way.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "Your waypoint route")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local world, refreshWorld = GP.UI.Check(panel, "Numbered pins on the world map",
        function() return P.Setting(KEY, "worldmap") end, function(on) P.SetSetting(KEY, "worldmap", on) end)
    world:SetPoint("TOPLEFT", head, "BOTTOMLEFT", -4, -8)
    refreshers[#refreshers + 1] = refreshWorld
    local mini, refreshMini = GP.UI.Check(panel, "Numbered pins on the minimap",
        function() return P.Setting(KEY, "minimap") end, function(on) P.SetSetting(KEY, "minimap", on) end,
        { tip = "The current step's pin stays on the minimap's edge while it is farther away." })
    mini:SetPoint("TOPLEFT", world, "BOTTOMLEFT", 0, -4)
    refreshers[#refreshers + 1] = refreshMini
    local pasteB = GP.UI.Button(panel, "Paste waypoints", 140, function() Frame.ShowPaste() end)
    pasteB:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 4, -14)
    local listB = GP.UI.Button(panel, "Show the route", 140, function() Frame.ShowList() end)
    listB:SetPoint("LEFT", pasteB, "RIGHT", 8, 0)
    local note = GP.UI.Label(panel,
        "/way 66 34 adds a step when no other add-on uses /way; /gpearls way always works. Alt-drag the compass "
            .. "to move it. Unverified until checked in game.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", pasteB, "BOTTOMLEFT", 0, -14)
    note:SetWidth(380)
    note:SetWordWrap(true)
    panel.pasteButton, panel.listButton = pasteB, listB
end

Frame._test = { list = function() return list end, paste = function() return paste end, frames = frames,
    paint = paintRows, offset = function() return offset end }
