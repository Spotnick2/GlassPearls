-- Library books (#72): the states (faction, handed in, carried, the bank and
-- its failure cases, unconfirmed and absent books), the pins (both displays,
-- HereBeDragons' axis order, only need and unknown), nearby (same continent,
-- unreadable positions, the latch and its re-arm, the quiet states, several
-- books at once, a book with several spots), the toast (click-only), the
-- settings, the command, and switching off.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.player.faction = "Alliance"
local GP = loadAddon()
local B, P, D = GP.Books, GP.Pearls, GP.BookData
local F = GP.BooksFrame

local function book(item) for _, b in ipairs(D.books) do if b.item == item then return b end end end
local THEO, RUMI, TAZO, LUDDITE, LIMINAL, STUDY = 203755, 208860, 207972, 215824, 220347, 228135
local theo = book(THEO)
local function st(item) return B.State(book(item)) end
local function at(spot, dx) WoW.playerWorld = { spot.y + (dx or 0), spot.x, spot.c } end   -- west, north, continent
local function shown(display) return WoW.hbdCount(display, B) end
local function spotsOf(filter)
    local n = 0
    for _, b in ipairs(D.books) do if filter(b) then n = n + #b.spots end end
    return n
end
local function refresh() B.Refresh() end

check(P.IsLive("books"), "on by default")
eq(P.Get("books").category, "Interface", "on the Interface page")
eq(P.Get("books").section, "Maps", "  under Maps")
check(P.Setting("books", "worldmap") and P.Setting("books", "minimap") and P.Setting("books", "nearby"),
    "the three settings on by default")
