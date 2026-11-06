-- The raid mark wheel's unit identity (#34). A session { token, guid, epoch }
-- holds while no event can have moved another unit into its token and, when
-- its GUID was plain, while it reads the same. No entry in Blizzard's unit
-- menus (#82: anything added there taints the menu's layout; an enemy's broke).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A target menu built before the pearl loads, and some after: nothing of ours in any.
local early
local GP = loadAddon({ before = function()
    WoW.units.target = { id = "OLD", guid = "Creature-0-1-OLD" }
    early = WoW.openMenu("TARGET", { unit = "target" })
end })
local M, P = GP.MarkWheel, GP.Pearls
local NAME = "Raid mark wheel"
check(next(WoW.menuModifiers) == nil, "no Menu.ModifyMenu at all: no unit menu is modified (#82)")
eq(#early.elements, 1, "  a menu built before: Blizzard's entries only")
for _, which in ipairs({ "TARGET", "FOCUS", "PARTY", "PLAYER", "SELF", "PET" }) do
    local d = WoW.openMenu(which, { unit = "target" })
    check(WoW.menuButton(d, NAME) == nil and #d.elements == 1, "  " .. which .. "'s menu: nothing of ours")
end
P.Set("markwheel", false)
P.Set("markwheel", true)
check(next(WoW.menuModifiers) == nil, "  switching off and on registers nothing either")
eq(P.Setting("markwheel", "menu"), nil, "the menu setting is gone")

WoW.mouse = { x = 500, y = 400 }
local function at(dx, dy) WoW.mouse = { x = 500 + dx, y = 400 + dy } end
local function choose(dx, dy)
    local b = M._test.button()
    at(dx, dy)
    WoW.click(b, "LeftButton", true)
    WoW.click(b, "LeftButton", false)
end

-- A session captured on the target, opened later (the key does both at once).
WoW.units.target = { id = "A", guid = "Creature-0-1-A" }
M.Open(M.Capture("target"))
check(M.IsOpen() and M.state.session.token == "target", "a captured session opens the wheel on the target")
choose(0, 100)
eq(WoW.marks.A, 8, "  and marks it")

-- The target changed between the capture and the open: refused.
local s = M.Capture("target")
WoW.units.target = { id = "B", guid = "Creature-0-1-B" }
WoW.fire("PLAYER_TARGET_CHANGED")
newChat()
M.Open(s)
check(not M.IsOpen(), "the target changed after the capture: refused")
check(chatHas("gone or changed"), "  and says so")

-- Even with no event, a plain GUID that changed is refused.
s = M.Capture("target")
WoW.units.target = { id = "C", guid = "Creature-0-1-C" }
M.Open(s)
check(not M.IsOpen(), "the GUID changed, no event: refused")

-- A GUID plain at capture, secret later: refused, not downgraded.
WoW.units.target = { id = "D", guid = "Creature-0-1-D" }
s = M.Capture("target")
WoW.units.target.guid = WoW.Secret("UnitGUID")
M.Open(s)
check(not M.IsOpen(), "a GUID plain then secret: refused")

-- A secret GUID at capture: the epoch alone vouches for it.
WoW.units.target = { id = "E", guid = WoW.Secret("UnitGUID") }
M.Open(M.Capture("target"))
check(M.IsOpen(), "a secret GUID: opens, resting on the epoch")
M.Close("test")
s = M.Capture("target")
WoW.fire("PLAYER_TARGET_CHANGED")
M.Open(s)
check(not M.IsOpen(), "  and a target change refuses it")

-- Focus, pets, raid pets: their events.
WoW.units.focus = { id = "F", guid = WoW.Secret("UnitGUID") }
s = M.Capture("focus")
WoW.fire("PLAYER_FOCUS_CHANGED")
M.Open(s)
check(not M.IsOpen(), "the focus changed: refused")
WoW.units.pet = { id = "P", guid = WoW.Secret("UnitGUID") }
s = M.Capture("pet")
WoW.fire("UNIT_PET", "player")
M.Open(s)
check(not M.IsOpen(), "the pet changed: refused")
WoW.units.raidpet3 = { id = "RP", guid = WoW.Secret("UnitGUID") }
s = M.Capture("raidpet3")
WoW.fire("GROUP_ROSTER_UPDATE")
M.Open(s)
check(not M.IsOpen(), "the roster changed (its slot may hold another pet now): refused")
WoW.units.party2 = { id = "P2", guid = "Player-1-P2" }
M.Open(M.Capture("party2"))
check(M.IsOpen() and M.state.session.token == "party2", "a party member's session opens on them")
WoW.fire("GROUP_ROSTER_UPDATE")
check(not M.IsOpen(), "  a roster change while open closes it")

-- Tokens no session can validate: no capture.
for _, token in ipairs({ "boss1", "vehicle", "arena1", "mouseover" }) do
    WoW.units[token] = { id = token, guid = "Creature-0-1-" .. token }
    check(M.Capture(token) == nil, "no session for the token " .. token)
end
check(M.Capture(WoW.Secret("unit")) == nil, "no session for a secret token")

-- A session kept across switching off and on again is dead (a secret GUID:
-- only the epoch can tell).
WoW.units.target = { id = "G2", guid = WoW.Secret("UnitGUID") }
s = M.Capture("target")
P.Set("markwheel", false)
WoW.units.target = { id = "H", guid = WoW.Secret("UnitGUID") }   -- unobserved while off
P.Set("markwheel", true)
M.Open(s)
check(not M.IsOpen(), "a session from before switching off and on: refused")

-- A session from before combat, opened in it: refused.
WoW.units.target = { id = "J", guid = "Creature-0-1-J" }
local before = M.Capture("target")
WoW.fire("PLAYER_REGEN_DISABLED")
newChat()
M.Open(before)
check(not M.IsOpen(), "a session from before combat, opened in combat: refused")
check(chatHas("Not in combat"), "  and says why")
check(not M.Test() and not M.IsOpen(), "Test in combat: refused")
WoW.fire("PLAYER_REGEN_ENABLED")

-- A read that throws: refused.
WoW.units.target = { id = "I", guid = "Creature-0-1-I" }
s = M.Capture("target")
local realExists = UnitExists
UnitExists = function(token) if token == "target" then error("boom") end return realExists(token) end
M.Open(s)
check(not M.IsOpen(), "a read that throws: refused")
UnitExists = realExists

-- The key: the mouseover resolved to a token at once.
WoW.units = { target = { id = "T", guid = "Creature-0-1-T" } }
WoW.units.nameplate3 = { id = "N", guid = WoW.Secret("UnitGUID") }
WoW.units.mouseover = WoW.units.nameplate3
at(0, 0)
M.OnKey()
check(M.IsOpen() and M.state.session.token == "nameplate3", "the key over a nameplate's unit: its token")
WoW.fire("NAME_PLATE_UNIT_REMOVED", "nameplate5")
check(M.IsOpen(), "  another plate removed: still open")
WoW.fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
check(not M.IsOpen(), "  its own plate removed: closed")
M.OnKey()
WoW.units.nameplate3 = { id = "N2", guid = WoW.Secret("UnitGUID") }   -- the token reused
WoW.fire("NAME_PLATE_UNIT_REMOVED", WoW.Secret("unit"))
check(not M.IsOpen(), "  a removal whose token is secret: closed too")
-- Party frames: the mouseover is the party member.
WoW.units.party1 = { id = "P1", guid = "Player-1-P1" }
WoW.units.mouseover = WoW.units.party1
M.OnKey()
eq(M.state.session and M.state.session.token, "party1", "over a party frame: the party token")
M.Close("test")
-- The target before a nameplate, when both are the mouseover.
WoW.units.nameplate7 = WoW.units.target
WoW.units.mouseover = WoW.units.target
M.OnKey()
eq(M.state.session and M.state.session.token, "target", "the target before its nameplate")
M.Close("test")
-- UnitIsUnit answering secrets: nothing matches, refused.
WoW.unitIsUnitSecret = true
M.OnKey()
check(not M.IsOpen(), "UnitIsUnit secret: no token, no wheel")
WoW.unitIsUnitSecret = nil
-- A world change ends an open wheel.
M.OnKey()
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(not M.IsOpen(), "a loading screen closes it")

eq(#WoW.forbidden, 0, "SetRaidTarget only ever from Blizzard's secure action")
done("test_markwheel_identity")
