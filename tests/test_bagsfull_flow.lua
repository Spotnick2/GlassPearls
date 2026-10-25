-- The bags-full helper's decisions (#6): when it shows and what it offers.
-- Loot that fits, that doesn't, that can't be told; which row it targets;
-- not worth it and choose anyway; closing it; make-room after an error;
-- combat; the pearl switched off.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local BF, Frame = GP.BagsFull, GP.BagsFullFrame
local function tick() WoW.flushTimers(0) end   -- the one coalesced re-evaluation

check(GP.Pearls.IsLive("bagsfull"), "the helper is on by default")
eq(GP.Pearls.Get("bagsfull").category, "Loot & Bags", "on the Loot & Bags page")

for id, it in pairs({
    [1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 },
    [2] = { name = "Old Boot", price = 30, quality = 0, maxStack = 1 },
    [3] = { name = "Linen Cloth", price = 13, quality = 1, maxStack = 20, classID = 7 },
    [10] = { name = "Ring", price = 620, quality = 2, maxStack = 1, classID = 4 },
    [11] = { name = "Wolf Pelt", price = 25, quality = 1, maxStack = 10, classID = 7 },
    [12] = { name = "Quest Tusk", price = 0, quality = 1, maxStack = 1, classID = 12 },
    [13] = { name = "Cheap Tooth", price = 1, quality = 0, maxStack = 1 },
}) do WoW.items[id] = it end
local function fullBags()
    WoW.bags[0] = { size = 4, items = { [1] = { id = 1 }, [2] = { id = 2 }, [3] = { id = 3, count = 20 }, [4] = { id = 1 } } }
end
fullBags()

-- Loot that fits: nothing shows.
WoW.openLoot({ { id = 3, qty = 0 } })
tick()
check(not Frame.IsShown(), "loot that fits (nothing to take): hidden")
WoW.closeLoot(); tick()
WoW.bags[0].items[3].count = 15
WoW.openLoot({ { id = 3, qty = 5 } })
tick()
check(not Frame.IsShown(), "loot that fits on a partial stack: hidden (the full bags alone don't prompt)")
WoW.closeLoot(); tick()
fullBags()

