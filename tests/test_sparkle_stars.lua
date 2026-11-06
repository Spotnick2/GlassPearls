-- The quest sparkle's experimental stars (#79): the option (off / quest /
-- all); the plate binding (qualifies or not, secrets, a reused plate, a
-- removed one, a hidden one); the temp CVars (effective values decide,
-- refused for a stars session, displaced and repaired, combat, cleanup after
-- the switch, on again before cleanup, gamepad both ways); easy fishing's
-- temps with the real Fishing logic (both orders, its refused set, its reset,
-- a session end in combat, never removing its names); the reports; the panel.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local NAMES = { "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetIconGameObject" }
-- The player's own values (the client's defaults), and fishing's other two names.
WoW.cvarValues.SoftTargetInteract = "1"
WoW.cvarValues.SoftTargetInteractRange = "10"
WoW.cvarValues.SoftTargetIconGameObject = "0"
WoW.cvarValues.SoftTargetInteractArc = "1"
WoW.cvarValues.SoftTargetIconInteract = "0"
WoW.known[7620] = true

local GP = loadAddon()
local ST, P, F = GP.SparkleStars, GP.Pearls, GP.Fishing

local function pass() WoW.tick(ST.TICK + 0.01) end
local function value(n) return C_CVar.GetCVar(n) end
local function ours()
    for _, n in ipairs(NAMES) do
        if WoW.tempCVars[n] == nil then return false end
    end
    return value("SoftTargetInteract") == "3" and value("SoftTargetInteractRange") == "60"
        and value("SoftTargetIconGameObject") == "1"
end
local function none()
    for _, n in ipairs(NAMES) do if WoW.tempCVars[n] ~= nil then return false end end
    return true
end
local function stars(mode) P.SetSetting("sparkle", "stars", mode) end
local function startFishing() WoW.channel = { id = 7620 }; WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "C", 7620) end
local function stopFishing() WoW.channel = nil; WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "C", 7620) end
local function combat(on) WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED") end

--------------------------------------------------------------------------------
-- Off by default

