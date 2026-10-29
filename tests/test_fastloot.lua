-- Faster loot (#36): when a pass runs (the auto-loot rule, once per session,
-- the zero-slot exception, switching off and on), its order, and every slot
-- it leaves to the game. The bags-full helper beside it is
-- test_fastloot_bagsfull.lua; the coin text test_fastloot_frame.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local L, P = GP.FastLoot, GP.Pearls
local T, M = Enum.LootSlotType, Enum.LootMethod

local function items(t) for id, it in pairs(t) do WoW.items[id] = it end end
local function bags(free)
    WoW.bags = { [0] = { size = free, items = {} } }
end
local function reset()
    WoW.resetBags()
    items({ [10] = { name = "Linen Cloth", maxStack = 20, quality = 1 }, [11] = { name = "Ring", maxStack = 1, quality = 2 },
            [12] = { name = "Sword", maxStack = 1, quality = 3 } })
    bags(10)
    WoW.group, WoW.lootMethod, WoW.lootThreshold = { raid = false, party = false }, M.Group, 2
end
local function lootCalls()
    local slots = {}
    for _, c in ipairs(WoW.calls) do if c[1] == "LootSlot" then slots[#slots + 1] = c[2] end end
    return slots
end
local function open(rows, opts)
    reset()
    WoW.openLoot(rows, opts)
    return lootCalls()
end
local function close() WoW.closeLoot() end
local AUTO = { autoloot = true }

-- The pearl.
local def = P.Get("fastloot")
check(def ~= nil and def.category == "Loot & Bags" and def.default == true, "registered: Loot & Bags, on by default")

-- Auto loot on: every slot, from the first up.
local calls = open({ { id = 10, qty = 5 }, { id = 11 }, { kind = T.Money } }, AUTO)
eq(table.concat(calls, ","), "1,2,3", "auto loot on: every slot, first up")
close()

-- The auto-loot rule.
eq(#open({ { id = 10 } }, { autoloot = false }), 0, "the payload false: nothing")
close()
eq(#open({ { id = 10 } }, { autoloot = true, noReady = true }), 1, "LOOT_OPENED alone, true: the pass")
close()
eq(#open({ { id = 10 } }, { autoloot = WoW.Secret("auto") }), 0, "a secret payload: nothing")
close()
for _, case in ipairs({ { true, false, 1 }, { true, true, 0 }, { false, true, 1 }, { false, false, 0 } }) do
    WoW.cvars.autoLootDefault, WoW.modified.AUTOLOOTTOGGLE = case[1], case[2]
    eq(#open({ { id = 10 } }, { autoloot = WoW.NIL }), case[3],
        ("no payload: auto loot %s, the toggle %s held"):format(tostring(case[1]), case[2] and "" or "not"))
    close()
end
WoW.cvars.autoLootDefault, WoW.modified.AUTOLOOTTOGGLE = true, nil
local realMod = IsModifiedClick
IsModifiedClick = function() error("boom") end
eq(#open({ { id = 10 } }, { autoloot = WoW.NIL }), 0, "no payload, the modifier can't be read: nothing")
close()
IsModifiedClick = function() return WoW.Secret("mod") end
eq(#open({ { id = 10 } }, { autoloot = WoW.NIL }), 0, "  a secret modifier: nothing")
close()
IsModifiedClick = realMod
WoW.cvars.autoLootDefault = nil

-- Once per session.
calls = open({ { id = 10 } }, AUTO)
eq(#calls, 1, "LOOT_READY and LOOT_OPENED: one pass only")
WoW.fire("LOOT_READY", true)
eq(#lootCalls(), 1, "a repeated LOOT_READY: nothing more")
close()
reset()
WoW.openLoot({ { id = 10 }, { id = 11 } }, { autoloot = true, emptyReady = true })
eq(#lootCalls(), 2, "no slots at LOOT_READY: the pass at LOOT_OPENED")
close()
reset()
WoW.openLoot({ { id = 10, locked = true } }, AUTO)
WoW.loot[1].locked = false
WoW.fire("LOOT_OPENED", true, false)
eq(#lootCalls(), 0, "a pass that left every row still counts: none at LOOT_OPENED")
close()
eq(#open({ { id = 10 } }, AUTO), 1, "a new session after LOOT_CLOSED: its own pass")
-- Switched off and on with the window open: no second pass.
P.Set("fastloot", false)
P.Set("fastloot", true)
WoW.fire("LOOT_OPENED", true, false)
eq(#lootCalls(), 1, "switched off and on with the window open: no second pass")
close()
-- A window closed while off: the next corpse has its pass.
reset()
P.Set("fastloot", false)
WoW.openLoot({ { id = 10 } }, AUTO)
eq(#lootCalls(), 0, "switched off: nothing")
WoW.closeLoot()
P.Set("fastloot", true)
eq(#open({ { id = 11 } }, AUTO), 1, "a window closed while off, then a new corpse: its pass runs")
close()
-- A corpse looted, the pearl switched off, its window closed while off, on
-- again: the next corpse has its pass (the close was seen while off).
reset()
WoW.openLoot({ { id = 10 } }, AUTO)
P.Set("fastloot", false)
WoW.closeLoot()
P.Set("fastloot", true)
WoW.calls = {}
WoW.openLoot({ { id = 11 } }, AUTO)
eq(#lootCalls(), 1, "a close seen while off: the next corpse's pass runs")
close()
-- A close during the pass: it stops.
reset()
local realLoot = LootSlot
LootSlot = function(i) realLoot(i); if i == 1 then WoW.closeLoot() end end
WoW.openLoot({ { id = 10 }, { id = 11 } }, AUTO)
eq(#lootCalls(), 1, "the window closed during the pass: it stops")
LootSlot = realLoot

-- What is left to the game.
local function takes(row, setup)
    reset()
    if setup then setup() end
    WoW.openLoot({ row }, AUTO)
    local n = #lootCalls()
    close()
    return n == 1
end
check(not takes({ id = 10, locked = true }), "a locked slot: left")
check(not takes({ id = 10, locked = WoW.Secret("locked") }), "a lock that can't be read: left")
check(not takes({ id = 10, kind = T.None }), "a None slot: left")
check(not takes({ id = 10, kind = 7 }), "an unknown type: left")
check(takes({ kind = T.Money }), "money: taken")
check(takes({ kind = T.Currency }), "currency: taken")
check(takes({ id = 10, isQuest = true }), "a quest item: taken")
check(not takes({ id = 10, qty = 0 }), "a quantity of 0: left")
check(not takes({ id = 10, qty = 1.5 }), "a fractional quantity: left")
check(not takes({ id = 10, qty = WoW.Secret("qty") }), "a secret quantity: left")
check(not takes({ id = 999 }), "an item the game hasn't cached: can't tell if it fits, left")
check(not takes({ id = 11 }, function() bags(0) end), "no room: left")
-- Room used up by an earlier row.
reset()
bags(1)
WoW.openLoot({ { id = 11 }, { id = 12 } }, AUTO)
eq(table.concat(lootCalls(), ","), "1", "one free slot, two items: only the first taken")
close()
-- A cleared slot (the game's own auto loot got it first).
reset()
WoW.openLoot({ { id = 10, taken = true }, { id = 11 } }, AUTO)
eq(table.concat(lootCalls(), ","), "2", "an already cleared slot: left")
close()

-- The loot methods.
local function grouped(method, quality, threshold)
    return takes({ id = 12, quality = quality }, function()
        WoW.group.party = true
        WoW.lootMethod = method
        WoW.lootThreshold = threshold or 2
    end)
end
check(takes({ id = 12 }), "solo: an epic is taken")
check(grouped(M.Freeforall, 4), "free-for-all: taken whatever its quality")
check(grouped(M.Roundrobin, 4), "round-robin: taken")
check(grouped(M.Personal, 4), "personal: taken")
for _, m in ipairs({ "Group", "Needbeforegreed", "Masterlooter" }) do
    check(not grouped(M[m], 2), m .. ": at the threshold, left (a roll or a list)")
    check(grouped(M[m], 1), m .. ": under it, taken")
end
check(grouped(M.Group, 0), "a grey (quality 0) under the threshold: taken")
check(not grouped(99, 1), "an unknown method: left")
local realGroup = IsInGroup
IsInGroup = function() return WoW.Secret("group") end
check(not takes({ id = 12 }), "whether you're in a group can't be read: left")
IsInGroup = realGroup
-- Uncertain bag room is no room (the strict snapshot).
check(not takes({ id = 11 }, function() WoW.bags = { [0] = { size = 4, familySecret = true, items = {} } } end),
    "the only free slots in a bag whose family can't be read: left")
check(not grouped(WoW.Secret("method"), 1), "a secret method: left")
check(not grouped(M.Group, 1, WoW.Secret("threshold")), "a threshold that can't be read: left")
check(not grouped(M.Group, WoW.Secret("q"), 2), "a quality that can't be read: left")

-- Never touched: Blizzard's window, the bind confirmation, the errors.
reset()
local lootFrameScale = LootFrame._scale
WoW.openLoot({ { id = 12 } }, AUTO)
WoW.fire("LOOT_BIND_CONFIRM", 1)
check(LootFrame._shown and LootFrame._scale == lootFrameScale and LootFrame._alpha == nil, "LootFrame untouched")
eq(WoW.calledCount("ConfirmLootSlot"), 0, "bind on pickup never confirmed")
close()

-- The report.
reset()
bags(1)
WoW.openLoot({ { id = 11 }, { id = 12 }, { id = 10, locked = true } }, AUTO)
newChat()
P.Command("fastloot").run("")
check(chatHas("3 slot%(s%), 1 loot call%(s%) made") and chatHas("locked 1") and chatHas("no room 1"),
    "the report: calls made, and what was left by reason")
close()

-- Switched off: nothing.
P.Set("fastloot", false)
eq(#open({ { id = 10 } }, AUTO), 0, "switched off: nothing")
close()
P.Set("fastloot", true)

done("test_fastloot")
