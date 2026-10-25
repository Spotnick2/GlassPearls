-- "Sell junk & repair" (#15): what is junk (grey, the lists, every never,
-- unknown data), the order, selling one at a time with each sale re-checked
-- and confirmed, the stops (close, combat, cursor, refusal, unconfirmed),
-- buyback-safe, Shift, the money lines, repair (guild first then mine, guild
-- short, no guild, [noautorepair], my money only, not enough money, a repair
-- that never settles, a merchant that can't repair), the commands and lists.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ITEMS = {
    [101] = { name = "Broken Fang", price = 5, quality = 0, classID = 15 },
    [102] = { name = "Torn Boots", price = 30, quality = 0, classID = 4 },
    [103] = { name = "Linen Cloth", price = 10, quality = 1, classID = 7 },
    [104] = { name = "Odd Trinket", price = 8, quality = 0, classID = 15, spell = true },
    [105] = { name = "Epic Blade", price = 1000, quality = 4, classID = 2 },
    [106] = { name = "Vendor Shirt", price = 20, quality = 1, classID = 4 },
    [107] = { name = "Quest Bone", price = 3, quality = 0, classID = 15 },
    [108] = { name = "Cracked Pot", price = 2, quality = 0, classID = 15 },
    [6948] = { name = "Hearthstone", price = 1, quality = 1, classID = 15 },   -- a price, to reach its own rule
    [2901] = { name = "Mining Pick", price = 4, quality = 1, classID = 2 },
}
local function fill()
    WoW.bags = { [0] = { size = 16, items = {
        [1] = { id = 101, count = 3 },           -- grey: 15c
        [2] = { id = 102, bound = true },        -- grey gear, bound: 30c
        [3] = { id = 103, count = 5 },           -- white: only if listed
        [4] = { id = 104 },                      -- grey with a use: kept
        [5] = { id = 105 },                      -- epic: never, even listed
        [6] = { id = 106, refundable = true },   -- refundable: never
        [7] = { id = 107 },                      -- a quest item
        [8] = { id = 108 },                      -- grey: 2c, the cheapest
        [9] = { id = 6948 },                     -- the Hearthstone
        [10] = { id = 2901 },                    -- a tool
        [11] = { id = 102 },                     -- grey gear, unbound: kept
    } } }
    WoW.quest = { ["0:7"] = { isQuestItem = true } }
end
for id, it in pairs(ITEMS) do WoW.items[id] = it end
fill()
WoW.money = 1000

local GP = loadAddon()
local J, P, SS = GP.Junk, GP.Pearls, GP.SettingsSync
-- Run every timer, again and again, as the client would over time.
local function drain()
    for _ = 1, 50 do
        if #WoW.timers == 0 then return end
        WoW.flushTimers()
    end
end
local function visit(m)
    newChat()
    WoW.openMerchant(m)
    drain()
    return newChat()