eq(#D.books, 40, "the client's 40 books")
check(B._test.ticker() ~= nil, "a ticker while nearby is on")

-- Before the bank was ever seen: a plain zero proves nothing.
eq(st(THEO), "unknown", "bank never seen: unknown, not need")
eq(B.BANK_COUNT_UNOPENED, false, "  the count before opening the bank isn't trusted (unmeasured)")
eq(st(TAZO), "hidden", "the Horde's book, as Alliance: hidden")
eq(st(RUMI), "unknown", "the Alliance's book, as Alliance: like any other")
eq(st(LIMINAL), "hidden", "an absent book: hidden")
local visible = spotsOf(function(b) return b.status ~= "absent" and b.faction ~= "Horde" end)
eq(shown("world"), visible, "every unknown book's spots on the world map")
eq(shown("mini"), visible, "  and on the minimap")
-- The calls: HereBeDragons' world is (west, north): our y then x.
local call
for _, c in ipairs(WoW.hbd.calls) do if c.ref == B and c.icon.book == theo and c.display == "world" then call = c end end
eq(call.kind, "World", "pins from world coordinates")
eq(call.args[1], theo.spots[1].c, "  the continent")
eq(call.args[2], theo.spots[1].y, "  HereBeDragons' x is our y (west)")
eq(call.args[3], theo.spots[1].x, "  its y is our x (north)")
eq(call.args[4], B.SHOW_CONTINENT, "  zone and continent maps")
eq(call.icon._clicks, false, "clicks go through to the map")

-- No note for an unknown book.
newChat()
at(theo.spots[1])
B.Tick()
eq(#newChat(), 0, "unknown: no chat line")
check(not F.IsShown(), "  no toast")

-- The bank opens: recorded, established.
WoW.fire("BANKFRAME_OPENED")
WoW.fire("BANKFRAME_CLOSED")
WoW.flushTimers(0)
check(B._test.store(false).bankSeen, "a bank visit establishes the bank")
eq(st(THEO), "need", "then a plain zero is need")
eq(shown("world"), visible, "need books are shown too")
check(B.TooltipLines(theo, theo.spots[1], "need")[1][1] == "Library book", "an uncached name: 'Library book'")
WoW.items[THEO] = { name = "Archmage Theocritus' Research Journal", icon = 133740 }
eq(B.TooltipLines(theo, theo.spots[1], "need")[1][1], "Archmage Theocritus' Research Journal", "  the client's name")
WoW.mapInfo[theo.spots[1].zone] = { name = "Elwynn Forest" }
eq(B.Where(theo.spots[1]), "Elwynn Forest 65.4, 70.1", "where: the client's zone name and the coordinates")

-- Nearby: once on entering; the latch holds until 150 yards.
B._test.latched[THEO] = nil
at(theo.spots[1])
newChat()
B.Tick()
local lines = newChat()
eq(#lines, 1, "within 100 yards: one chat line")
check(lines[1]:find("Library book nearby", 1, true) and lines[1]:find("Elwynn Forest 65.4, 70.1", 1, true),
    "  the book and where")
check(F.IsShown(), "  and the toast")
eq(F.Get().view.item, THEO, "  showing that book")
eq(F.Get().icon._file, 133740, "  with its icon")
B.Tick()
eq(#newChat(), 0, "still there: nothing again")
at(theo.spots[1], 120)
B.Tick()
at(theo.spots[1])
B.Tick()
eq(#newChat(), 0, "120 yards away and back: still latched (re-arm at 150)")
F.Hide()
B.Tick()
check(not F.IsShown() and #newChat() == 0, "closing the toast doesn't re-arm")
WoW.playerWorld = nil
B.Tick()
WoW.playerWorld = "throw"
B.Tick()
WoW.playerWorld = { WoW.Secret("x"), theo.spots[1].x, 0 }
B.Tick()
at(theo.spots[1])
B.Tick()
eq(#newChat(), 0, "no position, a refused read or a secret: nothing, and no re-arm")
eq(B.Position(), theo.spots[1].c, "a plain reading: its continent")
at(theo.spots[1], 160)
B.Tick()
at(theo.spots[1])
B.Tick()
eq(#newChat(), 1, "160 yards away and back: alerted again")

-- The same coordinates on the other continent are nowhere near.
F.Hide()
at(theo.spots[1], 200)
B.Tick()
WoW.playerWorld = { theo.spots[1].y, theo.spots[1].x, 1 }
newChat()
B.Tick()
eq(#newChat(), 0, "the same numbers on Kalimdor: no alert")
check(not B.Nearest(theo, 1, theo.spots[1].x, theo.spots[1].y), "  no distance across continents")

-- Quiet in an instance, dead, on a taxi; latches kept.
at(theo.spots[1], 200)
B.Tick()
for _, q in ipairs({ { "inInstance", true }, { "dead", true }, { "onTaxi", true } }) do
    WoW[q[1]] = q[2]
    at(theo.spots[1])
    B.Tick()
    eq(#newChat(), 0, q[1] .. ": quiet")
    WoW[q[1]] = nil
end
B.Tick()
eq(#newChat(), 1, "back to normal: the alert comes")
F.Hide()

-- A book with several spots: any of them; re-armed only away from all.
local study = book(STUDY)
check(#study.spots == 2, "A Study of the Light: two spots")
at(study.spots[2])
B.Tick()
eq(#newChat(), 1, "its second spot alerts")
at(study.spots[1])
B.Tick()
eq(#newChat(), 0, "  its first spot then doesn't (one latch per book)")
F.Hide()

-- Several books entering together: a line each, the nearest on the toast.
local enter = B.ENTER
B.ENTER, B.LEAVE = 1e6, 2e6
for k in pairs(B._test.latched) do B._test.latched[k] = nil end
at(theo.spots[1], 50)
B.Tick()
local many = newChat()
check(#many > 5, "everything in range at once: a line each (" .. #many .. ")")
eq(F.Get().view.item, THEO, "  the toast shows the nearest")
B.Tick()
eq(#newChat(), 0, "  and nothing replaces it the next second")
B.ENTER, B.LEAVE = enter, enter * 1.5
F.Hide()

-- States.
WoW.questsDone[theo.quest] = true
refresh()
eq(st(THEO), "done", "handed in: done")
eq(shown("world"), visible - 1, "  and off the map")
WoW.questsDone[theo.quest] = "throw"
eq(st(THEO), "unknown", "a completion read that throws: unknown")
WoW.questsDone[theo.quest] = WoW.Secret("q")
eq(st(THEO), "unknown", "  a secret one: unknown")
WoW.questsDone[theo.quest] = nil
WoW.itemCounts[THEO] = { bags = 1 }
eq(st(THEO), "have", "carried: have")
WoW.itemCounts[THEO] = { bags = WoW.Secret("n") }
eq(st(THEO), "unknown", "a secret count: unknown")
WoW.itemCountThrows[THEO] = true
eq(st(THEO), "unknown", "a count that throws: unknown")
WoW.itemCountThrows[THEO] = nil
WoW.itemCounts[THEO] = nil
eq(st(THEO), "need", "gone again: need")
eq(st(LUDDITE), "unknown", "an unconfirmed book is never need")
check(table.concat((function() local t = {} for _, l in ipairs(B.TooltipLines(book(LUDDITE), book(LUDDITE).spots[1], "unknown")) do t[#t + 1] = l[1] end return t end)(), "\n")
    :find("Not confirmed in WoW Forever", 1, true), "  and says so")
WoW.player.faction = nil
eq(st(RUMI), "unknown", "a faction that can't be read: a faction book is unknown, never hidden")
eq(st(TAZO), "unknown", "  either side's")
WoW.player.faction = WoW.Secret("f")
eq(st(RUMI), "unknown", "  a secret faction too")
WoW.player.faction = "Horde"
eq(st(RUMI), "hidden", "as Horde: the Alliance's book is hidden")
eq(st(TAZO), "need", "  and the Horde's needed")
WoW.player.faction = "Alliance"

-- The bank, case by case (books.bank / books.unsure).
local S = B._test.store(true)
local function visit(fn)
    WoW.fire("BANKFRAME_OPENED")
    if fn then fn() end
    WoW.fire("BANKFRAME_CLOSED")
end
visit(function() WoW.itemCounts[THEO] = { bank = 1 } end)
check(S.bank[THEO], "a banked book is recorded")
WoW.itemCounts[THEO] = nil   -- a later login where the count leaves the bank out
eq(st(THEO), "have", "  and stays have when the count says 0")
visit(function() WoW.itemCounts[THEO] = nil end)
eq(st(THEO), "need", "a visit that reads it gone: need")
-- Withdrawn, the bank closed before the deferred refresh, then deleted.
visit(function() WoW.itemCounts[THEO] = { bank = 1 } end)
WoW.fire("BANKFRAME_OPENED")
WoW.itemCounts[THEO] = { bags = 1 }
WoW.fire("BANKFRAME_CLOSED")
WoW.itemCounts[THEO] = nil
WoW.flushTimers(0)
eq(st(THEO), "need", "withdrawn, closed before any refresh, deleted: need")
-- A deposit whose counts can't be read: unknown, not need.
WoW.fire("BANKFRAME_OPENED")
WoW.itemCounts[THEO] = { bank = 1 }
WoW.itemCountThrows[THEO] = true
WoW.fire("BANKFRAME_CLOSED")
WoW.itemCountThrows[THEO] = nil
WoW.itemCounts[THEO] = nil
check(S.unsure[THEO], "an unreadable count during a visit: unresolved")
eq(st(THEO), "unknown", "  a deposit then: unknown, not need")
visit(function() WoW.itemCounts[THEO] = nil end)
eq(st(THEO), "need", "  a later visit resolves it")
-- A remembered book withdrawn, unreadable at the close, then deleted.
visit(function() WoW.itemCounts[THEO] = { bank = 1 } end)
WoW.fire("BANKFRAME_OPENED")
WoW.itemCounts[THEO] = { bags = 1 }
WoW.itemCountThrows[THEO] = true
WoW.fire("BANKFRAME_CLOSED")
WoW.itemCountThrows[THEO] = nil
WoW.itemCounts[THEO] = nil
eq(st(THEO), "unknown", "remembered, withdrawn, unreadable, deleted: unknown, not have")
WoW.itemCounts[THEO] = { bags = 1 }
eq(st(THEO), "have", "  a carried read resolves it")
check(not S.unsure[THEO] and not S.bank[THEO], "  and clears both")
WoW.itemCounts[THEO] = nil
eq(st(THEO), "need", "  deleted after: need")
-- Only books, item IDs only.
for k in pairs(S.bank) do check(type(k) == "number", "the bank list keeps item IDs") end

-- Events refresh a frame later, once.
WoW.questsDone[theo.quest] = true
WoW.fire("QUEST_TURNED_IN", theo.quest, 0, 0)
WoW.fire("QUEST_LOG_UPDATE")
eq(B._test.states()[THEO], "need", "an event: not at once")
WoW.flushTimers(0)
eq(B._test.states()[THEO], "done", "  a frame later")
WoW.questsDone[theo.quest] = nil
WoW.fire("UNIT_FACTION", "target")
WoW.flushTimers(0)
eq(B._test.states()[THEO], "done", "UNIT_FACTION for another unit: no refresh")
WoW.fire("UNIT_FACTION", "player")
WoW.flushTimers(0)
eq(B._test.states()[THEO], "need", "  for the player: refreshed")

-- Settings, local or from sync.
P.SetSetting("books", "worldmap", false)
eq(shown("world"), 0, "world map off: no world pins")
eq(shown("mini"), visible, "  the minimap keeps them")
P.SetSetting("books", "minimap", false)
eq(shown("mini"), 0, "both off: no pins")
P.SetSetting("books", "worldmap", true)
eq(shown("mini"), 0, "minimap off alone: no minimap pins")
eq(shown("world"), visible, "  the world map has them")
P.SetSetting("books", "minimap", true)
eq(shown("world"), visible, "both back")
P.SetSetting("books", "nearby", false)
check(B._test.ticker() == nil, "nearby off: the ticker stops")
B._test.latched[THEO] = nil
at(theo.spots[1])
B.Tick()
eq(#newChat(), 0, "  and a tick does nothing")
P.SetSetting("books", "nearby", true)
check(B._test.ticker() ~= nil, "nearby on: it starts again")

-- The command.
newChat()
SlashCmdList.GLASSPEARLS("books")
check(chatHas("Library books: %d+ to find"), "/gpearls books: the counts")
check(chatHas("Nearest to find"), "  and the nearest")
SlashCmdList.GLASSPEARLS("books test")
check(F.IsShown(), "/gpearls books test: the toast")
check(not F.Get()._special, "the toast isn't closed by Esc")
for _, name in ipairs(UISpecialFrames or {}) do check(name ~= F.NAME, "  not in UISpecialFrames") end
F.Get().ok:GetScript("OnClick")(F.Get().ok)
check(not F.IsShown(), "its OK closes it")

-- Off: everything goes; a deferred refresh from before does nothing.
WoW.fire("BAG_UPDATE_DELAYED")
F.Show(B.View(theo, theo.spots[1], 10))
P.Set("books", false)
eq(shown("world"), 0, "off: no world pins")
eq(shown("mini"), 0, "  no minimap pins")
check(B._test.ticker() == nil, "  the ticker cancelled")
check(not F.IsShown(), "  the toast hidden")
WoW.flushTimers(0)
eq(shown("world"), 0, "  a refresh queued before doesn't rebuild")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
WoW.flushTimers(0)
eq(shown("world"), 0, "  and no event does")
P.Set("books", true)
eq(shown("world"), visible, "back on: the pins again")
check(B._test.ticker() ~= nil, "  and the ticker")

done("test_books")