eq(P.Setting("sparkle", "stars"), "off", "the stars are off by default")
P.Set("sparkle", true)
eq(ST.Mode(), "off", "the pearl on, the stars off: nothing")
check(none(), "  no temp")
check(not ST.state.active, "  no listener")
check(ST._test.root() == nil, "  no art built")
stars("quest")
check(ours(), "stars on: the three CVars at ours, as temps")
eq(WoW.cvarValues.SoftTargetInteract, "1", "  the player's own value never written")
eq(#WoW.cvarSets, 0, "  no SetCVar at all")
check(ST.state.active, "  the listeners registered")
P.Set("sparkle", false)
check(none(), "the pearl off: every temp removed")
eq(ST.Mode(), "off", "  the stars off with it")
P.Set("sparkle", true)
check(ours(), "the pearl on again: back")

--------------------------------------------------------------------------------
-- The plate

local function object(token, t)
    local u = { id = t.id or token }
    for k, v in pairs(t) do u[k] = v end
    WoW.units[token] = u
end
WoW.units.softinteract = { id = "rock" }
object("nameplate1", { id = "rock", object = true, quest = true })
local plate = WoW.newPlate("nameplate1")
WoW.plates = { plate }
WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
local root = ST._test.root()
check(root ~= nil and root:IsShown(), "a quest object's plate: the stars show")
local pt = root and root._points[#root._points]
check(pt and pt[1] == "CENTER" and pt[2] == plate and pt[3] == "BOTTOM", "  anchored to the plate's bottom")
eq(ST.state.bound and ST.state.bound.unit, "nameplate1", "  bound to its unit")
eq(#ST._test.stars(), ST.STARS, "  four stars")
check(ST._test.stars()[1].anim._playing, "  playing")

local function judged(label, setup, want)
    ST.Unbind()
    setup()
    pass()
    eq(ST.state.bound ~= nil, want, label)
end
judged("not related to a quest, mode quest: no stars", function() WoW.units.nameplate1.quest = false end, false)
judged("  mode all: stars", function() stars("all") end, true)
judged("not a game object, mode all: no stars", function() WoW.units.nameplate1.object = false end, false)
WoW.units.nameplate1.object = true
stars("quest")
judged("the quest read secret: no stars", function() WoW.units.nameplate1.quest = WoW.Secret("quest") end, false)
judged("the quest read throws: no stars", function() WoW.units.nameplate1.quest = "throw" end, false)
WoW.units.nameplate1.quest = true
judged("not the soft-interact target: no stars", function() WoW.units.softinteract = { id = "other" } end, false)
WoW.units.softinteract = { id = "rock" }
judged("the comparison secret: no stars", function() WoW.unitIsUnitSecret = true end, false)
WoW.unitIsUnitSecret = nil
judged("the plate's token secret: no stars", function() plate.namePlateUnitToken = WoW.Secret("token") end, false)
plate.namePlateUnitToken = "nameplate1"
judged("qualifying again: stars", function() end, true)

-- Removal: the stored token, at once.
WoW.fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
check(ST.state.bound ~= nil, "another plate removed: the stars stay")
WoW.fire("NAME_PLATE_UNIT_REMOVED", WoW.Secret("token"))
check(ST.state.bound ~= nil, "  a secret payload: the stars stay")
WoW.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(ST.state.bound == nil and not root:IsShown(), "its plate removed: unbound at once")
check(not ST._test.stars()[1].anim._playing, "  the stars stopped")
-- A plate reused for another unit.
pass()
check(ST.state.bound ~= nil, "back on the next pass")
object("nameplate2", { id = "chest", object = true, quest = false })
plate.namePlateUnitToken = "nameplate2"
pass()
check(ST.state.bound == nil, "the plate reused for another unit: unbound")
plate.namePlateUnitToken = "nameplate1"
pass()
plate:Hide()
pass()
check(ST.state.bound == nil, "the plate hidden: unbound")
plate:Show()
pass()
check(ST.state.bound ~= nil, "  shown again: bound")
stars("off")
check(ST.state.bound == nil and not root:IsShown(), "the stars switched off: unbound")
check(none(), "  and the temps removed")
stars("quest")
pass()
check(ST.state.bound ~= nil and ours(), "on again")
-- In combat the visual still binds (an insecure UIParent child anchored to a plate).
combat(true)
ST.Unbind()
pass()
check(ST.state.bound ~= nil, "in combat the stars still bind")
combat(false)

--------------------------------------------------------------------------------
-- The temps: effective values decide

stars("off")
WoW.tempCalls = {}
WoW.cvarValues.SoftTargetInteract = "3"
stars("quest")
eq(WoW.tempCount("set", "SoftTargetInteract"), 0, "a name already at ours: not set")
eq(WoW.tempCount("set", "SoftTargetInteractRange"), 1, "  the others set")
stars("off")
eq(WoW.tempCount("remove", "SoftTargetInteract"), 0, "  and it isn't ours to remove")
WoW.cvarValues.SoftTargetInteract = "1"

-- Refused: not retried in this stars session; quest <-> all isn't a new one; off and on is.
WoW.tempRefused.SoftTargetInteractRange = true
WoW.tempCalls = {}
stars("quest")
eq(WoW.tempCount("set", "SoftTargetInteractRange"), 1, "a refused set: tried once")
pass(); pass()
eq(WoW.tempCount("set", "SoftTargetInteractRange"), 1, "  not retried on the next passes")
check(table.concat(ST.Lines(), "\n"):find("SoftTargetInteractRange: 10 now, 60 wanted, ours, unavailable: refused by the client",
    1, true), "  the report says it's unavailable")
stars("all")
pass()
eq(WoW.tempCount("set", "SoftTargetInteractRange"), 1, "  quest -> all: still not retried (the same session)")
WoW.tempRefused.SoftTargetInteractRange = nil
stars("off")
stars("quest")
eq(WoW.tempCount("set", "SoftTargetInteractRange"), 2, "  off and on: a new session tries again")
check(ours(), "  and it takes")

-- Displaced (fishing's removal, by hand here): repaired on the next pass.
WoW.tempCVars.SoftTargetIconGameObject = nil
pass()
eq(value("SoftTargetIconGameObject"), "1", "a displaced value: set again on the next pass")

-- Ineligible, and a throw.
stars("off")
WoW.cvarInfo.SoftTargetInteractRange = { secure = true }
WoW.tempThrows.SoftTargetIconGameObject = true
stars("quest")
check(table.concat(ST.Lines(), "\n"):find("unavailable: secure", 1, true), "a secure CVar: unavailable, not tried")
check(table.concat(ST.Lines(), "\n"):find("unavailable: the set threw", 1, true), "a throwing set: unavailable")
check(GP.failures["pearl sparkle stars SoftTargetIconGameObject"] ~= nil, "  recorded")
GP.failures["pearl sparkle stars SoftTargetIconGameObject"] = nil
WoW.cvarInfo.SoftTargetInteractRange, WoW.tempThrows.SoftTargetIconGameObject = nil, nil
stars("off")
stars("quest")
check(ours(), "both fine again in a new session")

--------------------------------------------------------------------------------
-- Combat: the CVars wait; cleanup outlives the switch

combat(true)
WoW.tempCVars.SoftTargetInteract = nil
pass()
eq(value("SoftTargetInteract"), "1", "displaced in combat: not repaired yet")
combat(false)
eq(value("SoftTargetInteract"), "3", "  repaired after combat")
combat(true)
WoW.tempCalls = {}
stars("off")
eq(WoW.tempCount("remove"), 0, "switched off in combat: nothing removed yet")
check(ST.state.active, "  the listeners kept while something is held")
combat(false)
check(none(), "  removed after combat")
check(not ST.state.active, "  then the listeners go")
stars("quest")
combat(true)
stars("off")
stars("quest")
WoW.tempCalls = {}
combat(false)
eq(WoW.tempCount("remove"), 0, "off then on again in combat: the obsolete removal never runs")
check(ours(), "  the values stay")

-- A removal that fails stays held and is retried (Codex review, PR #81).
WoW.tempRemoveThrows.SoftTargetInteract = true
stars("off")
eq(value("SoftTargetInteract"), "3", "a removal that throws: our value still there")
check(ST.state.held.SoftTargetInteract ~= nil, "  still held")
check(ST.state.active, "  the listeners kept")
check(ST._test.driver._scripts.OnUpdate ~= nil, "  and the passes, to retry")
check(GP.failures["pearl sparkle stars remove SoftTargetInteract"] ~= nil, "  recorded")
GP.failures["pearl sparkle stars remove SoftTargetInteract"] = nil
pass()
eq(value("SoftTargetInteract"), "3", "  retried while it still throws: still there")
WoW.tempRemoveThrows.SoftTargetInteract = nil
pass()
check(none(), "  the next pass once it works: removed")
check(not ST.state.active and ST._test.driver._scripts.OnUpdate == nil, "  then nothing left running")
stars("quest")
WoW.cvarInfo.SoftTargetInteractRange = { secure = true }
stars("off")
check(ST.state.held.SoftTargetInteractRange ~= nil, "a name ineligible at cleanup: still held, not given up")
WoW.cvarInfo.SoftTargetInteractRange = nil
pass()
check(none() and not ST.state.active, "  eligible again: removed on the next pass")
stars("quest")

--------------------------------------------------------------------------------
-- Gamepad

WoW.tempCalls = {}
WoW.inputStyle = 1
WoW.tempCVars.SoftTargetInteract, WoW.tempCVars.SoftTargetInteractRange, WoW.tempCVars.SoftTargetIconGameObject =
    "3", "60", "1"   -- Blizzard's own temps for the gamepad, the same values
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1)
check(next(ST.state.held) == nil, "into gamepad: what we held dropped")
WoW.flushTimers()
pass()
eq(WoW.tempCount("remove"), 0, "  and never removed (Blizzard's now)")
eq(WoW.tempCount("set"), 0, "  nothing set in gamepad style")
-- Blizzard removes its temps leaving gamepad; back in Mkb, ours again (a new session).
for _, n in ipairs(NAMES) do WoW.tempCVars[n] = nil end
WoW.tempRefused.SoftTargetInteract = true
WoW.inputStyle = 0
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0)
WoW.flushTimers()
eq(WoW.tempCount("set", "SoftTargetInteract"), 1, "back in mouse and keyboard: set again")
WoW.tempRefused.SoftTargetInteract = nil
WoW.inputStyle = 1
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1)
WoW.flushTimers()
for _, n in ipairs(NAMES) do WoW.tempCVars[n] = nil end   -- Blizzard's own removal, leaving gamepad
WoW.inputStyle = 0
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0)
WoW.flushTimers()
check(ours(), "  a later round trip is a new session: the refusal forgotten")
eq(WoW.tempCount("set", "SoftTargetInteract"), 2, "  (it was tried again)")
-- Switched on in gamepad style with nothing held, then Mkb: the listener starts them.
stars("off")
check(none(), "off: removed")
WoW.inputStyle = 1
stars("quest")
check(none() and next(ST.state.held) == nil, "on in gamepad style: nothing held")
check(ST.state.active, "  the transition listener is there anyway")
WoW.inputStyle = 0
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0)
WoW.flushTimers()
check(ours(), "  into mouse and keyboard: the stars' CVars set")

