-- The raid mark wheel's unit identity and Blizzard's unit menus (#34). A
-- session { token, guid, epoch } holds while no event can have moved another
-- unit into its token and, when its GUID was plain, while it reads the same.
-- The menu entry: on exactly the menus that carry Blizzard's Raid Target
-- Icon, captured when the menu is built, checked again when clicked.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A target menu built before the pearl is first enabled: Menu.ModifyMenu
-- hands it to the new modifier at once (Menu.lua:2723), at our registration.
local early
local GP = loadAddon({ before = function()
    WoW.units.target = { id = "OLD", guid = "Creature-0-1-OLD" }
    early = WoW.openMenu("TARGET", { unit = "target" })
end })
local M, P = GP.MarkWheel, GP.Pearls
local NAME = "Raid mark wheel"
check(WoW.menuButton(early, NAME) == nil, "a menu built before our registration gains no entry")

-- Registered on exactly these menus.
local registered = {}
for tag in pairs(WoW.menuModifiers) do registered[#registered + 1] = tag end
table.sort(registered)
eq(table.concat(registered, ","), "MENU_UNIT_FOCUS,MENU_UNIT_OTHERPET,MENU_UNIT_PARTY,MENU_UNIT_PET,"
    .. "MENU_UNIT_PLAYER,MENU_UNIT_RAID_PLAYER,MENU_UNIT_SELF,MENU_UNIT_TARGET",
    "the menus with Blizzard's Raid Target Icon (not ENEMY_PLAYER, VEHICLE, BOSS)")
-- Switching off and on again registers nothing more.
P.Set("markwheel", false)
P.Set("markwheel", true)
eq(#WoW.menuModifiers.MENU_UNIT_TARGET, 1, "registered once, kept")

WoW.mouse = { x = 500, y = 400 }
local function at(dx, dy) WoW.mouse = { x = 500 + dx, y = 400 + dy } end
local function choose(dx, dy)
    local b = M._test.button()
    at(dx, dy)
    WoW.click(b, "LeftButton", true)
    WoW.click(b, "LeftButton", false)
end

-- The entry, on the menu's own unit.
WoW.units.target = { id = "A", guid = "Creature-0-1-A" }
local d = WoW.openMenu("TARGET", { unit = "target" })
local entry = WoW.menuButton(d, NAME)
check(entry ~= nil, "the target's menu has the entry")
eq(d.elements[#d.elements - 1].kind, "divider", "  after a divider")
eq(d.elements[2].kind, "divider", "  appended after Blizzard's own entries")
entry()
check(M.IsOpen() and M.state.session.token == "target", "  it opens the wheel on the target")
choose(0, 100)
eq(WoW.marks.A, 8, "  and marks it")

-- The target changed between the menu and the click: refused.
d = WoW.openMenu("TARGET", { unit = "target" })
WoW.units.target = { id = "B", guid = "Creature-0-1-B" }
WoW.fire("PLAYER_TARGET_CHANGED")
newChat()
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "the target changed after the menu was built: refused")
check(chatHas("gone or changed"), "  and says so")

-- Even with no event, a plain GUID that changed is refused.
d = WoW.openMenu("TARGET", { unit = "target" })
WoW.units.target = { id = "C", guid = "Creature-0-1-C" }
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "the GUID changed, no event: refused")

-- A GUID plain at capture, secret later: refused, not downgraded.
WoW.units.target = { id = "D", guid = "Creature-0-1-D" }
d = WoW.openMenu("TARGET", { unit = "target" })
WoW.units.target.guid = WoW.Secret("UnitGUID")
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "a GUID plain then secret: refused")

-- A secret GUID at capture: the epoch alone vouches for it.
WoW.units.target = { id = "E", guid = WoW.Secret("UnitGUID") }
d = WoW.openMenu("TARGET", { unit = "target" })
WoW.menuButton(d, NAME)()
check(M.IsOpen(), "a secret GUID: opens, resting on the epoch")
M.Close("test")
d = WoW.openMenu("TARGET", { unit = "target" })
WoW.fire("PLAYER_TARGET_CHANGED")
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "  and a target change refuses it")

-- Focus, pets, raid pets: their events.
WoW.units.focus = { id = "F", guid = WoW.Secret("UnitGUID") }
d = WoW.openMenu("FOCUS", { unit = "focus" })
check(WoW.menuButton(d, NAME) ~= nil, "the focus's menu has the entry")
WoW.fire("PLAYER_FOCUS_CHANGED")
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "the focus changed: refused")
WoW.units.pet = { id = "P", guid = WoW.Secret("UnitGUID") }
d = WoW.openMenu("PET", { unit = "pet" })
WoW.fire("UNIT_PET", "player")
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "the pet changed: refused")
WoW.units.raidpet3 = { id = "RP", guid = WoW.Secret("UnitGUID") }
d = WoW.openMenu("OTHERPET", { unit = "raidpet3" })
check(WoW.menuButton(d, NAME) ~= nil, "a raid pet's menu has the entry")
WoW.fire("GROUP_ROSTER_UPDATE")
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "the roster changed (its slot may hold another pet now): refused")
WoW.units.party2 = { id = "P2", guid = "Player-1-P2" }
d = WoW.openMenu("PARTY", { unit = "party2" })
WoW.menuButton(d, NAME)()
check(M.IsOpen() and M.state.session.token == "party2", "a party member's menu opens on them")
WoW.fire("GROUP_ROSTER_UPDATE")
check(not M.IsOpen(), "  a roster change while open closes it")

