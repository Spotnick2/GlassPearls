-- The shared compass (#139, from #93's ring): owners and their requests. The
-- highest-priority owner with a request is shown, even while its own frame
-- keeps it hidden; Drop touches only its owner's request; Changed re-dresses
-- on the next frame; an owner with `near` arrives in the ring, one without is
-- drawn at any distance; the label over the lens. The drawing itself (bearing,
-- tooltip, drag) is test_books_compass.lua's.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local C = GP.Compass

-- Two owners: "low" (priority 1, arrives within 10) and "high" (priority 2, no arrival).
local low = { n = 100, w = 0, hidden = false, arrived = 0, icon = 1001, dressed = 0 }
local high = { n = 0, w = 100, hidden = false, label = "3", dressed = 0 }
C.Register("low", {
    priority = 1, near = 10,
    Arrive = function() low.arrived = low.arrived + 1; C.Drop("low") end,
    Hidden = function() return low.hidden end,
    Point = function() return low.n, low.w end,
    Icon = function() low.dressed = low.dressed + 1; return low.icon end,
    Tooltip = function(t) t:SetText("low") end,
})
C.Register("high", {
    priority = 2,
    Hidden = function() if high.hidden == "throw" then error("no") end return high.hidden end,
    Point = function() return high.n, high.w end,
    Label = function() high.dressed = high.dressed + 1; return high.label end,
    Tooltip = function(t) t:SetText("high") end,
})
WoW.playerWorld = { 0, 0, 1 }   -- west, north, continent
WoW.facing = 0
local function text() return C._test.text()._text end

C.Want("low")
check(C.IsShown() and C.Shown() == "low", "one owner: shown for it")
eq(text(), "100 yd", "  its distance")
eq(C._test.icon()._file, 1001, "  its icon")
check(C._test.icon():IsShown() and not C._test.label():IsShown(), "  an icon, no label")

C.Want("high")
eq(C.Shown(), "high", "a higher owner takes the ring")
eq(C._test.label()._text, "3", "  its label over the lens")
check(C._test.label():IsShown(), "  shown")
check(not C._test.icon():IsShown(), "  no icon")
check(C.Wants("low"), "  the lower one's request kept")

high.hidden = true
WoW.tick()
check(not C.IsShown(), "the higher owner hidden: the ring hides")
eq(C.Top(), "high", "  and stays reserved for it (no stale lower target)")
C.Want("low")
check(not C.IsShown(), "  a lower owner's Want doesn't show it meanwhile")
high.hidden = "throw"
C.Want("high")
check(not C.IsShown(), "Hidden() throwing: hidden")
high.hidden = false
C.Want("high")
check(C.IsShown() and C.Shown() == "high", "  its own Want brings it back")

C.Drop("low")
check(C.IsShown() and C.Shown() == "high" and C.Wants("high"), "the lower owner drops: the higher one is untouched")
C.Want("low")
C.Drop("high")
check(C.IsShown() and C.Shown() == "low", "the higher one drops: the ring goes to the lower one")
eq(text(), "100 yd", "  drawn for it at once")

-- Changed: re-dressed on the next frame, not at once.
local n = low.dressed
low.icon = 1002
C.Changed("low")
eq(low.dressed, n, "Changed: nothing at once")
WoW.tick()
eq(low.dressed, n + 1, "  re-dressed on the next frame")
eq(C._test.icon()._file, 1002, "  the new icon")

-- Arrival: only an owner with `near`.
low.n = 5
WoW.tick()
eq(low.arrived, 1, "an owner with near: arrives within it")
check(not C.IsShown(), "  dropping itself hides the ring")
high.n, high.w = 3, 0
C.Want("high")
check(C.IsShown() and text() == "3 yd", "an owner without near: drawn even 3 yards away")
WoW.tick()
check(C.IsShown(), "  and stays")

-- The target unreadable or on another continent: hidden, the request kept.
high.n = WoW.Secret("n")
WoW.tick()
check(not C.IsShown() and C.Wants("high"), "a secret target: hidden, still wanted")
high.n = 3
C.Want("high")
check(C.IsShown(), "  back")
C.Drop("high")
check(not C.IsShown() and C.Top() == nil, "no owner left: hidden")
C.Drop("high")
check(not C.IsShown(), "a second Drop: nothing")

done("test_compass")
