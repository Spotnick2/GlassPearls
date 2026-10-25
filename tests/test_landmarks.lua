-- The map landmarks pearl (#10): pins through HereBeDragons (world order,
-- the continent flag, a frame per display, clicks through), tooltips (names,
-- levels, sides, destinations), flight points (Blizzard's faction and
-- undiscovered rules, not where Blizzard draws them), the zone level line,
-- settings rebuilding, the options, switching off, and failures.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.player.faction = "Alliance"
local GP = loadAddon()
local LM, P, D = GP.Landmarks, GP.Pearls, GP.LandmarkData
local nE, nT = #D.entrances, #D.transports

check(P.IsLive("landmarks"), "on by default")
eq(P.Get("landmarks").category, "Interface", "on the Interface page")
eq(WoW.hbdCount("world"), nE + nT, "every entrance and transport on the world map")
eq(WoW.hbdCount("mini"), nE + nT, "and on the minimap")

-- The calls: world order swapped for HereBeDragons (x west, y north), the continent flag.
local first = D.entrances[1]
local wcall, mcall
for _, c in ipairs(WoW.hbd.calls) do
    if c.icon.entry == first and c.display == "world" then wcall = c end
    if c.icon.entry == first and c.display == "mini" then mcall = c end
end
eq(wcall.kind, "World", "entrances placed from world coordinates")
eq(wcall.ref, LM, "  under the pearl's own ref")
eq(wcall.args[1], first.c, "  the continent")
eq(wcall.args[2], first.y, "  HereBeDragons' x is our y (west)")
eq(wcall.args[3], first.x, "  its y is our x (north)")
eq(wcall.args[4], LM.SHOW_CONTINENT, "  shown on the zone and continent maps")
eq(mcall.args[2], first.y, "the minimap call swaps too")
eq(mcall.args[4], false, "  not floating on the edge")
check(wcall.icon ~= mcall.icon, "a separate frame per display")
eq(wcall.icon._clicks, false, "clicks pass through to the map")
eq(wcall.icon._motion, true, "  hover still shows the tooltip")
check(wcall.icon:GetScript("OnClick") == nil, "  and nothing happens on a click")

-- Icons: the client's atlas when it has one, else the file and a tint.
eq(wcall.icon.tex._atlas, nil, "no 'Dungeon' atlas: the file")
check(wcall.icon.tex._file ~= nil, "  a file texture")
WoW.atlases.Dungeon = true
LM.Build()
local entranceIcon
for icon, r in pairs(WoW.hbd.world) do if icon.entry == first then entranceIcon = icon end end
eq(entranceIcon.tex._atlas, "Dungeon", "with the atlas: the atlas")
WoW.atlases.Dungeon = nil