--------------------------------------------------------------------------------
-- Easy fishing's temps, with the real Fishing logic

-- Stars first, then fishing, then stars off mid-session: fishing's names never removed by us.
WoW.tempCalls = {}
startFishing()
check(F.state.held.SoftTargetInteract ~= nil, "fishing holds the interact names in its session")
stars("off")
eq(WoW.tempCount("remove", "SoftTargetInteract"), 0, "stars off mid-session: fishing's names not removed by us")
eq(value("SoftTargetInteract"), "3", "  fishing still has its value")
stars("quest")
stopFishing()
check(none(), "fishing's session ends: it removes its temps (ours with them)")
pass()
check(ours(), "  the stars set them again on the next pass")
-- Fishing first, then stars.
stars("off")
startFishing()
WoW.tempCalls = {}
stars("quest")
eq(WoW.tempCount("set"), 0, "fishing first: the values are already in place, nothing set")
stopFishing()
pass()
check(ours(), "  fishing ends: the stars take over")
-- Fishing's set refused, so its held doesn't prove the value: the stars set it.
stars("off")
WoW.tempRefused.SoftTargetIconGameObject = true
startFishing()
check(F.state.held.SoftTargetIconGameObject ~= nil and value("SoftTargetIconGameObject") == "0",
    "fishing holds a name its set didn't take")
