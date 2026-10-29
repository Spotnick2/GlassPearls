-- The junk seller's outcome for a visit (#14, restock waits for it): "ready"
-- only when selling and repairing ended with nothing that may still land;
-- "skip" after an unconfirmed or refused sale, the buyback check, combat, an
-- unconfirmed repair, or the pearl switched off mid-visit. Every early return
-- of the repair reports too.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.items[101] = { name = "Broken Fang", price = 5, quality = 0, classID = 15 }
local function fill()
    WoW.bags = { [0] = { size = 16, items = { [1] = { id = 101, count = 3 } } } }
end
fill()
WoW.money = 1000

local GP = loadAddon()
local J, P, M = GP.Junk, GP.Pearls, GP.Merchant
P.Set("restock", false)   -- this file is about the junk seller's report

local function drain()
    for _ = 1, 50 do
        if #WoW.timers == 0 then return end
        WoW.flushTimers()
    end
end
-- Open a merchant, run everything, and return what Junk reported (or nil).
local function visit(m, before)
    fill()
    WoW.calls, WoW.buyback = {}, {}
    local outcome
    WoW.openMerchant(m)
    M.Await("junk", M.Session(), 1000, function(o) outcome = o end)
    if before then before() end
    for _ = 1, 50 do
        if #WoW.timers == 0 or outcome then break end
        WoW.flushTimers(J.SETTLE_MAX)
    end
    local o = outcome
    drain()
    WoW.closeMerchant()
    return o
end

eq(visit({ repairs = false }), "ready", "sold, the merchant can't repair: ready")
WoW.repairCost = 50
eq(visit(), "ready", "sold and repaired: ready")
eq(WoW.repairCost, 0, "  (it repaired)")
WoW.repairCost = 50
P.SetSetting("junk", "autoRepair", false)
eq(visit(), "ready", "repair off: ready")
P.ResetSettings("junk")
WoW.repairCost = 0
eq(visit(), "ready", "nothing to repair: ready")
WoW.repairCost, WoW.money = 5000, 10
eq(visit(), "ready", "not enough money to repair (nothing attempted): ready")
WoW.money = 1000
WoW.repairCost, WoW.repairSilent = 50, true
eq(visit(), "skip", "a repair that never settles: skip")
WoW.repairSilent, WoW.repairCost = false, 0
P.SetSetting("junk", "autoSell", false)
eq(visit(), "ready", "selling off, nothing to repair: ready")
P.ResetSettings("junk")
WoW.bags[0].items = {}
eq(visit(nil, function() WoW.bags[0].items = {} end), "ready", "nothing to sell: ready")

-- Selling that may still land.
WoW.salesAsync = true
eq(visit(), "skip", "a sale never confirmed: skip")
WoW.salesAsync, WoW.pendingSales = false, {}
WoW.merchantRefuses = 51
eq(visit(), "skip", "a refused sale: skip")
WoW.merchantRefuses = nil
-- Buyback-safe, and this visit's sale seems gone from the page.
P.SetSetting("junk", "safe", true)
local link = GetBuybackItemLink
GetBuybackItemLink = function() return "|Hitem:999|h[Something else]|h" end
eq(visit(), "skip", "the buyback check failed: skip")
GetBuybackItemLink = link
P.ResetSettings("junk")
-- Something on the cursor stops selling before anything is in flight.
eq(visit(nil, function() WoW.cursor = { kind = "spell", id = 1 } end), "ready", "stopped for the cursor: ready")
WoW.cursor = nil
-- Combat when the delayed start comes.
eq(visit(nil, function() WoW.combat = true; WoW.fire("PLAYER_REGEN_DISABLED") end), "skip", "combat at the start: skip")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
-- Combat begins after selling, before the repair.
fill()
WoW.repairCost = 50
local got
WoW.openMerchant()
M.Await("junk", M.Session(), 1000, function(o) got = o end)
WoW.flushTimers(J.OPEN_DELAY)
WoW.flushTimers(0)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
for _ = 1, 20 do if got then break end WoW.flushTimers(J.SETTLE_MAX) end
eq(got, "skip", "combat before the repair: skip")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.closeMerchant()
drain()
WoW.repairCost = 0
-- A refused sale, then a repair that settles: still skip.
WoW.merchantRefuses, WoW.repairCost = 51, 50
eq(visit(), "skip", "a refused sale, then a repair: still skip")
eq(WoW.repairCost, 0, "  (the repair happened)")
WoW.merchantRefuses = nil
-- Switched off mid-visit.
WoW.salesAsync = true
eq(visit(nil, function() WoW.flushTimers(J.OPEN_DELAY); P.Set("junk", false) end), "skip",
    "switched off while a sale is in flight: skip")
WoW.salesAsync, WoW.pendingSales = false, {}
P.Set("junk", true)
-- Shift: Junk does nothing and says nothing (restock skips Shift visits itself).
WoW.shift = true
eq(visit(), nil, "Shift: no report")
WoW.shift = false

done("test_junk_outcome")
