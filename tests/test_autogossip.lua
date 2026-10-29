-- Auto gossip (#47): what gets picked and when. The lone rule and its
-- settings, the always list, every refusal, Blizzard's own lone pick in both
-- orders, one attempt per page, the fresh re-check, chains and how they end.
-- Learning is test_autogossip_learn.lua; the prompt and panel
-- test_autogossip_frame.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.fileIDs["Interface\\GossipFrame\\VendorGossipIcon"] = 132060
WoW.fileIDs["Interface\\GossipFrame\\BankerGossipIcon"] = 132050
local GP = loadAddon()
local G, P, SS = GP.AutoGossip, GP.Pearls, GP.SettingsSync

local VENDOR, BINDER, HEALER, TAXI, CHAT = 132060, 132052, 132054, 132057, 132053
local function opt(id, index, icon, extra)
    if icon == nil then icon = CHAT elseif icon == false then icon = nil end
    local o = { id = id, index = index or 1, icon = icon, status = 0,
        name = type(id) == "number" and ("Option " .. id) or "An option" }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end
local function selects() return #WoW.gossipSelects end
local function lastSelect() return WoW.gossipSelects[#WoW.gossipSelects] end
-- Open a page and let the deferred decision run.
local function talk(spec)
    WoW.openGossip(spec)
    WoW.flushTimers(0)
end
local function bye() WoW.closeGossip(false) end

-- The pearl.
local def = P.Get("autogossip")
check(def ~= nil and def.category == "Automation" and def.default == true, "registered: Automation, on by default")
eq(P.Setting("autogossip", "lone"), "most", "lone options: all but binder and healer by default")

-- A lone option: picked by ID, after a frame, never confirmed.
local n = selects()
WoW.openGossip({ options = { opt(101, 1, VENDOR) } })
eq(selects(), n, "nothing at the show itself: the decision waits a frame")
WoW.flushTimers(0)
eq(selects(), n + 1, "a lone option is picked")
check(lastSelect().fn == "SelectOption" and lastSelect().arg == 101, "  by its ID")
eq(lastSelect().confirmed, nil, "  never with confirmed")
eq(lastSelect().text, nil, "  and no text")
bye()

-- The lone rule.
local function picksLone(icon, extra)
    local before = selects()
    talk({ options = { opt(200 + (icon or 0) % 97, 1, icon, extra) } })
    bye()
    return selects() > before
end
check(not picksLone(BINDER), "most: never the hearthstone binder")
check(not picksLone(136458), "  nor its other icon")
check(not picksLone(HEALER), "  nor the spirit healer")
check(picksLone(CHAT), "  a story NPC's lone line: picked")
check(not picksLone(false), "  an option without an icon: not picked")
P.SetSetting("autogossip", "lone", "any")
check(picksLone(BINDER), "any: even the binder")
P.SetSetting("autogossip", "lone", "services")
check(picksLone(VENDOR), "services: a vendor (resolved from its path)")
check(picksLone(132050), "  a banker (resolved)")
check(picksLone(TAXI), "  a flight master (known icon)")
check(not picksLone(CHAT), "  not a story NPC")
check(not picksLone(132070), "  not the trainer icon's path, unresolved")
check(picksLone(132058), "  the trainer by its known icon")
P.SetSetting("autogossip", "lone", "off")
check(not picksLone(VENDOR), "off: nothing")
P.ResetSettings("autogossip")
check(picksLone(VENDOR, { override = BINDER }) == false, "the override icon counts first")

-- Refusals.
local function picks(spec)
    local before = selects()
    talk(spec)
    bye()
    return selects() > before
end
check(not picks({ options = { opt(301, 1, VENDOR) }, available = 1 }), "a quest to accept: nothing")
check(not picks({ options = { opt(302, 1, VENDOR) }, active = 1 }), "a quest to turn in: nothing")
WoW.shift = true
check(not picks({ options = { opt(303, 1, VENDOR) } }), "Shift held: nothing")
WoW.shift = false
WoW.fire("PLAYER_REGEN_DISABLED")
check(not picks({ options = { opt(304, 1, VENDOR) } }), "in combat: nothing")
WoW.fire("PLAYER_REGEN_ENABLED")
check(not picks({ options = { opt(305, 1, VENDOR, { status = 1 }) } }), "an unavailable option: nothing")
check(not picks({ options = { opt(306, 1, VENDOR) }, force = true }), "the NPC forces its gossip: no lone pick")
check(not picks({ options = { opt(307, 1, VENDOR), opt(308, 2, VENDOR) } }), "several options: nothing")
check(not picks({ options = { opt(309, 1, VENDOR) }, textureKit = "skyriding" }), "a custom gossip frame: out of scope")
check(not picks({ options = { opt(310, 1, VENDOR) }, textureKit = WoW.Secret("kit") }), "a secret texture kit: out of scope")
check(not picks({ options = { opt(311, 1, VENDOR) }, npc = false }), "no NPC (an object, a book): out of scope")
WoW.gossipOptionsSecret = true
check(not picks({ options = { opt(312, 1, VENDOR) } }), "options that can't be read: nothing")
WoW.gossipOptionsSecret = nil
check(not picks({ options = { opt(WoW.Secret("id"), 1, VENDOR) } }), "a secret option ID: nothing")

-- Blizzard's own lone pick: never a second select on top, in either order.
for _, first in ipairs({ true, false }) do
    local before = selects()
    talk({ options = { opt(401, 1, VENDOR, { only = true }) }, blizzardFirst = first })
    eq(selects() - before, 1, ("Blizzard's lone pick (%s first): one select only"):format(first and "Blizzard" or "ours"))
    eq(lastSelect().fn, "SelectOptionByIndex", "  Blizzard's")
    bye()
end
SS.SetAdd(G.ALWAYS, 402)
local before = selects()
talk({ options = { opt(402, 1, VENDOR, { only = true }) } })
eq(selects() - before, 1, "Blizzard's lone pick of an always option: still one select")
bye()

-- The always list.
SS.SetAdd(G.ALWAYS, 502)
before = selects()
talk({ options = { opt(501, 1, CHAT), opt(502, 2, BINDER) } })
check(selects() == before + 1 and lastSelect().arg == 502, "an always option among several: picked by ID")
bye()
before = selects()
talk({ options = { opt(503, 1, CHAT), opt(502, 2, CHAT) }, force = true })
check(selects() == before + 1 and lastSelect().arg == 502, "  even when the NPC forces its gossip")
bye()
SS.SetAdd(G.ALWAYS, 504)
check(not picks({ options = { opt(502, 1), opt(504, 2) } }), "two always options on a page: nothing")
check(not picks({ options = { opt(502, 1, CHAT, { status = 2 }), opt(505, 2) } }), "an always option locked: nothing")
check(not picks({ options = { opt(502, 1) }, available = 1 }), "an always option with quest business: nothing")

-- One attempt per page: anything selecting first cancels it.
before = selects()
WoW.openGossip({ options = { opt(601, 1, VENDOR), opt(602, 2, VENDOR) } })
SS.SetAdd(G.ALWAYS, 601)
WoW.playerPicks(2)
WoW.flushTimers(0)
check(selects() == before + 1 and lastSelect().arg == 2, "the player's pick before our frame: ours cancelled")
bye()
before = selects()
WoW.openGossip({ options = { opt(603, 1, VENDOR) } })
C_GossipInfo.SelectOption(603)      -- another addon
WoW.flushTimers(0)
eq(selects(), before + 1, "another addon's select before our frame: ours cancelled")
bye()
-- A refresh replaces the decision; and keeps the show's scope.
before = selects()
WoW.openGossip({ options = { opt(604, 1, VENDOR) } })
WoW.refreshGossip({ opt(604, 1, VENDOR), opt(605, 2, VENDOR) })
WoW.flushTimers(0)
eq(selects(), before, "a refresh with a second option: the lone decision is gone")
bye()
before = selects()
WoW.openGossip({ options = { opt(606, 1, VENDOR), opt(607, 2) }, textureKit = "kit" })
WoW.refreshGossip({ opt(606, 1, VENDOR) })
WoW.flushTimers(0)
eq(selects(), before, "a refresh of an out-of-scope page stays out of scope")
bye()
-- The fresh re-check: the page changed without an event.
before = selects()
WoW.openGossip({ options = { opt(608, 1, VENDOR) } })
table.insert(WoW.gossip.options, opt(609, 2, VENDOR))
WoW.flushTimers(0)
eq(selects(), before, "a lone option that gained a sibling before the pick: nothing")
bye()
before = selects()
WoW.openGossip({ options = { opt(610, 1, VENDOR) } })
WoW.gossip.available = 1
WoW.flushTimers(0)
eq(selects(), before, "a quest appearing before the pick: nothing")
bye()
-- Sparse and reordered orderIndex: by ID, whatever the order.
before = selects()
talk({ options = { opt(611, 7, CHAT), opt(502, 3, CHAT) } })
check(lastSelect().arg == 502 and selects() == before + 1, "sparse, reordered indexes: the always option by ID")
bye()

-- Chains: three picks at most, never the same option twice, none after a
-- pick by index only; a page shown inside our select keeps its decision.
local pageNo = 0
local function nextPage(ids)
    WoW.gossipOnSelect = function()
        pageNo = pageNo + 1
        local id = ids[pageNo]
        if id ~= nil then
            WoW.closeGossip(true)
            WoW.openGossip({ options = { opt(id == false and nil or id, 1, VENDOR) } })
        end
    end
end
nextPage({ 702, 703, 704, 705 })
before = selects()
talk({ options = { opt(701, 1, VENDOR) } })
WoW.flushTimers(0); WoW.flushTimers(0); WoW.flushTimers(0)
eq(selects() - before, 3, "a chain stops after three automatic picks")
WoW.gossipOnSelect = nil
bye()
pageNo = 0
nextPage({ 711 })
before = selects()
talk({ options = { opt(711, 1, VENDOR) } })
WoW.flushTimers(0)
eq(selects() - before, 1, "the same option on the next page: not picked twice")
WoW.gossipOnSelect = nil
bye()
pageNo = 0
nextPage({ 722 })
before = selects()
talk({ options = { opt(nil, 4, VENDOR) } })
check(lastSelect().fn == "SelectOptionByIndex" and lastSelect().arg == 4, "an option with a hidden ID: by its index")
WoW.flushTimers(0)
eq(selects() - before, 1, "  and no pick after it in the chain")
WoW.gossipOnSelect = nil
bye()

-- How a chain ends.
local function capChain()
    pageNo = 0
    nextPage({ 802, 803, 804 })
    talk({ options = { opt(801, 1, VENDOR) } })
    WoW.flushTimers(0); WoW.flushTimers(0)
    WoW.gossipOnSelect = nil
end
local function freshPicks()
    local b = selects()
    talk({ options = { opt(899, 1, VENDOR) } })
    return selects() > b
end
capChain()
WoW.closeGossip(true)
check(not freshPicks(), "a continuing close keeps the capped chain")
WoW.closeGossip(WoW.Secret("continuing"))
check(not freshPicks(), "  so does a close that can't be read")
WoW.closeGossip(false)
check(freshPicks(), "a terminal close ends it")
WoW.closeGossip(false)
capChain()
WoW.closeGossip(true)
WoW.units.npc = nil
WoW.flushTimers(1)
WoW.units.npc = { id = "NPC", guid = "Creature-0-1-2-3-4567-0000ABCD" }
check(freshPicks(), "a second after a close, the NPC gone: the chain ends")
WoW.closeGossip(false)
capChain()
WoW.closeGossip(true)
WoW.flushTimers(1)
check(not freshPicks(), "the NPC still there: the chain goes on")
WoW.closeGossip(true)
WoW.flushTimers(G.ABSENCE_SECONDS)
check(freshPicks(), "after a long absence of pages (a service window): it ends")
WoW.closeGossip(false)
-- An old chain's timer, falling due after a newer chain began, leaves it alone.
WoW.now = 1000
talk({ options = { opt(870, 1, VENDOR), opt(871, 2) } })   -- chain A
WoW.closeGossip(true)                                      -- A's timers: 1001, 1060
WoW.fire("PLAYER_ENTERING_WORLD", false, false)            -- A ends
WoW.advance(30)                                            -- 1030
capChain()                                                 -- chain B, capped
WoW.closeGossip(true)                                      -- B's timers: 1031, 1090
WoW.advance(31)                                            -- 1061: A's absence timer is due, not B's
check(not freshPicks(), "an old chain's timer leaves a newer chain alone")
WoW.closeGossip(false)
-- An out-of-scope page inside a running chain: still nothing.
talk({ options = { opt(880, 1, VENDOR), opt(881, 2) } })
WoW.closeGossip(true)
check(not picks({ options = { opt(882, 1, VENDOR) }, textureKit = "kit" }), "an out-of-scope page in a running chain: nothing")
capChain()
WoW.closeGossip(true)
talk({ options = { opt(890, 1, VENDOR), opt(891, 2) } })   -- a page: the absence restarts
WoW.closeGossip(true)
WoW.flushTimers(G.ABSENCE_SECONDS - 1)
check(not freshPicks(), "a page interrupts the absence")
WoW.closeGossip(false)
capChain()
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(freshPicks(), "a loading screen ends the chain")
bye()

-- A select that throws: recorded, and our flag is cleared (another addon's
-- select is seen again afterwards).
WoW.gossipSelectThrows = true
talk({ options = { opt(901, 1, VENDOR) } })
WoW.gossipSelectThrows = nil
check(GP.failures["pearl autogossip select"] ~= nil, "a throwing select is recorded")
eq(G.state.own, false, "  and the own-call flag cleared")
bye()

-- Switching off, or a setting changing, cancels a pending decision.
before = selects()
WoW.openGossip({ options = { opt(902, 1, VENDOR) } })
P.Set("autogossip", false)
WoW.flushTimers(0)
eq(selects(), before, "switched off before the frame: nothing")
WoW.closeGossip(false)
P.Set("autogossip", true)
WoW.openGossip({ options = { opt(903, 1, VENDOR) } })
P.SetSetting("autogossip", "offer", false)
WoW.flushTimers(0)
eq(selects(), before, "a setting changed before the frame: nothing")
P.ResetSettings("autogossip")
bye()

-- Every select of ours: never confirmed.
local confirmedAny = false
for _, s in ipairs(WoW.gossipSelects) do if s.confirmed ~= nil then confirmedAny = true end end
check(not confirmedAny, "no select ever passed confirmed")

done("test_autogossip")
