-- The raid mark wheel's art, animations and panel (#34): the segments' marks
-- and boundaries, the highlight placed and turned as Blizzard's gamepad wheel
-- does, the current mark, the label, the open and close animations, and the
-- panel. In WoW Forever's look with the client's atlases (this file); under
-- Glass UI's glass (test_markwheel_frame_glass.lua); and with no atlas at all
-- (test_markwheel_frame_plain.lua).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local mode = arg and arg[1] or "forever"
local ATLAS = { wheel = "gamepad-radial-menu-wheelbg", selected = "gamepad-radial-menu-selected",
    label = "gamepad-radial-menu-bottomtext", clear = "Radial_Wheel_Icon_Close" }
if mode ~= "plain" then
    WoW.atlases[ATLAS.wheel] = { width = 400, height = 400 }
    WoW.atlases[ATLAS.selected] = { width = 180, height = 120 }
    WoW.atlases[ATLAS.label] = { width = 260, height = 60 }
    WoW.atlases[ATLAS.clear] = true
end
if mode == "glass" then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local GP = loadAddon()
local M, FR, P = GP.MarkWheel, GP.MarkWheelFrame, GP.Pearls
eq(GP.Theme.Active(), mode == "glass" and "glass" or "forever", "the look: " .. mode)
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- Choices, clockwise from the top: skull, star, circle, diamond, triangle,
-- moon, square, cross.
local spots = { { 0, 100, 8 }, { 70, 70, 1 }, { 100, 0, 2 }, { 70, -70, 3 }, { 0, -100, 4 }, { -70, -70, 5 },
    { -100, 0, 6 }, { -70, 70, 7 } }
for _, s in ipairs(spots) do
    eq(M.Choice(s[1], s[2]), s[3], ("(%d, %d) is mark %d"):format(s[1], s[2], s[3]))
end
-- Boundaries.
eq(M.Segment(M.R_CLEAR, 0), 0, "on the centre ring's edge: Clear")
eq(M.Segment(M.R_CLEAR + 1, 0), 1, "just past it: segment 1")
eq(M.Segment(M.R_OUTER, 0), 1, "on the rim: still the segment")
eq(M.Segment(M.R_OUTER + 1, 0), "outside", "past the rim: outside")
local function polar(deg) return 100 * math.cos(math.rad(deg)), 100 * math.sin(math.rad(deg)) end
eq(M.Segment(polar(22.4)), 1, "22.4 degrees: segment 1")
eq(M.Segment(polar(22.6)), 2, "22.6 degrees: segment 2")
eq(M.Segment(polar(-22.4)), 1, "-22.4 degrees: segment 1")
eq(M.Segment(polar(-22.6)), 8, "-22.6 degrees: segment 8")
eq(M.Segment(polar(180)), 5, "180 degrees: segment 5")

-- The highlight's geometry (GamepadRadial.lua:1111-1117).
local r, x, y = FR.Geometry(1, 1)
check(near(r, math.rad(-270)) and near(x, 150) and near(y, 0), "segment 1: rotation -270 degrees, 150 east")
r, x, y = FR.Geometry(3, 0.8)
check(near(r, math.rad(-180)) and math.abs(x) < 1e-6 and near(y, 120), "segment 3 at k 0.8: -180 degrees, 120 north")

