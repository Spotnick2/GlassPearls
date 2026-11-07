-- The stars' interact CVars claimed like NodeRadar's marker (#90): the login
-- settle window; the on and off edges (a reload isn't one); a value already at
-- ours is the player's; someone else's change cancels until off and on;
-- combat blocks writes, not judgments; refused, throwing and unreadable
-- writes; the gamepad UI and easy fishing's temps mask a name; the logout
-- put-back and the next login's decision; a corrupt store. Codex's traces
-- from the four plan rounds are marked (rN).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local IA, RANGE, ICON = "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetIconGameObject"
-- The client's defaults; the first two are secure (measured 2026-11-06), so easy fishing never holds them.
WoW.cvarValues[IA], WoW.cvarValues[RANGE], WoW.cvarValues[ICON] = "1", "10", "0"
WoW.cvarValues.SoftTargetInteractArc, WoW.cvarValues.SoftTargetIconInteract = "1", "0"
WoW.cvarInfo[IA], WoW.cvarInfo[RANGE] = { secure = true }, { secure = true }
WoW.known[7620] = true

local GP = loadAddon()
local ST, P, F = GP.SparkleStars, GP.Pearls, GP.Fishing

-- A read-back made unreadable: GetCVar throws for that name after its next SetCVar.
-- setAs[name]: the next SetCVar of that name lands as another value (someone else's change racing ours).
local unreadableAfterSet, setAs = {}, {}
local realSet = C_CVar.SetCVar
C_CVar.SetCVar = function(name, value)
    local r = { realSet(name, value) }
    if setAs[name] then WoW.cvarValues[name] = setAs[name]; setAs[name] = nil end
    if unreadableAfterSet[name] then WoW.cvarRefuse[name] = "throwRead"; unreadableAfterSet[name] = nil end
    return unpack(r)
end
local function readable(name) WoW.cvarRefuse[name] = nil end

local function pass() WoW.tick(ST.TICK + 0.01) end
local function saved(n) return WoW.cvarValues[n] end
local function store() return ST._test.store() end
local function rec(n) return store().soft[n] end
local function st(n) local r = rec(n); return r and r.st end
local function stars(mode) P.SetSetting("sparkle", "stars", mode) end
local function combat(on) WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED") end
local function sets(name)
    local n = 0
    for _, s in ipairs(WoW.cvarSets) do if s[1] == name then n = n + 1 end end
    return n
end
local function defaults() WoW.cvarValues[IA], WoW.cvarValues[RANGE], WoW.cvarValues[ICON] = "1", "10", "0" end
local function lines() return table.concat(ST.Lines(), "\n") end
-- A new session (a reload or a login): the module's memory gone, the saved store kept.
local function session()
    ST.state.settleAt, ST.state.loggingOut, ST.state.notes = nil, false, {}
    WoW.fire("PLAYER_ENTERING_WORLD", false, true)
end
local function settle() WoW.now = (WoW.now or 0) + ST.SETTLE + 1; pass() end

check(ST.state.started, "Start ran at login")

--------------------------------------------------------------------------------
-- The settle window, the first claim

P.Set("sparkle", true)
stars("quest")
pass()
eq(sets(IA) + sets(RANGE) + sets(ICON), 0, "inside the login window: nothing written")
check(lines():find("the settings wait: the login settling", 1, true), "  the report says why")
check(store().softPending[IA] and store().softPending[ICON], "  the first claims pending")
settle()
eq(saved(IA) .. "," .. saved(RANGE) .. "," .. saved(ICON), "3,60,1", "settled: the three set, saved values (SetCVar)")
eq(st(IA) .. st(RANGE) .. st(ICON), "ownedownedowned", "  each owned")
eq(rec(RANGE).old, "10", "  the player's value kept")
check(next(store().softPending) == nil, "  nothing pending")
eq(store().softActive, true, "  the activation saved")
eq(#WoW.tempCalls, 0, "  no temp CVar at all")
check(lines():find("SoftTargetInteractRange: 60 now, 60 wanted, ours (yours was 10).", 1, true), "  the report")

-- quest <-> all isn't an edge.
local before = #WoW.cvarSets
stars("all")
pass()
eq(#WoW.cvarSets, before, "quest -> all: nothing written")

--------------------------------------------------------------------------------
-- The off edge, and a value already at ours

stars("off")
eq(saved(IA) .. "," .. saved(RANGE) .. "," .. saved(ICON), "1,10,0", "stars off: put back at once")
check(next(store().soft) == nil and store().softActive == nil, "  nothing left, the activation cleared")
check(ST._test.driver._scripts.OnUpdate == nil and not ST.state.active, "  the passes and the listeners stop")

WoW.cvarValues[IA] = "3"                       -- the player's (or NodeRadar's) already
stars("quest")
eq(st(IA), nil, "already at ours: not claimed")
check(lines():find("SoftTargetInteract: 3 now, 3 wanted, yours, already at ours.", 1, true), "  the report says yours")
eq(st(RANGE), "owned", "  the others claimed")
stars("off")
eq(saved(IA), "3", "  never put back")
defaults()

--------------------------------------------------------------------------------
-- Someone else's change while on: cancelled, theirs stands, until off and on

stars("quest")
WoW.cvarValues[RANGE] = "30"
pass()
eq(st(RANGE), "cancelled", "changed by someone else: cancelled")
pass()
eq(st(RANGE), "cancelled", "  kept on the next passes")
check(lines():find("changed since: yours stands", 1, true), "  the report")
pass()
eq(saved(RANGE), "30", "  never written again while on")
stars("off")
eq(saved(RANGE), "30", "off: theirs left as it is")
eq(rec(RANGE), nil, "  the cancellation forgotten")
stars("quest")
eq(saved(RANGE), "60", "off and on: claimed again")
eq(rec(RANGE).old, "30", "  from their value")
stars("off")
eq(saved(RANGE), "30", "  and put back to it")
defaults()

--------------------------------------------------------------------------------
-- Combat blocks writes, not judgments

combat(true)
stars("quest")
pass()
eq(saved(IA), "1", "turned on in combat: nothing written")
combat(false)
eq(saved(IA), "3", "  written after combat")
combat(true)
WoW.cvarValues[RANGE] = "25"
pass()
eq(st(RANGE), "cancelled", "changed in combat: cancelled in combat (r1: a later login can't take it for ours)")
combat(false)
stars("off")
eq(saved(RANGE), "25", "  theirs stands")
defaults()

stars("quest")
combat(true)
stars("off")
pass()
eq(saved(IA), "3", "off in combat: put back after the fight")
eq(st(IA), "release", "  waiting to put back")
check(ST._test.driver._scripts.OnUpdate ~= nil, "  the passes kept")
combat(false)
eq(saved(IA), "1", "  put back after combat")

stars("quest")
combat(true)
local n = sets(IA)
stars("off")
stars("quest")
eq(st(IA), "owned", "off and on inside a fight: retained, read at once as still ours: owned again")
eq(sets(IA), n, "  nothing written")
combat(false)
eq(sets(IA), n, "  nothing written after the fight")

combat(true)
stars("off")
stars("quest")
WoW.cvarValues[RANGE] = "2"
pass()
eq(st(RANGE), "cancelled", "off, on, then changed by someone else, all in combat: cancelled (r2)")
combat(false)
eq(saved(RANGE), "2", "  never overwritten after the fight")
stars("off")
defaults()

--------------------------------------------------------------------------------
-- Refused, throwing and unreadable writes

stars("quest")
WoW.cvarRefuse[RANGE] = false                  -- SetCVar returns false and changes nothing
stars("off")
eq(saved(RANGE), "60", "a refused put-back: ours still there")
eq(st(RANGE), "release", "  kept to retry (r2)")
pass()
eq(st(RANGE), "release", "  still refused: still kept")
WoW.cvarRefuse[RANGE] = nil
pass()
eq(saved(RANGE), "10", "  the next pass once it works: put back")
eq(rec(RANGE), nil, "  done")

WoW.cvarRefuse[RANGE] = false
stars("quest")
eq(rec(RANGE), nil, "a refused first claim: nothing recorded")
check(lines():find("the set didn't take", 1, true), "  the report says so")
n = sets(RANGE)
pass()
eq(store().softPending[RANGE], nil, "  resolved: not retried this activation")
WoW.cvarRefuse[RANGE] = "throw"
stars("off")
stars("quest")
check(lines():find("SoftTargetInteractRange: 10 now, 60 wanted, the set threw.", 1, true), "a throwing set: said")
check(GP.failures["pearl sparkle stars SoftTargetInteractRange"] ~= nil, "  recorded")
GP.failures["pearl sparkle stars SoftTargetInteractRange"] = nil
WoW.cvarRefuse[RANGE] = nil
stars("off")
setAs[RANGE] = "33"
stars("quest")
eq(rec(RANGE), nil, "a first claim read back as a third value: someone else's, nothing recorded")
check(lines():find("changed meanwhile", 1, true), "  said")
stars("off")
eq(saved(RANGE), "33", "  left as it is")
defaults()
stars("quest")
stars("off")
check(not lines():find("changed meanwhile", 1, true), "  a new activation forgets the last one's notes")

-- A first claim whose read-back is unreadable: unconfirmed, then decided (r1).
unreadableAfterSet[ICON] = true
stars("quest")
eq(st(ICON), "unconfirmed", "a set read back unreadable: unconfirmed, the old value kept")
eq(rec(ICON).old, "0", "  old kept")
check(lines():find("ours, not confirmed yet (yours was 0)", 1, true), "  the report")
stars("off")
eq(st(ICON), "release", "  off before it's decided: to put back")
pass()
eq(saved(ICON), "1", "  unreadable: nothing written")
readable(ICON)
pass()
eq(saved(ICON), "0", "  readable: put back")
eq(rec(ICON), nil, "  done")

unreadableAfterSet[ICON] = true
stars("quest")
readable(ICON)
pass()
eq(st(ICON), "owned", "unconfirmed then read as ours: owned")
stars("off")

unreadableAfterSet[ICON], WoW.cvarRefuse[ICON] = true, false
stars("quest")
eq(st(ICON), "unconfirmed", "a refused set read back unreadable: unconfirmed")
WoW.cvarRefuse[ICON] = nil                     -- readable again: it reads the old value
pass()
eq(st(ICON), "cancelled", "  then read as the old value: cancelled, nothing written")
eq(saved(ICON), "0", "  the player's value")
stars("off")
eq(rec(ICON), nil, "  forgotten at off")
defaults()

-- A put-back that worked but read back unreadable, then on again (r3).
stars("quest")
unreadableAfterSet[IA] = true
stars("off")
eq(saved(IA), "1", "a put-back made, its read-back unreadable")
eq(st(IA), "release", "  kept")
stars("quest")
eq(st(IA), "retained", "on again: retained (the put-back may have happened)")
readable(IA)
pass()
eq(saved(IA), "3", "  read as the old value: ours applied again in this activation")
eq(st(IA), "owned", "  owned")
unreadableAfterSet[IA] = true
stars("off")
combat(true)
stars("quest")
readable(IA)
pass()
eq(saved(IA), "1", "  the same with combat: nothing written in the fight")
combat(false)
eq(saved(IA), "3", "  applied after it")
unreadableAfterSet[IA] = true
stars("off")
stars("quest")
readable(IA)
unreadableAfterSet[IA] = true
pass()
eq(st(IA), "unconfirmed", "  applied again with an unreadable read-back: unconfirmed")
readable(IA)
pass()
eq(st(IA), "owned", "  then owned")
unreadableAfterSet[IA] = true
stars("off")
stars("quest")
readable(IA)
setAs[IA] = "2"
pass()
eq(st(IA), "cancelled", "  applied again, read back as a third value: cancelled")
eq(saved(IA), "2", "  theirs")
stars("off")
defaults()

--------------------------------------------------------------------------------
-- The gamepad UI masks every name

stars("quest")
WoW.inputStyle = 1
WoW.tempCVars[IA], WoW.tempCVars[RANGE], WoW.tempCVars[ICON] = "3", "60", "0"   -- Blizzard_Gamepad's temps
WoW.cvarValues[RANGE] = "45"                   -- the saved value changed underneath
pass()
eq(st(RANGE), "owned", "in the gamepad UI: nothing judged")
check(lines():find("waiting: the gamepad UI", 1, true), "  the report says why")
stars("off")
pass()
eq(saved(IA), "3", "  off in the gamepad UI: nothing put back yet")
WoW.tempCVars[IA], WoW.tempCVars[RANGE], WoW.tempCVars[ICON] = nil, nil, nil
WoW.inputStyle = 0
pass()
eq(saved(IA), "1", "back to mouse and keyboard: put back")
eq(saved(RANGE), "45", "  the one changed meanwhile left as it is")
eq(rec(RANGE), nil, "  and given up")
defaults()

WoW.inputStyle = 1
stars("quest")
pass()
eq(saved(IA), "1", "turned on in the gamepad UI: pending")
WoW.inputStyle = 0
pass()
eq(saved(IA), "3", "  claimed once out of it")
stars("off")

--------------------------------------------------------------------------------
-- Easy fishing's temp masks its name (only the icon: the other two are secure)

stars("quest")
local function fish(on)
    WoW.channel = on and { id = 7620 } or nil
    WoW.fire(on and "UNIT_SPELLCAST_CHANNEL_START" or "UNIT_SPELLCAST_CHANNEL_STOP", "player", "C", 7620)
end
fish(true)
check(F.state.held[ICON] ~= nil and F.state.held[IA] == nil, "fishing holds the icon, never the secure two")
WoW.cvarValues[ICON] = "0"                     -- the saved value changed under fishing's temp
fish(false)                                    -- the whole session between two passes (r2)
pass()
eq(st(ICON), "cancelled", "its temp gone: the saved value judged, someone else's: cancelled")
stars("off")
defaults()

fish(true)
stars("quest")
pass()
eq(rec(ICON), nil, "turned on while fishing holds the icon: its claim waits")
check(store().softPending[ICON], "  still pending")
check(lines():find("waiting: easy fishing", 1, true), "  the report says why")
eq(st(IA), "owned", "  the others claimed")
fish(false)
pass()
eq(st(ICON), "owned", "  fishing over: claimed")
stars("off")
defaults()

--------------------------------------------------------------------------------
-- Logout and the next login (r1, r3)

stars("quest")
WoW.fire("PLAYER_LOGOUT")
eq(saved(IA) .. "," .. saved(RANGE) .. "," .. saved(ICON), "1,10,0", "logout: ours put back")
eq(st(IA), "retained", "  the records kept, retained")
pass()
eq(saved(IA), "1", "  no pass while logging out")
session()
pass()
eq(saved(IA), "1", "next login, inside the window: nothing")
settle()
eq(saved(IA) .. "," .. saved(RANGE) .. "," .. saved(ICON), "3,60,1", "  settled: ours applied again")
eq(st(IA), "owned", "  owned")

WoW.fire("PLAYER_LOGOUT")
session()
WoW.cvarValues[RANGE] = "40"                   -- changed while we weren't loaded
settle()
eq(st(RANGE), "cancelled", "a value changed while unloaded: someone else's")
eq(saved(RANGE), "40", "  left as it is")
stars("off")
defaults()

stars("quest")
unreadableAfterSet[IA] = true
WoW.fire("PLAYER_LOGOUT")
eq(st(IA), "retained", "a logout put-back read back unreadable: retained (r3)")
readable(IA)
session()
settle()
eq(saved(IA), "3", "  next login: applied again")
WoW.cvarRefuse[IA] = false
unreadableAfterSet[IA] = true
WoW.fire("PLAYER_LOGOUT")
eq(st(IA), "retained", "a refused logout put-back read back unreadable: retained")
WoW.cvarRefuse[IA] = nil
session()
settle()
eq(st(IA), "owned", "  next login, still ours: owned, nothing written")

-- An early exit inside the window writes nothing (r3).
session()
WoW.fire("PLAYER_LOGOUT")
eq(saved(IA), "3", "a logout before the window ends: nothing put back")
eq(st(IA), "owned", "  the record as it was")
session()
settle()
combat(true)
WoW.fire("PLAYER_LOGOUT")
eq(saved(IA), "3", "a logout in combat: nothing put back")
combat(false)
session()
settle()
WoW.inputStyle = 1
WoW.fire("PLAYER_LOGOUT")
eq(saved(IA), "3", "a logout in the gamepad UI: nothing put back (masked)")
WoW.inputStyle = 0
session()
settle()
-- A loading screen later doesn't open the window again.
WoW.cvarValues[RANGE] = "60"
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
WoW.cvarValues[RANGE] = "41"
pass()
eq(st(RANGE), "cancelled", "a later loading screen: still settled, judged at once")
stars("off")
stars("quest")

-- Retained at a login where the stars are no longer wanted.
WoW.fire("PLAYER_LOGOUT")
session()
P.Set("sparkle", false)
settle()
eq(rec(IA), nil, "retained, the stars off at login, reading the old value: dropped, nothing written")
eq(saved(IA), "1", "  the player's")
P.Set("sparkle", true)
stars("quest")
settle()
WoW.cvarRefuse[IA] = false
WoW.fire("PLAYER_LOGOUT")
WoW.cvarRefuse[IA] = nil
eq(st(IA), "owned", "a refused logout put-back read back as ours: as it was")
WoW.cvarRefuse[IA] = false
unreadableAfterSet[IA] = true
WoW.fire("PLAYER_LOGOUT")
WoW.cvarRefuse[IA] = nil
session()
P.Set("sparkle", false)
eq(st(IA), "retained", "retained (refused, unreadable) with the stars off at login")
settle()
eq(st(IA), "release", "  read as ours: to put back")
pass()
eq(saved(IA), "1", "  and put back on the next pass")
eq(rec(IA), nil, "  done")
P.Set("sparkle", true)
settle()
WoW.cvarRefuse[IA] = false
WoW.fire("PLAYER_LOGOUT")
WoW.cvarRefuse[IA] = nil
session()
P.Set("sparkle", false)
eq(st(IA), "release", "  the stars off: to put back")
settle()
eq(saved(IA), "1", "  put back once settled")
P.Set("sparkle", true)
stars("off")
defaults()

-- A reload with the activation saved and nothing claimed isn't a turn-on.
stars("quest")
local s = store()
s.soft = {}
WoW.cvarValues[IA], WoW.cvarValues[RANGE], WoW.cvarValues[ICON] = "1", "10", "0"
session()
settle()
eq(saved(IA), "1", "a reload with the activation saved and no claim: nothing claimed")
stars("off")

--------------------------------------------------------------------------------
-- A corrupt store

s = store()
s.soft = { [IA] = "junk", [RANGE] = { st = "owned" }, [ICON] = { st = "weird", old = "0", ours = "1" } }
check(next(store().soft) == nil, "corrupt records dropped")

done("test_sparkle_claims")