-- Tooltips.
local function door(key) for _, e in ipairs(D.entrances) do if e.key == key then return e end end end
local function text(lines) local t = {} for _, l in ipairs(lines) do t[#t + 1] = l[1] end return table.concat(t, "\n") end
local brm = text(LM.TooltipLines(door("brm")))
check(brm:find("Blackrock Depths", 1, true) and brm:find("Molten Core", 1, true), "Blackrock Mountain: all five")
check(brm:find("Dungeon and raid entrance", 1, true), "  'Dungeon and raid entrance'")
check(brm:find("(52-60)", 1, true), "  with each range")
check(text(LM.TooltipLines(door("lfg41"))):find("Raid entrance", 1, true), "Zul'Gurub: 'Raid entrance'")
check(text(LM.TooltipLines(door("lfg3271"))):find("(28+)", 1, true), "a minimum alone: '28+'")
WoW.lfgNames[1] = "Cavernes des Lamentations"
check(text(LM.TooltipLines(door("lfg1"))):find("Cavernes des Lamentations", 1, true), "the client's (localized) name when it has one")
WoW.lfgNames[1] = 42
check(text(LM.TooltipLines(door("lfg1"))):find("Wailing Caverns", 1, true), "  junk from the client: our English name")
WoW.lfgNames[1] = nil
-- Level colours as Blizzard's zone label: below (red here), inside (difficult), above (grey).
WoW.playerLevel = 30
check(LM.LevelText(52, 60):find("^|cffff1919"), "a range above you: its minimum's colour")
check(LM.LevelText(25, 35):find("^|cffff7f3f"), "inside it: 'difficult'")
check(LM.LevelText(1, 10):find("^|cff7f7f7f"), "below you: its maximum - 2's colour")
-- Ranges where the two candidate levels colour differently (stub: +-4 is "standard").
check(LM.LevelText(33, 45):find("^|cffffd100"), "above you: the minimum's colour (33), not the maximum's (45)")
check(LM.LevelText(20, 27):find("^|cff7f7f7f"), "below you: maximum - 2 (25, grey), not the maximum (27)")
-- Transports.
local function dock(name, kind)
    for _, t in ipairs(D.transports) do if t.name == name and (not kind or t.kind == kind) then return t end end
end
local zep = text(LM.TooltipLines(dock("Orgrimmar", "zeppelin")))
check(zep:find("(Horde only)", 1, true), "as Alliance, a Horde zeppelin is marked")
check(zep:find("Zeppelin", 1, true) and zep:find("To ", 1, true), "  kind and destinations")
WoW.player.faction = "Horde"
check(not text(LM.TooltipLines(dock("Orgrimmar", "zeppelin"))):find("only", 1, true), "as Horde: not marked")
WoW.player.faction = "Alliance"
check(not text(LM.TooltipLines(dock("Ratchet"))):find("only", 1, true), "a neutral ship isn't marked")
check(text(LM.TooltipLines(dock("Ironforge", "tram"))):find("Deeprun Tram", 1, true), "the tram")
-- On the frame: GameTooltip.
wcall.icon:GetScript("OnEnter")(wcall.icon)
eq(GameTooltip._owner, wcall.icon, "hovering an icon shows its tooltip")

-- Flight points: the runtime API, Blizzard's faction and undiscovered rules.
WoW.taxi[1411] = {
    { nodeID = 1, position = { x = 0.52, y = 0.43 }, name = "Razor Hill", faction = 1, atlasName = "TaxiNode_Horde" },
    { nodeID = 2, position = { x = 0.6, y = 0.4 }, name = "Alliance Post", faction = 2 },
    { nodeID = 3, position = { x = 0.7, y = 0.7 }, name = "Neutral Roost", faction = 0, isUndiscovered = true },
}
LM.Build()
local flights = { world = 0, mini = 0 }
local undisc
for display in pairs(flights) do
    for icon, r in pairs(WoW.hbd[display]) do
        if icon.entry and icon.entry.kind == "flight" then
            flights[display] = flights[display] + 1
            check(icon.entry.name ~= "Razor Hill", "as Alliance, no Horde flight master")
            eq(r.kind, "Map", "  placed from map coordinates")
            if icon.entry.undiscovered then undisc = icon end
        end
    end
end
eq(flights.world, 2, "your faction's and the neutral one on the world map")
eq(flights.mini, 2, "  and on the minimap")
check(undisc and undisc.tex._desaturated, "an undiscovered one is greyed")
check(text(LM.TooltipLines(undisc.entry)):find("Undiscovered", 1, true), "  and says so")
-- Where Blizzard draws them on the world map: not there, still on the minimap.
WoW.taxiShown[1411] = true
WoW.fire("TAXI_NODE_STATUS_CHANGED")
flights = { world = 0, mini = 0 }
for display in pairs(flights) do
    for icon in pairs(WoW.hbd[display]) do if icon.entry and icon.entry.kind == "flight" then flights[display] = flights[display] + 1 end end
end
eq(flights.world, 0, "Blizzard draws them on that map: none of ours on the world map")
eq(flights.mini, 2, "  still on the minimap (Blizzard has none there)")
eq(WoW.hbdCount("world"), nE + nT, "a rebuild never doubles a pin")
WoW.taxiShown[1411], WoW.taxi[1411] = nil, nil
LM.Build()

-- Settings rebuild at once (from the options, a slash command or settings sync).
P.SetSetting("landmarks", "entrancesWorld", false)
eq(WoW.hbdCount("world"), nT, "entrances off on the world map: only transports")
eq(WoW.hbdCount("mini"), nE + nT, "  the minimap keeps them")
P.SetSetting("landmarks", "transportsMinimap", false)
eq(WoW.hbdCount("mini"), nE, "transports off on the minimap")
P.SetSetting("landmarks", "size", 130)
local anyIcon = next(WoW.hbd.mini)
eq(anyIcon._width, LM.BASE_SIZE * 1.3, "the icon size follows")
P.ResetSettings("landmarks")
eq(WoW.hbdCount("world"), nE + nT, "Reset: everything back")

-- The zone level line, only where Blizzard's own range is empty.
WorldMapFrame:Show()
WoW.cursorMap = { mapID = 1414, x = 0.6, y = 0.3, focus = true }
WoW.mapAt[1414] = { mapID = 1411, name = "Durotar" }
local lbl = LM._test.label()
LM._test.update()
check(lbl.text:IsShown(), "over Durotar on the Kalimdor map: the line shows")
check(lbl.text:GetText():find("(1-10)", 1, true), "  Durotar's range")
-- Under the visible text, not the 128-tall label frame (Codex review of #11).
local function anchor()
    local pts = lbl.text._points
    return pts[#pts], #pts
end
local pt, n = anchor()
eq(n, 1, "  one anchor (cleared each time)")
eq(pt[1], "TOP", "  its top")
eq(pt[2], WoW.areaLabel.Name, "  under Blizzard's zone name, not the label frame")
eq(pt[3], "BOTTOM", "  at the name's bottom")
check(pt[5] < 0 and pt[5] >= -8, "  just below it")
WoW.areaLabel.Description:SetText("Contested Territory")
LM._test.update()
pt = anchor()
eq(pt[2], WoW.areaLabel.Description, "with a description line: under that")
WoW.areaLabel.Description:SetText("")
LM._test.update()
eq(anchor()[2], WoW.areaLabel.Name, "  and back under the name when it empties")
eq(select(2, anchor()), 1, "  still one anchor after three updates")
eq(WoW.areaLabel.Name:GetText(), nil, "Blizzard's label is never written")
WoW.mapLevels[1411] = { 1, 10 }
LM._test.update()
check(not lbl.text:IsShown(), "Blizzard shows its own range: ours steps aside")
WoW.mapLevels[1411] = nil
WoW.cursorMap.focus = false
LM._test.update()
check(not lbl.text:IsShown(), "the cursor off the map: hidden")
WoW.cursorMap.focus = true
WoW.mapAt[1414] = { mapID = 1414 }
D.zones[1414] = { 1, 60 }
LM._test.update()
check(not lbl.text:IsShown(), "over the continent itself: hidden (even with a range)")
D.zones[1414] = nil
WoW.mapAt[1414] = { mapID = 1453, name = "Stormwind City" }
LM._test.update()
check(not lbl.text:IsShown(), "a zone without a range (a city): hidden")
WoW.mapAt[1414] = { mapID = 1411 }
P.SetSetting("landmarks", "zoneLevels", false)
LM._test.update()
check(not lbl.text:IsShown(), "the option off: hidden")
P.ResetSettings("landmarks")
WorldMapFrame:Hide()

-- The Configuration Panel: seven switches and the size.
GP.Options.Open("cat:Interface")
local row
for _, pl in ipairs(GP.Options._test.pages["cat:Interface"].placed) do if pl.key == "landmarks" then row = pl.row end end
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:landmarks"].frame._children[1]
local checks, radios = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
    if w._template == "UIRadioButtonTemplate" then radios[#radios + 1] = w end
end
eq(#checks, 7, "seven switches")
eq(#radios, 3, "three icon sizes")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("landmarks", "entrancesWorld"), false, "the first switch: entrances on the world map")
eq(WoW.hbdCount("world"), nT, "  applied at once")
P.ResetSettings("landmarks")
GP.Options._test.win():Hide()

-- Failures: a pin HereBeDragons refuses is recorded; no library, nothing built.
WoW.hbdFail = true
GP.failures["pearl landmarks pin"] = nil
LM.Build()
check(GP.failures["pearl landmarks pin"] ~= nil, "a refused pin is recorded")
WoW.hbdFail = false
local realLib = LibStub.libs["HereBeDragons-Pins-2.0"]
LibStub.libs["HereBeDragons-Pins-2.0"] = nil
GP.failures["pearl landmarks"] = nil
check(not LM.Build(), "no HereBeDragons: nothing built")
check(GP.failures["pearl landmarks"]:find("HereBeDragons", 1, true), "  and recorded")
LibStub.libs["HereBeDragons-Pins-2.0"] = realLib
LM.Build()

-- Switched off: every pin removed, the line gone, events ignored.
P.Set("landmarks", false)
eq(WoW.hbdCount("world"), 0, "off: no world map pins")
eq(WoW.hbdCount("mini"), 0, "  no minimap pins")
check(not LM._test.label():IsShown(), "  no zone line")
WoW.fire("TAXI_NODE_STATUS_CHANGED")
eq(WoW.hbdCount("world"), 0, "  and a taxi event builds nothing")
P.SetSetting("landmarks", "size", 80)
eq(WoW.hbdCount("world"), 0, "  nor a settings change")
P.ResetSettings("landmarks")
P.Set("landmarks", true)
eq(WoW.hbdCount("world"), nE + nT, "back on: everything again")

done("test_landmarks")
