-- Waypoint routes' windows and pins (#139): the step list (rows: number,
-- arrow, distance or zone or "no position", note; current, done; a row's
-- click; Previous, Next, Paste, Clear; the X remembered; the wheel, and the
-- current step brought into view only when it changes), the paste box (Load,
-- Cancel), the numbered pins (0-1 map coordinates, the current one on the
-- minimap by world position floating on the edge, the settings) and the
-- Configuration Panel. In both looks: test_way_frame_glass.lua runs it under
-- Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local ELWYNN, DUROTAR = 1429, 1411
WoW.zoneRects[ELWYNN] = { 1000, 700, 0, 0, 0 }
WoW.zoneRects[DUROTAR] = { 800, 600, 5000, 5000, 1 }
WoW.mapInfo[ELWYNN] = { name = "Elwynn Forest" }
WoW.mapInfo[DUROTAR] = { name = "Durotar" }
WoW.playerZone = { ELWYNN, 3 }
local GP = loadAddon()
local W, F, P = GP.Way, GP.WayFrame, GP.Pearls
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))
local function at(x, y) WoW.playerWorld = { -10 * x, -7 * y, 0 } end
at(0, 0)
WoW.facing = 0

--------------------------------------------------------------------------------
-- The step list

check(F._test.list() == nil, "nothing built before a route")
W.Load("/way 10 0 east\n/way 0 10\n/way #1411 50 50 orc town")
local list = F._test.list()
check(list and list:IsShown(), "a route loaded: the list shows")
eq(list:GetHeight(), F.Height(3), "  as tall as its three steps")
local p = list._points[#list._points]
check(p[1] == "TOP", "  placed by its top (a shorter route shortens it downwards)")
eq(list.count:GetText(), "Step 1 of 3", "  the header")
local rows = list.rows
eq(rows[1].num:GetText(), "1.", "row 1: its number")
eq(rows[1].dist:GetText(), "100 yd", "  its distance")
eq(rows[1].text:GetText(), "10.0, 0.0 east", "  coordinates and note")
check(rows[1].arrow:IsShown(), "  an arrow")
check(math.abs(rows[1].arrow._rotation + math.pi / 2) < 0.01, "  east of a player facing north: to the right")
check(rows[1].current:IsShown(), "  the current step highlighted")
check(not rows[2].current:IsShown(), "row 2 not")
eq(rows[2].dist:GetText(), "70 yd", "  its distance")
check(math.abs(math.abs(rows[2].arrow._rotation) - math.pi) < 0.01, "  south: straight behind")
eq(rows[3].dist:GetText(), "Durotar", "another continent: the zone instead")
check(not rows[3].arrow:IsShown(), "  no arrow")
check(not rows[4]:IsShown(), "unused rows hidden")
WoW.facing = 3 * math.pi / 2
WoW.tick(F.REPAINT)
check(math.abs(rows[1].arrow._rotation) < 0.01, "repainted while shown: facing east, the first step ahead")
WoW.facing = 0

at(10, 0)
W.Tick()
eq(list.count:GetText(), "Step 2 of 3", "a step reached: the header follows")
check(rows[1].check:IsShown() and rows[1]:GetAlpha() < 1, "  the done step checked and dimmed")
check(rows[2].current:IsShown(), "  the next highlighted")
rows[3]:GetScript("OnClick")(rows[3])
eq(W.Route().current, 3, "a row's click: that step current")
list.prev:GetScript("OnClick")(list.prev)
eq(W.Route().current, 2, "Previous")
list.next:GetScript("OnClick")(list.next)
eq(W.Route().current, 3, "Next")
list.next:GetScript("OnClick")(list.next)
eq(list.count:GetText(), "Complete: 3 steps", "Next past the last: complete")
check(not list.next:IsEnabled(), "  Next disabled")
list.paste:GetScript("OnClick")(list.paste)
check(F.PasteShown(), "Paste opens the paste box")
F._test.paste():Hide()

-- The X: hidden, remembered across a login; a new route shows it again.
list.close:GetScript("OnClick")(list.close)
check(not list:IsShown() and W.Route().closed == true, "the X hides it, remembered")
W.Select(1)
P.Set("way", false)
P.Set("way", true)
check(not list:IsShown(), "  not shown again at login")
P.Command("way").run("")
check(list:IsShown() and W.Route().closed == nil, "/gpearls way: shown again")
P.Command("way").run("")
check(not list:IsShown(), "  and toggled")
W.Load("/way 1 1")
check(list:IsShown(), "a new route: shown")
list.clear:GetScript("OnClick")(list.clear)
check(W.Route() == nil and not list:IsShown(), "Clear: no route, no list")

-- Scrolling: the wheel browses; the current step comes into view only when it changes.
local many = {}
for i = 1, 20 do many[i] = ("/way %d 1"):format(i) end
W.Load(table.concat(many, "\n"))
eq(rows[1].num:GetText(), "1.", "a long route: from the top")
eq(list:GetHeight(), F.Height(F.ROWS), "  at most ROWS rows tall")
list:GetScript("OnMouseWheel")(list, -1)
eq(rows[1].num:GetText(), "2.", "the wheel scrolls")
for _ = 1, 30 do list:GetScript("OnMouseWheel")(list, -1) end
eq(rows[1].num:GetText(), (20 - F.ROWS + 1) .. ".", "  not past the end")
W.Select(2)
eq(rows[1].num:GetText(), "2.", "a step chosen out of view: brought into view")
list:GetScript("OnMouseWheel")(list, -3)
WoW.tick(F.REPAINT)
F.Refresh()
eq(rows[1].num:GetText(), "5.", "  browsing isn't undone while the current step stays")
-- Scrolled to the bottom with step 1 current, then a short route pasted (step 1 current too): from the top.
W.Select(1)
for _ = 1, 30 do list:GetScript("OnMouseWheel")(list, -1) end
eq(rows[1].num:GetText(), (20 - F.ROWS + 1) .. ".", "browsed to the bottom, step 1 current")
W.Load("/way 1 1\n/way 2 2")
check(rows[1]:IsShown() and rows[1].num:GetText() == "1." and rows[2].num:GetText() == "2.",
    "a replacement route: shown from its top, never blank")
W.Load(table.concat(many, "\n"))
for _ = 1, 30 do list:GetScript("OnMouseWheel")(list, -1) end
W.Load(table.concat(many, "\n"))
eq(rows[1].num:GetText(), "1.", "  as long, step 1 current again: from the top too (a new route, not browsing)")

--------------------------------------------------------------------------------
-- The paste box

W.Clear()
F.ShowPaste()
local paste = F._test.paste()
check(paste:IsShown(), "the paste box")
paste.edit:SetText("nothing valid")
paste.load:GetScript("OnClick")(paste.load)
check(paste:IsShown() and paste.edit:GetText() == "nothing valid", "nothing loaded: it stays, the text kept")
paste.edit:SetText("/way 10 10\n/way 20 20")
paste.load:GetScript("OnClick")(paste.load)
check(not paste:IsShown() and paste.edit:GetText() == "", "loaded: closed and emptied")
eq(#W.Route().steps, 2, "  the route")
F.ShowPaste()
paste.cancel:GetScript("OnClick")(paste.cancel)
check(not paste:IsShown(), "Cancel closes it")

--------------------------------------------------------------------------------
-- Pins

W.Load("/way 10 0\n/way 0 10\n/way #1411 50 50")
local function pins(display)
    local out = {}
    for icon, r in pairs(WoW.hbd[display]) do if r.ref == F then out[icon.index] = r end end
    return out
end
local world, mini = pins("world"), pins("mini")
eq(WoW.hbdCount("world", F), 3, "a world map pin per step")
check(world[1].kind == "Map" and world[1].args[1] == ELWYNN and world[1].args[2] == 0.1 and world[1].args[3] == 0,
    "  by its map, in 0-1 coordinates")
eq(world[3].args[1], DUROTAR, "  each on its own map")
eq(WoW.hbdCount("mini", F), 3, "a minimap pin per step")
check(mini[1].kind == "World" and mini[1].args[1] == 0 and mini[1].args[2] == -100 and mini[1].args[3] == 0
    and mini[1].args[4] == true, "  the current one by world position (continent, west, north), on the edge")
check(mini[2].kind == "Map" and mini[2].args[1] == ELWYNN and mini[2].args[2] == 0 and mini[2].args[3] == 0.1
    and mini[2].args[5] == false, "  the others by map, 0-1, not on the edge")
local f1
for icon, r in pairs(WoW.hbd.world) do if r.ref == F and icon.index == 1 then f1 = icon end end
eq(f1.num:GetText(), "1", "a pin shows its number")
eq(f1.kind, "current", "  the current one marked")
check(f1._clicks == false, "  clicks pass through")
f1:GetScript("OnEnter")(f1)
eq(GameTooltip:GetOwner(), f1, "  hover: its tooltip")
f1:GetScript("OnLeave")(f1)
at(10, 0)
W.Tick()
mini = pins("mini")
check(mini[1].kind == "Map" and mini[2].kind == "World", "a step reached: the next one floats on the edge")
P.SetSetting("way", "worldmap", false)
eq(WoW.hbdCount("world", F), 0, "world map pins switched off")
eq(WoW.hbdCount("mini", F), 3, "  the minimap's kept")
P.SetSetting("way", "minimap", false)
eq(WoW.hbdCount("mini", F), 0, "minimap pins switched off")
P.ResetSettings("way")
eq(WoW.hbdCount("world", F), 3, "on again")
P.Set("way", false)
check(WoW.hbdCount("world", F) == 0 and WoW.hbdCount("mini", F) == 0, "the pearl off: no pins")
P.Set("way", true)
eq(WoW.hbdCount("world", F), 3, "  on: back")
W.Clear()
check(WoW.hbdCount("world", F) == 0 and WoW.hbdCount("mini", F) == 0, "cleared: no pins")

--------------------------------------------------------------------------------
-- The Configuration Panel

GP.Options.Open("cat:Interface")
local page = GP.Options._test.pages["cat:Interface"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "way" then row = pl.row end end
check(row ~= nil, "on the Interface page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:way"].content
local checks = {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
eq(#checks, 2, "two switches")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("way", "worldmap"), false, "  the world map pins")
checks[2]:SetChecked(false)
checks[2]:GetScript("OnClick")(checks[2])
eq(P.Setting("way", "minimap"), false, "  the minimap pins")
content.pasteButton:GetScript("OnClick")(content.pasteButton)
check(F.PasteShown(), "Paste waypoints opens the box")

done("test_way_frame" .. (glass and " (glass)" or ""))
