-- The restock pearl's choices (#14, R.Plan): the best usable offer (value
-- beats level, never bind on pickup), as-good-or-better counting (conjured
-- and locked stacks count, an unreadable slot skips the line), water only for
-- mana users, ammo by the ranged weapon, reagents of the highest known rank,
-- Buffy's reagents left to it, the last pack past the target, and every offer
-- rule (extended cost, currency, high price, not purchasable or usable, stock,
-- secret or throwing reads).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ITEMS = {
    [159] = "Refreshing Spring Water", [1205] = "Melon Juice", [1708] = "Sweet Nectar",
    [287964] = "Morning Glory Dew", [8766] = "Morning Glory Dew", [5350] = "Conjured Water",
    [8079] = "Conjured Crystal Water", [4540] = "Tough Hunk of Bread", [4544] = "Mulgore Spice Bread",
    [17031] = "Rune of Teleportation", [17032] = "Rune of Portals", [17056] = "Light Feather",
    [17020] = "Arcane Powder", [17034] = "Maple Seed", [17035] = "Stranglethorn Seed",
    [19222] = "Cheap Beer",
}
for id, name in pairs(ITEMS) do WoW.items[id] = { name = name, maxStack = 20, price = 1, quality = 1 } end
for _, id in ipairs({ 2515, 3030, 3033 }) do WoW.items[id] = { name = "ammo " .. id, maxStack = 200, family = 1 } end
WoW.items[2504] = { name = "Worn Shortbow", classID = 2, subclassID = 2 }
WoW.items[2508] = { name = "Old Blunderbuss", classID = 2, subclassID = 3 }
WoW.items[2132] = { name = "Short Staff", classID = 2, subclassID = 10 }
WoW.items[2101] = { name = "Light Quiver", classID = 4, subclassID = 2 }

local GOODS = {
    { id = 159, price = 25, pack = 5 },
    { id = 1205, price = 500, pack = 5 },
    { id = 1708, price = 1000, pack = 5 },        -- the best water a level 26 can use
    { id = 287964, price = 4000, pack = 5 },      -- more, but bind on pickup
    { id = 8766, price = 4000, pack = 5 },        -- level 45
    { id = 4540, price = 25, pack = 5 },
    { id = 4544, price = 1000, pack = 5 },
    { id = 17031, price = 1000, pack = 1 },
    { id = 17032, price = 2000, pack = 1 },       -- Portals: not known
    { id = 17056, price = 30, pack = 1 },
    { id = 17020, price = 1000, pack = 1 },
    { id = 19222, price = 10, pack = 1 },         -- beer: not in the data
    { id = 2515, price = 50, pack = 200 },
    { id = 3030, price = 300, pack = 200 },
    { id = 3033, price = 300, pack = 200 },
    { id = 17034, price = 200, pack = 1 },
    { id = 17035, price = 400, pack = 1 },
}
local function goods()
    WoW.goods = {}
    for i, g in ipairs(GOODS) do
        local c = {}
        for k, v in pairs(g) do c[k] = v end
        WoW.goods[i] = c
    end
end
local function bags(items)
    WoW.bags = { [0] = { size = 16, items = items or {} }, [1] = { size = 8, items = {} } }
end
goods()
bags()
WoW.class, WoW.playerLevel, WoW.money = "MAGE", 26, 100000
WoW.known[130], WoW.known[3561] = true, true   -- Slow Fall, Teleport: Stormwind
local GP = loadAddon()
local R, P = GP.Restock, GP.Pearls
P.Set("junk", false)

local function plan()
    WoW.merchant = { repairs = true }
    local lines, notes = R.Plan()
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = l.id .. "x" .. (l.packs * l.pack) end
    return table.concat(out, " "), lines, notes
end
local function find(lines, id) for _, l in ipairs(lines) do if l.id == id then return l end end end

-- A level-26 mage with empty bags.
local text, lines = plan()
eq(text, "17031x10 17056x20 1708x20 4544x20", "reagents, then water, then food: the best usable, to the targets")
eq(lines[3].kind, "drink", "  Sweet Nectar is the water line")
eq(R.Cost(lines), 10000 + 600 + 4000 + 4000, "  their cost")
check(not find(lines, 287964), "  never the bind-on-pickup Morning Glory Dew, however much it restores")
check(not find(lines, 8766), "  never one above the character's level")
check(not find(lines, 17032), "  never the reagent of a spell not known")
check(not find(lines, 19222), "  never what isn't in the data (beer)")