-- Loot that doesn't fit: shown, the cheapest offered, that row targeted.
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
check(Frame.IsShown(), "loot that doesn't fit: shown")
local v = BF.view
eq(v.mode, "loot", "  in loot mode")
eq(v.target.id, 10, "  targeting the ring")
eq(v.candidate.id, 1, "  offering the cheapest grey (Grey Junk, 5c)")
eq(#v.candidates, 3, "  three greys: two Grey Junk and the Old Boot (the cloth is white)")
check(not v.notWorth, "  worth it")

-- Browsing the candidates.
BF.NextCandidate(1)
eq(BF.view.candidate.id, 1, "> : the second Grey Junk (same value, the next slot)")
eq(BF.view.candidate.slot, 4, "  from slot 4")
BF.NextCandidate(1)
eq(BF.view.candidate.id, 2, "> : the Old Boot")
BF.NextCandidate(1)
eq(BF.view.candidate.slot, 1, "> wraps around")
BF.NextCandidate(-1)
eq(BF.view.candidate.id, 2, "< goes back")
WoW.closeLoot(); tick()
check(not Frame.IsShown(), "LOOT_CLOSED hides it")

-- Several rows that don't fit: quest loot first, else the most valuable; click cycles.
WoW.openLoot({ { id = 11, qty = 1 }, { id = 10, qty = 1 }, { id = 12, qty = 1, isQuest = true } })
tick()
eq(BF.view.target.id, 12, "quest loot is targeted first")
eq(#BF.view.rows, 3, "  three rows don't fit")
BF.NextLoot()
eq(BF.view.target.id, 11, "clicking the card: the next row")
BF.NextLoot()
eq(BF.view.target.id, 10, "  and the next")
WoW.closeLoot(); tick()
WoW.openLoot({ { id = 11, qty = 1 }, { id = 10, qty = 1 } })
tick()
eq(BF.view.target.id, 10, "no quest loot: the most valuable (the ring)")
WoW.closeLoot(); tick()

-- Uncached loot never prompts; it shows once the item info arrives.
local ring = WoW.items[10]
WoW.items[10] = nil
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
check(not Frame.IsShown(), "uncached loot: no prompt")
WoW.items[10] = ring
WoW.fire("GET_ITEM_INFO_RECEIVED", 10, true)
tick()
check(Frame.IsShown(), "  shown once GET_ITEM_INFO_RECEIVED says it's cached")
WoW.closeLoot(); tick()

-- A loot row whose quantity can't be read is left out (known data only; Codex review of #9).
WoW.openLoot({ { id = 10, qty = WoW.Secret("qty") } })
tick()
check(not Frame.IsShown(), "a row with an unreadable quantity: no prompt")
WoW.closeLoot(); tick()

-- Not worth it: the loot is worth less than every candidate; "choose anyway".
WoW.bags[0].items = { [1] = { id = 2 }, [2] = { id = 2 }, [3] = { id = 2 }, [4] = { id = 2 } }   -- Old Boots, 30c each
WoW.openLoot({ { id = 13, qty = 1 } })   -- a 1c tooth
tick()
check(BF.view.notWorth, "loot worth less than everything: not worth it")
BF.ChooseAnyway()
check(not BF.view.notWorth, "'Choose anyway' offers the candidates again")
eq(BF.view.candidate.id, 2, "  the Old Boot")
WoW.closeLoot(); tick()
WoW.items[13] = { name = "Quest Tooth", price = 1, quality = 0, maxStack = 1 }
WoW.openLoot({ { id = 13, qty = 1, isQuest = true } })
tick()
check(not BF.view.notWorth, "quest loot is always worth it")
WoW.closeLoot(); tick()
fullBags()

-- Closed by the player: quiet for the rest of that loot window, back at the next.
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
BF.Dismiss()
check(not Frame.IsShown(), "the close button hides it")
WoW.fire("LOOT_SLOT_CHANGED", 1); tick()
check(not Frame.IsShown(), "  and it stays quiet in that loot window")
WoW.closeLoot(); tick()
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
check(Frame.IsShown(), "  the next loot window prompts again")
WoW.closeLoot(); tick()

-- Make room: a full-bags error with no loot window (a node, a quest object).
WoW.fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
tick()
check(Frame.IsShown(), "a full-bags error (its name, ERR_INV_FULL): make-room mode")
eq(BF.view.mode, "room", "  mode room")
eq(BF.view.target, nil, "  nothing to loot")
BF.Dismiss(); tick()
WoW.fire("UI_ERROR_MESSAGE", 999, ERR_INV_FULL)
tick()
check(Frame.IsShown(), "  an unnamed error with the client's ERR_INV_FULL text: make-room too")
WoW.fire("UI_ERROR_MESSAGE", 50, "Spell is not ready yet.")
tick()
eq(BF.view.mode, "room", "  another error changes nothing")
WoW.bags[0].items[4] = nil
WoW.fire("BAG_UPDATE_DELAYED"); tick()
check(not Frame.IsShown(), "room appears: make-room ends")
fullBags()
WoW.fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
tick()
WoW.now = (WoW.now or 0) + BF.MAKE_ROOM_SECONDS + 1
WoW.fire("BAG_UPDATE_DELAYED"); tick()
check(not Frame.IsShown(), "  and it ends after " .. BF.MAKE_ROOM_SECONDS .. " s")

-- Combat: hidden, and back after it if still relevant.
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
check(Frame.IsShown(), "shown before combat")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED"); tick()
check(not Frame.IsShown(), "combat hides it")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED"); tick()
check(Frame.IsShown(), "  and it's back after combat")
WoW.closeLoot(); tick()

-- Settings: white allowed, greys first.
GP.Pearls.SetSetting("bagsfull", "scope", "white")
WoW.bags[0].items = { [1] = { id = 3, count = 1 }, [2] = { id = 2 }, [3] = { id = 3, count = 20 }, [4] = { id = 10 } }
WoW.items[3].maxStack = 1   -- so the cloth doesn't count as room
WoW.openLoot({ { id = 11, qty = 1 } })
tick()
eq(BF.view.candidate.id, 2, "white allowed, greys first (default): the grey Old Boot first")
GP.Pearls.SetSetting("bagsfull", "greysFirst", false)
BF.Evaluate()
eq(BF.view.candidate.id, 3, "  greys first off: the cheapest (1 cloth, 13c)")
GP.Pearls.ResetSettings("bagsfull")
WoW.closeLoot(); tick()
WoW.items[3].maxStack = 20
fullBags()

-- The never-suggest list (the X): kept items aren't offered, on any character.
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
check(BF.Never(BF.view.candidate), "the X adds the item to the list")
check(GP.SettingsSync.SetHas(BF.KEEP, 1), "  in the synced set")
eq(BF.view.candidate.id, 2, "  and it's no longer offered")
WoW.closeLoot(); tick()
GP.SettingsSync.SetRemove(BF.KEEP, 1)

-- /gpearls cheapest
newChat()
SlashCmdList.GLASSPEARLS("cheapest")
check(chatHas("Cheapest: "), "/gpearls cheapest names the first candidate")
check(chatHas("Grey Junk"), "  Grey Junk")
SlashCmdList.GLASSPEARLS("help")
check(chatHas("/gpearls cheapest %- the first item"), "  and /gpearls help lists it")

-- Switched off: no events, never shown; back on, it works again.
GP.Pearls.Set("bagsfull", false)
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
check(not Frame.IsShown(), "switched off: nothing")
WoW.closeLoot(); tick()
GP.Pearls.Set("bagsfull", true)
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
check(Frame.IsShown(), "switched back on (live, no reload): it works")
WoW.closeLoot(); tick()

done("test_bagsfull_flow")
