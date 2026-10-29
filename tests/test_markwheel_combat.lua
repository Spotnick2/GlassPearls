-- The raid mark wheel and combat (#34). Inside PLAYER_REGEN_DISABLED the
-- lockdown hasn't started (porting guide): the wheel closes and its secure
-- button is hidden there. Once locked, nothing protected is touched; what
-- couldn't be done is done when combat ends, even if the pearl was switched
-- off meanwhile. A click on the disc survives GLOBAL_MOUSE_DOWN in either
-- order.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local M, P = GP.MarkWheel, GP.Pearls

local function at(dx, dy) WoW.mouse = { x = 500 + dx, y = 400 + dy } end
WoW.units.mouseover = { id = "A", guid = "Creature-0-1-A" }
WoW.units.target = WoW.units.mouseover
local function open()
    at(0, 0)
    M.OnKey()
    return M._test.button()
end

-- Combat starts: closed inside PLAYER_REGEN_DISABLED, before the lockdown.
local b = open()
b:SetAttribute("type", "raidtarget")   -- as if armed
WoW.fire("PLAYER_REGEN_DISABLED")
check(GP.API.InCombat(), "PLAYER_REGEN_DISABLED: in combat for the pearls")
check(not InCombatLockdown(), "  but no lockdown yet")
check(not M.IsOpen(), "the wheel closes")
check(not b:IsShown(), "  the button is hidden")
eq(b:GetAttribute("type"), nil, "  and disarmed")
eq(#WoW.blocked, 0, "  nothing refused")
eq(M.state.pendingCleanup, false, "  nothing left for later")
WoW.combat = true
newChat()
M.OnKey()
check(not M.IsOpen() and chatHas("Not in combat"), "the key in combat: refused")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")

-- Already locked (the cleanup window missed): Esc closes the art; nothing
-- protected is touched; combat's end finishes the job.
b = open()
WoW.combat = true
GP.MarkWheelFrame._test.frame():Hide()
check(not M.IsOpen(), "locked, Esc: the wheel's session ends")
eq(#WoW.blocked, 0, "  no protected call made")
check(M.state.pendingCleanup, "  the cleanup waits")
check(b:IsShown(), "  the button stays (the client wouldn't hide it)")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not b:IsShown(), "combat over: the button is hidden")
eq(b:GetAttribute("type"), nil, "  and disarmed")
eq(M.state.pendingCleanup, false, "  done")

-- Locked mid-click: the release arms nothing and PostClick writes nothing.
b = open()
local before = #WoW.raidCalls
at(0, 100)
WoW.click(b, "LeftButton", true)
WoW.combat = true
WoW.click(b, "LeftButton", false)
eq(#WoW.raidCalls, before, "locked before the release: no mark")
eq(#WoW.blocked, 0, "  no protected call made")
check(not M.IsOpen(), "  the session ends")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not b:IsShown(), "  the button hidden when combat ends")

-- Switched off while locked: the cleanup still happens.
b = open()
WoW.combat = true
P.Set("markwheel", false)
check(not M.IsOpen(), "switched off in combat: closed")
eq(#WoW.blocked, 0, "  no protected call made")
check(b:IsShown(), "  the button waits")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not b:IsShown(), "combat over, pearl off: the button is hidden anyway")
P.Set("markwheel", true)

-- GLOBAL_MOUSE_DOWN before or after the button's own down edge: a click on
-- the disc still marks.
b = open()
at(0, 100)
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
eq(WoW.marks.A, 8, "GLOBAL_MOUSE_DOWN first: skull")
b = open()
at(0, 100)
WoW.click(b, "LeftButton", true)
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
WoW.click(b, "LeftButton", false)
eq(WoW.marks.A, nil, "GLOBAL_MOUSE_DOWN after the down edge: skull again, removed")
eq(#WoW.raidCalls, before + 2, "  two marks in all")

eq(#WoW.forbidden, 0, "SetRaidTarget only ever from Blizzard's secure action")
done("test_markwheel_combat")
