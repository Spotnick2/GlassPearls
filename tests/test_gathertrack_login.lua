-- Gathering tracking (#110) at the edges of a session: a reload (Enable at
-- PLAYER_LOGIN before the registry's Start, PLAYER_ENTERING_WORLD not an
-- initial login) arms nothing; a login while dead waits for the revival.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local HERBS = 2383
local GP = loadAddon({ initialLogin = false, before = function()
    WoW.now = 100
    WoW.known[HERBS] = true
    WoW.tracking = { { name = "Find Herbs", spellID = HERBS, active = false } }
    WoW.trackingEventInside = true     -- the client tells the change
end })
local GT = GP.GatherTrack
local S = GT.state
local function step(dt)
    local n = math.ceil(dt / 0.05 - 1e-9)
    for _ = 1, n do WoW.advance(dt / n) end
end

check(GT.enabled and S.started, "a reload: on, and started")
check(S.arm == nil, "  no arm")
step(10)
eq(#WoW.trackingCalls, 0, "  no call: tracking the player left off stays off")

-- The login's PLAYER_ENTERING_WORLD while dead: the death noted, no arm; the revival arms.
S.loggedIn = false
WoW.dead = true
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(S.died and S.arm == nil, "logged in dead: the death noted, no arm")
step(10)
eq(#WoW.trackingCalls, 0, "  no call while dead")
WoW.dead = false
WoW.fire("PLAYER_UNGHOST")
check(S.arm and S.arm.reason == "revival", "  the revival arms")
step(1.1)
eq(#WoW.trackingCalls, 1, "  and calls")
-- A second initial-login PLAYER_ENTERING_WORLD in the session arms nothing.
WoW.tracking[1].active = false
WoW.trackingCalls = {}
step(5)
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
step(10)
eq(#WoW.trackingCalls, 0, "only the session's first login arms")

done("test_gathertrack_login")
