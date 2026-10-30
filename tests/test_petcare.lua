-- Hunter pet care (#38): the feeding reminder (threshold, once per drop,
-- dismissed, hidden by combat, re-armed), the food choice, the event
-- payloads, the pet checks at a fight start and a ready check, and the
-- out-of-combat "away" check. The window, the Feed button, the tooltip line
-- and the bag marks are test_petcare_frame.lua; another class,
-- test_petcare_mage.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local QUAIL, MEAT, BREAD, FISH, OLD = 8952, 3770, 4540, 4593, 117
local GP = loadAddon({ before = function()
    WoW.class = "HUNTER"
    WoW.known[883] = true
    WoW.pet = { happiness = 3, level = 60, guid = "Pet-1" }
    WoW.items[QUAIL] = { name = "Roasted Quail", price = 200, level = 55, quality = 1 }
    WoW.items[MEAT] = { name = "Spiced Wolf Meat", price = 6, level = 10, quality = 1 }
    WoW.items[BREAD] = { name = "Tough Hunk of Bread", price = 1, level = 5, quality = 1 }
    WoW.items[FISH] = { name = "Bristle Whisker Catfish", price = 4, level = 52, quality = 1 }
    WoW.edible[QUAIL], WoW.edible[MEAT], WoW.edible[FISH] = true, true, true
    WoW.edible[BREAD] = false
    WoW.bags[0] = { size = 16, items = { [1] = { id = QUAIL, count = 5 }, [2] = { id = BREAD, count = 20 } } }
end })
local PC, P, SS, N, API = GP.PetCare, GP.Pearls, GP.SettingsSync, GP.Notice, GP.API
local FR = GP.PetCareFrame
WoW.now = WoW.now or 0

local function lines() return newChat() end
local function said(text)
    for _, l in ipairs(lines()) do if l:find(text, 1, true) then return true end end
    return false
end
local function happy(h)
    WoW.pet.happiness = h
    WoW.fire("UNIT_HAPPINESS", "pet")
end
local function fight()
    WoW.fire("PLAYER_REGEN_DISABLED")   -- before lockdown, as on the client
    WoW.combat = true
end
local function peace()
    WoW.combat = false
    WoW.fire("PLAYER_REGEN_ENABLED")
end
local function bags(items) WoW.bags[0] = { size = 16, items = items } end