-- Tokens no session can validate: no entry.
for _, token in ipairs({ "boss1", "vehicle", "arena1", "nameplate4", "mouseover" }) do
    WoW.units[token] = { id = token, guid = "Creature-0-1-" .. token }
    d = WoW.openMenu("TARGET", { unit = token })
    check(WoW.menuButton(d, NAME) == nil, "no entry for the token " .. token)
end
d = WoW.openMenu("PLAYER", { name = "Someone" })
check(WoW.menuButton(d, NAME) == nil, "no entry for a menu without a unit (a name from chat)")
d = WoW.openMenu("TARGET", { unit = WoW.Secret("unit") })
check(WoW.menuButton(d, NAME) == nil, "no entry for a secret token")

-- The setting, read when the menu is built and again on the click.
WoW.units.target = { id = "G", guid = "Creature-0-1-G" }
d = WoW.openMenu("TARGET", { unit = "target" })
P.SetSetting("markwheel", "menu", false)
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "the entry turned off after the menu was built: nothing")
d = WoW.openMenu("TARGET", { unit = "target" })
check(WoW.menuButton(d, NAME) == nil, "  and new menus have no entry")
P.SetSetting("markwheel", "menu", true)

-- A responder kept across switching off and on again is dead (a secret GUID:
-- only the epoch can tell).
WoW.units.target = { id = "G2", guid = WoW.Secret("UnitGUID") }
d = WoW.openMenu("TARGET", { unit = "target" })
P.Set("markwheel", false)
check(WoW.menuButton(WoW.openMenu("TARGET", { unit = "target" }), NAME) == nil, "switched off: no entry")
WoW.units.target = { id = "H", guid = WoW.Secret("UnitGUID") }   -- unobserved while off
P.Set("markwheel", true)
WoW.menuButton(d, NAME)()
check(not M.IsOpen(), "a responder from before switching off and on: refused")

-- No entry in combat; an entry built before combat, clicked in it: refused.
WoW.units.target = { id = "J", guid = "Creature-0-1-J" }
local before = WoW.openMenu("TARGET", { unit = "target" })
WoW.fire("PLAYER_REGEN_DISABLED")
d = WoW.openMenu("TARGET", { unit = "target" })
check(WoW.menuButton(d, NAME) == nil, "in combat: no entry")
newChat()
WoW.menuButton(before, NAME)()
check(not M.IsOpen(), "an entry from before combat, clicked in combat: refused")
check(chatHas("Not in combat"), "  and says why")
check(not M.Test() and not M.IsOpen(), "Test in combat: refused")
WoW.fire("PLAYER_REGEN_ENABLED")

-- A read that throws: refused.
WoW.units.target = { id = "I", guid = "Creature-0-1-I" }
d = WoW.openMenu("TARGET", { unit = "target" })
local realExists = UnitExists
UnitExists = function(token) if token == "target" then error("boom") end return realExists(token) end
WoW.menuButton(d, NAME)()
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
