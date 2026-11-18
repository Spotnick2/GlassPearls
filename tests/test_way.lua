-- Waypoint routes (#139): the route's life. Paste (replacing; an invalid one
-- leaving it), append (a new route, to a complete one, the cap), Previous /
-- Next / a row, Clear; the controller (eligibility before anything, one
-- advance per tick, arming for a step chosen by hand, no-position steps,
-- another continent, recovery with Books off and the windows closed); the
-- ring's owner above the books; the saved route across a login; /way.
-- Parsing is test_way_parse.lua; the windows and pins test_way_frame.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ELWYNN, DUROTAR, NOWHERE = 1429, 1411, 4444
WoW.zoneRects[ELWYNN] = { 1000, 700, 0, 0, 0 }
WoW.zoneRects[DUROTAR] = { 800, 600, 5000, 5000, 1 }
WoW.mapInfo[ELWYNN] = { name = "Elwynn Forest" }
WoW.mapInfo[DUROTAR] = { name = "Durotar" }
WoW.playerZone = { ELWYNN, 3 }
local GP = loadAddon({ before = function() end })
local W, C, P = GP.Way, GP.Compass, GP.Pearls

-- The player at Elwynn's (x, y), dw yards further west; continent 0.
local function at(x, y, dw, c) WoW.playerWorld = { -10 * x + (dw or 0), -7 * y, c or 0 } end
WoW.facing = 0
local function cur() local r = W.Route(); return r and r.current end
local function steps() local r = W.Route(); return r and #r.steps or 0 end
local function isDone(i) return W.Route().steps[i].done == true end

check(P.IsOn("way"), "on by default")
eq(SlashCmdList.GLASSPEARLSWAY, nil, "/way not claimed during the login itself")
WoW.flushTimers(0)
eq(_G.SLASH_GLASSPEARLSWAY1, "/way", "a frame after Start: /way claimed (free)")
eq(W.Route(), nil, "no route at first")
check(not C.Wants("way"), "  the ring not asked for")

--------------------------------------------------------------------------------
-- Loading

at(0, 0)
newChat()
check(W.Load("/way 10 10\n/way 20 10 two\n/way 30 10\nnonsense"), "a paste loads")
eq(steps(), 3, "  three steps")
eq(cur(), 1, "  the first current")
check(chatHas("3 steps loaded") and chatHas("line 4: no coordinates"), "  said, with the problem")
check(C.Wants("way") and C.Shown() == "way", "  the ring points at it")
WoW.tick()
eq(C._test.label()._text, "1", "  the step's number over the lens")
eq(C._test.text()._text, "122 yd", "  its distance")
newChat()
check(not W.Load("junk\n\n"), "a paste with nothing valid")
eq(steps(), 3, "  leaves the route as it was")
check(chatHas("nothing to load, the route is unchanged"), "  and says so")

--------------------------------------------------------------------------------
-- The controller

local function tick() W.Tick() end
at(10, 10, 5)
local function eligibleCase(label, set, unset)
    set()
    tick()
    eq(cur(), 1, label .. ": nothing advances")
    check(not isDone(1), "  nothing done")
    check(C.Wants("way"), "  the ring still asked for")
    WoW.tick()
    check(not C.IsShown(), "  the ring hides itself")
    unset()
end
eligibleCase("dead", function() WoW.dead = true end, function() WoW.dead = nil end)
eligibleCase("on a taxi", function() WoW.onTaxi = true end, function() WoW.onTaxi = nil end)
eligibleCase("in an instance", function() WoW.inInstance = true end, function() WoW.inInstance = nil end)
eligibleCase("the taxi secret", function() WoW.onTaxi = WoW.Secret("t") end, function() WoW.onTaxi = nil end)
eligibleCase("the position unreadable", function() WoW.playerWorld = "throw" end, function() at(10, 10, 5) end)
tick()
eq(cur(), 2, "eligible within 10 yards: the next step current")
check(isDone(1), "  the first done")
check(C.IsShown() and C.Shown() == "way", "  the ring back, for the next step")
WoW.tick()
eq(C._test.label()._text, "2", "  its number")

-- Two steps under the player: one per tick.
W.Load("/way 50 50\n/way 50.01 50\n/way 90 90")
at(50, 50)
tick()
eq(cur(), 2, "a fresh step under the player: reached at once")
for _ = 1, 5 do WoW.tick() end
eq(cur(), 2, "  the ring's frames never advance a route")
tick()
eq(cur(), 3, "  the next close one on the next tick")

-- Chosen by hand: disarmed until the player is farther than NEAR.
W.Previous()
eq(cur(), 2, "Previous: the step before")
tick()
eq(cur(), 2, "  chosen by hand nearby: not reached at once")
WoW.tick()
check(C.IsShown() and C._test.text()._text == "0 yd", "  the ring draws it anyway (no arrival in the ring)")
at(50, 50, 30)
tick()
eq(cur(), 2, "  30 yards away: armed, still current")
at(50, 50)
tick()
eq(cur(), 3, "  back within 10 yards: reached")
W.Select(1)
eq(cur(), 1, "a row: that step, done or not")
check(isDone(1), "  still marked done")
W.Next()
eq(cur(), 2, "Next")

