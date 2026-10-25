-- The bags-full helper's action (#6): destroy and loot from one click. Grey in
-- one click, white armed by a second; the exact stack checked again; the
-- cursor and the slot lock confirmed; a refused delete puts the item back
-- and switches to by hand; the loot only after the slot is empty, in the
-- same loot window, from the same row.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local BF = GP.BagsFull
local function tick() WoW.flushTimers(0) end

for id, it in pairs({
    [1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 },
    [3] = { name = "Linen Cloth", price = 13, quality = 1, maxStack = 20, classID = 7 },
    [10] = { name = "Ring", price = 620, quality = 2, maxStack = 1, classID = 4 },
    [11] = { name = "Pelt", price = 25, quality = 1, maxStack = 1, classID = 7 },
}) do WoW.items[id] = it end
local function setup(scope)
    WoW.resetBags()
    for id, it in pairs({
        [1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 },
        [3] = { name = "Linen Cloth", price = 13, quality = 1, maxStack = 1, classID = 7 },
        [10] = { name = "Ring", price = 620, quality = 2, maxStack = 1, classID = 4 },
        [11] = { name = "Pelt", price = 25, quality = 1, maxStack = 1, classID = 7 },
    }) do WoW.items[id] = it end
    WoW.bags[0] = { size = 2, items = { [1] = { id = 1 }, [2] = { id = 3 } } }
    GP.Pearls.SetSetting("bagsfull", "scope", scope or "grey")
    BF._test.reset()
    WoW.openLoot({ { id = 10, qty = 1 } })
    tick()
end

-- Grey: one click deletes; the loot follows the bag update, once.
setup()
eq(BF.view.candidate.id, 1, "the grey junk is offered")
eq(BF.Destroy(), "destroyed", "one click destroys a grey item")
eq(WoW.calledCount("PickupContainerItem"), 1, "  picked up")
eq(WoW.calledCount("DeleteCursorItem"), 1, "  deleted")
eq(WoW.bags[0].items[1], nil, "  the slot is empty")
eq(WoW.calledCount("LootSlot"), 0, "  no loot before the bag update")
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 1, "the bag update loots the row")
eq(WoW.calls[#WoW.calls][2], 1, "  row 1, the ring")
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 1, "  only once")

-- White: the first click arms, the second destroys; it disarms after 3 s.
setup("white")
GP.Pearls.SetSetting("bagsfull", "greysFirst", false)
WoW.bags[0].items = { [1] = { id = 3 }, [2] = { id = 11 } }
BF.Evaluate()
eq(BF.view.candidate.id, 3, "white scope: the cloth (13c) is offered")
eq(BF.Destroy(), "armed", "the first click on a white item arms")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")
check(GP.BagsFullFrame._test.frame().button:GetText() == "Click again to destroy", "  the button says so")
eq(BF.Destroy(), "destroyed", "the second click destroys")
setup("white")
WoW.bags[0].items = { [1] = { id = 3 }, [2] = { id = 11 } }
BF.Evaluate()
BF.Destroy()
WoW.now = (WoW.now or 0) + BF.ARM_SECONDS + 0.5
WoW.flushTimers(BF.ARM_SECONDS)
eq(BF.Destroy(), "armed", "after 3 s the second click only arms again")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")
-- The time decides, not only the timer (a late timer, a frame hitch).
setup("white")
WoW.bags[0].items = { [1] = { id = 3 }, [2] = { id = 11 } }
BF.Evaluate()
BF.Destroy()
WoW.now = (WoW.now or 0) + BF.ARM_SECONDS + 0.5   -- 3.5 s later, the disarm timer not yet run
eq(BF.Destroy(), "armed", "a second click 3.5 s later arms again, even before the timer runs")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")
WoW.flushTimers()
BF.NextCandidate(1)
eq(BF.Destroy(), "armed", "browsing to another item disarms: its first click arms")
GP.Pearls.ResetSettings("bagsfull")

-- Refusals before anything is touched.
setup()
WoW.cursor = { bag = 9, slot = 9, id = 99 }
eq(BF.Destroy(), "cursor", "something on the cursor: refused")
eq(WoW.calledCount("PickupContainerItem"), 0, "  nothing picked up")
WoW.cursor = nil
WoW.combat = true
eq(BF.Destroy(), "combat", "in combat: refused")
WoW.combat = false
WoW.bags[0].items[1] = { id = 1, count = 2 }   -- the stack changed under the window
eq(BF.Destroy(), "changed", "the stack changed since it was offered: refused")
eq(WoW.calledCount("PickupContainerItem"), 0, "  nothing picked up")
setup()
WoW.bags[0].items[1] = { id = 3 }   -- another item in that slot now
eq(BF.Destroy(), "changed", "another item in the slot: refused")

-- The pickup didn't take: the cursor is cleared, nothing deleted.
setup()
WoW.pickupFails = true
eq(BF.Destroy(), "pickup", "a pickup that didn't take: stopped")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")
eq(WoW.calledCount("ClearCursor"), 1, "  the cursor cleared")
WoW.pickupFails = false

-- The delete refused (ADDON_ACTION_FORBIDDEN): the item goes back, no loot, by hand from now on.
setup()
WoW.deleteForbidden = true
GP.failures["pearl bagsfull delete"] = nil
eq(BF.Destroy(), "refused", "a forbidden delete: refused")
check(WoW.bags[0].items[1] ~= nil, "  the item is still in the bag")
eq(WoW.cursor, nil, "  and off the cursor (put back)")
check(BF.state.byHand, "  by-hand mode")
check(GP.failures["pearl bagsfull delete"] ~= nil, "  recorded for /gpearls failures")
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "  no loot")
check(BF.view.byHand, "the window shows by-hand mode")
check(not GP.BagsFullFrame._test.frame().button:IsShown(), "  with no destroy button")
eq(BF.Destroy(), "changed", "  and the action stays off for the session")
WoW.deleteForbidden = false

