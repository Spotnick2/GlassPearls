-- Auto gossip after the audit (#61): a confirmation that names no option
-- (CONFIRM_BINDER, _TALENT_WIPE, _XP_LOSS) after OUR OWN pick names that pick,
-- so an always-listed binder or talent master asks once, then comes off the
-- list; it's forgotten after PENDING_SECONDS; the player's pending pick still
-- comes first; switched off, nothing is remembered.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local G, P, SS = GP.AutoGossip, GP.Pearls, GP.SettingsSync
local CHAT, BINDER = 132053, 132052
local function opt(id, index, icon)
    return { id = id, index = index or 1, icon = icon or CHAT, status = 0, name = "Option " .. id }
end
local function selects() return #WoW.gossipSelects end
local function talk(spec) WoW.openGossip(spec); WoW.flushTimers(0) end
local function bye() WoW.closeGossip(false) end
local confirms = G._test.db().confirms

-- An always-listed binder: our pick, Blizzard's popup (CONFIRM_BINDER inside
-- the select), the option off the list and said; never picked again.
SS.SetAdd(G.ALWAYS, 702)
G._test.db().names[702] = "Make this inn your home"
WoW.gossipOnSelect = function(fn, arg) if arg == 702 then WoW.fire("CONFIRM_BINDER", "The inn") end end
newChat()
local n = selects()
talk({ options = { opt(701, 1), opt(702, 2, BINDER) } })
eq(selects(), n + 1, "the always-listed binder is picked (the design: always wins)")
check(not SS.SetHas(G.ALWAYS, 702), "a confirmation after our own pick takes it off the always list")
check(confirms[702] == true, "  and marks it confirmed")
check(chatHas("Make this inn your home"), "  and says which, by its text")
bye()
n = selects()
talk({ options = { opt(701, 1), opt(702, 2, BINDER) } })
eq(selects(), n, "  never picked again")
bye()
WoW.gossipOnSelect = nil

-- The confirmation after the gossip closed (the client closes it first): still ours.
SS.SetAdd(G.ALWAYS, 703)
n = selects()
talk({ options = { opt(701, 1), opt(703, 2, BINDER) } })
eq(selects(), n + 1, "picked")
bye()                                   -- the client closes the gossip (not continuing)
WoW.fire("CONFIRM_TALENT_WIPE", 1000)
check(not SS.SetHas(G.ALWAYS, 703) and confirms[703] == true, "a confirmation after the close still names our pick")

-- Forgotten after PENDING_SECONDS: a late confirmation names nothing.
SS.SetAdd(G.ALWAYS, 704)
n = selects()
talk({ options = { opt(701, 1), opt(704, 2) } })
eq(selects(), n + 1, "picked")
bye()
WoW.flushTimers(G.PENDING_SECONDS)
WoW.fire("CONFIRM_XP_LOSS")
check(SS.SetHas(G.ALWAYS, 704) and not confirms[704], "a confirmation later than the wait names nothing")

-- The player's own pending pick comes first.
SS.SetAdd(G.ALWAYS, 705)
n = selects()
talk({ options = { opt(701, 1), opt(705, 2) } })   -- ours: 705, the page stays
eq(selects(), n + 1, "picked")
check(WoW.playerPicks(1), "the player then clicks the first option")
WoW.fire("CONFIRM_BINDER", "The inn")
check(confirms[701] == true and not confirms[705], "the player's pending pick is named, not ours")
check(SS.SetHas(G.ALWAYS, 705), "  ours stays listed")
bye()

-- Switched off: nothing remembered, nothing heard.
SS.SetAdd(G.ALWAYS, 706)
n = selects()
talk({ options = { opt(701, 1), opt(706, 2) } })
eq(selects(), n + 1, "picked")
P.Set("autogossip", false)
WoW.fire("CONFIRM_BINDER", "The inn")
P.Set("autogossip", true)
check(SS.SetHas(G.ALWAYS, 706) and not confirms[706], "switched off: nothing remembered or removed")
bye()

done("test_autogossip_audit")