WoW.tempRefused.SoftTargetIconGameObject = nil
stars("quest")
eq(value("SoftTargetIconGameObject"), "1", "  the stars read the effective value and set it")
stopFishing()
pass()
-- /gpearls fishing reset removes every interact name, ours too: repaired.
F.Reset()
check(none(), "fishing's reset removes our temps too")
pass()
check(ours(), "  repaired on the next pass")
-- A session end in combat: repaired after the fight.
startFishing()
combat(true)
stopFishing()
pass()
check(none(), "fishing ends in combat: the temps gone, not repaired in combat")
combat(false)
check(ours(), "  repaired after combat")

--------------------------------------------------------------------------------
-- The reports

newChat()
P.Command("sparkle").run("")
check(chatHas("  Stars: quest%."), "/gpearls sparkle: the stars' mode")
check(chatHas("SoftTargetInteract: 3 now, 3 wanted, ours%."), "  each CVar")
startFishing()
newChat()
P.Command("sparkle").run("")
check(chatHas("easy fishing holds it"), "  and whether fishing holds it")
stopFishing()
pass()

local function target() newChat(); P.Command("sparkle").run("target"); return table.concat(newChat(), "\n") end
WoW.unitNames.nameplate1 = "Rough Rock"
local t = target()
check(t:find("Soft-interact object: Rough Rock.", 1, true), "target: the object's name")
check(t:find("UnitIsRelatedToActiveQuest true, UnitIsQuestBoss false", 1, true), "  what the client says")
check(t:find("The stars are on it.", 1, true), "  and that the stars are on it")
WoW.units.nameplate1.quest = false
ST.Unbind()
t = target()
check(t:find("UnitIsRelatedToActiveQuest false", 1, true) and t:find("No stars: the quest test read false.", 1, true),
    "a non-quest object: found anyway (the quest test isn't how it's found), and why no stars")
WoW.units.nameplate1.quest = WoW.Secret("quest")
check(target():find("No stars: the quest test read secret.", 1, true), "  the quest test secret: said")
WoW.units.nameplate1.quest = true
WoW.unitIsUnitSecret = true
t = target()
check(t:find("Could not determine the soft-interact object plate: UnitIsUnit(softinteract) read secret on Rough Rock.",
    1, true), "the comparison secret: could not determine, never 'no plate'")
WoW.unitIsUnitSecret = nil
WoW.unitIsUnitThrows = true
check(target():find("UnitIsUnit(softinteract) read error", 1, true), "  the comparison throwing: said")
WoW.unitIsUnitThrows = nil
WoW.units.nameplate1.object = "throw"
check(target():find("UnitIsGameObject read error", 1, true), "  the object read throwing: said")
WoW.units.nameplate1.object = true
WoW.units.softinteract = { id = "other" }
check(target():find("No soft-interact object plate", 1, true), "no plate is the soft-interact one: none observed")
WoW.units.softinteract = { id = "rock" }
WoW.plates = "throw"
check(target():find("Nameplates can't be read (error).", 1, true), "the plates unreadable: said")
WoW.plates = { plate }

--------------------------------------------------------------------------------
-- The panel

GP.Options.Open("cat:Loot & Bags")
local page = GP.Options._test.pages["cat:Loot & Bags"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "sparkle" then row = pl.row end end
check(row ~= nil and row.gear ~= nil, "the quest loot sparkle has a gear now")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:sparkle"].frame._children[1]
local radios = {}
for _, w in ipairs(content._children) do if w.value then radios[#radios + 1] = w end end
eq(#radios, 3, "three choices")
radios[1]:GetScript("OnClick")(radios[1])
eq(P.Setting("sparkle", "stars"), "off", "  Off")
check(none(), "  the temps removed through the setting's change")
radios[3]:GetScript("OnClick")(radios[3])
eq(P.Setting("sparkle", "stars"), "all", "  any object")
check(ours(), "  set through the setting's change")
P.ResetSettings("sparkle")
eq(P.Setting("sparkle", "stars"), "off", "  reset: off")
check(none(), "  and the temps removed")
GP.Options._test.win():Hide()

done("test_sparkle_stars")
