-- The restock pearl after the audit (#61), the witnesses of its findings: a
-- purchase never dispatched once the visit is replaced (another merchant
-- opened with no close), a cursor read that throws counts as unknown, more
-- arriving than was bought stops the run, room on a strict snapshot, the Ask
-- window's limits bounding the run (lowered counts, raised waits), and every
-- line of a plan shown (a rogue's ten). test_restock_buy.lua is the
-- regression base; this file adds the audit's cases.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

for id, name in pairs({ [1708] = "Sweet Nectar", [4544] = "Mulgore Spice Bread", [17031] = "Rune of Teleportation",
                        [17056] = "Light Feather" }) do
    WoW.items[id] = { name = name, maxStack = 20, price = 1, quality = 1 }
end
local GOODS = {
    { id = 1708, price = 1000, pack = 5 },
    { id = 4544, price = 1000, pack = 5 },
    { id = 17031, price = 1000, pack = 1 },
    { id = 17056, price = 30, pack = 1, maxStack = 5 },
}
local function goods(list)
    WoW.goods = {}
    for i, g in ipairs(list or GOODS) do
        local c = {}
        for k, v in pairs(g) do c[k] = v end
        WoW.goods[i] = c
    end
end
local function bags(items, size) WoW.bags = { [0] = { size = size or 16, items = items or {} } } end
goods()
bags()
WoW.class, WoW.playerLevel, WoW.money = "MAGE", 26, 100000
WoW.known[130], WoW.known[3561] = true, true
local GP = loadAddon()
local R, P = GP.Restock, GP.Pearls
P.Set("junk", false)   -- the junk seller out of the way: restock starts 0.3 s after the show

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
    P.ResetSettings("restock")
    newChat()
end
-- A visit with the first purchase (the runes) left in flight.
local function firstBuyInFlight()
    reset()
    WoW.buysAsync = true
    WoW.openMerchant()
    soon()
    eq(table.concat(buys(), ","), "10", "  (the runes in flight)")
end

-- R8: another merchant opened with no MERCHANT_CLOSED: the old run ends; its
-- landing purchase never starts the next one at the new merchant.
firstBuyInFlight()
WoW.openMerchant()           -- the second merchant, straight from the first
WoW.applyBuys()              -- the old purchase lands
WoW.flushTimers(0)
eq(table.concat(buys(), ","), "10", "a replaced visit: the old run buys nothing more")
check(R.state.run == nil or R.state.run.ended, "  it ended")
soon()                       -- the new visit plans afresh (0.3 s) and buys what's still short
check(#buys() >= 2 and R.state.run ~= nil and R.state.run.session == GP.Merchant.Session(),
    "  the new visit's run buys, under its own session")
WoW.buysAsync = false
WoW.applyBuys()
drain()

-- R7: a cursor read that throws is unknown, not empty: stopped.
firstBuyInFlight()
local realCursor = GetCursorInfo
GetCursorInfo = function() error("no cursor for you") end
WoW.applyBuys()
soon()
eq(#buys(), 1, "a cursor read that throws: stopped, nothing more bought")
check(has(newChat(), "Something is on your cursor: stopped buying."), "  and said as a cursor stop")
GetCursorInfo = realCursor
drain()

-- R1: more arrived than was bought (something else of the item came in the
-- same breath): recorded, then stopped. Exactly the chunk goes on.
firstBuyInFlight()
WoW.bags[0].items[12] = { id = 17031, count = 3 }   -- three runes from the mail meanwhile
WoW.applyBuys()
soon()
eq(#buys(), 1, "more arrived than was bought: stopped")
local said = newChat()
check(has(said, "Bought 10 Rune of Teleportation"), "  the chunk recorded as bought")
check(has(said, "More arrived than was bought: stopped buying."), "  and the reason said")
drain()
firstBuyInFlight()
WoW.applyBuys()
soon()
check(#buys() >= 2, "exactly the chunk: confirmed, the next line goes on")
WoW.buysAsync = false
WoW.applyBuys()
drain()

-- R2: room on a strict snapshot: a bag whose family can't be read offers none.
reset()
WoW.bags[0].familySecret = true
WoW.openMerchant()
drain()
local chat = newChat()
eq(#buys(), 0, "a bag whose family can't be read: no room, nothing attempted")
check(has(chat, "No room for"), "  and said")
WoW.bags[0].familySecret = nil

-- R4: the Ask window's limits bound the run: raised since, the shown limit holds; lowered, the lower holds.
reset()
P.SetSetting("restock", "mode", "ask")
P.SetSetting("restock", "maxSpend", 1)      -- at most 1g: the runes (10s) only
WoW.openMerchant()
drain()
check(GP.RestockFrame.IsShown(), "ask first: the window")
check((GP.RestockFrame.Get().limits:GetText() or ""):find("1g", 1, true) ~= nil, "  says at most 1g")
P.SetSetting("restock", "maxSpend", 100)    -- raised meanwhile (a sync)
GP.RestockFrame.Buy()
drain()
eq(table.concat(buys(), ","), "10", "raised after the window: the shown 1g still holds")
eq(WoW.money, 100000 - 10000, "  1g spent")
reset()
P.SetSetting("restock", "mode", "ask")
WoW.openMerchant()
drain()
P.SetSetting("restock", "maxSpend", 1)      -- lowered meanwhile
GP.RestockFrame.Buy()
drain()
eq(table.concat(buys(), ","), "10", "lowered after the window: the lower holds")
reset()

-- R6: every line of a plan is shown: a rogue's nine reagents and food.
local ROGUE_REAGENTS = { 2928, 2930, 3371, 3372, 5140, 5173, 8923, 8924, 8925 }
local list = {}
for _, id in ipairs(ROGUE_REAGENTS) do
    WoW.items[id] = { name = "reagent " .. id, maxStack = 20, price = 1, quality = 1 }
    list[#list + 1] = { id = id, price = 100, pack = 1 }
end
list[#list + 1] = { id = 4544, price = 1000, pack = 5 }
goods(list)
WoW.class = "ROGUE"
for k in pairs(WoW.known) do WoW.known[k] = nil end
for _, sid in ipairs({ 5763, 2837, 3421, 11341, 1857 }) do WoW.known[sid] = true end   -- the highest known ranks
P.SetSetting("restock", "mode", "ask")
WoW.openMerchant()
drain()
local lines = R.state.last.lines
eq(#lines, 10, "a rogue's plan: nine reagents and food, ten lines")
local shown = 0
for i = 1, #lines do if GP.RestockFrame.Get().rows[i]:IsShown() then shown = shown + 1 end end
eq(shown, #lines, "  every line has a row in the window")
check(#lines <= GP.RestockFrame.MAX_ROWS, "  within the window's rows")
local most = 0
for _, t in pairs(GP.RestockData.reagents) do
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    most = math.max(most, n)
end
check(most + 3 <= GP.RestockFrame.MAX_ROWS, "the window has a row for the largest reagent set plus water, food and ammunition")
GP.RestockFrame.Hide()
WoW.closeMerchant()
drain()

done("test_restock_audit")
