-- The raid mark wheel (#34): the key, the gates, choosing a mark, clearing it,
-- and every way the wheel closes. The click's edges are
-- test_markwheel_click.lua, the unit's identity and the menus
-- test_markwheel_identity.lua, combat test_markwheel_combat.lua, the art
-- test_markwheel_frame.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local M, P = GP.MarkWheel, GP.Pearls
local button

local CX, CY = 500, 400
local function at(dx, dy) WoW.mouse = { x = CX + dx, y = CY + dy } end
-- A whole left click (both edges) at an offset from the wheel's centre.
local function click(dx, dy, mouseButton)
    at(dx, dy)
    WoW.click(button, mouseButton or "LeftButton", true)
    WoW.click(button, mouseButton or "LeftButton", false)
end
local function openOnTarget()
    at(0, 0)
    return M.OnKey()
end
local SKULL, STAR = { 0, 100 }, { 70, 70 }

-- The pearl.
local def = P.Get("markwheel")
check(def ~= nil, "registered")
eq(def.category, "Social", "on the Social page")
eq(def.default, true, "on by default")
check(P.IsLive("markwheel"), "enabled at login")
eq(BINDING_NAME_GLASSPEARLS_MARKWHEEL, "Raid mark wheel", "the key's name in Key Bindings")

-- Nothing under the cursor.
newChat()
M.OnKey()
check(not M.IsOpen(), "nothing under the cursor: no wheel")
check(chatHas("Point at a unit"), "  and says so")

-- A unit no token is: refused.
WoW.units.mouseover = { id = "A", guid = "Creature-0-1-A" }
newChat()
M.OnKey()
check(not M.IsOpen(), "a unit no token is: no wheel")
check(chatHas("can't be followed"), "  and says so")

-- The target.
WoW.units.target = WoW.units.mouseover
openOnTarget()
check(M.IsOpen(), "the mouseover is the target: the wheel opens")
eq(M.state.session.token, "target", "  on the token 'target'")
button = M._test.button()
check(button:IsShown(), "  the secure button is shown")
eq(button:GetAttribute("type"), nil, "  and disarmed")
local p = button._points[#button._points]
check(p[1] == "CENTER" and p[2] == UIParent and p[4] == CX and p[5] == CY, "  at the cursor")
check(GP.MarkWheelFrame.IsShown(), "  the art too")
check(M._test.events._events.GLOBAL_MOUSE_DOWN, "  a click outside is watched")
eq(button:GetAttribute("useOnKeyDown"), false, "the button acts on release")
eq(button._registeredClicks[1] .. "," .. button._registeredClicks[2], "AnyDown,AnyUp", "  both edges registered")

-- The key again closes it.
M.OnKey()
check(not M.IsOpen(), "the key again closes it")
check(not button:IsShown(), "  the button hidden")
check(not M._test.events._events.GLOBAL_MOUSE_DOWN, "  clicks no longer watched")

-- Choosing skull marks the target; the same again removes it; the centre clears.
openOnTarget()
click(SKULL[1], SKULL[2])
eq(#WoW.raidCalls, 1, "a click on skull: one mark")
check(WoW.raidCalls[1][1] == "target" and WoW.raidCalls[1][2] == 8, "  skull (8) on the target")
eq(WoW.marks.A, 8, "  the target wears skull")
check(not M.IsOpen() and not button:IsShown(), "  and the wheel closes")
eq(button:GetAttribute("type"), nil, "  disarmed again")
openOnTarget()
click(SKULL[1], SKULL[2])
eq(WoW.raidCalls[2][2], 0, "skull again: removed (toggle)")
eq(WoW.marks.A, nil, "  the target wears nothing")
openOnTarget()
click(STAR[1], STAR[2])
eq(WoW.marks.A, 1, "a click on star: star")
openOnTarget()
click(5, -5)
eq(WoW.raidCalls[#WoW.raidCalls][2], 0, "the centre: cleared")
eq(WoW.marks.A, nil, "  the target wears nothing")

-- Right-click cancels.
local calls = #WoW.raidCalls
openOnTarget()
click(SKULL[1], SKULL[2], "RightButton")
eq(#WoW.raidCalls, calls, "a right-click marks nothing")
check(not M.IsOpen(), "  and closes the wheel")

-- Released outside the disc (inside the button's square): nothing, closed.
openOnTarget()
click(150, 150)
eq(#WoW.raidCalls, calls, "released outside the disc: nothing")
check(not M.IsOpen(), "  and the wheel closes")

-- A click elsewhere on the screen closes it; one on the disc doesn't.
openOnTarget()
at(400, 0)
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
check(not M.IsOpen(), "a click elsewhere closes it")
openOnTarget()
at(SKULL[1], SKULL[2])
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
check(M.IsOpen(), "a click on the disc doesn't")
M.Close("test")

-- An up edge with no down of ours (the click that opened it from a menu).
openOnTarget()
at(SKULL[1], SKULL[2])
WoW.click(button, "LeftButton", false)
eq(#WoW.raidCalls, calls, "a lone release: nothing")
check(M.IsOpen(), "  and the wheel stays open")
M.Close("test")

-- Esc hides the art: the wheel ends with it.
openOnTarget()
local inSpecial = false
for _, name in ipairs(UISpecialFrames) do if name == GP.MarkWheelFrame.NAME then inSpecial = true end end
check(inSpecial, "the art is in UISpecialFrames")
check(UISpecialFrames == WoW.uiSpecialFrames, "  inserted into, never replaced")
GP.MarkWheelFrame._test.frame():Hide()
check(not M.IsOpen(), "Esc closes the wheel")
check(not button:IsShown(), "  and hides the button")

-- The gates.
newChat()
WoW.group = { raid = true, leader = false, assistant = false }
openOnTarget()
check(not M.IsOpen(), "in a raid without lead or assist: refused")
check(chatHas("leader or an assistant"), "  and says why")
WoW.group.assistant = true
openOnTarget()
check(M.IsOpen(), "an assistant may")
M.Close("test")
WoW.group = { raid = true, leader = true, assistant = false }
openOnTarget()
check(M.IsOpen(), "the leader may")
M.Close("test")
WoW.group = { raid = false, leader = false, assistant = false }
WoW.units.target.markable = false
newChat()
openOnTarget()
check(not M.IsOpen(), "a unit that can't be marked: refused")
check(chatHas("can't be marked"), "  and says why")
WoW.units.target.markable = WoW.Secret("CanBeRaidTarget")
openOnTarget()
check(M.IsOpen(), "can't tell if it can be marked: opens (the server decides)")
M.Close("test")
WoW.units.target.markable = nil
WoW.fire("PLAYER_REGEN_DISABLED")
newChat()
openOnTarget()
check(not M.IsOpen(), "in combat: refused")
check(chatHas("Not in combat"), "  and says why")
WoW.fire("PLAYER_REGEN_ENABLED")

-- The panel's Test: on yourself.
check(M.Test(), "Test opens the wheel")
eq(M.state.session.token, "player", "  on yourself")
click(SKULL[1], SKULL[2])
check(WoW.raidCalls[#WoW.raidCalls][1] == "player" and WoW.marks.me == 8, "  and marks you")

-- Off: the key says so; switching off closes an open wheel.
openOnTarget()
P.Set("markwheel", false)
check(not M.IsOpen(), "switched off: the wheel closes")
newChat()
M.OnKey()
check(not M.IsOpen() and chatHas("is off"), "  the key says it's off")
P.Set("markwheel", true)

-- The command.
newChat()
GP.Pearls.Command("markwheel").run("")
check(chatHas("not bound"), "the report: no key yet")
WoW.bindings.GLASSPEARLS_MARKWHEEL = "SHIFT-G"
GP.Pearls.Command("markwheel").run("")
check(chatHas("key SHIFT%-G"), "  then the key")
GP.Pearls.Command("markwheel").run("test")
check(M.IsOpen() and M.state.session.token == "player", "/gpearls markwheel test opens it on you")
M.Close("test")

-- Never SetRaidTarget from our code.
eq(#WoW.forbidden, 0, "SetRaidTarget only ever from Blizzard's secure action")

done("test_markwheel")
