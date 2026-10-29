-- Core/Bags.lua (#6): room (true / false / unknown, partial stacks, specialty
-- bags), what may be offered (known data only, every exclusion), the order.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local B = GP.Bags

local function items(t) for id, it in pairs(t) do WoW.items[id] = it end end
items({
    [1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 },
    [2] = { name = "Linen Cloth", price = 13, quality = 1, maxStack = 20, classID = 7 },
    [3] = { name = "Green Ring", price = 900, quality = 2, maxStack = 1, classID = 4 },
    [4] = { name = "Peacebloom", price = 4, quality = 1, maxStack = 20, family = 32 },   -- an herb
    [5] = { name = "Grey Potion", price = 1, quality = 0, maxStack = 5, classID = 0 },
    [6] = { name = "White Potion", price = 2, quality = 1, maxStack = 5, classID = 0 },
    [7] = { name = "Worn Wand", price = 3, quality = 1, maxStack = 1, classID = 2, spell = true },
    [8] = { name = "Grey With Use", price = 2, quality = 0, maxStack = 1, classID = 15, spell = true },
})

-- Room.
WoW.bags[0] = { size = 4, items = { [1] = { id = 1 }, [2] = { id = 2, count = 15 }, [3] = { id = 3 }, [4] = { id = 1 } } }
local snap = B.Snapshot()
eq(snap.general, 0, "a full backpack: no free general slot")
eq(B.Fits(2, 5, snap), true, "a partial stack is room (15 + 5 <= 20)")
eq(B.Fits(2, 6, snap), false, "  but not for more than its space")
eq(B.Fits(3, 1, snap), false, "an item that doesn't stack, no free slot: doesn't fit")
eq(B.Fits(999, 1, snap), nil, "an uncached item: can't be told (never prompts)")
eq(B.Fits(2, 0, snap), true, "nothing to fit always fits")
-- A herb bag with room takes herbs, nothing else.
WoW.bags[1] = { size = 2, family = 32, items = {} }
snap = B.Snapshot()
eq(B.Fits(4, 1, snap), true, "a herb fits the herb bag though the backpack is full")
eq(B.Fits(3, 1, snap), false, "  a ring doesn't")
eq(#snap.specialty, 1, "the herb bag is a specialty bag")
-- Quantity across several slots.
WoW.bags[1] = { size = 2, items = {} }
snap = B.Snapshot()
eq(B.Fits(2, 25, snap), true, "25 cloth: 5 on the stack + 20 in a free slot")
eq(B.Fits(2, 46, snap), false, "  46 doesn't (5 + 2 x 20)")
-- A locked stack offers no room.
WoW.bags[0].items[2].locked = true
snap = B.Snapshot()
eq(B.Fits(2, 1, B.Snapshot()) and B.Snapshot().stacks[2], nil, "a locked stack isn't counted as room")
WoW.bags[0].items[2].locked = nil
WoW.bags[1] = nil

-- Eligibility: grey scope.
local opts = { scope = "grey", tools = GP.ToolItems, setItems = {}, keep = function() return false end }
local function why(bag, slot, o)
    local c, w = B.Eligible(B.Slot(bag, slot), o or opts)
    return c and "ok" or w
end
eq(why(0, 1), "ok", "a grey item with a price: eligible")
eq(why(0, 2), "quality", "a white item, grey scope: no")
eq(why(0, 3), "quality", "a green item: never")
local white = { scope = "white", tools = GP.ToolItems, setItems = {}, keep = function() return false end }
eq(why(0, 2, white), "ok", "a white item, white scope: eligible")
eq(why(0, 3, white), "quality", "  a green one still never")
local function only(id, extra)
    WoW.bags[0].items = { [1] = { id = id } }
    for k, v in pairs(extra or {}) do WoW.bags[0].items[1][k] = v end
    return why(0, 1, white)
end
-- Every exclusion.
items({ [20] = { name = "Ammo", price = 1, quality = 1, classID = 6 }, [21] = { name = "Recipe", price = 9, quality = 1, classID = 9 },
        [22] = { name = "Bag", price = 50, quality = 1, classID = 1 }, [23] = { name = "Reagent", price = 2, quality = 1, classID = 5 },
        [24] = { name = "Quiver", price = 9, quality = 1, classID = 11 }, [25] = { name = "Quest", price = 1, quality = 1, classID = 12 },
        [26] = { name = "Key", price = 1, quality = 1, classID = 13 }, [27] = { name = "Pole", price = 4, quality = 1, classID = 2, subclassID = 20 },
        [2901] = { name = "Mining Pick", price = 4, quality = 1, classID = 7 }, [30] = { name = "Set Gear", price = 40, quality = 1, classID = 4 },
        [31] = { name = "Free", price = 0, quality = 0 } })
eq(only(20), "ammunition", "ammunition: never")
eq(only(21), "a recipe", "a recipe: never")
eq(only(22), "a container", "a bag: never")
eq(only(23), "a reagent", "a reagent: never")
eq(only(24), "a quiver", "a quiver: never")
eq(only(25), "a quest item", "a quest-class item: never")
eq(only(26), "a key", "a key: never")
eq(only(27), "a fishing pole", "a fishing pole: never")
eq(only(2901), "a tool", "a profession tool (from the client's tool list): never")
eq(only(31), "no value", "no sell price: never")
eq(only(2, { locked = true }), "locked", "a locked stack: never")
eq(only(6), "a consumable", "a white consumable: never")
eq(only(5), "ok", "  a grey one: yes (junk)")
eq(only(7), "it has a use", "a white item with a use: never")
eq(only(8), "ok", "  a grey one with a use: yes")
WoW.quest["0:1"] = { isQuestItem = true }
eq(only(1), "a quest item", "a quest item (its quest info): never")
WoW.quest["0:1"] = { questID = 77 }
eq(only(1), "a quest item", "a quest starter: never")
WoW.quest["0:1"] = nil
-- Equipment sets, the keep list.
local withSets = { scope = "white", tools = GP.ToolItems, setItems = { [30] = true }, keep = function() return false end }
WoW.bags[0].items = { [1] = { id = 30 } }
eq(select(2, B.Eligible(B.Slot(0, 1), withSets)), "in an equipment set", "an equipment-set item: never")
local keepOpts = { scope = "white", tools = GP.ToolItems, setItems = {}, keep = function(id) return id == 30 end }
eq(select(2, B.Eligible(B.Slot(0, 1), keepOpts)), "kept", "an item on the keep list: never")

-- Unknown is ineligible, never "probably fine".
WoW.bags[0].items = { [1] = { id = 1 } }
local cached = WoW.items[1]
WoW.items[1] = nil
WoW.bags[0].items[1].quality = 0
eq(why(0, 1), "not cached", "an uncached item: ineligible")
WoW.items[1] = cached
WoW.bags[0].items[1].quality = nil
WoW.items[1] = { name = "Grey Junk", price = 5, maxStack = 1 }   -- no quality anywhere
eq(why(0, 1), "unknown quality", "no quality: ineligible")
WoW.items[1] = cached
WoW.questUnreadable = true
eq(why(0, 1), "unknown quest info", "unreadable quest info: ineligible")
WoW.questUnreadable = false
eq(select(2, B.Eligible(B.Slot(0, 1), { scope = "grey", tools = {}, setItems = nil })), "equipment sets unreadable",
    "unreadable equipment sets: ineligible")
WoW.bags[0].items[1] = { id = 1, count = WoW.Secret("count") }
local s, w = B.Slot(0, 1)
eq(s, nil, "a secret stack count: no facts")
eq(w, "unreadable", "  and it says unreadable, not empty")
WoW.bags[0].items[1] = nil
s, w = B.Slot(0, 1)
eq(w, "empty", "a slot the client says is empty: empty")
local realInfo = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function() error("boom") end
eq(select(2, B.Slot(0, 1)), "unreadable", "an error reading the slot: unreadable, not empty")
C_Container.GetContainerItemInfo = realInfo
WoW.bags[0].items[1] = { id = 1 }

-- Order: cheapest first by price x count; greys first when asked.
items({ [40] = { name = "Cheap White", price = 1, quality = 1, maxStack = 20 },
        [41] = { name = "Dear Grey", price = 50, quality = 0, maxStack = 1 },
        [42] = { name = "Grey Stack", price = 2, quality = 0, maxStack = 20 } })
WoW.bags[0].items = { [1] = { id = 41 }, [2] = { id = 40, count = 3 }, [3] = { id = 42, count = 10 }, [4] = { id = 3 } }
local function order(o)
    local ids = {}
    for _, c in ipairs(B.Candidates(o)) do ids[#ids + 1] = c.id .. "=" .. c.value end
    return table.concat(ids, ",")
end
eq(order({ scope = "white", greysFirst = false, tools = {} }), "40=3,42=20,41=50", "white scope: cheapest first (value = price x count)")
eq(order({ scope = "white", greysFirst = true, tools = {} }), "42=20,41=50,40=3", "greys first: every grey before any white")
eq(order({ scope = "grey", tools = {} }), "42=20,41=50", "grey scope: greys only")
local first = B.Candidates({ scope = "grey", tools = {} })[1]
check(first.bag == 0 and first.slot == 3 and first.count == 10 and first.link:find("Grey Stack", 1, true),
    "a candidate carries its bag, slot, count and link")
eq(B.FreeGeneral(), 0, "FreeGeneral: none in a full backpack")
WoW.bags[1] = { size = 3, items = {} }
eq(B.FreeGeneral(), 3, "  three in an empty bag")

-- Take (faster loot, #36): Fits, and the room it found is reserved.
WoW.resetBags()
items({ [2] = { name = "Linen Cloth", maxStack = 20 }, [3] = { name = "Green Ring", maxStack = 1 },
        [4] = { name = "Peacebloom", maxStack = 20, family = 32 } })
WoW.bags[0] = { size = 2, items = { [1] = { id = 2, count = 15 } } }    -- one free slot
snap = B.Snapshot()
eq(B.Take(2, 5, snap), true, "5 cloth onto the partial stack")
eq(snap.general, 1, "  no slot used")
eq(B.Take(2, 1, snap), true, "1 more: the stack is full, a slot is used")
eq(snap.general, 0, "  the free slot reserved")
eq(B.Take(3, 1, snap), false, "a ring after that: no room left")
eq(B.Take(2, 19, snap), true, "19 cloth onto the new stack of 1")
eq(B.Take(2, 1, snap), false, "  and then it's full")
-- Two rows that each fit alone, but not together.
snap = B.Snapshot()
eq(B.Take(3, 1, snap), true, "one ring into the one free slot")
eq(B.Take(3, 1, snap), false, "  a second ring: the slot is taken")
-- A quantity over several slots.
WoW.bags[1] = { size = 3, items = {} }
snap = B.Snapshot()
eq(B.Take(2, 45, snap), true, "45 cloth: 5 on the stack, then two slots")
eq(snap.general, 2, "  two of the four free slots used")
-- False or nil leaves the snapshot as it was.
snap = B.Snapshot()
local before = snap.general
eq(B.Take(2, 500, snap), false, "too much: false")
eq(snap.general, before, "  nothing reserved")
eq(B.Take(999, 1, snap), nil, "an uncached item: nil")
eq(snap.general, before, "  nothing reserved")
-- A matching specialty bag first: a herb and a ring with one general and one
-- herb slot both fit.
WoW.resetBags()
items({ [3] = { name = "Green Ring", maxStack = 1 }, [4] = { name = "Peacebloom", maxStack = 20, family = 32 } })
WoW.bags[0] = { size = 1, items = {} }
WoW.bags[1] = { size = 1, family = 32, items = {} }
snap = B.Snapshot()
eq(B.Take(4, 1, snap), true, "a herb: into the herb bag")
eq(B.Take(3, 1, snap), true, "  so a ring still fits the general slot")

-- The strict snapshot: uncertain room is no room; the plain one is unchanged.
WoW.resetBags()
items({ [2] = { name = "Linen Cloth", maxStack = 20 } })
WoW.bags[0] = { size = 2, items = { [1] = { id = 2, count = 15 } } }
WoW.bags[1] = { size = 3, familySecret = true, items = {} }
eq(B.Snapshot().general, 4, "plain: a bag whose family can't be read counts as general")
eq(B.Snapshot(true).general, 1, "strict: it offers no room")
WoW.bags[0].items[1].lockSecret = true
eq(#(B.Snapshot().stacks[2] or {}), 1, "plain: a stack whose lock can't be read is room")
eq(#(B.Snapshot(true).stacks[2] or {}), 0, "strict: it isn't")
WoW.bags[0].items[1].lockSecret = nil
eq(#(B.Snapshot(true).stacks[2] or {}), 1, "strict: a stack plainly unlocked is room")
eq(B.Slot(0, 1).lockKnown, true, "Slot: lockKnown when the lock reads plainly")

done("test_bags")
