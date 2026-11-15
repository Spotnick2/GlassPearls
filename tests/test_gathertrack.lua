-- Gathering tracking (#110): the login arm, revival after a death, switching
-- on, the scan (indexes, unreadable entries, kinds not known), permanent
-- satisfaction (a player's off never fought), the gates and the tracking
-- spell's cooldown (no attempt spent), one call in flight and the GCD between
-- two kinds, 3 tries, the deadline, loading screens holding the arm, NodeRadar's
-- experiment, Disable. Codex's traces (three rounds) are marked "Codex".
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local HERBS, ORE = 2383, 2580
local GP = loadAddon({ before = function()
    WoW.now = 100
    WoW.known[HERBS] = true
    WoW.spells[HERBS], WoW.spells[ORE] = { name = "Find Herbs" }, { name = "Find Minerals" }
    WoW.tracking = { { name = "Find Herbs", spellID = HERBS, active = false },
        { name = "Flight Master", active = true } }
end })
local GT, P = GP.GatherTrack, GP.Pearls
local S = GT.state
local KEY = GT.KEY

-- Real time in 0.05 s ticks: WoW.advance moves the clock to the end before firing what fell due.
local function step(dt)
    dt = dt or 0
    if dt <= 0 then WoW.advance(0) return end
    local n = math.ceil(dt / 0.05 - 1e-9)
    for _ = 1, n do WoW.advance(dt / n) end
end
local function calls() local n = #WoW.trackingCalls; WoW.trackingCalls = {}; return n end
local function lastLog() local l = GP.charDB.gathertrack; return l and l[#l] end
local function herbs() for _, t in ipairs(WoW.tracking) do if t.spellID == HERBS then return t end end end
-- The player turns a tracking off (or on) through the minimap's menu.
local function byHand(t, on) t.active = on; WoW.fire("MINIMAP_UPDATE_TRACKING"); step() end
-- A fresh arm: the pearl switched off and on after the login.
local function rearm()
    P.Set(KEY, false)
    P.Set(KEY, true)
end
local function quiet(seconds) step(seconds or 30); calls() end

-- Login: nothing before 3 s, then one call on Find Herbs' entry.
check(S.arm and S.arm.reason == "login", "the login arms")
step(2.9)
eq(calls(), 0, "  nothing before 3 s")
step(0.2)
eq(#WoW.trackingCalls, 1, "  one call at 3 s")
eq(WoW.trackingCalls[1][1], 1, "  on Find Herbs' entry")
eq(WoW.trackingCalls[1][2], true, "  turning it on")
calls()
WoW.fire("MINIMAP_UPDATE_TRACKING")
check(S.arm == nil, "  seen on: the arm is done")
eq(lastLog().outcome, "on", "  logged")
eq(lastLog().reason, "login", "  with its reason")
quiet()

-- A reload's PLAYER_ENTERING_WORLD and an ordinary loading screen arm nothing.
herbs().active = false
WoW.fire("PLAYER_LEAVING_WORLD")
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
step(10)
eq(calls(), 0, "a reload or a zone change: nothing (only a login or a revival)")

-- Switching the pearl on after the login arms it (1 s).
rearm()
check(S.arm and S.arm.reason == "switched", "switching on arms")
step(1.1)
eq(calls(), 1, "  one call after 1 s")
quiet()

-- Already on when armed: satisfied, no call.
rearm()
step(5)
eq(calls(), 0, "already on: no call")
eq(lastLog().outcome, "already on", "  logged so")
quiet()

-- Codex 1: the player turns it off after ours turned it on: never turned back on.
herbs().active = false
WoW.trackingEventInside = true
rearm()
step(1.1)
eq(calls(), 1, "ours turns it on")
check(S.arm == nil, "  seen on at once (the event inside the call)")
byHand(herbs(), false)
step(20)
eq(calls(), 0, "  the player's off afterwards: left off")
WoW.trackingEventInside = false
-- And off by hand during the first delay while it was on at the arm: satisfied at the arm, left off.
herbs().active = true
rearm()
byHand(herbs(), false)
step(20)
eq(calls(), 0, "on at the arm, off by hand before the first step: left off")
-- Seen on through the event before nextAt: satisfied at once (Codex 3, optional).
rearm()
check(S.arm ~= nil and S.arm.kinds.herbs == "pending", "pending")
byHand(herbs(), true)
check(S.arm == nil, "  seen on through the event before the first step: done")
byHand(herbs(), false)
quiet()

-- Codex 2: the tracking spell cooling (the player's own GCD): wait, no attempt spent.
WoW.cooldowns[HERBS] = true
rearm()
step(12)
eq(calls(), 0, "cooling: no call")
eq(S.arm.attempts.herbs, 0, "  no attempt spent")
eq(S.arm.waiting, "cooldown", "  waiting for the cooldown")
WoW.cooldowns[HERBS] = "secret"
step(6)
eq(calls(), 0, "  an unreadable cooldown: still no call")
WoW.cooldowns[HERBS] = nil
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", 133)
step()
eq(calls(), 1, "  ready: called, woken by the cast's end")
quiet()

-- The gates: each one waits, and its end lets the call through.
local gates = {
    { "combat", function() WoW.fire("PLAYER_REGEN_DISABLED") end, function() WoW.fire("PLAYER_REGEN_ENABLED") end },
    { "a cast", function() WoW.casting = "Frostbolt" end, function() WoW.casting = nil end },
    { "an unreadable cast", function() WoW.casting = "secret" end, function() WoW.casting = nil end },
    { "a cast read that throws", function() WoW.casting = "throw" end, function() WoW.casting = nil end },
    { "a channel", function() WoW.channel = { spellID = 5143 } end, function() WoW.channel = nil end },
    { "stealth", function() WoW.stealthed = true end, function() WoW.stealthed = nil end },
    { "a taxi", function() WoW.onTaxi = true end, function() WoW.onTaxi = nil end },
    { "feign death", function() WoW.feign = true end, function() WoW.feign = nil end },
    { "no full control", function() WoW.fullControl = false end, function() WoW.fullControl = nil end },
    { "a vehicle", function() WoW.vehicle = true end, function() WoW.vehicle = nil end },
}
for _, g in ipairs(gates) do
    herbs().active = false
    g[2]()
    rearm()
    step(12)
    eq(calls(), 0, g[1] .. ": no call")
    eq(S.arm and S.arm.attempts.herbs, 0, "  no attempt spent")
    g[3]()
    step(GT.POLL + 0.1)
    eq(calls(), 1, "  once over: called")
    quiet()
end

-- Codex 4: NodeRadar's learning experiment (Learn.Busy) holds it; unreadable holds it too.
local busy = true
rawset(_G, "NodeRadar", { Learn = { Busy = function() if busy == "throw" then error("boom") end return busy end } })
herbs().active = false
rearm()
step(12)
eq(calls(), 0, "NodeRadar experimenting: no call")
eq(S.arm.waiting, "NodeRadar", "  waiting for it")
busy = "throw"
step(6)
eq(calls(), 0, "  its answer unreadable: no call")
busy = false
step(GT.POLL + 0.1)
eq(calls(), 1, "  done: called")
rawset(_G, "NodeRadar", nil)
quiet()

-- Three tries, then it gives up; one call in flight, judged 1.5 s later.
herbs().active = false
WoW.trackingNoEffect = true
rearm()
step(1.1)
eq(calls(), 1, "first try")
step(1.3)
eq(calls(), 0, "  nothing while in flight")
step(0.3)
eq(calls(), 1, "  judged at 1.5 s, the second try (after the GCD)")
step(1.7)
eq(calls(), 1, "  the third, a GCD later")
step(3)
eq(calls(), 0, "  no fourth")
check(S.arm == nil, "  the arm ends")
eq(lastLog().outcome, "gave up after 3", "  logged")
WoW.trackingNoEffect = false
quiet()

-- A call that throws: recorded, the attempt stands.
WoW.trackingRefuses = true
rearm()
step(1.1)
eq(calls(), 1, "a refused call")
check(GP.failures["pearl gathertrack SetTracking"] ~= nil, "  recorded")
eq(S.arm.attempts.herbs, 1, "  the attempt counted")
WoW.trackingRefuses = false
quiet()

-- The indexes are read again at every step.
herbs().active = false
rearm()
table.insert(WoW.tracking, 1, { name = "Innkeeper", active = false })
step(1.1)
eq(WoW.trackingCalls[1] and WoW.trackingCalls[1][1], 2, "an entry inserted before: the call uses the new index")
eq(WoW.tracking[1].active, false, "  the other tracker untouched")
table.remove(WoW.tracking, 1)
quiet()

-- Codex round 2: an unreadable scan never drops a known kind.
herbs().active = false
WoW.trackingThrows[1] = true
rearm()
check(S.arm and S.arm.kinds.herbs == "pending", "an unreadable first scan: still pending")
step(6)
eq(calls(), 0, "  no call while it can't be read")
WoW.trackingThrows[1] = nil
step(GT.POLL + 0.1)
eq(calls(), 1, "  readable again: called")
quiet()
-- The list without the kind while the spell is known (filled late at login): waits for it.
herbs().active = false
local saved = WoW.tracking
WoW.tracking = { { name = "Flight Master", active = true } }
rearm()
step(12)
eq(calls(), 0, "known but no entry yet: no call")
check(S.arm and S.arm.kinds.herbs == "pending", "  still pending")
WoW.tracking = saved
step(GT.POLL + 0.1)
eq(calls(), 1, "  the entry appears: called")
quiet()
-- A secret entry, secret ID, secret active: no call on it.
for _, what in ipairs({ "trackingSecret", "trackingSecretID", "trackingSecretActive" }) do
    herbs().active = false
    WoW[what][1] = true
    rearm()
    step(12)
    eq(calls(), 0, what .. ": no call")
    local _, complete = GT.Scan()
    eq(complete, what == "trackingSecretActive", "  the scan says whether the list read plainly")
    WoW[what][1] = nil
    quiet()
end
-- Not known at all: dropped, nothing called.
herbs().active = false
WoW.known[HERBS] = nil
rearm()
check(S.arm == nil, "a kind plainly not known: no arm")
step(10)
eq(calls(), 0, "  no call")
WoW.known[HERBS] = true
quiet()

-- Two kinds: herbs, then minerals no sooner than the GCD after.
WoW.known[ORE] = true
table.insert(WoW.tracking, { name = "Find Minerals", spellID = ORE, active = false })
herbs().active = false
P.Set(KEY, false)
P.Set(KEY, true)
check(S.arm and S.arm.reason == "switched", "the pearl switched on after the login arms both")
step(1.1)
eq(#WoW.trackingCalls, 1, "  herbs first")
eq(WoW.trackingCalls[1][1], 1, "  its entry")
calls()
WoW.fire("MINIMAP_UPDATE_TRACKING")
step(1.4)
eq(calls(), 0, "  minerals not within the GCD")
step(0.2)
eq(#WoW.trackingCalls, 1, "  then minerals")
eq(WoW.trackingCalls[1][1], 3, "  its entry")
quiet()
table.remove(WoW.tracking, 3)
WoW.known[ORE] = nil

-- A death, then the revival: release (PLAYER_ALIVE as a ghost) arms nothing; the corpse does.
herbs().active = false
WoW.dead = true
WoW.fire("PLAYER_DEAD")
check(S.died and S.arm == nil, "a death: noted, no arm")
WoW.fire("PLAYER_ALIVE")
step(5)
eq(calls(), 0, "  released as a ghost: nothing")
WoW.dead = false
WoW.fire("PLAYER_UNGHOST")
check(S.arm and S.arm.reason == "revival", "  back at the corpse: armed")
step(1.1)
eq(calls(), 1, "  and called")
quiet()
-- A death during an arm ends it; a resurrection (PLAYER_ALIVE alive) arms again.
herbs().active = false
rearm()
WoW.dead = true
WoW.fire("PLAYER_DEAD")
step(5)
eq(calls(), 0, "a death mid-arm: nothing")
check(S.arm == nil, "  the arm ended")
WoW.dead = false                        -- alive, but no revival event yet: nothing acts
WoW.fire("UNIT_AURA", "player")
step(GT.POLL + 1)
eq(calls(), 0, "  alive with no revival event: still nothing")
WoW.dead = false
WoW.fire("PLAYER_ALIVE")
step(1.1)
eq(calls(), 1, "  resurrected: called")
quiet()

-- Codex 3: a loading screen holds the arm; nothing runs during it, whatever wakes.
herbs().active = false
WoW.dead = true
WoW.fire("PLAYER_DEAD")
WoW.dead = false
WoW.fire("PLAYER_ALIVE")
WoW.fire("PLAYER_LEAVING_WORLD")
step(5)
WoW.fire("UNIT_AURA", "player")
WoW.fire("PLAYER_REGEN_ENABLED")
herbs().active = true
WoW.fire("MINIMAP_UPDATE_TRACKING")
step(5)
eq(calls(), 0, "loading: no call, whatever wakes")
check(S.arm and S.arm.kinds.herbs == "pending", "  and nothing marked while loading")
-- Every entry point holds while loading, called directly too (Codex 3).
GT.Observe(GT.Scan())
check(S.arm and S.arm.kinds.herbs == "pending", "  an observation while loading marks nothing")
herbs().active = false
S.nextAt = 0
GT.Step()
eq(calls(), 0, "  a step called while loading: no call")
herbs().active = false
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
step(0.1)
eq(calls(), 1, "  the world back: the revival's arm resumes")
quiet()
-- Death, loading, then alive on entering the world: the revival is read on PLAYER_ENTERING_WORLD.
herbs().active = false
WoW.dead = true
WoW.fire("PLAYER_DEAD")
WoW.fire("PLAYER_LEAVING_WORLD")
WoW.dead = false
WoW.fire("PLAYER_ALIVE")                -- during the loading screen: arms, but runs nothing
step(5)
eq(calls(), 0, "revived during a loading screen: nothing yet")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
step(1.1)
eq(calls(), 1, "  after it: called")
quiet()
-- An unreadable alive read keeps the death for the next event.
herbs().active = false
WoW.dead = true
WoW.fire("PLAYER_DEAD")
WoW.dead = false
WoW.deadSecret = true
WoW.fire("PLAYER_UNGHOST")
check(S.died and S.arm == nil, "an unreadable revival: the death kept, no arm")
WoW.deadSecret = nil
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
step(1.1)
eq(calls(), 1, "  read plainly later: called")
quiet()

-- The deadline: still waiting after 10 minutes, dropped.
herbs().active = false
WoW.stealthed = true
rearm()
step(GT.DEADLINE + 10)
check(S.arm == nil, "10 minutes waiting: dropped")
eq(lastLog().outcome, "dropped after waiting", "  logged")
WoW.stealthed = nil
step(10)
eq(calls(), 0, "  nothing after")

-- Disable ends everything; Enable while dead arms nothing.
rearm()
P.Set(KEY, false)
step(10)
eq(calls(), 0, "switched off mid-arm: nothing")
WoW.dead = true
P.Set(KEY, true)
check(S.arm == nil, "switched on while dead: no arm")
WoW.dead = false

-- The log keeps 10; the report prints without errors.
for i = 1, 12 do rearm(); step(1.1); WoW.fire("MINIMAP_UPDATE_TRACKING"); herbs().active = false end
eq(#GP.charDB.gathertrack, GT.LOG_MAX, "the log keeps the last 10")
newChat()
SlashCmdList.GLASSPEARLS("gathertrack")
local said = table.concat(newChat(), "\n")
check(said:find("Find Herbs: entry 1, spell 2383", 1, true), "the report: " .. said)

done("test_gathertrack")