-- The delete silently didn't happen (the item still on the cursor): the same.
setup()
WoW.deleteSilent = true
eq(BF.Destroy(), "refused", "a delete that left the item on the cursor: refused")
eq(WoW.cursor, nil, "  put back")
check(WoW.bags[0].items[1] ~= nil, "  still in the bag")
WoW.deleteSilent = false

-- The loot only after a confirmed empty slot, in the same window, from the same row.
setup()
BF.Destroy()
WoW.bags[0].items[1] = { id = 3 }   -- something moved into the slot
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "the slot isn't empty (an item moved in): no loot")
setup()
BF.Destroy()
WoW.closeLoot()
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "the loot window closed: no loot")
setup()
BF.Destroy()
WoW.closeLoot()
WoW.openLoot({ { id = 10, qty = 1 } })   -- another corpse, same layout
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "another loot window: no loot from the old row")
setup()
BF.Destroy()
WoW.loot[1].id = 11   -- the row now holds something else
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "the row holds another item: no loot")
setup()
BF.Destroy()
WoW.loot[1].taken = true
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "the row was looted already: no loot")
setup()
BF.Destroy()
WoW.now = (WoW.now or 0) + BF.PENDING_SECONDS + 1
WoW.flushTimers(BF.PENDING_SECONDS)
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "after 2 s without a bag update the loot is forgotten")

-- Make room: destroy only, no loot.
WoW.resetBags()
WoW.items[1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 }
WoW.bags[0] = { size = 1, items = { [1] = { id = 1 } } }
BF._test.reset()
WoW.fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
tick()
eq(BF.view.mode, "room", "make-room mode")
newChat()
eq(BF.Destroy(), "destroyed", "  destroys")
check(chatHas("loot it again"), "  and says to loot again")
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("LootSlot"), 0, "  no LootSlot")

-- The button's click is what runs it.
setup()
local f = GP.BagsFullFrame._test.frame()
f.button:GetScript("OnClick")(f.button)
eq(WoW.calledCount("DeleteCursorItem"), 1, "the window's button runs the action")

done("test_bagsfull_action")