-- Open on the target, wearing circle.
WoW.units.mouseover = { id = "A", guid = "Creature-0-1-A" }
WoW.units.target = WoW.units.mouseover
WoW.unitNames.target = "Defias Thug"
WoW.marks.A = 2
WoW.mouse = { x = 500, y = 400 }
M.OnKey()
local f = FR._test.frame()
local k = mode == "plain" and (M.R_OUTER * 2 / FR.NATIVE) or (M.R_OUTER * 2 / 400)
check(near(f.k, k), "the art's scale from the wheel atlas's width")
check(f:IsShown(), "the art is shown")
eq(f._mouse, false, "click-through")
eq(f.label._mouse, false, "  its label too")
check(not f._protected, "the art is not protected")
local p = f._points[#f._points]
check(p[1] == "CENTER" and p[2] == UIParent and p[4] == 500 and p[5] == 400, "at the cursor, anchored to UIParent")
local b = M._test.button()
local bp = b._points[#b._points]
check(bp[2] == UIParent, "the button anchored to UIParent, never to the art")
check(b._parent == UIParent, "  and parented to it")

-- The marks on the segments.
for g, marker in ipairs(M.MARKERS) do
    local _, ix, iy = FR.Geometry(g, f.k)
    local icon = f.icons[marker]
    local ip = icon._points[#icon._points]
    check(icon._file == FR.ICON .. marker and near(ip[4], ix) and near(ip[5], iy),
        ("mark %d's icon on segment %d"):format(marker, g))
end
check(f.current:IsShown(), "the current mark is ringed")
local cp = f.current._points[#f.current._points]
check(near(cp[4], f.icons[2].x) and near(cp[5], f.icons[2].y), "  around circle")
eq(f.label.unit:GetText(), "Defias Thug", "the label names the unit")

-- Hovering skull: the highlight on segment 3, the label names it.
WoW.mouse = { x = 500, y = 500 }
WoW.tick()
eq(f.hover, 8, "hovering skull")
eq(f.label.name:GetText(), "Skull", "  the label: Skull (English when the client's string is absent)")
check(f.icons[8]._width > FR.ICON_SIZE, "  its icon grows")
if mode ~= "plain" then
    local hl = f.highlight
    check(hl and hl:IsShown(), "the highlight shows")
    local hr, hx, hy = FR.Geometry(3, f.k)
    local hp = hl._points[#hl._points]
    check(near(hl._rotation, hr) and near(hp[4], hx) and near(hp[5], hy), "  on segment 3, turned as Blizzard turns it")
    check(near(hl._width, 180 * f.k) and near(hl._height, 120 * f.k), "  sized from its atlas, scaled")
    eq(hl._atlas, ATLAS.selected, "  the gamepad wheel's selected art")
else
    eq(f.highlight, nil, "no highlight art: none")
end
rawset(_G, "RAID_TARGET_8", "Totenkopf")
WoW.mouse = { x = 500, y = 400 }
WoW.tick()
eq(f.label.name:GetText(), "Clear", "on the centre: Clear")
if f.highlight then check(not f.highlight:IsShown(), "  the highlight hides") end
WoW.mouse = { x = 500, y = 500 }
WoW.tick()
eq(f.label.name:GetText(), "Totenkopf", "the client's own name for skull when it has one")
WoW.mouse = { x = 500, y = 700 }
WoW.tick()
eq(f.label.name:GetText(), "", "outside: no name")

-- The look's art.
if mode == "forever" then
    eq(f.art, "atlas", "WoW Forever: the gamepad wheel's art")
    eq(f.bg._atlas, ATLAS.wheel, "  its background")
    eq(f.label.art, "atlas", "  the label on its bottom text art")
    eq(f.clear._atlas, ATLAS.clear, "  the centre: the ping wheel's close icon")
elseif mode == "glass" then
    eq(f.art, "glass", "glass: a LibGlass disc")
    check(f.glass ~= nil, "  built")
    eq(f.label.art, "glass", "  the label on a glass shell")
    check(f.highlight._desaturated, "  the highlight desaturated")
    local c = f.highlight._vertex
    check(c and near(c[1], 0.9) and near(c[2], 0.7) and near(c[3], 0.2), "  and in the suite's accent")
else
    eq(f.art, "plain", "no atlas: a plain disc")
    eq(f.bg._atlas, nil, "  no atlas set")
    check(f.bg._color ~= nil and f.bg._masks ~= nil, "  a dark fill, masked round")
    local lines = 0
    for _, region in ipairs(f._regions) do if region._type == "Line" then lines = lines + 1 end end
    eq(lines, 8, "  eight dividers")
    eq(f.label.art, "forever", "  the label on Blizzard's dialog art")
    eq(f.clear._file, FR.CLEAR_ICON, "  the centre: a plain icon")
end

-- The current mark: a secret answer rings nothing.
M.Close("test")
WoW.marksSecret = true
WoW.mouse = { x = 500, y = 400 }
M.OnKey()
check(not f.current:IsShown(), "a secret current mark: no ring")
WoW.marksSecret = nil
WoW.unitNames.target = WoW.Secret("UnitName")
M.Close("test")
M.OnKey()
eq(f.label.unit:GetText(), "", "a secret name: none shown")
WoW.unitNames.target = nil

-- Animations: open plays; close plays, then hides; a re-open during a close
-- is never hidden by the old close.
check(f.opening:IsPlaying(), "opening plays")
M.Close("test")
check(f.closing:IsPlaying(), "closing plays")
check(f:IsShown(), "  the art stays while it fades")
check(not b:IsShown(), "  the secure button is already gone")
f.closing._scripts.OnFinished(f.closing)
check(not f:IsShown(), "faded: hidden")
M.OnKey()
M.Close("test")
local oldClose = f.closing
M.OnKey()
check(f:IsShown() and not f.closing:IsPlaying(), "re-opened during the close: the close stopped")
check(f.opening:IsPlaying(), "  the opening plays")
oldClose._scripts.OnFinished(oldClose)
check(f:IsShown() and M.IsOpen(), "  the old close's end doesn't hide the new wheel")
M.Close("test")
f.closing._scripts.OnFinished(f.closing)

-- The panel.
GP.Options.Open("cat:Social")
local page = GP.Options._test.pages["cat:Social"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "markwheel" then row = pl.row end end
check(row ~= nil, "on the Social page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:markwheel"].frame._children[1]
local checks = {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
eq(#checks, 1, "one switch")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("markwheel", "menu"), false, "  the unit menu entry")
P.ResetSettings("markwheel")
check(content.key:GetText():find("No key yet", 1, true), "no key: says where to bind one")
WoW.bindings.GLASSPEARLS_MARKWHEEL = "SHIFT-G"
GP.Options.Open("cat:Social")
row.gear:GetScript("OnClick")(row.gear)
eq(content.key:GetText(), "Key: SHIFT-G", "  then names it")
WoW.mouse = { x = 500, y = 400 }
content.test:GetScript("OnClick")(content.test)
check(M.IsOpen() and M.state.session.token == "player", "Test opens the wheel on you")
M.Close("test")

done("test_markwheel_frame" .. (mode ~= "forever" and (" (" .. mode .. ")") or ""))
