-- Faster loot (#36) beside the bags-full helper (#6): our pass takes what
-- fits and leaves the rest; the helper targets the leftover; its own
-- destroy-and-loot is then the only LootSlot for that row, because our pass
-- never runs again in the session; and no pass at all while its loot is
-- pending. Also: saved off at login, then switched on with a window open.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ db = { pearls = { fastloot = false } } })
local BF, L, P = GP.BagsFull, GP.FastLoot, GP.Pearls
local function tick() WoW.flushTimers(0) end
local AUTO = { autoloot = true }

local function setup()
    WoW.resetBags()
    for id, it in pairs({
        [1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 },
        [3] = { name = "Linen Cloth", price = 13, quality = 1, maxStack = 20, classID = 7 },
        [10] = { name = "Ring", price = 620, quality = 2, maxStack = 1, classID = 4 },
    }) do WoW.items[id] = it end
    -- One stack of cloth with room, one grey, no free slot.
    WoW.bags[0] = { size = 2, items = { [1] = { id = 1 }, [2] = { id = 3, count = 10 } } }
    BF._test.reset()
end

-- Saved off at login: a window opened then gets no pass, even once switched on.
setup()
WoW.openLoot({ { id = 3, qty = 5 } }, AUTO)
P.Set("fastloot", true)
tick()
eq(WoW.calledCount("LootSlot"), 0, "off at login, switched on with a window open: nothing for that window")
WoW.fire("LOOT_OPENED", true, false)
eq(WoW.calledCount("LootSlot"), 1, "  a further qualifying event: its first pass runs")
WoW.closeLoot()
tick()

-- A row that fits and one that doesn't: only the first taken by us.
setup()
WoW.calls = {}
WoW.openLoot({ { id = 3, qty = 5 }, { id = 10, qty = 1 } }, AUTO)
eq(WoW.calledCount("LootSlot"), 1, "our pass: one loot call")
eq(WoW.calls[#WoW.calls][2], 1, "  the cloth (it fits the partial stack)")
-- The game gives the cloth.
WoW.bags[0].items[2].count = 15
WoW.takeLoot(1)
tick()
check(BF.view and BF.view.target and BF.view.target.id == 10, "the bags-full helper targets the leftover ring")
-- Its destroy and loot: the only LootSlot for that row.
eq(BF.Destroy(), "destroyed", "the helper destroys the grey")
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 2, "its loot is the second call in all")
eq(WoW.calls[#WoW.calls][2], 2, "  row 2, the ring")
WoW.fire("LOOT_READY", true)
WoW.fire("LOOT_OPENED", true, false)
eq(WoW.calledCount("LootSlot"), 2, "our pass never runs again in the session")
WoW.closeLoot()
tick()

-- No pass while the helper's loot is pending.
setup()
WoW.calls = {}
BF.state.pending = { bag = 0, slot = 1, id = 1, lootSlot = 1, lootLink = "x" }
WoW.openLoot({ { id = 3, qty = 5 } }, AUTO)
eq(WoW.calledCount("LootSlot"), 0, "the helper's loot pending: no pass")
BF.state.pending = nil
WoW.closeLoot()

done("test_fastloot_bagsfull")
