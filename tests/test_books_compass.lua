-- Library books' compass (#93): the target's life (set by the toast; ended by
-- arrival, by the 150-yard re-arm, by have / done / hidden, by the switches;
-- kept and hidden while unknown, quiet, unreadable, on another continent, in
-- combat; brought back by the ticker with no new toast), the bearing
-- (NodeRadar's measured convention), the tooltip and its entrance line, the
-- rim's tint, Alt-drag and its clamp, and the reset command.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.player.faction = "Alliance"
local GP = loadAddon()
local B, P, D, C = GP.Books, GP.Pearls, GP.BookData, GP.BooksCompass

local function book(item) for _, b in ipairs(D.books) do if b.item == item then return b end end end
local THEO = 203755
local theo = book(THEO)
local spot = theo.spots[1]
WoW.items[THEO] = { name = "Archmage Theocritus' Research Journal", icon = 133740 }
-- The player dx yards west of the spot (it lies east), or dn yards south (it lies north).
local function at(dx, dn, continent) WoW.playerWorld = { spot.y + (dx or 0), spot.x - (dn or 0), continent or spot.c } end
local function shown() return C.IsShown() end
local function arrowAt()
    local a = C._test.arrow()
    local p = a._points[#a._points]
    return p[4], p[5]
end
local function near(a, b) return math.abs(a - b) < 0.01 end
local function leave() at(200); B.Tick() end

-- The bank seen: Theocritus' journal is need.
WoW.fire("BANKFRAME_OPENED")
WoW.fire("BANKFRAME_CLOSED")
WoW.flushTimers(0)
eq(B._test.states()[THEO], "need", "the journal is needed")
check(P.Setting("books", "compass"), "the compass is on by default")
WoW.facing = 0

--------------------------------------------------------------------------------
-- Set by the toast, shown

eq(B.Target(), nil, "no target before a toast")
check(C._test.root() == nil, "  nothing built")
at(50)
newChat()
B.Tick()
eq(#newChat(), 1, "within 100 yards: the toast's chat line")
eq(B.Target(), theo, "the toast's book is the compass's target")
check(shown(), "  the compass shows")
eq(C._test.text()._text, "50 yd", "  the distance")
eq(C._test.icon()._file, 133740, "  the book's icon")
local v = C._test.rim()._vertex
check(v and near(v[1], 0.80) and near(v[3], 0.38), "  the rim bronze in WoW Forever's look")

-- The bearing: the book east of a character facing north points right; facing west, behind.
local x, y = arrowAt()
check(near(x, C.ORBIT) and near(y, 0), "east, facing north: the arrow on the right")
check(near(C._test.arc()._rotation, -math.pi / 2), "  the arc turned with it")
WoW.facing = math.pi / 2
WoW.tick()
x, y = arrowAt()
check(near(x, 0) and near(y, -C.ORBIT), "east, facing west: the arrow behind")
WoW.facing = 0
at(0, 50)
WoW.tick()
x, y = arrowAt()
check(near(x, 0) and near(y, C.ORBIT), "north, facing north: the arrow ahead")
WoW.facing = math.pi / 2
WoW.tick()
x, y = arrowAt()
check(near(x, C.ORBIT) and near(y, 0), "north, facing west: the arrow on the right")
WoW.facing = 0
at(50)

--------------------------------------------------------------------------------
-- Temporary hides: kept, brought back by the ticker without a new toast

local function hiddenThenBack(label, set, unset)
    set()
    WoW.tick()
    check(not shown() and B.Target() == theo, label .. ": hidden by the ring's own frame, the target kept")
    B.Tick()
    check(not shown() and B.Target() == theo, "  still hidden after a tick")
    unset()
    newChat()
    B.Tick()
    check(shown(), label .. ": back on the next tick")
    eq(#newChat(), 0, "  with no new toast")
end
hiddenThenBack("the facing unreadable", function() WoW.facing = "throw" end, function() WoW.facing = 0 end)
hiddenThenBack("the facing secret", function() WoW.facing = WoW.Secret("f") end, function() WoW.facing = 0 end)
hiddenThenBack("the position unreadable", function() WoW.playerWorld = "throw" end, function() at(50) end)
hiddenThenBack("in an instance", function() WoW.inInstance = true end, function() WoW.inInstance = nil end)
hiddenThenBack("dead", function() WoW.dead = true end, function() WoW.dead = nil end)
hiddenThenBack("on a taxi", function() WoW.onTaxi = true end, function() WoW.onTaxi = nil end)
hiddenThenBack("another continent", function() at(50, 0, spot.c == 0 and 1 or 0) end, function() at(50) end)
check(B._test.latched[THEO], "  the latch kept across continents (no second toast on return)")
hiddenThenBack("in combat (affecting combat)", function() WoW.unitCombat.player = true end,
    function() WoW.unitCombat.player = nil end)

WoW.fire("PLAYER_REGEN_DISABLED")
check(not shown(), "a fight starts: hidden at once")
B.Tick()
check(not shown(), "  the ticker keeps it hidden in combat")
WoW.fire("PLAYER_REGEN_ENABLED")
check(shown(), "  the fight over: back at once")
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.inInstance = true
WoW.fire("PLAYER_REGEN_ENABLED")
check(not shown(), "the fight over while another hide holds: still hidden")
WoW.inInstance = nil
B.Tick()
check(shown(), "  then back")

-- Unknown: kept and hidden; need again: back. Have / done: ended.
local stb = B._test.store(true)
stb.unsure[THEO] = true
B.Refresh()
check(not shown() and B.Target() == theo, "unknown: hidden, kept")
B.Tick()
check(not shown(), "  the ticker doesn't show it while unknown")
stb.unsure[THEO] = nil
B.Refresh()
B.Tick()
check(shown(), "  need again: back")
WoW.itemCounts[THEO] = { bags = 1 }
B.Refresh()
check(B.Target() == nil and not shown(), "picked up (have): ended")
WoW.itemCounts[THEO] = nil
B.Refresh()
B.Tick()
check(B.Target() == nil, "  not back while still latched")

--------------------------------------------------------------------------------
-- Ended: the 150-yard re-arm, arrival (backing away doesn't bring it back)

leave()
at(50)
B.Tick()
check(B.Target() == theo and shown(), "away and back: a new toast, the compass again")
WoW.questsDone[theo.quest] = true
B.Refresh()
check(B.Target() == nil, "handed in (done): ended")
WoW.questsDone[theo.quest] = nil
B.Refresh()
leave()
at(50)
B.Tick()
at(200)
B.Tick()
check(B.Target() == nil and not shown(), "150 yards away: ended with the latch's re-arm")
at(50)
B.Tick()
at(5)
WoW.tick()
check(B.Target() == nil and not shown(), "within 10 yards (the ring's own frame): arrived, ended")
at(20)
B.Tick()
check(B.Target() == nil and not shown(), "  backing away: nothing")
leave()
at(50)
B.Tick()
at(5)
B.Tick()
check(B.Target() == nil and not shown(), "within 10 yards (the ticker): arrived, ended")
leave()
local before = C._test.root():IsShown()
at(5)
B.Tick()
check(B.Target() == nil and not shown() and not before, "a toast already within 10 yards: never shown")

--------------------------------------------------------------------------------
-- The switches

leave()
at(50)
B.Tick()
P.SetSetting("books", "compass", false)
check(B.Target() == nil and not shown(), "the compass switched off: ended")
P.SetSetting("books", "compass", true)
B.Tick()
check(B.Target() == nil, "  on again: nothing until the next toast")
leave()
P.SetSetting("books", "compass", false)
at(50)
B.Tick()
check(B.Target() == nil, "a toast with the compass off: no target")
P.SetSetting("books", "compass", true)
leave()
at(50)
B.Tick()
P.SetSetting("books", "nearby", false)
check(B.Target() == nil and not shown(), "the notes switched off: ended")
P.SetSetting("books", "nearby", true)
B._test.latched[THEO] = nil
at(50)
B.Tick()
check(B.Target() == theo, "  on again: a toast sets it")
P.Set("books", false)
check(B.Target() == nil and not shown(), "the pearl off: ended")
P.Set("books", true)
WoW.fire("BANKFRAME_OPENED")
WoW.fire("BANKFRAME_CLOSED")
WoW.flushTimers(0)

--------------------------------------------------------------------------------
-- The tooltip, the drag, the reset

B._test.latched[THEO] = nil
at(50)
B.Tick()
local disc = C._test.disc()
check(disc._clicks == false, "the disc lets clicks through")
disc:GetScript("OnEnter")(disc)
eq(GameTooltip:GetOwner(), disc, "hovered: the book's tooltip")
check(not table.concat(GameTooltip._lines, "\n"):find(C.ENTRANCE, 1, true), "  no entrance line for a book in the open")
local cave
for _, b in ipairs(D.books) do if b.entrance then cave = b end end
B._test.setTarget(cave)
C.Show(cave, cave.spots[1])
check(table.concat(GameTooltip._lines, "\n"):find(C.ENTRANCE, 1, true),
    "the target changed under the cursor: its tooltip follows, the entrance line for a cave book")
disc:GetScript("OnLeave")(disc)
B._test.setTarget(theo)
B.Tick()

UIParent:SetSize(1000, 800)
local cx, cy = C._test.clamp(10000, -10000)
check(near(cx, 500 - C.REACH) and near(cy, -400 + C.FOOT), "the drag's clamp keeps the whole footprint on screen")
local hit, grip, root = C._test.hit(), C._test.grip(), C._test.root()
rawset(hit, "IsMouseOver", function() return true end)
WoW.tick()
check(not grip:IsShown(), "over the compass without Alt: no grip (clicks reach the world)")
WoW.altDown = true
WoW.tick()
check(grip:IsShown(), "Alt over the compass: the grip")
grip:GetScript("OnDragStart")(grip)
check(C._test.dragging(), "  dragging")
rawset(root, "GetCenter", function() return 600, 300 end)
rawset(UIParent, "GetCenter", function() return 500, 400 end)
grip:GetScript("OnDragStop")(grip)
check(GP.charDB.booksCompass and near(GP.charDB.booksCompass.x, 100) and near(GP.charDB.booksCompass.y, -100),
    "  dropped: the spot saved per character")
grip:GetScript("OnDragStart")(grip)
WoW.altDown = false
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
check(not C._test.dragging() and not grip:IsShown(), "Alt let go mid-drag: the drag ends")
rawset(UIParent, "GetCenter", nil)
P.Set("books", false)
newChat()
P.Command("books").run("compass reset")
eq(GP.charDB.booksCompass, nil, "/gpearls books compass reset, the pearl off: the spot forgotten")
check(table.concat(newChat(), "\n"):find("back under your character", 1, true), "  said")
local p = root._points[#root._points]
check(p[1] == "CENTER" and p[2] == UIParent and near(p[4], C.HOME[1]) and near(p[5], C.HOME[2]), "  placed home")

done("test_books_compass")
