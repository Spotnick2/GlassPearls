-- The quest sparkle's experimental stars (#79): the option (off / quest /
-- all); the plate binding (qualifies or not, secrets, a reused plate, a
-- removed one, a hidden one); the CVars set and put back with the option
-- (their rules: test_sparkle_claims); the reports; the panel.
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
local ST, P = GP.SparkleStars, GP.Pearls
WoW.now = ST.SETTLE + 1                        -- past the login settle window

local function pass() WoW.tick(ST.TICK + 0.01) end
local function value(n) return C_CVar.GetCVar(n) end
local function ours()
    return value("SoftTargetInteract") == "3" and value("SoftTargetInteractRange") == "60"
        and value("SoftTargetIconGameObject") == "1"
end
local function none()
    return value("SoftTargetInteract") == "1" and value("SoftTargetInteractRange") == "10"
        and value("SoftTargetIconGameObject") == "0"
end
local function stars(mode) P.SetSetting("sparkle", "stars", mode) end
local function combat(on) WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED") end

--------------------------------------------------------------------------------
-- Off by default

eq(P.Setting("sparkle", "stars"), "off", "the stars are off by default")
P.Set("sparkle", true)
eq(ST.Mode(), "off", "the pearl on, the stars off: nothing")
check(none(), "  no CVar changed")
check(not ST.state.active, "  no listener")
check(ST._test.root() == nil, "  no art built")
stars("quest")
check(ours(), "stars on: the three CVars at ours")
eq(#WoW.tempCalls, 0, "  no temp CVar")
check(ST.state.active, "  the listeners registered")
P.Set("sparkle", false)
check(none(), "the pearl off: the player's values back")
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
check(none(), "  and the CVars put back")
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
-- The reports

newChat()
P.Command("sparkle").run("")
check(chatHas("  Stars: quest%."), "/gpearls sparkle: the stars' mode")
check(chatHas("SoftTargetInteract: 3 now, 3 wanted, ours %(yours was 1%)%."), "  each CVar")

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
check(none(), "  the CVars put back through the setting's change")
radios[3]:GetScript("OnClick")(radios[3])
eq(P.Setting("sparkle", "stars"), "all", "  any object")
check(ours(), "  set through the setting's change")
P.ResetSettings("sparkle")
eq(P.Setting("sparkle", "stars"), "off", "  reset: off")
check(none(), "  and the CVars put back")
GP.Options._test.win():Hide()

done("test_sparkle_stars")
