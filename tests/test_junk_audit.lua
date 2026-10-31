-- "Sell junk & repair" after the audit (#61), the witnesses of its findings:
-- a sale never dispatched once the visit is replaced (another vendor opened
-- with no close) or gone (a loading screen: with no merchant the client would
-- use the item), selling switched off mid-run, a lock that can't be read, the
-- buyback page's growth as evidence only with our sale as its newest entry,
-- a repair settled only by a cost that fell, the personal step's own checks,
-- and no repair once the pearl is off, a settle wait pending included.
-- test_junk.lua is the regression base; this file adds the audit's cases.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ITEMS = {
    [101] = { name = "Broken Fang", price = 5, quality = 0, classID = 15 },
    [102] = { name = "Torn Boots", price = 30, quality = 0, classID = 4 },
    [103] = { name = "Linen Cloth", price = 10, quality = 1, classID = 7 },
    [108] = { name = "Cracked Pot", price = 2, quality = 0, classID = 15 },
}
for id, it in pairs(ITEMS) do WoW.items[id] = it end
local function fill()
    WoW.bags = { [0] = { size = 16, items = {
        [1] = { id = 101, count = 3 },        -- grey: 15c
        [2] = { id = 102, bound = true },     -- grey gear, bound: 30c
        [3] = { id = 103, count = 5 },        -- white: never sold unlisted
        [8] = { id = 108 },                   -- grey: 2c, the cheapest
    } } }
end
fill()
WoW.money = 1000
local GP = loadAddon()
local J, P = GP.Junk, GP.Pearls
P.Set("restock", false)   -- the restock pearl out of the way (test_restock_audit.lua is its side)

local function drain()
    for _ = 1, 50 do
        if #WoW.timers == 0 then return end
        WoW.flushTimers()
    end
