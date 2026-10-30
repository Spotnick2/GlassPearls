-- Instance gear reminders (#43): the case data, Evaluate (the instance, the
-- standing, the trinket slots, carried and banked counts, every unreadable
-- read silent), the timing (one check per entry, 5 s after a loading screen
-- with isReloadingUi plainly false, LEAVING closes it) and the texts.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local SCHOLO = { name = "Scholomance", type = "party", id = 289 }
local STRAT = { name = "Stratholme", type = "party", id = 329 }
local COMMISSION, SEAL, RUNE, MARK, MARK2 = 12846, 13209, 19812, 23206, 23207

-- Logged in inside Scholomance, the Commission in the bags: the harness's own
-- ADDON_LOADED -> PLAYER_LOGIN -> PLAYER_ENTERING_WORLD.
local GP = loadAddon({ before = function()
    WoW.instance = SCHOLO
    WoW.factions[529] = { name = "Argent Dawn", reaction = 6 }
    WoW.itemCounts[COMMISSION] = { bags = 1 }
    WoW.items[COMMISSION] = { name = "Argent Dawn Commission" }
end })
local IG, P, FR = GP.InstanceGear, GP.Pearls, GP.InstanceGearFrame
local CASE = IG.CASES[1]
WoW.now = WoW.now or 0
newChat()
WoW.advance(4.9)
eq(#newChat(), 0, "logged in inside Scholomance: nothing before 5 s")
WoW.advance(0.2)
local lines = newChat()
eq(#lines, 1, "  then said")
check(lines[1] and lines[1]:find("Equip your Argent Dawn Commission: Scourgestones drop only while it's on "
    .. "(you're below Exalted with the Argent Dawn).", 1, true), "  the chat line, with the client's names")
eq(FR.Text(), "Equip your Argent Dawn Commission", "  and the centre text")
check(FR.IsShown(), "  shown")

-- The data.
for _, case in ipairs(IG.CASES) do
    for _, list in ipairs({ case.instances, case.items, case.slots }) do
        for _, v in ipairs(list) do check(type(v) == "number", case.key .. ": numbers only") end
    end
    eq(P.Setting("instancegear", case.key), true, case.key .. ": its own switch, on by default")
end
eq(P.Setting("instancegear", "exalted"), false, "also at Exalted: off by default")

-- Evaluate.
local function reset()
    WoW.instance = SCHOLO
    WoW.factions[529] = { name = "Argent Dawn", reaction = 6 }
    WoW.itemCounts, WoW.itemCountThrows, WoW.equipped = {}, {}, {}
    WoW.itemCounts[COMMISSION] = { bags = 1 }
end
local function ev() return IG.Evaluate(CASE) end
local function kind() local r = ev(); return r and r.kind end
reset()
eq(kind(), "equip", "Scholomance, carried, not worn: equip")
WoW.instance = STRAT
eq(kind(), "equip", "Stratholme too")
WoW.instance = { name = "Eastern Kingdoms", type = "none", id = 0 }
eq(kind(), nil, "outdoors (the continent): nothing")
WoW.instance = { name = "Eastern Kingdoms", type = "none", id = 289 }
eq(kind(), nil, "type none, whatever the ID: nothing")
WoW.instance = { name = "Naxxramas", type = "raid", id = 533 }
eq(kind(), nil, "another instance: nothing")
WoW.instance = { name = WoW.Secret("n"), type = WoW.Secret("t"), id = 289 }
eq(kind(), nil, "a secret instance type: nothing")
WoW.instance = { name = "Scholomance", type = "party", id = WoW.Secret("id") }
eq(kind(), nil, "a secret map ID: nothing")
reset()
WoW.factions[529] = { name = "Argent Dawn", reaction = 8 }
eq(kind(), nil, "Exalted: nothing")
P.SetSetting("instancegear", "exalted", true)
local r = ev()
eq(r and r.kind, "equip", "Exalted with 'also at Exalted': equip")
local line = IG.Texts(CASE, r)
check(not line:find("below Exalted", 1, true), "  without the standing clause")
P.ResetSettings("instancegear")
WoW.factions[529] = { name = "Argent Dawn", reaction = 7 }
eq(kind(), "equip", "Revered: equip")
for label, bad in pairs({ ["0"] = 0, ["9"] = 9, ["6.5"] = 6.5, secret = WoW.Secret("reaction") }) do
    WoW.factions[529] = { name = "Argent Dawn", reaction = bad }
    eq(kind(), nil, "reaction " .. label .. ": nothing")
end
WoW.factions[529] = nil
eq(kind(), nil, "no faction data: nothing")
WoW.factions[529] = WoW.Secret("faction")
eq(kind(), nil, "secret faction data: nothing")
-- The slots.
for _, worn in ipairs({ COMMISSION, SEAL, RUNE, MARK, MARK2 }) do
    for _, slot in ipairs({ 13, 14 }) do
        reset()
        WoW.equipped[slot] = worn
        eq(kind(), nil, worn .. " in slot " .. slot .. ": satisfied")
    end
end
reset()
WoW.equipped[13] = 11815                         -- another trinket
eq(kind(), "equip", "another trinket worn: equip")
WoW.equipped[14] = WoW.Secret("slot")
eq(kind(), nil, "a secret slot: nothing")
reset()
local inv = GetInventoryItemID
GetInventoryItemID = function() error("no") end
eq(kind(), nil, "a throwing slot read: nothing")
GetInventoryItemID = inv
-- Counts: carried, banked, preference, unreadable.
reset()
WoW.itemCounts[COMMISSION] = nil
eq(kind(), nil, "none at all: nothing")
WoW.itemCounts[COMMISSION] = { bank = 1 }
r = ev()
eq(r and r.kind, "bank", "only in the bank: bank")
eq(r and r.item, COMMISSION, "  the Commission")
WoW.itemCounts[MARK] = { bags = 1 }
WoW.itemCounts[COMMISSION] = { bags = 1 }
eq(ev().item, MARK, "two carried: the first in preference order")
reset()
WoW.itemCounts[MARK] = { bank = 1 }
r = ev()
eq(r and r.kind, "equip", "a carried lower-preference item beats a banked higher one")
eq(r and r.item, COMMISSION, "  the carried one")
reset()
WoW.itemCounts[COMMISSION] = { bags = WoW.Secret("n") }
eq(kind(), nil, "a secret count: skipped, never zero")
WoW.itemCounts[COMMISSION] = { bags = 0, bank = WoW.Secret("b") }
eq(kind(), nil, "a secret bank count: skipped")
WoW.itemCounts[COMMISSION] = { bags = -1, bank = 3 }
eq(kind(), nil, "a negative count: skipped")
WoW.itemCounts[COMMISSION] = { bank = 1 }
WoW.itemCountThrows[COMMISSION] = true
eq(kind(), nil, "a throwing count: skipped")
reset()
WoW.itemCounts[RUNE] = { bags = WoW.Secret("n") }
WoW.itemCounts[COMMISSION] = { bags = 1 }
eq(ev().item, COMMISSION, "an unreadable one skipped, the next carried taken")
P.SetSetting("instancegear", "argentdawn", false)
eq(kind(), nil, "the case switched off: nothing")
P.ResetSettings("instancegear")

-- The texts.
reset()
r = ev()
local l, short = IG.Texts(CASE, r)
eq(short, "Equip your Argent Dawn Commission", "equip: the short text")
WoW.items[COMMISSION] = nil
l, short = IG.Texts(CASE, r)
eq(short, "Equip your Argent Dawn trinket", "  the name not cached: the fallback")
WoW.factions[529] = { name = WoW.Secret("name"), reaction = 6 }
l = IG.Texts(CASE, ev())
check(l:find("below Exalted with the Argent Dawn).", 1, true), "  the faction's name secret: the fallback")
WoW.factions[529] = { name = "", reaction = 6 }
l = IG.Texts(CASE, ev())
check(l:find("below Exalted with the Argent Dawn).", 1, true), "  the faction's name empty: the fallback")
WoW.items[COMMISSION] = { name = "Argent Dawn Commission" }
WoW.itemCounts[COMMISSION] = { bank = 1 }
l, short = IG.Texts(CASE, ev())
eq(short, "Your Argent Dawn Commission is in your bank", "bank: the short text")
eq(l, "Your Argent Dawn Commission is in your bank: Scourgestones drop only while it's equipped.", "  the line")

-- The timing.
local function enter(reloading)
    WoW.fire("PLAYER_LEAVING_WORLD")
    if reloading == nil then reloading = false end
    WoW.fire("PLAYER_ENTERING_WORLD", false, reloading)
end
local function said(dt) WoW.advance(dt or 5.1); return #newChat() end
reset()
newChat()
enter()
eq(said(), 1, "entering: said once, 5 s later")
eq(said(30), 0, "  and only once")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(said(), 0, "a duplicate PEW after the check: nothing more")
enter()
WoW.advance(2)
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(said(), 1, "a duplicate PEW before the check: one reminder")
enter(true)
eq(said(), 0, "a reload: nothing")
enter(WoW.Secret("reload"))
eq(said(), 0, "isReloadingUi secret: nothing")
enter("no")
eq(said(), 0, "isReloadingUi not a boolean: nothing")
WoW.fire("PLAYER_LEAVING_WORLD")
WoW.fire("PLAYER_ENTERING_WORLD", false)
eq(said(), 0, "isReloadingUi nil: nothing")
enter()
WoW.advance(2)
WoW.fire("PLAYER_LEAVING_WORLD")
eq(said(), 0, "left before 5 s: nothing")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(said(), 1, "  back to the same map: reminded again")
enter()
WoW.advance(2)
P.Set("instancegear", false)
eq(said(), 0, "switched off before 5 s: nothing")
check(not IG._test.events:IsEventRegistered("PLAYER_ENTERING_WORLD"), "  its events released")
enter()
WoW.advance(2)
P.Set("instancegear", false)
P.Set("instancegear", true)
eq(said(), 0, "switched off and on before 5 s: the old timer does nothing")
enter()
eq(said(), 1, "  the next entry works")
enter()
WoW.advance(2)
P.SetSetting("instancegear", "argentdawn", false)
eq(said(), 0, "the case switched off while pending: nothing")
P.ResetSettings("instancegear")
enter()
WoW.advance(2)
WoW.instance = { name = "Eastern Kingdoms", type = "none", id = 0 }
eq(said(), 0, "outdoors at the check: nothing")
reset()
enter()
WoW.advance(2)
WoW.equipped[13] = COMMISSION
eq(said(), 0, "equipped before the check: nothing")

-- The report.
reset()
newChat()
P.Command("instancegear").run("")
check(chatHas("Scholomance %(party, 289%)"), "/gpearls instancegear: the instance")
check(chatHas("standing 6 %(Argent Dawn%)") and chatHas("slot 13 empty"), "  the standing and the slots")
check(chatHas("12846: carried %+ worn 1, with bank 1, bank 0"), "  the counts, labelled truthfully")
check(chatHas("Now: Equip your Argent Dawn Commission"), "  what it would say")
WoW.equipped[13] = COMMISSION
newChat()
P.Command("instancegear").run("")
check(chatHas("12846: carried %+ worn 2, with bank 2") and chatHas("Now: nothing %(worn%)"),
    "  worn: counted as carried + worn, nothing to say")

done("test_instancegear")
