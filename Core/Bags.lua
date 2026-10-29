-- Core/Bags.lua: what's in the bags, what fits, and what could go (#6).
-- Reusable by any pearl; the bags-full helper is the first.
--
-- Room follows GlassMail's measured rules (GlassMail/Core/Loot.lua, its
-- FOREVER-PROBE sessions): a partial stack of the item is room; a specialty
-- bag of a matching family takes its items, even when the general bags are
-- full; bags 0-4 only. Fits answers true, false, or nil when it can't be told
-- (the item's facts aren't cached): nil never prompts anyone.
--
-- What may be offered to destroy is decided on full, known data only:
-- anything unknown (uncached item info, unread quest info, a secret value)
-- makes the stack ineligible, never "probably fine".

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Bags = {}
GP.Bags = Bags

Bags.FIRST, Bags.LAST = 0, 4   -- the backpack and the four bag slots

-- Item classes never offered (ItemConstantsDocumentation.lua:269). Consumable
-- only when it isn't grey (a grey consumable is junk).
Bags.NEVER_CLASSES = { [1] = "a container", [5] = "a reagent", [6] = "ammunition", [9] = "a recipe",
                       [11] = "a quiver", [12] = "a quest item", [13] = "a key" }
Bags.CONSUMABLE = 0
Bags.WEAPON, Bags.FISHING_POLE = 2, 20   -- ItemWeaponSubclass.Fishingpole
Bags.MAX_QUALITY = { grey = 0, white = 1 }   -- green and better are never offered

local function plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