end
local function text(lines) return table.concat(lines, "\n") end
local function has(lines, s) return text(lines):find(s, 1, true) ~= nil end
local function sold() local t = {} for _, c in ipairs(WoW.calls) do if c[1] == "UseContainerItem" then t[#t + 1] = c[3] end end return t end
local function reset() fill(); WoW.calls, WoW.buyback, WoW.money = {}, {}, 1000; WoW.closeMerchant() end

check(P.IsLive("junk"), "on by default")
eq(P.Get("junk").category, "Loot & Bags", "on the Loot & Bags page")

-- What is junk.
local function why(slot) local _, w = J.Judge(GP.Bags.Slot(0, slot), {}) return w end
local function junk(slot) return J.Judge(GP.Bags.Slot(0, slot), {}) ~= nil end
check(junk(1), "a grey with a price")
check(junk(2), "bound grey gear")
eq(why(3), "not junk", "a white, unlisted")
eq(why(4), "it has a use", "a grey with a use")
eq(why(6), "refundable", "a refundable purchase")
eq(why(7), "a quest item", "a quest item")
eq(why(9), "never sold", "the Hearthstone")
eq(why(10), "a tool", "a tool")
eq(why(11), "unbound grey gear", "unbound grey gear")
eq(select(2, J.Judge(GP.Bags.Slot(0, 1), nil)), "equipment sets unreadable", "equipment sets unreadable: nothing")
eq(select(2, J.Judge(GP.Bags.Slot(0, 1), { [101] = true })), "in an equipment set", "an equipment-set item")
WoW.bags[0].items[1].locked = true
eq(why(1), "locked", "a locked stack")
WoW.bags[0].items[1].locked = nil
WoW.items[101] = nil
WoW.bags[0].items[1].quality = 0   -- the container still says grey
eq(why(1), "not cached", "uncached: not junk")
WoW.items[101] = ITEMS[101]
WoW.bags[0].items[1].quality = nil
WoW.questUnreadable = true
eq(why(1), "unknown quest info", "unreadable quest info: not junk")
WoW.questUnreadable = false
local realRefund = C_Item.CanBeRefunded
C_Item.CanBeRefunded = function() error("x") end
eq(why(1), "unknown refund", "an unreadable refund state: not junk")
C_Item.CanBeRefunded = realRefund
local realBound = C_Item.IsBound
C_Item.IsBound = function() return WoW.Secret("bound") end
eq(why(2), "unknown binding", "a secret binding: not junk")
C_Item.IsBound = realBound
-- The lists.
J.List("sell", 103)
check(junk(3), "a listed white: sold")
J.List("sell", 104)
check(junk(4), "a listed grey with a use: sold")
J.List("sell", 11 == 11 and 102)
check(junk(11), "listed grey gear, unbound: sold")
J.List("sell", 105)
eq(why(5), "epic or better", "a listed epic: never")
J.List("sell", 106)
eq(why(6), "refundable", "a listed refundable: never")
J.List("keep", 101)
eq(why(1), "kept", "the keep list wins over the grey rule")
check(not SS.SetHas(J.SELL, 101) and SS.SetHas(J.KEEP, 101), "  listed on one list only")
J.List("sell", 101)
check(SS.SetHas(J.SELL, 101) and not SS.SetHas(J.KEEP, 101), "moving it to sell takes it off keep")
J.Forget(101)
check(not SS.SetHas(J.SELL, 101) and not SS.SetHas(J.KEEP, 101), "forget: off both")
for _, id in ipairs({ 103, 104, 102, 105, 106 }) do J.Forget(id) end
P.SetSetting("junk", "sellGrey", false)
eq(why(1), "not junk", "the grey rule off: greys stay")
P.ResetSettings("junk")

-- The order: cheapest first by price x count.
local order = {}
for _, e in ipairs(J.Candidates()) do order[#order + 1] = e.id end
eq(table.concat(order, ","), "108,101,102", "cheapest first: 2c, 15c, 30c")

-- A visit: sells, one at a time, then says what changed.
local lines = visit()
eq(table.concat(sold(), ","), "8,1,2", "sold the three, cheapest first")
eq(WoW.money, 1000 + 2 + 15 + 30, "the money arrived")
check(has(lines, "Sold 5 items (3 stacks): your money +47c."), "the line: items, stacks, money observed")
eq(WoW.bags[0].items[4].id, 104, "the grey with a use stays")
eq(WoW.bags[0].items[11].id, 102, "  the unbound grey gear stays")
eq(#WoW.buyback, 3, "three on the buyback page")
reset()
-- Nothing to sell: nothing said.
WoW.bags = { [0] = { size = 4, items = { [1] = { id = 103 } } } }
lines = visit()
eq(#sold(), 0, "nothing junk: nothing sold")
check(not has(lines, "Sold"), "  and nothing said")
reset()

-- Shift held: nothing this visit. Combat: nothing. Off: nothing.
WoW.shift = true
visit()
eq(#sold(), 0, "Shift held: nothing sold")
WoW.shift = false
reset()
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
lines = visit()
eq(#sold(), 0, "in combat: nothing")
eq(#lines, 0, "  and nothing said: the visit is just skipped")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
reset()
P.SetSetting("junk", "autoSell", false)
visit()
eq(#sold(), 0, "selling off: nothing sold")
P.ResetSettings("junk")
reset()

-- Each sale re-checked just before: a stack swapped for another of the same
-- item and count (another GUID) is skipped.
WoW.salesAsync = true
newChat()
WoW.openMerchant()
WoW.flushTimers(J.OPEN_DELAY)
eq(table.concat(sold(), ","), "8", "one sale in flight at a time")
WoW.bags[0].items[1] = { id = 101, count = 3, guid = "Item-other" }
WoW.applySales()
drain()
eq(table.concat(sold(), ","), "8,2", "a stack swapped since the queue: skipped, the next sold")
WoW.salesAsync = false
reset()
-- An unconfirmed sale stops the run.
WoW.salesAsync = true
lines = visit()
eq(#sold(), 1, "a sale never confirmed: no second one")
check(has(lines, "A sale wasn't confirmed: stopped selling."), "  and said")
WoW.salesAsync, WoW.pendingSales = false, {}
reset()
-- The merchant closes mid-run.
WoW.salesAsync = true
newChat()
WoW.openMerchant()
WoW.flushTimers(J.OPEN_DELAY)
WoW.closeMerchant()
WoW.applySales()
drain()
eq(#sold(), 1, "closed mid-run: no more sales")
WoW.salesAsync = false
reset()
-- Something on the cursor: stops before selling.
WoW.cursor = { bag = 0, slot = 3, id = 103 }
lines = visit()
eq(#sold(), 0, "something on the cursor: nothing sold")
check(has(lines, "Something is on your cursor: stopped selling."), "  and said")
WoW.cursor = nil
reset()
-- The merchant refuses: stopped by the error's name, only for our sale.
WoW.merchantRefuses = 51
lines = visit()
eq(#sold(), 1, "a refusal stops after the first try")
check(has(lines, "This merchant won't take more: stopped."), "  and said")
WoW.merchantRefuses = nil
reset()
local realInfo = GetGameMessageInfo
GetGameMessageInfo = function() return WoW.Secret("name") end
WoW.merchantRefuses = 52
lines = visit()
eq(#sold(), 1, "an unreadable error name: the localized text still stops it")
check(has(lines, "This merchant won't take more: stopped."), "  as a refusal, not a timeout")
GetGameMessageInfo = realInfo
WoW.merchantRefuses = nil
reset()
-- Between two of our sales (none in flight), someone else's refusal is ignored.
WoW.salesAsync = true
newChat()
WoW.openMerchant()
WoW.flushTimers(J.OPEN_DELAY)
WoW.applySales()               -- the first sale confirmed; the next not yet started
WoW.fire("UI_ERROR_MESSAGE", 51, ERR_VENDOR_DOESNT_BUY)
WoW.salesAsync = false
drain()
eq(#sold(), 3, "a refusal while none of ours is in flight is ignored: all three sold")
reset()

-- Buyback-safe: the room left on the page, cheapest first; stops if one of ours is gone.
P.SetSetting("junk", "safe", true)
for i = 1, 10 do WoW.buyback[i] = { link = "old" .. i, count = 1 } end
lines = visit()
eq(table.concat(sold(), ","), "8,1", "two slots of room: the two cheapest sold")
check(has(lines, "Buyback-safe: sold 2 of 3 stacks; the rest next visit."), "  and the rest left for next time")
eq(WoW.bags[0].items[2].id, 102, "  the most valuable kept")
reset()
for i = 1, 11 do WoW.buyback[i] = { link = "old" .. i, count = 1 } end
local realSell = C_Container.UseContainerItem
C_Container.UseContainerItem = function(bag, slot)
    realSell(bag, slot)
    for _ = 1, 4 do   -- four sales of the player's in between
        table.insert(WoW.buyback, { link = "mine", count = 1 })
        if #WoW.buyback > 12 then table.remove(WoW.buyback, 1) end
    end
end
for i = 1, 11 do WoW.buyback[i] = nil end
for i = 1, 8 do WoW.buyback[i] = { link = "old" .. i, count = 1 } end
lines = visit()
C_Container.UseContainerItem = realSell
check(has(lines, "may no longer be on the buyback page"), "one of ours pushed off the page: stopped and said")
P.ResetSettings("junk")
reset()

-- Repair: guild funds first, then mine.
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 500 }
WoW.repairCost = 300
lines = visit()
eq(WoW.repairCost, 0, "repaired")
eq(WoW.guild.allowance, 200, "  by the guild")
check(has(lines, "Repaired with guild funds."), "  and said, after selling")
check(text(lines):find("Sold") < text(lines):find("Repaired"), "  selling first, then repair")
reset()
-- The guild covers part: the rest from my money, said as observed.
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 100 }
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
lines = visit()
eq(WoW.repairCost, 0, "repaired in full")
eq(WoW.money, 800, "  my money paid the 200 the guild didn't")
check(has(lines, "Repaired, guild funds first: your money -200c."), "  said as the money change observed")
reset()
-- The guild covers part and my money doesn't cover the rest. In this client
-- the guild call itself takes what it can; the second call must not happen.
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 100 }
WoW.repairCost, WoW.money = 300, 50
WoW.bags = { [0] = { size = 1, items = {} } }
lines = visit()
local repairs = 0
for _, c in ipairs(WoW.calls) do if c[1] == "RepairAllItems" then repairs = repairs + 1 end end
eq(repairs, 1, "not enough for the rest: one guild call, no second")
check(has(lines, "Guild funds covered part; not enough money for the rest (200c)."), "  and said")
reset()
-- [noautorepair] in the guild's info: my money only.
WoW.guild = { member = true, mayRepair = true, info = "Welcome! [NoAutoRepair] please", allowance = 500 }
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
lines = visit()
eq(WoW.guild.allowance, 500, "[noautorepair]: the guild is never charged")
eq(WoW.money, 700, "  my money paid")
check(has(lines, "Repaired: your money -300c."), "  and said")
reset()
local realInfoText = GetGuildInfoText
GetGuildInfoText = function() return WoW.Secret("info") end
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 500 }
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
visit()
eq(WoW.guild.allowance, 500, "unreadable guild info: the guild is never charged")
GetGuildInfoText = realInfoText
reset()
-- Not allowed by the guild, not in a guild, or "my money only".
for _, g in ipairs({ { member = true, mayRepair = false }, { member = false, mayRepair = false } }) do
    WoW.guild = { member = g.member, mayRepair = g.mayRepair, info = "", allowance = 500 }
    WoW.repairCost = 300
    WoW.bags = { [0] = { size = 1, items = {} } }
    visit()
    eq(WoW.guild.allowance, 500, "no guild repair right: my money")
    reset()
end
P.SetSetting("junk", "repairFunds", "mine")
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 500 }
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
visit()
eq(WoW.guild.allowance, 500, "'my money only': the guild never charged")
eq(WoW.money, 700, "  my money paid")
P.ResetSettings("junk")
reset()
-- Not enough money, nothing to repair, a merchant that can't, repair off, Shift.
WoW.guild = { member = false, mayRepair = false, info = "", allowance = 0 }
WoW.repairCost, WoW.money = 300, 100
WoW.bags = { [0] = { size = 1, items = {} } }
lines = visit()
check(has(lines, "Not enough money to repair (300c)."), "not enough money: said, nothing paid")
eq(WoW.money, 100, "  nothing spent")
reset()
WoW.repairCost = 0
WoW.bags = { [0] = { size = 1, items = {} } }
lines = visit()
eq(#lines, 0, "nothing to repair, nothing to sell: silent")
reset()
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
visit({ repairs = false })
eq(WoW.repairCost, 300, "a merchant that can't repair: nothing")
reset()
P.SetSetting("junk", "autoRepair", false)
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
visit()
eq(WoW.repairCost, 300, "repair off: nothing")
P.ResetSettings("junk")
reset()
-- A repair that never settles: stopped, never paid twice.
WoW.repairSilent = true
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 500 }
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
lines = visit()
repairs = 0
for _, c in ipairs(WoW.calls) do if c[1] == "RepairAllItems" then repairs = repairs + 1 end end
eq(repairs, 1, "an unsettled repair: one call only")
check(has(lines, "The repair couldn't be confirmed"), "  and said")
WoW.repairSilent = false
reset()
-- A durability update that leaves the cost unchanged is not a settled repair.
local realRepair = RepairAllItems
RepairAllItems = function(guild)
    table.insert(WoW.calls, { "RepairAllItems", guild == true })
    WoW.fire("UPDATE_INVENTORY_DURABILITY")   -- something else changed; the cost didn't
end
WoW.guild = { member = true, mayRepair = true, info = "", allowance = 500 }
WoW.repairCost = 300
WoW.bags = { [0] = { size = 1, items = {} } }
lines = visit()
RepairAllItems = realRepair
repairs = 0
for _, c in ipairs(WoW.calls) do if c[1] == "RepairAllItems" then repairs = repairs + 1 end end
eq(repairs, 1, "an unchanged cost after the event: still unsettled, no second call")
check(has(lines, "The repair couldn't be confirmed"), "  and said")
reset()
-- Repair alone when selling is off.
P.SetSetting("junk", "autoSell", false)
WoW.guild = { member = false, mayRepair = false, info = "", allowance = 0 }
WoW.repairCost = 300
visit()
eq(WoW.repairCost, 0, "selling off: it still repairs")
eq(#sold(), 0, "  and sells nothing")
P.ResetSettings("junk")
reset()

-- Commands.
newChat()
SlashCmdList.GLASSPEARLS("sell")
local list = newChat()
check(has(list, "3 stacks would be sold, worth 47c:"), "/gpearls sell lists what would sell, and its worth")
SlashCmdList.GLASSPEARLS("sell " .. WoW.itemLink(103))
check(SS.SetHas(J.SELL, 103), "/gpearls sell <link>: on the sell list (the link lowercased by the slash)")
check(has(newChat(), "Linen Cloth will be sold at merchants."), "  and said")
SlashCmdList.GLASSPEARLS("keep 108")
check(SS.SetHas(J.KEEP, 108), "/gpearls keep <id>: on the keep list")
SlashCmdList.GLASSPEARLS("forget " .. WoW.itemLink(103))
check(not SS.SetHas(J.SELL, 103), "/gpearls forget <link>: off")
SlashCmdList.GLASSPEARLS("keep")
check(has(newChat(), "Shift-click an item into chat"), "no item: how to give one")
eq(J.ItemIDOf("|cff9d9d9d|hitem:4567::::|h[x]|h|r"), 4567, "a lowercased link's item ID")
eq(J.ItemIDOf("[Broken Fang]"), nil, "a name is never an ID")
SlashCmdList.GLASSPEARLS("junk off")
check(not P.IsLive("junk"), "/gpearls junk off switches the pearl")
SlashCmdList.GLASSPEARLS("junk on")
J.Forget(108)
-- The lists full: refused and said.
local i = 0
while SS.Core.SetEntries(GP.db.sync) < SS.SET_MAX do
    i = i + 1
    SS.SetAdd(GP.BagsFull.KEEP, 200000 + i)
end
newChat()
SlashCmdList.GLASSPEARLS("sell 109")   -- never listed: no tombstone to reuse
check(has(newChat(), "The lists are full"), "the shared cap reached: refused and said")
check(not SS.SetHas(J.SELL, 109), "  nothing listed")
SS.SetClear(GP.BagsFull.KEEP)

-- Switched off: a merchant does nothing.
P.Set("junk", false)
reset()
visit()
eq(#sold(), 0, "off: nothing sold")
P.Set("junk", true)

done("test_junk")
