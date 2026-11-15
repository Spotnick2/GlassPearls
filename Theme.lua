-- Theme.lua: the look of every GlassPearls window (#3).
--
-- Two looks. "forever", the default: WoW Forever's own dialog art
-- (DialogBorderDarkTemplate, Blizzard's fonts and widgets). "glass": the
-- embedded LibGlass-1.0's reflective shell, only when Glass UI is here and
-- GlassPearls follows it (the owner: Forever by default; Glass comes from
-- Glass UI). There is no glass of our own choosing.
--
-- Following Glass UI (..\GlassUI\docs\SUITE.md, SUITE-LOOK.md; the model is
-- ..\Stakeout\Theme.lua, GlassUI#152). With Glass UI loaded, GlassPearls
-- follows it by default: the suite's material, body (tint, backing, wash) and
-- accent. "Use Glass UI appearance" (Settings) turns it off; the Forever look
-- applies then and is reported as declined, never as a failure. Asked once, at
-- ADDON_LOADED (`## OptionalDeps: GlassUI` has Glass UI ready by then): the
-- material and following itself are fixed for the session.
--
-- Live (#117): the tint and accent follow EventRegistry
-- "GlassUI.Suite.LookChanged", registered before the one pull of Look() (the
-- event isn't replayed). The payload is shared and read-only: only its tint
-- and accent strings are copied. Each change repaints every shell (tint,
-- backing, wash), every accent title and each OnLook consumer at once, in
-- combat too (colours and textures on our own regions only), then reports
-- live = true with the effective look; a repaint that throws is recorded and
-- not reported. A key Glass UI can't answer falls back to ours, named in the
-- report and flagged own: tint "glasspearls" (the recipe), accent "font"
-- (the title's first colour). Without the event (no Look, no EventRegistry)
-- the look is built once and reported live = false.
--
-- Every helper dresses the frame in the session's look and returns the look
-- it used. Glass from the window recipe in
-- C:\Projects\WoW\References\Docs\LIBGLASS-WINDOW-STYLING.md.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Theme = {}
GP.Theme = Theme

Theme.LOOKS = { "forever", "glass" }
Theme.LABELS = { forever = "WoW Forever", glass = "Glass" }
Theme.SUITE_ADDON = "GlassPearls"
Theme.EVENT = "GlassUI.Suite.LookChanged"
Theme.OWN_TINT, Theme.OWN_ACCENT = "glasspearls", "font"   -- our fallbacks' names in the report

local active      -- the session's look, fixed by Init
local Glass       -- this session's LibGlass instance, under the glass look
local following   -- what the session built from Glass UI's suite, or nil
local suite       -- Glass UI's suite while following
local live = false
local optionsFn   -- our window's opener, for Glass UI's page
local shells = {} -- every window shell, repainted on a change
local titles = setmetatable({}, { __mode = "k" })   -- accent title -> its first colour, or false
local onLook = {} -- texture consumers of the accent (the mark wheel)
local classPending
local retryFrame

-- The recipe's values, by surface role.
local SHELL = {
    tint = { 0.085, 0.095, 0.115, 0.78 }, backing = { 0.03, 0.03, 0.035, 0.55 },
    rim = 0.12, dark = 0.55, shadow = 0.18,
}
local READING = { 0.072, 0.082, 0.10, 0.94 }
local CONTROL = {
    tint = { 0.095, 0.11, 0.135, 0.90 }, wash = 0.025,
    rim = 0.22, dark = 0.35, shadow = 0.05,
}
-- The Forever look's own surfaces: a reading pane and a control's fill and
-- edge, drawn as plain textures inside the dialog art.
local FOREVER_READING = { 0, 0, 0, 0.35 }
local FOREVER_CONTROL = { fill = { 0.04, 0.04, 0.05, 0.85 }, edge = { 0.45, 0.42, 0.35, 0.9 } }

-- A LibGlass instance in `preset` with what the reflective shell needs (r9:
-- Reflect, SetSurfaceAlpha) and the library's minor; or nil, why not, and the
-- suite's reason code for it.
function Theme.NewGlass(preset)
    local stub = rawget(_G, "LibStub")
    local lib, minor
    if stub then lib, minor = stub("LibGlass-1.0", true) end
    if not lib then return nil, "LibGlass-1.0 isn't loaded", "build-failed" end
    local ok, inst = pcall(lib.New, lib, { preset = preset })
    if not ok or type(inst) ~= "table" then
        local why = tostring(inst)
        return nil, why, why:find("unknown preset", 1, true) and "library-too-old" or "build-failed"
    end
    if type(inst.Reflect) ~= "function" or type(inst.SetSurfaceAlpha) ~= "function" then
        return nil, "the loaded LibGlass-1.0 is older than r9", "library-too-old"
    end
    return inst, minor
end

-- Glass UI's suite API when it speaks version 1; anything else counts as absent.
local function SuiteAPI()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil end
    local S = rawget(G, "Suite")
    if type(S) ~= "table" or rawget(S, "API") ~= 1 then return nil end
    if type(rawget(S, "Theme")) ~= "function" or type(rawget(S, "Report")) ~= "function" then
        return nil
    end
    return S
end

-- One of the suite's optional functions, feature-detected on its own. A
-- missing function or a nil answer is an ordinary fallback; a throw is
-- recorded as "theme <name>" (#117).
local function SuiteCall(s, name, ...)
    local fn = rawget(s, name)
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
    API.Fail("theme " .. name, r)
end

local function IsColor(c, n)
    if type(c) ~= "table" then return false end
    for i = 1, n do
        if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 1 then return false end
    end
    return true
end

local function Copy(c) return { unpack(c) } end

-- The suite's body for a tint, checked and copied, or nil. A class body has
-- no colour, only its shade.
local function SuiteBody(suite, tint)
    local b = SuiteCall(suite, "Body", tint)
    if type(b) ~= "table" or type(b.wash) ~= "number" or b.wash < 0 or not IsColor(b.backing, 4) then
        return nil
    end
    if IsColor(b.tint, 4) then
        return { tint = Copy(b.tint), backing = Copy(b.backing), wash = b.wash }
    elseif b.tint == nil and type(b.classShade) == "number" then
        return { classShade = b.classShade, backing = Copy(b.backing), wash = b.wash }
    end
end

-- The player's class colour, or nil while it can't be read or isn't plain.
local function ClassColor()
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or API.IsSecret(class) or type(class) ~= "string" then return nil end
    local ok2, c = pcall(C_ClassColor.GetClassColor, class)
    if not ok2 or type(c) ~= "table" then return nil end
    local r, g, b = c.r, c.g, c.b
    for _, v in ipairs({ r, g, b }) do
        if API.IsSecret(v) or type(v) ~= "number" then return nil end
    end
    return r, g, b
end

-- The suite's answer: a fresh `following` with its own LibGlass instance (the
-- material, fixed for the session), or nil, with the report's reason when the
-- suite's material couldn't be built. The look comes after (Derive).
local function Follow(s)
    local ok, answer = pcall(s.Theme, Theme.SUITE_ADDON)
    if not (ok and type(answer) == "table" and type(answer.preset) == "string") then return nil end
    local inst, minor, code = Theme.NewGlass(answer.preset)
    if not inst then return nil, code end
    return { preset = answer.preset, inst = inst, minor = minor, own = {} }
end

-- The effective look from the suite's (`look` is its shared payload: only its
-- tint and accent strings are read). A key the suite can't answer is ours.
local function Derive(look)
    local f = following
    local tint = type(look) == "table" and look.tint or nil
    local accent = type(look) == "table" and look.accent or nil
    f.own, f.body, f.accentRGB = {}, nil, nil
    if type(tint) == "string" and not API.IsSecret(tint) then f.body = SuiteBody(suite, tint) end
    if f.body then f.tint = tint else f.tint, f.own.tint = Theme.OWN_TINT, true end
    local rgb = type(accent) == "string" and not API.IsSecret(accent) and SuiteCall(suite, "Accent", accent)
    if IsColor(rgb, 3) then
        f.accent, f.accentRGB = accent, { rgb[1], rgb[2], rgb[3] }
    else
        f.accent, f.own.accent = Theme.OWN_ACCENT, true
    end
end

local function SuiteReport(s, state)
    local ok, err = pcall(s.Report, Theme.SUITE_ADDON, state)
    if not ok then API.Fail("theme report", err) end
end

-- What we show now, for Glass UI's page (plain values, fresh tables).
local function FollowingReport()
    local own = {}
    for k in pairs(following.own) do own[k] = true end
    return { api = 1, live = live, built = following.preset, minor = following.minor, options = optionsFn,
             look = { tint = following.tint, accent = following.accent }, own = next(own) and own or nil }
end

-- Is Glass UI here, speaking the suite's API? (The Settings switch shows only then.)
function Theme.SuiteAvailable()
    return SuiteAPI() ~= nil
end

local Repaint   -- below, with the surfaces it paints

-- A LookChanged: derive, repaint, report; a repaint that throws is recorded
-- and nothing is reported (the surfaces may be half painted).
function Theme.OnLookChanged(_, look)
    if not (following and live) then return end
    local ok, err = pcall(function()
        Derive(look)
        Repaint()
        SuiteReport(suite, FollowingReport())
    end)
    if not ok then API.Fail("theme look", err) end
end

-- Register for the suite's changes; true when registered (then we're live).
local function Listen()
    if type(rawget(suite, "Look")) ~= "function" then return false end
    local reg = rawget(_G, "EventRegistry")
    if type(reg) ~= "table" or type(reg.RegisterCallback) ~= "function" then return false end
    local ok, err = pcall(reg.RegisterCallback, reg, Theme.EVENT, Theme.OnLookChanged, Theme)
    if not ok then API.Fail("theme listen", err) end
    return ok
end

-- Fix the session's look and tell Glass UI what was built. `follow` is the
-- player's "Use Glass UI appearance"; `options` opens our window (Glass UI's
-- link to it). Returns the look in use.
function Theme.Init(follow, options)
    if active then return active end
    optionsFn = options
    local s = SuiteAPI()
    local reason
    if s and follow ~= false then following, reason = Follow(s) end
    if following then
        Glass, active, suite = following.inst, "glass", s
        following.inst = nil
        following.wash = Glass.STYLE.wash   -- the preset's own: the body's is a factor of it
        live = Listen()                     -- before the pull: a change isn't replayed
        Derive(SuiteCall(s, "Look"))
        SuiteReport(s, FollowingReport())
    elseif s then
        local report = { api = 1, live = false, options = options, reason = reason }
        if follow == false then report.declined = Theme.LABELS.forever end
        SuiteReport(s, report)
        active = "forever"
    else
        active = "forever"
    end
    return active
end

function Theme.Active() return active or "forever" end
function Theme.Following() return following ~= nil end
-- The session's LibGlass instance (glass look only), for a pearl's own surfaces.
function Theme.Glass() return Glass end

local function Paint(g, role)
    Glass.SetSurfaceTint(g, unpack(role.tint))
    Glass.SetWash(g, role.wash or 0)
    Glass.SetSurfaceAlpha(g, "rim", role.rim)
    Glass.SetSurfaceAlpha(g, "dark", role.dark)
    Glass.SetSurfaceAlpha(g, "shadow", role.shadow)
    Glass.SetSurfaceAlpha(g, "grain", 0)
end

-- A shell's body: the suite's while following, else the recipe's, backing
-- included (a tint that becomes unknown goes back to all three, #117).
local function PaintShell(g)
    local body = following and following.body
    g.backing:SetColorTexture(unpack(body and body.backing or SHELL.backing))
    Paint(g, SHELL)
    if not body then return end
    if body.classShade then
        local r, gg, b = ClassColor()
        local s = body.classShade
        if r then
            Glass.SetSurfaceTint(g, r * s, gg * s, b * s)
        else
            Glass.SetSurfaceTint(g)
            classPending = true
        end
    else
        Glass.SetSurfaceTint(g, unpack(body.tint))
    end
    Glass.SetWash(g, following.wash * body.wash)
end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now.
function Theme.Retry()
    if not classPending or not ClassColor() then return end
    classPending = false
    for _, g in ipairs(shells) do PaintShell(g) end
end

local function WaitForClass()
    if retryFrame or not classPending then return end
    retryFrame = CreateFrame("Frame")
    API.RegisterEvents(retryFrame, { "PLAYER_ENTERING_WORLD" })
    retryFrame:SetScript("OnEvent", Theme.Retry)
end

-- A title's first colour (its font's), when every component reads plain.
local function FirstColor(fs)
    local ok, r, g, b, a = pcall(fs.GetTextColor, fs)
    if not ok then return false end
    local c = { r, g, b, a }
    for i = 1, 4 do
        if API.IsSecret(c[i]) or type(c[i]) ~= "number" then return false end
    end
    return c
end

local function PaintTitle(fs, first)
    local c = following and following.accentRGB
    if c then
        fs:SetTextColor(c[1], c[2], c[3])
    elseif first then
        fs:SetTextColor(first[1], first[2], first[3], first[4])
    end
end

-- A title in the suite's accent while following, kept in it through every
-- change; its font's own colour otherwise (and back to it when the suite's
-- accent can't be read).
function Theme.Accent(fs)
    if not following then return end
    if titles[fs] == nil then titles[fs] = FirstColor(fs) end
    PaintTitle(fs, titles[fs])
end

-- A texture consumer of the accent (AccentRGB), called after every change.
function Theme.OnLook(fn)
    if type(fn) == "function" then onLook[#onLook + 1] = fn end
end

-- Every surface again, in the current look: shells (backing, tint, wash),
-- titles, then each consumer on its own (one failing doesn't stop the rest).
Repaint = function()
    classPending = false
    for _, g in ipairs(shells) do PaintShell(g) end
    WaitForClass()
    for fs, first in pairs(titles) do PaintTitle(fs, first) end
    for _, fn in ipairs(onLook) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("theme onlook", err) end
    end
end

-- The suite's accent as r, g, b while following (a texture's tint), else nil.
function Theme.AccentRGB()
    local c = following and following.accentRGB
    if c then return c[1], c[2], c[3] end
end

-- The Forever look's window: Blizzard's dark dialog art on a child frame, or,
-- if the template is missing, a plain dark fill (never a bare frame).
local function ForeverWindow(frame)
    local border, ok = API.SafeFrame("Frame", frame, "DialogBorderDarkTemplate", "Bg")
    border:SetAllPoints(frame)
    if not ok then
        local fill = border:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(border)
        fill:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    end
    frame.border = border
    return border
end

-- A window's outer shell. opts.header: the height of its title area, which
-- the glass reflection lights and fades out over.
function Theme.Window(frame, opts)
    if active ~= "glass" then
        ForeverWindow(frame)
        return "forever"
    end
    opts = opts or {}
    local g = Glass.Apply(frame, "large")
    -- BACKGROUND -7: over the library's shadow (-8), under its tint (-6).
    -- Made before the first paint, which colours it.
    local backing = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    backing:SetAllPoints(frame)
    backing:AddMaskTexture(g.mask)
    g.backing = backing
    PaintShell(g)
    shells[#shells + 1] = g
    WaitForClass()
    Glass.SetEdge(g, 0, 0, 0)   -- the reflection's top highlight takes its place
    local header = opts.header
    Glass.Reflect(g, frame, (header and header > 0) and { header = header } or nil)
    frame.glass = g
    return "glass"
end

-- A reading region on `host` over `area` (default: host) grown by `outset`.
function Theme.Reading(host, area, outset)
    area, outset = area or host, outset or 0
    local pane = host:CreateTexture(nil, "BACKGROUND", nil, 0)
    pane:SetPoint("TOPLEFT", area, "TOPLEFT", -outset, outset)
    pane:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", outset, -outset)
    host.reading = pane
    if active ~= "glass" then
        pane:SetColorTexture(unpack(FOREVER_READING))
        return "forever"
    end
    pane:SetColorTexture(unpack(READING))
    local S = Glass.SIZES.thin_small
    pane:AddMaskTexture(Glass.Mask(host, S.mask, S.maskMargin, 0, pane))
    return "glass"
end

-- A control with its own surface (an item card, a list box).
function Theme.Control(frame)
    if active ~= "glass" then
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        fill:SetAllPoints(frame)
        fill:SetColorTexture(unpack(FOREVER_CONTROL.fill))
        local edges = {}
        for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                             { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local e = frame:CreateTexture(nil, "BORDER")
            e:SetPoint(p[1], frame, p[1])
            e:SetPoint(p[2], frame, p[2])
            if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
            e:SetColorTexture(unpack(FOREVER_CONTROL.edge))
            edges[i] = e
        end
        frame.surface = { fill = fill, edges = edges }
        return "forever"
    end
    local g = Glass.Apply(frame, "small")
    Paint(g, CONTROL)
    Glass.SetEdge(g, 0.10, 0.015, 0.12, 3)
    frame.glass = g
    return "glass"
end

-- Test seam (tests/). Harmless in game.
Theme._test = {
    reset = function()
        active, Glass, following, suite, classPending, retryFrame, optionsFn = nil, nil, nil, nil, nil, nil, nil
        live, shells, onLook = false, {}, {}
        for fs in pairs(titles) do titles[fs] = nil end
    end,
    following = function() return following end,
    live = function() return live end,
    titles = titles,
    SHELL = SHELL, READING = READING, CONTROL = CONTROL,
}