-- The facts of one bag slot, or nil and why: "empty" only when the client
-- says the slot holds nothing (GetContainerItemInfo returns nil), else
-- "unreadable" (an error, a secret, a field missing). The difference matters:
-- only a confirmed empty slot proves a delete happened (Codex review of #9).
function Bags.Slot(bag, slot)
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok then return nil, "unreadable" end
    if info == nil then return nil, "empty" end
    if type(info) ~= "table" then return nil, "unreadable" end
    local id, count, link = plain(info.itemID), plain(info.stackCount), plain(info.hyperlink)
    if type(id) ~= "number" or type(count) ~= "number" or type(link) ~= "string" then return nil, "unreadable" end
    return {
        bag = bag, slot = slot, id = id, count = count, link = link,
        quality = plain(info.quality), locked = plain(info.isLocked) == true,
        lockKnown = type(plain(info.isLocked)) == "boolean",
        noValue = plain(info.hasNoValue) == true, icon = plain(info.iconFileID),
        name = plain(info.itemName),
    }
end

-- Free slots of a bag and its family (0 = general), both plain numbers, and
-- whether the family could be read (an unreadable one counts as 0 here).
local function freeSlots(bag)
    local ok, free, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
    if not ok then return 0, 0, false end
    free, family = plain(free), plain(family)
    return type(free) == "number" and free or 0, type(family) == "number" and family or 0, type(family) == "number"
end

local function numSlots(bag)
    local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
    n = ok and plain(n)
    return type(n) == "number" and n or 0
end

-- { general = free general slots, specialty = { { free, family }, ... },
--   stacks = { [itemID] = { count, ... } } } over the unlocked stacks.
-- `strict` (an automatic action relies on it): uncertain room is no room. A
-- bag whose family can't be read offers no free slots (else: general), a
-- stack whose lock can't be read no room (else: unlocked).
function Bags.Snapshot(strict)
    local snap = { general = 0, specialty = {}, stacks = {} }
    for bag = Bags.FIRST, Bags.LAST do
        local free, family, known = freeSlots(bag)
        if strict and not known then free = 0 end
        if family == 0 then snap.general = snap.general + free
        elseif free > 0 then snap.specialty[#snap.specialty + 1] = { free = free, family = family } end
        for slot = 1, numSlots(bag) do
            local s = Bags.Slot(bag, slot)
            -- A locked stack (on the cursor, mid-move) offers no room.
            if s and not s.locked and (s.lockKnown or not strict) then
                local list = snap.stacks[s.id] or {}
                list[#list + 1] = s.count
                snap.stacks[s.id] = list
            end
        end
    end
    return snap
end

-- Would `qty` of `itemID` fit? true, false, or nil when it can't be told.
function Bags.Fits(itemID, qty, snap)
    if type(itemID) ~= "number" then return nil end
    qty = qty or 1
    if qty <= 0 then return true end
    local okS, maxStack = pcall(C_Item.GetItemMaxStackSizeByID, itemID)
    maxStack = okS and plain(maxStack)
    if type(maxStack) ~= "number" or maxStack < 1 then return nil end
    local room = 0
    for _, count in ipairs(snap.stacks[itemID] or {}) do
        if count < maxStack then room = room + (maxStack - count) end
    end
    if room >= qty then return true end
    local slots = snap.general
    if #snap.specialty > 0 then
        local okF, family = pcall(C_Item.GetItemFamily, itemID)
        family = okF and plain(family)
        if type(family) ~= "number" then return nil end
        for _, b in ipairs(snap.specialty) do
            if family ~= 0 and bit.band(family, b.family) ~= 0 then slots = slots + b.free end
        end
    end
    return room + slots * maxStack >= qty
end

-- Like Fits, and when it fits, the room is reserved in `snap` (so the next
-- row sees what's left): this item's partial stacks first, then free slots,
-- a matching specialty bag first (GlassMail's measured rule, Core\Loot.lua:4),
-- then general. False or nil leaves `snap` as it was. Bookkeeping to avoid
-- predictable failures, not a model of the client's placement.
function Bags.Take(itemID, qty, snap)
    local fits = Bags.Fits(itemID, qty, snap)
    if fits ~= true then return fits end
    qty = qty or 1
    local maxStack = plain(C_Item.GetItemMaxStackSizeByID(itemID))
    local stacks = snap.stacks[itemID] or {}
    snap.stacks[itemID] = stacks
    local rest = qty
    for i, count in ipairs(stacks) do
        if rest <= 0 then break end
        local room = maxStack - count
        if room > 0 then
            local put = math.min(room, rest)
            stacks[i] = count + put
            rest = rest - put
        end
    end
    local family = 0
    if rest > 0 and #snap.specialty > 0 then
        local okF, f = pcall(C_Item.GetItemFamily, itemID)
        family = okF and plain(f) or 0
    end
    while rest > 0 do
        local put = math.min(maxStack, rest)
        local bagged = false
        if type(family) == "number" and family ~= 0 then
            for _, b in ipairs(snap.specialty) do
                if b.free > 0 and bit.band(family, b.family) ~= 0 then
                    b.free = b.free - 1
                    bagged = true
                    break
                end
            end
        end
        if not bagged then snap.general = snap.general - 1 end
        stacks[#stacks + 1] = put
        rest = rest - put
    end
    return true
end

-- Free general slots, for "has room appeared?".
function Bags.FreeGeneral()
    local n = 0
    for bag = Bags.FIRST, Bags.LAST do
        local free, family = freeSlots(bag)
        if family == 0 then n = n + free end
    end
    return n
end

-- Item IDs in any equipment set, or nil when they can't be read.
function Bags.SetItems()
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return {} end
    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return nil end
    local out = {}
    for _, setID in ipairs(ids) do
        local ok2, items = pcall(C_EquipmentSet.GetItemIDs, setID)
        if not ok2 or type(items) ~= "table" then return nil end
        for _, id in pairs(items) do
            if type(id) == "number" and not API.IsSecret(id) then out[id] = true end
        end
    end
    return out
end

-- An item's sell price, quality, class and subclass from the cache, or nil
-- on a miss (GetItemInfo returns nothing then: porting guide).
function Bags.ItemFacts(itemID)
    local ok, name, _, quality, _, _, _, _, _, _, _, price, classID, subclassID = pcall(C_Item.GetItemInfo, itemID)
    if not ok or name == nil then return nil end
    price, quality, classID, subclassID = plain(price), plain(quality), plain(classID), plain(subclassID)
    if type(price) ~= "number" or type(quality) ~= "number" or type(classID) ~= "number" then return nil end
    return { price = price, quality = quality, classID = classID, subclassID = subclassID }
end

-- Does the item have a use spell? true, false, or nil when it can't be told.
local function hasUse(itemID)
    local ok, spellName, spellID = pcall(C_Item.GetItemSpell, itemID)
    if not ok then return nil end
    if API.IsSecret(spellName) or API.IsSecret(spellID) then return nil end
    return spellName ~= nil or spellID ~= nil
end
Bags.HasUse = hasUse

-- Is the stack in this slot a quest item (or starts one)? true, false, or nil
-- when it can't be told.
function Bags.IsQuestItem(bag, slot)
    local ok, q = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if not ok or type(q) ~= "table" then return nil end
    if API.IsSecret(q.isQuestItem) or API.IsSecret(q.questID) then return nil end
    return (q.isQuestItem or q.questID) and true or false
end

-- One stack as a destroy candidate, or nil and why not.
-- opts: scope ("grey" | "white"), keep(itemID) -> bool, tools ({ [id] = true }),
--       setItems ({ [id] = true } or nil when unreadable).
function Bags.Eligible(s, opts)
    if not s then return nil, "empty" end
    if s.locked then return nil, "locked" end
    if s.noValue then return nil, "no value" end
    local maxQ = Bags.MAX_QUALITY[opts.scope] or 0
    if type(s.quality) ~= "number" then return nil, "unknown quality" end
    if s.quality > maxQ then return nil, "quality" end
    if opts.keep and opts.keep(s.id) then return nil, "kept" end
    if opts.tools and opts.tools[s.id] then return nil, "a tool" end
    if opts.setItems == nil then return nil, "equipment sets unreadable" end
    if opts.setItems[s.id] then return nil, "in an equipment set" end
    local quest = Bags.IsQuestItem(s.bag, s.slot)
    if quest == nil then return nil, "unknown quest info" end
    if quest then return nil, "a quest item" end
    local f = Bags.ItemFacts(s.id)
    if not f then return nil, "not cached" end
    if f.price <= 0 then return nil, "no value" end
    if f.quality ~= s.quality then return nil, "quality changed" end
    local never = Bags.NEVER_CLASSES[f.classID]
    if never then return nil, never end
    if f.classID == Bags.WEAPON and f.subclassID == Bags.FISHING_POLE then return nil, "a fishing pole" end
    if s.quality > 0 then
        if f.classID == Bags.CONSUMABLE then return nil, "a consumable" end
        local use = hasUse(s.id)
        if use == nil then return nil, "unknown use" end
        if use then return nil, "it has a use" end
    end
    return {
        bag = s.bag, slot = s.slot, id = s.id, link = s.link, count = s.count, quality = s.quality,
        icon = s.icon, name = s.name, price = f.price, value = f.price * s.count,
    }
end

-- Every candidate in the general bags, cheapest first. opts as Eligible, and
-- greysFirst: any grey before any white. Ties: item ID, then bag and slot.
function Bags.Candidates(opts)
    local list = {}
    opts.setItems = opts.setItems == nil and Bags.SetItems() or opts.setItems
    for bag = Bags.FIRST, Bags.LAST do
        local _, family = freeSlots(bag)
        if family == 0 then
            for slot = 1, numSlots(bag) do
                local c = Bags.Eligible(Bags.Slot(bag, slot), opts)
                if c then list[#list + 1] = c end
            end
        end
    end
    table.sort(list, function(a, b)
        if opts.greysFirst and a.quality ~= b.quality then return a.quality < b.quality end
        if a.value ~= b.value then return a.value < b.value end
        if a.id ~= b.id then return a.id < b.id end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return list
end
