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

-- Two conversations within the ten seconds (PR #63 review): our pick belongs to
-- its own conversation. A nameless confirmation in the next one (a Blizzard or
-- keyboard selection, no PreClick of ours) never names it.
local NPC_A = { id = "NPC", guid = "Creature-0-1-2-3-4567-0000AAAA" }
local NPC_B = { id = "NPC", guid = "Creature-0-1-2-3-4568-0000BBBB" }
-- Another NPC after a terminal close: a new chain.
WoW.units.npc = NPC_A
SS.SetAdd(G.ALWAYS, 710)
n = selects()
talk({ options = { opt(701, 1), opt(710, 2) } })
eq(selects(), n + 1, "picked at the first NPC")
bye()                                              -- terminal close: the chain ends
WoW.units.npc = NPC_B
talk({ options = { opt(711, 1), opt(712, 2) } })   -- the second NPC: nothing picked
eq(selects(), n + 1, "  nothing picked at the second")
WoW.fire("CONFIRM_BINDER", "The inn")              -- the player picked there, not through our hook
check(SS.SetHas(G.ALWAYS, 710) and not confirms[710], "another NPC's confirmation never names our earlier pick")
bye()
-- The same NPC, a new conversation (a new chain): the same.
WoW.units.npc = NPC_A
SS.SetAdd(G.ALWAYS, 713)
n = selects()
talk({ options = { opt(701, 1), opt(713, 2) } })
eq(selects(), n + 1, "picked")
bye()
talk({ options = { opt(714, 1), opt(715, 2) } })
WoW.fire("CONFIRM_TALENT_WIPE", 1000)
check(SS.SetHas(G.ALWAYS, 713) and not confirms[713], "a new conversation at the same NPC: not ours either")
bye()
-- Another NPC within a chain the close left open (continuing or unknown): its GUID tells.
SS.SetAdd(G.ALWAYS, 716)
n = selects()
talk({ options = { opt(701, 1), opt(716, 2) } })
eq(selects(), n + 1, "picked")
WoW.closeGossip(true)                              -- a close that may continue: the chain stays
WoW.units.npc = NPC_B
talk({ options = { opt(717, 1), opt(718, 2) } })
WoW.fire("CONFIRM_BINDER", "The inn")
check(SS.SetHas(G.ALWAYS, 716) and not confirms[716], "another NPC in an open chain: not ours")
bye()
-- The same conversation's next page keeps it (a multi-page NPC, then the popup).
WoW.units.npc = NPC_A
SS.SetAdd(G.ALWAYS, 719)
n = selects()
talk({ options = { opt(701, 1), opt(719, 2) } })
eq(selects(), n + 1, "picked")
talk({ options = { opt(720, 1), opt(721, 2) } })   -- the same NPC's next page, the chain open
WoW.fire("CONFIRM_BINDER", "The inn")
check(not SS.SetHas(G.ALWAYS, 719) and confirms[719], "the same conversation's next page: still ours")
bye()

done("test_autogossip_audit")