-- Complete.
W.Next()
newChat()
at(90, 90, 30)
tick()
at(90, 90)
tick()
eq(cur(), 4, "the last step reached: complete")
check(W.IsComplete() and chatHas("Waypoint route complete."), "  said")
eq(#newChat(), 1, "  once")
tick()
eq(#newChat(), 0, "  not again")
check(not C.Wants("way") and not C.IsShown(), "  the ring let go")
W.Next()
eq(cur(), 4, "Next on a complete route: nothing")
W.Previous()
eq(cur(), 3, "Previous from complete: the last step")
W.Next()
eq(cur(), 4, "Next from the last: complete")

-- Append.
newChat()
check(W.Append("/way 70 70 more"), "a step appended")
eq(steps(), 4, "  at the end")
eq(cur(), 4, "  to a complete route: it becomes current")
check(chatHas("step 4 added %(Elwynn Forest 70%.00, 70%.00%)"), "  said")
-- Complete by hand (disarmed), then a step appended under the player: fresh, so reached.
W.Next()
check(W.IsComplete(), "complete by hand")
at(80, 80)
W.Append("80 80")
tick()
check(W.IsComplete() and isDone(5), "  an appended step under the player: armed, reached")
W.Select(1)
W.Append("71 71")
eq(cur(), 1, "  to a route under way: the current step unchanged")
newChat()
check(not W.Append("/way 66"), "a bad line: nothing added")
check(chatHas("two coordinates"), "  why")
newChat()
local before = steps()
check(not W.Append("/way Durotar") and steps() == before, "a zone alone on /way: nothing added")
check(chatHas("sets the zone of the lines after it in a paste"), "  said what it's for")
W.Load("Durotar\n/way 50 50\n/way 60 60")
check(W.Route().steps[1].map == DUROTAR and W.Route().steps[2].map == DUROTAR, "a paste with a zone line: its zone")
W.Select(1)
W.Clear()
eq(W.Route(), nil, "Clear: no route")
check(not C.Wants("way"), "  the ring let go")
W.Append("/way 1 1")
check(steps() == 1 and cur() == 1, "an append with no route: a new one")
local big = {}
for i = 1, W.MAX_STEPS do big[i] = "/way 1 1" end
W.Load(table.concat(big, "\n"))
newChat()
check(not W.Append("/way 2 2") and steps() == W.MAX_STEPS, "a full route: an append refused")
check(chatHas("holds 100 steps"), "  said")

-- No position: passed by the route's own advance, kept when chosen by hand.
WoW.zoneRects[NOWHERE] = { 100, 100, 0, 0, 0 }
W.Load("/way 10 10\n/way #4444 5 5\n/way 30 10")
WoW.zoneRects[NOWHERE] = nil
W._test.positions()
check(W.Position(2) == false, "a step HereBeDragons can't place: no position")
at(10, 10)
tick()
eq(cur(), 2, "reached the first")
at(0, 0)
tick()
eq(cur(), 3, "  the no-position step passed by the advance")
check(not isDone(2), "  not marked done")
W.Previous()
tick()
tick()
eq(cur(), 2, "  chosen by hand: it stays")

-- Another continent: kept, the ring hidden; back on this one: resumes.
W.Load("/way 10 10\n/way 20 20")
at(10, 10, 50, 1)
tick()
WoW.tick()
check(cur() == 1 and C.Wants("way") and not C.IsShown(), "another continent: kept, hidden")
at(10, 10)
tick()
eq(cur(), 2, "  back on its continent: reached")

-- Recovery with Books off and the windows closed, by the ticker alone.
P.Set("books", false)
GP.WayFrame.HideAll()
WoW.dead = true
WoW.tick()
check(not C.IsShown(), "dead: hidden")
WoW.dead = nil
WoW.advance(W.TICK)
check(C.IsShown() and C.Shown() == "way", "the ticker brings it back, no window open")

--------------------------------------------------------------------------------
-- The ring's owner above the books

P.Set("books", true)
C.Want("books")
eq(C.Shown(), "way", "a book's request meanwhile: the route keeps the ring")
W.Clear()
check(C.Top() == "books", "the route cleared: the books' request takes it")
C.Drop("books")

--------------------------------------------------------------------------------
-- Saved per character, cleaned at the next login (the pearl's Enable)

W.Load("/way 10 10\n/way 20 20\n/way 30 30")
at(10, 10)
tick()
GP.charDB.way.steps[3].x = 500                    -- a broken saved step
P.Set("way", false)
check(not C.Wants("way"), "switched off: the ring let go")
check(not GP.WayFrame.ListShown(), "  the list hidden")
P.Set("way", true)
eq(steps(), 2, "on again: the saved route, cleaned")
eq(cur(), 2, "  where it was")
check(isDone(1), "  with what was done")
GP.charDB.way.current = 3
P.Set("way", false)
P.Set("way", true)
check(W.IsComplete(), "complete stays complete")

--------------------------------------------------------------------------------
-- Commands and /way

local cmd = P.Command("way").run
W.Clear()
cmd("")
check(GP.WayFrame.PasteShown(), "/gpearls way with no route: the paste box")
cmd("12 34 note")
eq(steps(), 1, "/gpearls way x y note: a step")
cmd("clear")
eq(W.Route(), nil, "/gpearls way clear")
SlashCmdList.GLASSPEARLSWAY("40 40")
eq(steps(), 1, "/way x y: a step")
GP.WayFrame._test.paste():Hide()
GP.WayFrame.ShowList()
SlashCmdList.GLASSPEARLSWAY("")
check(GP.WayFrame.PasteShown() and GP.WayFrame.ListShown(), "/way alone with a route: the paste box, the list left")
GP.WayFrame._test.paste():Hide()
SlashCmdList.GLASSPEARLSWAY("reset all")
eq(W.Route(), nil, "/way reset: cleared")
P.Set("way", false)
newChat()
SlashCmdList.GLASSPEARLSWAY("40 40")
check(W.Route() == nil and chatHas("Waypoint routes is off"), "/way while off: said, nothing added")
P.Set("way", true)

done("test_way")
