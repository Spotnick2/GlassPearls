-- Core/EquipSets.lua: which equipment sets hold one item (#142), for any pearl
-- (the equipment set guard, easy delete).
--
-- By the item's GUID, so a second copy outside the set is never named:
-- C_Item.GetItemLocation(guid), then
-- - a bag slot: the client's own C_Container.GetContainerItemEquipmentSetInfo
--   (inSet, setList: the names, shown as the client gives them);
-- - an equipment slot: each set's C_EquipmentSet.GetItemLocations, decoded as
--   Blizzard's EquipmentManager_GetLocationData does (Shared/
--   EquipmentManager.lua: the ITEM_INVENTORY_LOCATION_* bits of
--   Constants.lua:129), a player location without the bag or bank bits naming
--   this slot; the set's name from GetEquipmentSetInfo.
-- The answer: a string of names, false (plainly in no set), or nil (unknown:
-- any throw, secret or odd value, another kind of location). No item-ID
-- fallback: a list of set item IDs can't prove a copy is outside every set.
-- Unmeasured.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local ES = {}
GP.EquipSets = ES

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

-- One call's values, or nothing when it threw.
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, table.maxn(r))
end

local function method(obj, name)
    local fn = plain(obj, "table") and obj[name]
    if API.IsSecret(fn) or type(fn) ~= "function" then return nil end
    return function(...) return call(fn, obj, ...) end
end

-- A method's boolean answer: true, false, or nil.
local function ask(fn)
    if not fn then return nil end
    return plain((fn()), "boolean")
end

-- A packed set location: the equipment slot it names; false for a location
-- that plainly isn't worn gear (a bag, the bank, the special values: -1
-- missing, 0 empty, 1 ignored); nil when it can't be read (a secret, not a
-- whole number, the constants or bit library unreadable).
function ES.Decode(v)
    local P = plain(rawget(_G, "ITEM_INVENTORY_LOCATION_PLAYER"), "number")
    local B = plain(rawget(_G, "ITEM_INVENTORY_LOCATION_BAGS"), "number")
    local K = plain(rawget(_G, "ITEM_INVENTORY_LOCATION_BANK"), "number")
    v = plain(v, "number")
    if not (P and B and K and v) or v % 1 ~= 0 or not (bit and bit.band) then return nil end
    if v < P then return false end
    if bit.band(v, P) == 0 or bit.band(v, B) ~= 0 or bit.band(v, K) ~= 0 then return false end
    local slot = v - P
    if slot < 1 then return false end
    return slot
end

local function inBag(bag, slot)
    local fn = C_Container and C_Container.GetContainerItemEquipmentSetInfo
    local r = { pcall(fn, bag, slot) }
    if not r[1] then return nil end
    local inSet, list = r[2], r[3]
    if API.IsSecret(inSet) or API.IsSecret(list) then return nil end
    if inSet == false then return false end
    if inSet ~= true or type(list) ~= "string" or list == "" then return nil end
    return (list:gsub("|", "||"))
end

-- The sets holding what's worn in this equipment slot: names, false or nil.
function ES.ForWornSlot(equipSlot)
    local CE = C_EquipmentSet
    if not (CE and CE.GetEquipmentSetIDs) then return nil end
    local ids = call(CE.GetEquipmentSetIDs)
    if not plain(ids, "table") then return nil end
    local names = {}
    for _, setID in ipairs(ids) do
        setID = plain(setID, "number")
        if not setID then return nil end
        local locs = call(CE.GetItemLocations, setID)
        if not plain(locs, "table") then return nil end
        -- A match names the set at once; an unreadable value before one makes
        -- the whole answer unknown, so "in none" (false) is only ever said
        -- after every value of every set was read.
        for _, v in pairs(locs) do
            local slot = ES.Decode(v)
            if slot == nil then return nil end
            if slot == equipSlot then
                local name = plain((call(CE.GetEquipmentSetInfo, setID)), "string")
                if not name or name == "" then return nil end
                names[#names + 1] = (name:gsub("|", "||"))
                break
            end
        end
    end
    if #names == 0 then return false end
    return table.concat(names, ", ")
end

-- The sets holding the item at this ItemLocation: names, false or nil.
function ES.ForLocation(loc)
    if not plain(loc, "table") then return nil end
    local isBag, getBag = method(loc, "IsBagAndSlot"), method(loc, "GetBagAndSlot")
    local isEquip, getEquip = method(loc, "IsEquipmentSlot"), method(loc, "GetEquipmentSlot")
    if ask(isBag) == true and getBag then
        local bag, slot = getBag()
        bag, slot = plain(bag, "number"), plain(slot, "number")
        if not (bag and slot) then return nil end
        return inBag(bag, slot)
    end
    if ask(isEquip) == true and getEquip then
        local slot = plain((getEquip()), "number")
        if not slot then return nil end
        return ES.ForWornSlot(slot)
    end
    return nil
end

-- The sets holding the item with this GUID, wherever it is now.
function ES.ForGUID(guid)
    guid = plain(guid, "string")
    if not guid or guid == "" or not (C_Item and C_Item.GetItemLocation) then return nil end
    return ES.ForLocation((call(C_Item.GetItemLocation, guid)))
end