-- As good or better.
bags({ [1] = { id = 1205, count = 15 }, [2] = { id = 5350, count = 20 } })
eq(find(select(2, plan()), 1708).packs, 4, "15 Melon Juice and 20 Conjured Water don't count toward Sweet Nectar")
bags({ [1] = { id = 1708, count = 10 }, [2] = { id = 8079, count = 5 } })
eq(find(select(2, plan()), 1708).packs, 1, "10 Sweet Nectar and 5 Conjured Crystal Water do (better, conjured): one pack")
bags({ [1] = { id = 1708, count = 20, locked = true } })
check(not find(select(2, plan()), 1708), "a locked stack counts: nothing to buy")
bags({ [1] = { id = 1708, count = 18 } })
eq(find(select(2, plan()), 1708).packs, 1, "18 of 20: one pack of 5, past the target (a floor)")
bags({ [1] = { id = WoW.Secret("id"), count = 1 } })
local _, l2, notes = plan()
check(not find(l2, 1708) and #notes > 0, "an unreadable slot: the lines skipped, never counted as none")
bags()

-- Mana users only for water.
WoW.class = "WARRIOR"
eq(plan(), "4544x20", "a warrior: food only (no reagents, no water)")
WoW.class = "MAGE"
P.SetSetting("restock", "water", false)
check(not find(select(2, plan()), 1708), "water switched off")
P.ResetSettings("restock")
P.SetSetting("restock", "r17056", 0)
check(not find(select(2, plan()), 17056), "a reagent at 0: never")
P.ResetSettings("restock")
P.SetSetting("restock", "reagents", false)
eq(plan(), "1708x20 4544x20", "reagents switched off")
P.ResetSettings("restock")

-- Buffy's reagents: left to it only while it restocks them.
WoW.known[23028] = true   -- Arcane Brilliance
check(find(select(2, plan()), 17020) ~= nil, "Arcane Powder without Buffy: bought")
WoW.loadedAddOns.Buffy = true
local buffyOn = true
rawset(_G, "Buffy", { Get = function() return buffyOn end,
    class = { restock = { enabledKey = "autoBuyPowder", items = function() return { 17020 } end } } })
check(not find(select(2, plan()), 17020), "  Buffy restocking it: left to Buffy")
check(R.BuffyHas(17020) and not R.BuffyHas(17031), "  only the reagents Buffy lists")
buffyOn = false
check(find(select(2, plan()), 17020) ~= nil, "  Buffy's restock off: bought")
rawset(_G, "Buffy", {})
check(not find(select(2, plan()), 17020), "  Buffy unreadable: its fixed list is left to it")
WoW.loadedAddOns.Buffy, WoW.known[23028] = nil, nil
rawset(_G, "Buffy", nil)

-- A druid's Rebirth: the reagent of the highest rank known.
WoW.class = "DRUID"
WoW.known[20484] = true
eq(plan(), "17034x5 1708x20 4544x20", "Rebirth 1: Maple Seed")
WoW.known[20739] = true
eq(plan(), "17035x5 1708x20 4544x20", "Rebirth 2 known too: Stranglethorn Seed, no more Maple Seed")
WoW.known[20484], WoW.known[20739] = nil, nil

-- A hunter's ammo, by the ranged weapon.
WoW.class = "HUNTER"
WoW.equipped[18] = 2504
eq(find(select(2, plan()), 3030) and find(select(2, plan()), 3030).packs, 5, "a bow: Razor Arrows (level 25), 1000")
check(not find(select(2, plan()), 2515), "  not the weaker Sharp Arrows")
bags({ [1] = { id = 3030, count = 200 }, [2] = { id = 3030, count = 200 }, [3] = { id = 3030, count = 200 },
       [4] = { id = 3030, count = 200 }, [5] = { id = 3030, count = 150 }, [6] = { id = 2515, count = 200 } })
eq(find(select(2, plan()), 3030).packs, 1, "950 Razor Arrows (Sharp ones don't count): one pack, to 1150")
bags()
WoW.equipped[18] = 2508
check(find(select(2, plan()), 3033) and not find(select(2, plan()), 3030), "a gun: Solid Shot")
WoW.equipped[18] = 2132
check(not find(select(2, plan()), 3033), "a staff: no ammo")
WoW.equipped[18] = 2101
check(not find(select(2, plan()), 3030), "not a weapon (armour, its subclass a bow's number): no ammo")
WoW.equipped[18] = nil
check(not find(select(2, plan()), 3030), "no ranged weapon: no ammo")
WoW.class = "MAGE"

-- Every offer rule: Sweet Nectar refused one way or another, Melon Juice next.
local function without(field, value, what)
    goods()
    WoW.goods[3][field] = value
    check(find(select(2, plan()), 1205) ~= nil and not find(select(2, plan()), 1708), what)
end
without("extended", true, "an extended cost: not bought")
without("currencyID", 1, "a currency: not bought")
without("price", 1500000, "Blizzard's high price: not bought")
without("purchasable", false, "not purchasable: not bought")
without("usable", false, "not usable: not bought")
without("stock", 4, "fewer in stock than a pack: not bought")
without("stock", 0, "sold out: not bought")
without("price", WoW.Secret("price"), "a secret price: not bought")
without("pack", 0, "no pack size: not bought")
goods()
WoW.goods[3].stock = 5
check(find(select(2, plan()), 1708) ~= nil, "a limited stock of one pack: still an offer")
goods()
local getID = GetMerchantItemID
GetMerchantItemID = function(i) if i == 3 then error("x") end return getID(i) end
check(find(select(2, plan()), 1205) ~= nil, "a read that throws: not bought")
GetMerchantItemID = getID

done("test_restock_plan")