check(PC.state.hunter, "a hunter")
check(PC._test.events:IsEventRegistered("UNIT_HAPPINESS"), "  its events registered")
eq(#lines(), 0, "a happy pet at login: nothing said")
check(not FR.IsShown(), "  no window")

-- Settings and the sync budget's view of them.
eq(P.Setting("petcare", "food"), "tooltip", "food: tooltip by default")
eq(P.Setting("petcare", "feedAt"), "content", "feedAt: content by default")
eq(P.Setting("petcare", "away"), false, "away: off by default")
for _, k in ipairs({ "feed", "missing", "passive", "atFight", "atReady" }) do
    eq(P.Setting("petcare", k), true, k .. ": on by default")
end

--------------------------------------------------------------------------------
-- The feeding reminder

happy(2)
local l = lines()
eq(#l, 1, "Content: one line")
check(l[1] and l[1]:find("Your pet is Content: feed it (Roasted Quail, 5 in your bags).", 1, true), "  the line")
check(FR.IsShown(), "  the window")
eq(FR.Choice() and FR.Choice().id, QUAIL, "  offering the quail")
happy(2)
WoW.fire("BAG_UPDATE_DELAYED")
eq(#lines(), 0, "announced once per drop")
check(FR.IsShown(), "  the window stays")

PC.Dismiss()
check(not FR.IsShown(), "dismissed: closed")
WoW.fire("BAG_UPDATE_DELAYED")
happy(1)
check(not FR.IsShown(), "  a bag update or a further drop doesn't reopen it")
eq(#lines(), 0, "  and says nothing")
happy(3)
check(not PC.state.dismissed and not PC.state.announced, "happy again: re-armed")
happy(2)
check(said("Your pet is Content"), "  the next drop is said again")
check(FR.IsShown(), "  and offered")

-- The threshold.
P.SetSetting("petcare", "feedAt", "unhappy")
check(not FR.IsShown(), "only Unhappy: Content closes it")
happy(2)
check(not FR.IsShown() and #lines() == 0, "  Content: nothing")
happy(1)
check(said("Your pet is Unhappy: feed it"), "  Unhappy: said")
check(FR.IsShown(), "  offered")
P.SetSetting("petcare", "feedAt", "content")
happy(3)

-- Unknown, secret or odd happiness, or not a hunter pet: nothing.
for _, h in ipairs({ 0, 4, 1.5 }) do
    happy(h)
    check(not FR.IsShown() and #lines() == 0, "happiness " .. h .. ": nothing")
end
WoW.pet.happiness = WoW.Secret("happiness")
WoW.fire("UNIT_HAPPINESS", "pet")
check(not FR.IsShown() and #lines() == 0, "secret happiness: nothing")
WoW.pet.hunter = false
happy(1)
check(not FR.IsShown() and #lines() == 0, "not a hunter pet: nothing")
WoW.pet.hunter = WoW.Secret("hunter")
happy(1)
check(not FR.IsShown() and #lines() == 0, "a secret hunter-pet answer: nothing")
WoW.pet.hunter = nil
happy(3)

-- A drop during a fight: nothing until it ends.
fight()
happy(2)
eq(#lines(), 0, "a drop in combat: nothing said")
peace()
check(said("Your pet is Content"), "  said after the fight")
happy(3)

-- In combat: held, hidden, offered again after.
happy(2)
lines()
check(FR.IsShown(), "hungry before the fight")
fight()
check(not FR.IsShown(), "hidden as the fight starts")
check(not PC.state.dismissed, "  not dismissed")
happy(1)
WoW.fire("BAG_UPDATE_DELAYED")
check(not FR.IsShown(), "  nothing in combat")
peace()
check(FR.IsShown(), "offered again after the fight")
eq(#lines(), 0, "  without a second line")
happy(3)
check(not FR.IsShown(), "happy: closed")

-- Switched off (the feed setting).
P.SetSetting("petcare", "feed", false)
happy(1)
check(not FR.IsShown() and #lines() == 0, "feed off: nothing")
P.SetSetting("petcare", "feed", true)
check(FR.IsShown(), "feed back on: offered")
lines()
happy(3)

-- Event payloads.
WoW.pet.happiness = 2
WoW.fire("UNIT_HAPPINESS", "player")
WoW.fire("UNIT_HAPPINESS", WoW.Secret("unit"))
WoW.fire("UNIT_PET", "pet")
WoW.fire("UNIT_PET", WoW.Secret("unit"))
check(not FR.IsShown() and #lines() == 0, "UNIT_HAPPINESS for another unit, UNIT_PET for the pet, secrets: ignored")
WoW.fire("UNIT_PET", "player")
check(FR.IsShown() and said("Your pet is Content"), "UNIT_PET for the player: checked")
happy(3)

-- The pet goes: the window closes.
happy(2)
lines()
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
check(not FR.IsShown(), "the pet dismissed: closed")
WoW.pet = { happiness = 3, level = 60, guid = "Pet-1" }
WoW.fire("UNIT_PET", "player")

-- A new pet re-arms.
happy(2)
PC.Dismiss()
lines()
WoW.pet = { happiness = 2, level = 60, guid = "Pet-2" }
WoW.fire("UNIT_PET", "player")
check(FR.IsShown() and said("Your pet is Content"), "a new pet: offered again")
WoW.pet.happiness = 3
WoW.fire("UNIT_HAPPINESS", "pet")

--------------------------------------------------------------------------------
-- The food choice

local pet60 = { level = 60 }
bags({ [1] = { id = QUAIL, count = 5 }, [2] = { id = FISH, count = 3 }, [3] = { id = MEAT, count = 9 },
    [4] = { id = BREAD, count = 20 } })
local list, out = PC.Candidates(pet60)
eq(#list, 3, "three edible stacks (the bread isn't)")
eq(list[1].id, FISH, "within 10 levels, the cheapest first: the catfish (4) before the quail (200)")
eq(list[2].id, QUAIL, "  then the quail")
eq(list[3].id, MEAT, "  then the meat, outside the band")
eq(out.never + out.uncached + out.locked, 0, "  nothing left out")
bags({ [1] = { id = MEAT, count = 9 }, [2] = { id = QUAIL, count = 5 } })
list = PC.Candidates(pet60)
eq(list[1].id, QUAIL, "within the band first, even after a cheaper one outside it")
bags({ [1] = { id = QUAIL, count = 5 }, [2] = { id = FISH, count = 3 }, [3] = { id = MEAT, count = 9 } })
list = PC.Candidates({ level = 70 })
eq(list[1].id, QUAIL, "a pet at 70: nothing within the band, the highest level first")
eq(list[2].id, FISH, "  then the catfish")
list = PC.Candidates({})
eq(list[1].id, QUAIL, "a pet level unknown: the highest level first")

-- Ties by bag and slot.
WoW.bags[1] = { size = 4, items = { [1] = { id = FISH, count = 1 } } }
bags({ [7] = { id = FISH, count = 1 }, [3] = { id = FISH, count = 2 } })
list = PC.Candidates(pet60)
check(list[1].bag == 0 and list[1].slot == 3 and list[2].slot == 7 and list[3].bag == 1, "ties: bag, then slot")
eq(list[1].count, 4, "  the count is the item's total in the bags")
WoW.bags[1] = nil

-- The never list.
bags({ [1] = { id = QUAIL, count = 5 }, [2] = { id = FISH, count = 3 } })
SS.SetAdd(PC.NEVER, FISH)
local c
c, out = PC.ChooseFood(pet60)
eq(c and c.id, QUAIL, "the never list leaves the catfish out")
eq(out.never, 1, "  and counts it as left out")
SS.SetRemove(PC.NEVER, FISH)

-- A secret or throwing edibility answer: not edible.
WoW.edible[FISH] = WoW.Secret("edible")
c = PC.ChooseFood(pet60)
eq(c and c.id, QUAIL, "a secret CanPetEatItem: left out")
WoW.edible[FISH] = true

-- A locked stack is skipped.
bags({ [1] = { id = FISH, count = 3, locked = true }, [2] = { id = QUAIL, count = 5 } })
c, out = PC.ChooseFood(pet60)
eq(c and c.id, QUAIL, "a locked stack: skipped")
eq(out.locked, 1, "  counted as busy")

bags({ [1] = { id = QUAIL, count = 5, locked = true }, [2] = { id = QUAIL, count = 2 } })
c, out = PC.ChooseFood(pet60)
eq(c and c.slot, 2, "a locked stack and a free one: the free one")
eq(out.locked, 0, "  not counted as busy")
-- A cached food whose level isn't plain: left out, as not loaded.
WoW.items[FISH].level = WoW.Secret("level")
bags({ [1] = { id = FISH, count = 3 } })
c, out = PC.ChooseFood(pet60)
check(c == nil and out.uncached == 1, "a secret item level: left out")
WoW.items[FISH].level = 52

-- The empty-state wording.
bags({ [1] = { id = FISH, count = 3 } })
SS.SetAdd(PC.NEVER, FISH)
WoW.pet.happiness = 2
WoW.fire("UNIT_HAPPINESS", "pet")
local l2 = lines()
check(l2[1] and l2[1]:find("(no eligible food in your bags: 1 left out by your never-feed list).", 1, true),
    "only never-listed food: says it was left out, not that there's nothing")
check(FR.IsShown() and FR.Choice() == nil, "  the window, with nothing to feed")
SS.SetRemove(PC.NEVER, FISH)
happy(3)
bags({ [1] = { id = BREAD, count = 3 } })
happy(2)
check(said("(no food it eats in your bags)."), "nothing edible: says so")
happy(3)

-- The cache: an uncached edible item is asked for, then chosen when it arrives.
local NEW = 21023
WoW.edible[NEW] = true
bags({ [1] = { id = NEW, count = 2 } })
WoW.calls = {}
happy(2)
check(said("1 not loaded yet"), "an uncached food: not loaded yet")
eq(WoW.calledCount("RequestLoadItemDataByID"), 1, "  asked for once")
WoW.fire("BAG_UPDATE_DELAYED")
eq(WoW.calledCount("RequestLoadItemDataByID"), 1, "  not asked again")
WoW.items[NEW] = { name = "Dirge's Kickin' Chimaerok Chops", price = 1000, level = 55, quality = 1 }
WoW.fire("GET_ITEM_INFO_RECEIVED", 99999, true)
check(FR.Choice() == nil, "another item's arrival: nothing")
WoW.fire("GET_ITEM_INFO_RECEIVED", NEW, true)
eq(FR.Choice() and FR.Choice().id, NEW, "  its arrival: chosen")
happy(3)
bags({ [1] = { id = QUAIL, count = 5 } })

--------------------------------------------------------------------------------
-- The pet checks: at the start of a fight and at a ready check

local function warned(text)
    local got = lines()
    return #got == 1 and got[1]:find(text, 1, true) ~= nil and N.Text() == text:gsub("%.$", "")
end

WoW.pet = nil
fight()
check(warned("You have no pet out."), "a fight starts with no pet: said once, and the centre text")
peace()
WoW.pet = { happiness = 3, level = 60, guid = "Pet-2", dead = true }
fight()
check(warned("Your pet is dead."), "a dead pet")
peace()
WoW.petBar[4] = { name = "Passive", texture = "PET_PASSIVE_TEXTURE", isToken = true, isActive = true }
fight()
check(warned("Your pet is dead."), "dead and on Passive: dead, not Passive")
peace()
WoW.pet.dead = false
fight()
check(warned("Your pet is on Passive."), "a live pet on Passive")
peace()
WoW.petBar[4].isActive = false
WoW.petBar[5] = { name = "Defensive", texture = "PET_DEFENSIVE_TEXTURE", isToken = true, isActive = true }
fight()
eq(#lines(), 0, "Defensive: nothing")
peace()
WoW.petBar[4].isActive = true
WoW.pet.hunter = false
fight()
eq(#lines(), 0, "Passive on a pet that isn't a hunter pet: nothing")
peace()
WoW.pet.hunter = nil

-- Each checkbox.
P.SetSetting("petcare", "passive", false)
fight()
eq(#lines(), 0, "passive off: nothing")
peace()
P.SetSetting("petcare", "passive", true)
WoW.pet = nil
P.SetSetting("petcare", "missing", false)
fight()
eq(#lines(), 0, "missing off: no pet says nothing")
peace()
P.SetSetting("petcare", "missing", true)
P.SetSetting("petcare", "atFight", false)
fight()
eq(#lines(), 0, "atFight off: nothing at a fight start")
peace()
P.SetSetting("petcare", "atFight", true)

-- The shared combat flag already set by another frame: still checked.
API.NoteCombat("PLAYER_REGEN_DISABLED")
fight()
check(warned("You have no pet out."), "the combat flag noted first: still checked")
peace()

-- No Call Pet, unreadable values: silence.
WoW.known[883] = nil
fight()
eq(#lines(), 0, "no Call Pet: nothing")
peace()
WoW.known[883] = true
WoW.petExistsSecret = true
fight()
eq(#lines(), 0, "a secret UnitExists: nothing")
peace()
WoW.petExistsSecret = nil
WoW.pet = { happiness = 3, level = 60, guid = "Pet-2", dead = WoW.Secret("dead") }
fight()
eq(#lines(), 0, "a secret UnitIsDead: nothing")
peace()
WoW.pet.dead = false
WoW.petBar[4].texture = WoW.Secret("texture")
fight()
eq(#lines(), 0, "a secret pet bar: nothing")
peace()
WoW.petBar[4].texture = "PET_PASSIVE_TEXTURE"
WoW.petBarThrows = true
eq(PC.Passive(), nil, "a pet bar that throws: unknown")
fight()
eq(#lines(), 0, "  nothing said")
peace()
WoW.petBarThrows = nil
WoW.petBar = {}

-- A ready check, out of combat and in combat.
WoW.pet = nil
WoW.fire("READY_CHECK", "Leader", 35)
check(warned("You have no pet out."), "a ready check with no pet")
fight()
lines()
WoW.fire("READY_CHECK", "Leader", 35)
check(warned("You have no pet out."), "a ready check in combat: still said")
WoW.petExistsSecret = true
WoW.fire("READY_CHECK", "Leader", 35)
eq(#lines(), 0, "  a secret read in combat: nothing")
WoW.petExistsSecret = nil
WoW.pet = { happiness = 1, level = 60, guid = "Pet-2" }
WoW.fire("READY_CHECK", "Leader", 35)
check(not FR.IsShown() and #lines() == 0, "  a hungry pet at a ready check in combat: no feeding work")
peace()
lines()
happy(3)
P.SetSetting("petcare", "atReady", false)
WoW.pet = nil
WoW.fire("READY_CHECK", "Leader", 35)
eq(#lines(), 0, "atReady off: nothing")
P.SetSetting("petcare", "atReady", true)

--------------------------------------------------------------------------------
-- Away: out of combat, when the pet disappears

WoW.timers = {}
WoW.fire("UNIT_PET", "player")
WoW.advance(10)
eq(#lines(), 0, "away off: nothing")
P.SetSetting("petcare", "away", true)
WoW.fire("UNIT_PET", "player")
WoW.advance(9.9)
eq(#lines(), 0, "away: nothing before 10 s")
WoW.advance(0.2)
check(warned("You have no pet out."), "  then said")
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
eq(#lines(), 0, "once per absence")
fight()
check(warned("You have no pet out."), "  the away latch doesn't silence a fight start")
peace()
WoW.fire("READY_CHECK", "Leader", 35)
check(warned("You have no pet out."), "  or a ready check")
WoW.pet = { happiness = 3, level = 60, guid = "Pet-3" }
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
eq(#lines(), 0, "a live pet: nothing, and re-armed")
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
WoW.advance(5)
WoW.fire("PLAYER_CONTROL_GAINED")
WoW.advance(5.1)
eq(#lines(), 0, "a newer trigger replaces the timer")
WoW.advance(5)
check(warned("You have no pet out."), "  and says it 10 s after the newer one")

-- A death through UNIT_FLAGS, without UNIT_PET.
WoW.pet = { happiness = 3, level = 60, guid = "Pet-3" }
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
WoW.pet.dead = true
WoW.fire("UNIT_FLAGS", "target")
WoW.advance(10.1)
eq(#lines(), 0, "UNIT_FLAGS for another unit: nothing")
WoW.fire("UNIT_FLAGS", "pet")
WoW.advance(10.1)
check(warned("Your pet is dead."), "UNIT_FLAGS for the pet: the death said")

-- Revived without UNIT_PET: the next death is a new absence.
WoW.pet.dead = false
WoW.fire("UNIT_FLAGS", "pet")
WoW.advance(10.1)
eq(#lines(), 0, "revived: nothing")
WoW.pet.dead = true
WoW.fire("UNIT_FLAGS", "pet")
WoW.advance(10.1)
check(warned("Your pet is dead."), "  dead again: said again")

-- A timer expiring in combat: said after it.
WoW.pet.dead = false
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
P.SetSetting("petcare", "atFight", false)
fight()
WoW.advance(10.1)
eq(#lines(), 0, "expired in combat: held")
peace()
check(warned("You have no pet out."), "  said after the fight")
P.SetSetting("petcare", "atFight", true)

-- Quiet times.
local function quietWith(label, set, unset)
    WoW.pet = { happiness = 3, level = 60, guid = "Pet-4" }
    WoW.fire("UNIT_PET", "player")
    WoW.advance(10.1)
    WoW.pet = nil
    set()
    WoW.fire("UNIT_PET", "player")
    WoW.advance(10.1)
    eq(#lines(), 0, label .. ": nothing")
    unset()
end
quietWith("on a taxi", function() WoW.onTaxi = true end, function() WoW.onTaxi = nil end)
quietWith("a secret taxi read", function() WoW.onTaxi = WoW.Secret("taxi") end, function() WoW.onTaxi = nil end)
quietWith("mounted", function() WoW.mounted = true end, function() WoW.mounted = nil end)
quietWith("feigning death", function() WoW.feign = true end, function() WoW.feign = nil end)
quietWith("without full control", function() WoW.fullControl = false end, function() WoW.fullControl = nil end)
quietWith("dead", function() WoW.dead = true end, function() WoW.dead = nil end)
quietWith("at the stable master", function() WoW.fire("PET_STABLE_SHOW") end,
    function() WoW.fire("PET_STABLE_CLOSED") end)
quietWith("without Call Pet", function() WoW.known[883] = nil end, function() WoW.known[883] = true end)
-- Possessed: the pet's there (dead here, so there's something to say).
WoW.pet = { happiness = 3, level = 60, guid = "Pet-4" }
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
WoW.pet.dead, WoW.pet.possessed = true, true
WoW.fire("UNIT_FLAGS", "pet")
WoW.advance(10.1)
eq(#lines(), 0, "possessed: nothing")
WoW.pet.possessed = false
WoW.fire("UNIT_FLAGS", "pet")
WoW.advance(10.1)
check(warned("Your pet is dead."), "  not possessed: said")

-- Missing off: away says nothing.
WoW.pet = { happiness = 3, level = 60, guid = "Pet-5" }
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
P.SetSetting("petcare", "missing", false)
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
eq(#lines(), 0, "missing off: away says nothing")
P.SetSetting("petcare", "missing", true)

-- Stale after leaving the world and after switching off (a live pet first,
-- so the latch is open).
WoW.pet = { happiness = 3, level = 60, guid = "Pet-5" }
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
WoW.fire("PLAYER_LEAVING_WORLD")
WoW.advance(10.1)
eq(#lines(), 0, "left the world: the timer is stale")
WoW.pet = { happiness = 3, level = 60, guid = "Pet-5" }
WoW.fire("UNIT_PET", "player")
WoW.advance(10.1)
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
P.Set("petcare", false)
check(not PC._test.events:IsEventRegistered("UNIT_PET"), "switched off: its events unregistered")
P.Set("petcare", true)
WoW.advance(10.1)
eq(#lines(), 0, "  the timer from before is stale, even back on")
lines()
P.SetSetting("petcare", "away", false)

--------------------------------------------------------------------------------
-- Commands

WoW.pet = { happiness = 2, level = 60, guid = "Pet-6" }
bags({ [1] = { id = QUAIL, count = 5 } })
WoW.fire("UNIT_PET", "player")
lines()
P.Command("petcare").run("")
check(said("Hunter pet care: on. Pet: out yes, dead no, hunter pet yes, happiness 2 Content, level 60."),
    "/gpearls petcare: the pet")
P.Command("petcare").run("never")
check(SS.SetHas(PC.NEVER, QUAIL), "never (no item): the food on offer")
check(said("Roasted Quail will never be chosen"), "  said")
P.Command("petcare").run("forget " .. WoW.itemLink(QUAIL))
check(not SS.SetHas(PC.NEVER, QUAIL), "forget <item>: off the list")
P.Command("petcare").run("never 3770")
check(SS.SetHas(PC.NEVER, MEAT), "never <id>")
SS.SetRemove(PC.NEVER, MEAT)
P.Command("petcare").run("forget")
check(said("Shift-click a food"), "forget without an item: how to")

done("test_petcare")
