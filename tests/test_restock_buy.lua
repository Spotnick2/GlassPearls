-- The restock pearl's buying (#14, R.Run): after the junk seller says
-- "ready" (or right away without it; never on "skip" or its timeout; never
-- with Shift), one purchase in flight in whole packs within the max stack,
-- each step reading everything again (the offer, the recount, room, both
-- limits on observed money), confirmed only by the full increase, and every
-- stop (partial, refusal, close, combat, cursor, off).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

for id, name in pairs({ [1708] = "Sweet Nectar", [4544] = "Mulgore Spice Bread", [17031] = "Rune of Teleportation",
                        [17056] = "Light Feather" }) do
    WoW.items[id] = { name = name, maxStack = 20, price = 1, quality = 1 }
end
WoW.items[101] = { name = "Broken Fang", price = 5, quality = 0, classID = 15 }
local GOODS = {
    { id = 1708, price = 1000, pack = 5 },
    { id = 4544, price = 1000, pack = 5 },
    { id = 17031, price = 1000, pack = 1 },
    { id = 17056, price = 30, pack = 1, maxStack = 5 },   -- five per call
}
local function goods()
    WoW.goods = {}
    for i, g in ipairs(GOODS) do
        local c = {}
        for k, v in pairs(g) do c[k] = v end
        WoW.goods[i] = c
    end
end
local function bags(items, size)
    WoW.bags = { [0] = { size = size or 16, items = items or {} } }
end
goods()
bags()
WoW.class, WoW.playerLevel, WoW.money = "MAGE", 26, 100000
WoW.known[130], WoW.known[3561] = true, true
local GP = loadAddon()
local R, P, J = GP.Restock, GP.Pearls, GP.Junk

-- The stub's timers run by delay, not by clock: soon() runs only the short
-- ones (the junk seller's steps, the restock's start and steps), leaving the
-- 2 s confirmation and the 10 s junk wait; drain() then runs those too.
local function soon()
    for _ = 1, 100 do
        local any = false
        for _, t in ipairs(WoW.timers) do if t.s <= 1 then any = true end end
        if not any then return end
        WoW.flushTimers(1)
    end
end
local function drain()
    for _ = 1, 60 do
        soon()
        if #WoW.timers == 0 then return end
        WoW.flushTimers()
    end
end
local function count(id)
    local n = 0
    for _, b in pairs(WoW.bags) do for _, s in pairs(b.items) do if s.id == id then n = n + s.count end end end
    return n