end
-- The timers due within `upTo` seconds, again and again (a client's frames).
local function soon(upTo)
    for _ = 1, 50 do
        local any = false
        for _, t in ipairs(WoW.timers) do if t.s <= upTo then any = true end end
        if not any then return end
        WoW.flushTimers(upTo)
    end
end
local function sold() local t = {} for _, c in ipairs(WoW.calls) do if c[1] == "UseContainerItem" then t[#t + 1] = c[3] end end return t end
local function repairs() local n = 0 for _, c in ipairs(WoW.calls) do if c[1] == "RepairAllItems" then n = n + 1 end end return n end
local function text(lines) return table.concat(lines, "\n") end
local function has(lines, s) return text(lines):find(s, 1, true) ~= nil end
local function reset()
    fill()
    WoW.calls, WoW.buyback, WoW.money, WoW.usedItems = {}, {}, 1000, {}
    WoW.salesAsync, WoW.pendingSales, WoW.repairSilent, WoW.repairCost = false, {}, false, 0
    WoW.guild = { member = false, mayRepair = false, info = "", allowance = 0 }
    if WoW.merchant then WoW.closeMerchant() end
    drain()
    newChat()
end
-- A visit with the first (cheapest) sale left in flight: the client answers later.
local function firstSaleInFlight()
    reset()
    WoW.salesAsync = true
    WoW.openMerchant()
    WoW.flushTimers(J.OPEN_DELAY)
    eq(table.concat(sold(), ","), "8", "  (the cheapest sale in flight)")
end

-- J3: another vendor opened with no MERCHANT_CLOSED: the old run ends; its
-- landing sale never starts the next one; the new visit sells afresh.
firstSaleInFlight()
WoW.openMerchant()           -- the second vendor, straight from the first
WoW.applySales()             -- the old sale lands (the slot empties)
WoW.flushTimers(0)           -- the frame after: the old run's next sale, if any
eq(table.concat(sold(), ","), "8", "a replaced visit: the old run sells nothing more")
check(J.state.run == nil or J.state.run.ended, "  it ended")
WoW.flushTimers(J.OPEN_DELAY)
eq(table.concat(sold(), ","), "8,1", "  the new visit's run sells what's left, in its own time")
eq(J.state.run.session, GP.Merchant.Session(), "  under the new visit")
WoW.salesAsync = false
WoW.applySales()
drain()

-- J1: a loading screen with a sale in flight: nothing more is dispatched (with
-- no merchant, UseContainerItem would use the item: eat it, equip it, open it).
firstSaleInFlight()
WoW.merchantGone()
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
WoW.applySales()             -- the sale the server was processing lands anyway
WoW.flushTimers(0)
eq(#WoW.usedItems, 0, "a loading screen mid-run: no item is used by a sale sent to no merchant")
eq(#sold(), 1, "  nothing more dispatched")
drain()
eq(#sold(), 1, "  nor later")

-- J2: selling switched off mid-run (by hand or by sync): the queue stops; the repair still runs.
firstSaleInFlight()
WoW.repairCost = 300
P.SetSetting("junk", "autoSell", false)
WoW.applySales()
drain()
eq(#sold(), 1, "selling switched off mid-run: no more sales")
eq(repairs(), 1, "  the repair still runs")
P.ResetSettings("junk")

-- J7: a lock that can't be read: not junk.
reset()
WoW.bags[0].items[8].lockSecret = true
eq(select(2, J.Judge(GP.Bags.Slot(0, 8), {})), "unknown lock", "a lock that can't be read: not junk")
WoW.openMerchant()
drain()
eq(table.concat(sold(), ","), "1,2", "  never sold; the rest is")

-- J6: the buyback page grew for another reason (the player sold by hand):
-- not our sale's confirmation; it waits for the slot, then goes on.
firstSaleInFlight()
WoW.salesAsync = false
C_Container.UseContainerItem(0, 3)   -- the player sells the cloth by hand: lands at once, the page grows
WoW.salesAsync = true
WoW.flushTimers(0)
eq(table.concat(sold(), ","), "8,3", "the page grew by the player's own sale: ours isn't taken as sold, no next sale")
check(J.state.run.inFlight ~= nil, "  still waiting for ours")
WoW.applySales()                      -- ours lands: the slot empties
WoW.flushTimers(0)
eq(table.concat(sold(), ","), "8,3,1", "  then the next one")
WoW.salesAsync = false
WoW.applySales()
drain()
-- Growth with our sale as the newest entry still counts (a client that
-- empties the slot late).
firstSaleInFlight()
WoW.pendingSales = {}
table.insert(WoW.buyback, { link = WoW.itemLink(108), count = 1 })   -- the page first, the slot later
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers(0)
eq(table.concat(sold(), ","), "8,1", "the page grew with our sale as its newest entry: confirmed, the next sale starts")
WoW.salesAsync = false
WoW.applySales()
drain()

-- A RepairAllItems that only spends the guild's allowance on a guild call
-- (the client's own takes the rest from the player too: test_junk.lua), so
-- the personal step is reached.
local function guildOnly(guild)
    table.insert(WoW.calls, { "RepairAllItems", guild == true })
    if guild then
        local paid = math.min(WoW.repairCost, WoW.guild.allowance)
        WoW.guild.allowance, WoW.repairCost = WoW.guild.allowance - paid, WoW.repairCost - paid
    else
        WoW.money, WoW.repairCost = WoW.money - WoW.repairCost, 0
    end
    WoW.fire("UPDATE_INVENTORY_DURABILITY")
end
local realRepair = RepairAllItems

-- J5: a durability change that raised the cost (a hit at the vendor) is not
-- the guild repair settling: nothing from the player on it; the timeout stops.
reset()
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 500 }
WoW.repairCost, WoW.repairSilent = 300, true    -- the guild call hasn't landed
WoW.bags = { [0] = { size = 1, items = {} } }
WoW.openMerchant()
soon(1)                                           -- nothing to sell, the settle wait, the guild step
eq(repairs(), 1, "the guild step called")
WoW.repairCost = 400                              -- hit meanwhile: the cost rose
WoW.fire("UPDATE_INVENTORY_DURABILITY")
eq(repairs(), 1, "a cost that rose: not settled, no payment from the player")
eq(WoW.money, 1000, "  nothing paid")
drain()
check(has(newChat(), "The repair couldn't be confirmed"), "  the timeout stops it, and says so")
-- A cost that fell is the repair settling: the rest from my money, as before.
reset()
RepairAllItems = guildOnly
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 100 }
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
WoW.openMerchant()
drain()
RepairAllItems = realRepair
eq(repairs(), 2, "a cost that fell: settled, the rest from my money")
eq(WoW.money, 800, "  paid")

-- J4: between the guild step and the personal one: the setting off, or combat.
for _, case in ipairs({ "setting", "combat" }) do
    reset()
    RepairAllItems = function(guild)
        if guild and case == "setting" then P.SetSetting("junk", "autoRepair", false) end
        if guild and case == "combat" then WoW.combat = true; WoW.fire("PLAYER_REGEN_DISABLED") end
        guildOnly(guild)
    end
    WoW.guild = { member = true, mayRepair = true, info = "", allowance = 100 }
    WoW.repairCost = 300
    WoW.bags = { [0] = { size = 1, items = {} } }
    WoW.openMerchant()
    drain()
    RepairAllItems = realRepair
    eq(repairs(), 1, case .. " after the guild step: no personal payment")
    eq(WoW.money, 1000, "  nothing paid")
    if case == "combat" then check(has(newChat(), "Combat: the repair stopped."), "  and said") end
    P.ResetSettings("junk")
    WoW.combat = false
    WoW.fire("PLAYER_REGEN_ENABLED")
end

-- J9: switched off during the settle wait after selling: no repair starts.
reset()
WoW.repairCost = 300
WoW.openMerchant()
soon(0.2)                                   -- the sales, at once; the settle wait pending
eq(#sold(), 3, "sold (at once)")
check(J.state.run and J.state.run.ended, "  the run ended, its settle wait pending")
P.Set("junk", false)
drain()
eq(repairs(), 0, "switched off during the settle wait: no repair")
eq(WoW.money, 1000 + 2 + 15 + 30, "  nothing paid")
P.Set("junk", true)

done("test_junk_audit")