end
local function buys()
    local t = {}
    for _, c in ipairs(WoW.calls) do if c[1] == "BuyMerchantItem" then t[#t + 1] = c[3] end end
    return t
end
local function text(lines) return table.concat(lines, "\n") end
local function has(lines, s) return text(lines):find(s, 1, true) ~= nil end
local function reset(items)
    goods()
    bags(items)
    WoW.calls, WoW.money = {}, 100000
    WoW.buysAsync, WoW.buyRefuses, WoW.buyShort, WoW.pendingBuys = false, nil, nil, {}
    if WoW.merchant then WoW.closeMerchant() end
    drain()
    newChat()
end
local function visit(before)
    WoW.openMerchant()
    if before then before() end
    drain()
    return newChat()
end

-- The whole visit: Junk (nothing to sell) says ready, then everything.
reset()
local chat = visit()
eq(count(17031) .. "/" .. count(17056) .. "/" .. count(1708) .. "/" .. count(4544), "10/20/20/20",
    "after the junk seller: runes, feathers, water and food to their targets")
eq(WoW.money, 100000 - 18600, "  paid what they cost")
check(has(chat, "Bought 10 Rune of Teleportation, 20 Light Feather, 20 Sweet Nectar, 20 Mulgore Spice Bread: your money -18600c."),
    "  and said in one line: " .. text(chat))
eq(table.concat(buys(), ","), "10,5,5,5,5,20,20", "  whole packs, at most the merchant's max stack per call")
reset({ [1] = { id = 17031, count = 10 }, [2] = { id = 17056, count = 20 }, [3] = { id = 1708, count = 20 },
        [4] = { id = 4544, count = 20 } })
visit()
eq(#buys(), 0, "a full stock: nothing bought")

-- When it may start.
reset({ [1] = { id = 101, count = 1 } })
WoW.salesAsync = true
visit()
eq(#buys(), 0, "the junk seller says skip (a sale unconfirmed): nothing bought")
WoW.salesAsync, WoW.pendingSales = false, {}
reset()
local report = GP.Merchant.Report
GP.Merchant.Report = function() end
WoW.openMerchant()
WoW.flushTimers(R.JUNK_WAIT - 1)
eq(#buys(), 0, "no word from the junk seller: still waiting")
drain()
eq(#buys(), 0, "  and nothing after 10 s either")
GP.Merchant.Report = report
reset()
P.Set("junk", false)
WoW.openMerchant()
WoW.flushTimers(R.OPEN_DELAY)
check(#buys() > 0, "the junk seller off: it starts on its own")
drain()
P.Set("junk", true)
for _, junk in ipairs({ true, false }) do
    P.Set("junk", junk)
    local with = junk and " (the junk seller on)" or " (the junk seller off)"
    reset()
    WoW.shift = true
    visit()
    eq(#buys(), 0, "Shift: nothing this visit" .. with)
    WoW.shift = false
    reset()
    visit(function() WoW.combat = true; WoW.fire("PLAYER_REGEN_DISABLED") end)
    eq(#buys(), 0, "in combat: nothing" .. with)
    WoW.combat = false
    WoW.fire("PLAYER_REGEN_ENABLED")
end
P.Set("junk", true)

-- One purchase in flight; the step after it reads everything again.
reset()
WoW.buysAsync = true
WoW.openMerchant()
soon()
eq(#buys(), 1, "one purchase in flight")
soon()
eq(#buys(), 1, "  nothing more until it lands")
WoW.applyBuys()
soon()
check(#buys() == 2 and #WoW.pendingBuys == 1, "  then the next")
WoW.pendingBuys = {}
reset()

-- A recount before each chunk: feathers that arrive meanwhile end the line.
WoW.buysAsync = true
WoW.openMerchant()
soon()   -- the runes wait
WoW.applyBuys()
soon()   -- the first five feathers wait
eq(buys()[2], 5, "five feathers asked for")
WoW.bags[0].items[12] = { id = 17056, count = 15 }
WoW.applyBuys()
soon()
eq(buys()[3], 20, "  fifteen more arrived meanwhile: the feathers are done, the water next")
WoW.pendingBuys = {}
reset()

-- Stops.
WoW.buyShort = 1
local stopped = visit()
eq(#buys(), 1, "a smaller increase than asked: stopped")
check(has(stopped, "A purchase wasn't confirmed: stopped buying."), "  and said")
check(not has(stopped, "Bought"), "  nothing claimed as bought")
reset()
WoW.buyRefuses = 53
stopped = visit()
eq(#buys(), 1, "a refusal (not enough money): stopped")
check(has(stopped, "The merchant refused: stopped buying."), "  and said")
reset()
WoW.buysAsync = true
WoW.openMerchant()
soon()
WoW.closeMerchant()
WoW.applyBuys()
drain()
eq(#buys(), 1, "the merchant closed: stopped")
reset()
WoW.buysAsync = true
WoW.openMerchant()
soon()
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.applyBuys()
drain()
eq(#buys(), 1, "combat: stopped")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
reset()
WoW.buysAsync = true
WoW.openMerchant()
soon()
WoW.cursor = { kind = "spell", id = 1 }
WoW.applyBuys()
drain()
eq(#buys(), 1, "something on the cursor: stopped")
WoW.cursor = nil
reset()
WoW.buysAsync = true
WoW.openMerchant()
soon()
P.Set("restock", false)
WoW.applyBuys()
drain()
eq(#buys(), 1, "switched off: stopped")
P.Set("restock", true)
reset()

-- Limits: the share of the money, the gold, the money observed.
P.SetSetting("restock", "budget", 10)
visit()
eq(table.concat(buys(), ","), "10", "10% of 10g: the runes (10s), then nothing")
reset()
P.ResetSettings("restock")
P.SetSetting("restock", "maxSpend", 1)
chat = visit()
eq(table.concat(buys(), ","), "10", "at most 1g: the same")
check(has(chat, "The spending limit for this visit is reached."), "  and said")
P.ResetSettings("restock")
reset()
WoW.buysAsync = true
WoW.openMerchant()
soon()
WoW.money = WoW.money - 45000   -- spent elsewhere while the runes were bought
WoW.applyBuys()
drain()
eq(#buys(), 1, "money gone meanwhile counts toward the limit: stopped")
reset()

-- Room, fresh each step: two lines can't both have the last free slot.
bags({ [1] = { id = 4544, count = 20 } }, 2)   -- one free slot
WoW.class = "WARRIOR"                          -- food only... and water? no: a warrior
P.SetSetting("restock", "foodTarget", 40)
visit()
eq(table.concat(buys(), ","), "20", "one free slot: one stack of bread")
P.ResetSettings("restock")
WoW.class = "MAGE"
reset({}, 1)
bags({}, 1)
chat = visit()
eq(table.concat(buys(), ","), "10", "one slot for four lines: the runes, then no room")
check(has(chat, "No room for Light Feather."), "  and said")

-- Room that can't be told (the item's stack size unknown): the line skipped.
reset()
local bread = WoW.items[4544]
WoW.items[4544] = nil
chat = visit()
check(count(4544) == 0 and count(1708) == 20, "an item whose stack size can't be read: skipped, the rest bought")
check(has(chat, "Can't tell whether item 4544 fits: skipped."), "  and said: " .. text(chat))
WoW.items[4544] = bread

-- The offer changed since the plan: that line skipped.
reset()
P.SetSetting("restock", "mode", "ask")
WoW.openMerchant()
drain()
check(GP.RestockFrame.IsShown(), "ask first: the window, nothing bought yet")
eq(#buys(), 0, "  nothing bought")
WoW.goods[1].price = 2000
GP.RestockFrame.Buy()
chat = newChat()
drain()
chat = newChat()
check(count(1708) == 0 and count(17031) == 10, "Buy: Sweet Nectar's price changed, skipped; the rest bought")
check(has(chat, "Sweet Nectar changed at the merchant: skipped."), "  and said: " .. text(chat))
P.ResetSettings("restock")
reset()

done("test_restock_buy")
