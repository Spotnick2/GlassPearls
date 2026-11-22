-- Camp timers (#149): the sleeping bag's presence, `entered` and the one
-- anchoring rule, unresolved reads and the shared retry, 3/3, the countdown's
-- digits and sounds, the campfire, settings, the generation, AA.Read's two new
-- returns, and every trace of the plan's eight Codex rounds.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.spells[429959] = { name = "Ausgeruht", icon = 132802 }        -- the client's own names (German)
WoW.spells[1229739] = { name = "Einladendes Lagerfeuer", icon = 135805 }
local GP = loadAddon()
local C, P, CF, AA = GP.Camp, GP.Pearls, GP.CampFrame, GP.AuraAlert
local TRACK, RESTED, FIRE, BENEFITS = 429960, 429959, 1229739, 1229741

check(P.IsLive("camp"), "on by default")
eq(P.Get("camp").category, "Interface", "on the Interface page")
eq(P.Get("camp").section, "Timers", "  in Timers")
for _, k in ipairs({ "bag", "campfire", "countdown", "sound" }) do
    eq(P.Setting("camp", k), true, "  " .. k .. " on by default")
end

-- Driving: auras, a UNIT_AURA (its payload secret: never read), a frame.
local function track(id) WoW.auras[TRACK] = { expirationTime = 0, duration = 0, auraInstanceID = id } end
local function rested(n, app, noTime)
    if n == nil then WoW.auras[RESTED] = nil return end
    WoW.auras[RESTED] = { expirationTime = noTime and 0 or app + 7200, duration = noTime and 0 or 7200,
                          applications = n }
end
local function at(t) WoW.now = t end
local function aura() WoW.fire("UNIT_AURA", "player", WoW.Secret("info")); WoW.advance(0) end
local function frame(dt) WoW.tick(dt or 0.06) end
local function rows()
    local f = CF._test.frame()
    local out = {}
    if not (f and f:IsShown()) then return out end
    for _, r in ipairs(f.rows) do if r:IsShown() then out[#out + 1] = r end end
    return out
end
local function bag() local r = rows()[1]; return r and r.view and r.view.kind == "bag" and r or nil end
local function played(kit)
    local n = 0
    for _, s in ipairs(WoW.soundsPlayed) do if s[1] == kit then n = n + 1 end end
    return n
end
local function clear()
    WoW.auras[TRACK], WoW.auras[RESTED], WoW.auras[FIRE], WoW.auras[BENEFITS] = nil, nil, nil, nil
    WoW.spellAuraSecret[TRACK], WoW.spellAuraSecret[RESTED] = nil, nil
    aura()
end
local TICK, FINISH = 158565, 158566

--------------------------------------------------------------------------------
-- One uninterrupted rest: entered, three stacks, the countdown, 3/3.
at(0); aura()
eq(#rows(), 0, "nothing to show outside a bag")
track(11); aura()
local r = bag()
check(r ~= nil, "lying down: the bag's bar")
eq(r.label:GetText(), "Ausgeruht 0/3", "  the client's name and the stacks")
eq(r.time:GetText(), "1:00", "  the first stack a minute after lying down")
at(30); frame()
eq(bag().time:GetText(), "0:30", "  counting")
at(60); rested(1, 60); aura()
eq(bag().label:GetText(), "Ausgeruht 1/3", "the first stack")
eq(bag().time:GetText(), "1:00", "  re-anchored on its own application time")
at(110); frame()
eq(CF.DigitText(), nil, "  one stack: the next is the second, no countdown")
at(120); rested(2, 120); aura()
eq(bag().label:GetText(), "Ausgeruht 2/3", "the second stack")
local ticks = played(TICK)
at(169.9); frame(0.06)
eq(CF.DigitText(), nil, "no digit before the last 10 s")
at(170); frame(0.06)
eq(CF.DigitText(), "10", "10 s before the third stack: 10")
eq(played(TICK), ticks + 1, "  one tick")
at(170.5); frame(0.06)
eq(played(TICK), ticks + 1, "  the same digit: no second tick")
at(171.1); frame(0.06)
eq(CF.DigitText(), "9", "  9")
at(176.0); frame(0.06)    -- a stall from 9 to 4 (3.94 s left)
eq(CF.DigitText(), "4", "  a stall shows the current digit")
eq(played(TICK), ticks + 3, "  and ticks it once")
at(180.01); frame(0.06)
eq(CF.DigitText(), nil, "zero: the digit clears")
eq(played(TICK), ticks + 3, "  silently")
eq(played(FINISH), 0, "  no finish before the read shows it")
at(180.2); rested(3, 180); aura()
eq(GP.Notice.Text(), "Ausgeruht 3/3", "the third stack read: 3/3")
eq(played(FINISH), 1, "  the finish sound")
eq(bag(), nil, "  the bag's bar goes (full)")
at(240); rested(3, 240); aura()
eq(played(FINISH), 1, "  said once")
clear()
-- The third stack and leaving the bag in one check: still 3/3.
at(500); aura(); track(15); rested(2, 490); aura()
at(560); WoW.auras[TRACK] = nil; rested(3, 560); aura()
eq(played(FINISH), 2, "the third stack and leaving in one check: still finished")
eq(bag(), nil, "  the bar gone")
clear()

--------------------------------------------------------------------------------
-- Already at 3/3 with an hour gone (the owner, 2026-11-21): the next tick puts it
-- back to its full 2 h, so that is what the bar and the countdown aim at.
at(1000); track(21); rested(3, 1000 - 3600); aura()
r = bag()
check(r ~= nil, "lying down at 3/3 with an hour gone: the bar")
eq(r.label:GetText(), "Ausgeruht 3/3", "  the stacks")
eq(r.time:GetText(), "1:00", "  the refresh a minute after lying down")
at(1050); frame()
eq(CF.DigitText(), "10", "  counted down")
eq(played(FINISH), 2, "  nothing said yet")
at(1060.2); rested(3, 1060); aura()
eq(played(FINISH), 3, "the refresh read: 3/3, full")
eq(bag(), nil, "  the bar goes")
eq(CF.DigitText(), nil, "  and the digit")
at(1120); rested(3, 1120); aura()
eq(played(FINISH), 3, "  the next refresh: said once")
eq(bag(), nil, "  no bar")
clear()
-- A reload at 3/3: waiting (its application is from before), the refresh fills it.
at(1500); track(22); rested(3, 1490)
P.Set("camp", false); P.Set("camp", true)
eq(bag().time:GetText(), "...", "a reload at 3/3: waiting")
at(1500.4); rested(3, 1500.4); aura()
eq(played(FINISH), 3, "  an application inside the margin: not full")
at(1550); rested(3, 1550); aura()
eq(played(FINISH), 4, "  the next refresh: full")
eq(bag(), nil, "  the bar gone")
clear()
-- 3 stacks with no readable count: never full, the bar stays.
at(1700); aura(); track(23); rested(nil, nil)
WoW.auras[RESTED] = { expirationTime = 1700 + 3600, duration = 7200 }
aura()
at(1760); WoW.auras[RESTED] = { expirationTime = 1760 + 7200, duration = 7200 }; aura()
eq(played(FINISH), 4, "no count: never full")
check(bag() ~= nil, "  the bar stays")
clear()

-- Reload mid-rest (Enable with the tracking aura on): waiting, then a stack anchors.
at(2000); track(31); rested(1, 1990)
P.Set("camp", false); P.Set("camp", true)
r = bag()
eq(r.time:GetText(), "...", "after a reload: waiting, no time")
eq(r.label:GetText(), "Ausgeruht 1/3", "  the stacks known")
at(2050); rested(2, 2050); aura()
eq(bag().time:GetText(), "1:00", "  the next stack after the reload anchors")
clear()

-- Reload with Well-Rested plainly absent: its first stack anchors (round 2).
at(2500); track(32)
P.Set("camp", false); P.Set("camp", true)
eq(bag().time:GetText(), "...", "reload, Well-Rested absent: waiting")
at(2530); rested(1, 2530); aura()
eq(bag().time:GetText(), "1:00", "  its first stack (witnessed absent -> present) anchors")
clear()

-- An application before the presence never anchors.
at(3000); track(41); rested(1, 2990)
P.Set("camp", false); P.Set("camp", true)
at(3005); aura()
eq(bag().time:GetText(), "...", "an application from before: no anchor")
clear()

--------------------------------------------------------------------------------
-- Two visits: an instance ID change, A -> nil -> B, PLAYER_ENTERING_WORLD.
at(4000); aura(); track(51); rested(2, 3990); aura()     -- entered at 4000, with 2 old stacks
eq(bag().time:GetText(), "1:00", "entered with two stacks")
at(4049); track(52); aura()                           -- left and back between two checks
eq(bag().time:GetText(), "1:00", "a new instance ID: a new visit, entered now")
at(4050); frame()
eq(CF.DigitText(), nil, "  the old deadline gone: no digit at 4050")
at(4099); frame()
eq(CF.DigitText(), "10", "  the new one counts down at 4099")
clear()
CF.Digit(nil)
at(5000); aura(); track(61); rested(2, 4990); aura()
at(5049); track(nil); aura()                           -- A -> nil
eq(bag().time:GetText(), "...", "an instance ID unreadable after a readable one: a new presence, waiting")
at(5049.5); track(62); aura()                          -- nil -> B: can't date it
at(5050); frame()
eq(CF.DigitText(), nil, "  A -> nil -> B: no digit at 50")
eq(bag().time:GetText(), "...", "  still waiting")
clear()
at(5500); aura(); track(nil); aura()
eq(bag().time:GetText(), "1:00", "IDs never readable: entered from the absent before")
at(5510); aura()
eq(bag().time:GetText(), "0:50", "  and the presence continues (no ID to compare)")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(bag().time:GetText(), "...", "a loading screen: a new presence, phase unknown")
clear()

--------------------------------------------------------------------------------
-- Lost: the tracking aura unknown hides the bar at once and retries.
at(6000); aura(); track(71); rested(1, 5990); aura()
WoW.auras[TRACK] = WoW.Secret("aura")
aura()
eq(bag(), nil, "the tracking aura unknown: the bar hides at once")
track(71)
WoW.advance(1)
r = bag()
check(r ~= nil, "  the retry a second later finds it again")
eq(r.time:GetText(), "...", "  as a new presence: waiting")
clear()

-- 2 -> unreadable -> 3 with no event: the retry finishes it once.
local finishes = played(FINISH)
at(7000); aura(); track(81); rested(2, 6990); aura()
at(7060); WoW.auras[RESTED] = WoW.Secret("aura"); aura()
eq(CF.DigitText(), nil, "Well-Rested unreadable: no countdown")
rested(3, 7060)
WoW.advance(1)
eq(played(FINISH), finishes + 1, "2 -> unreadable -> 3: one finish, from the retry")
WoW.advance(1); aura()
eq(played(FINISH), finishes + 1, "  only one")
clear()

-- Round 3: 1 at 60, unreadable at 120, 2 read at 121 with time 120: anchor 120.
at(8000); aura(); track(91); aura()
at(8060); rested(1, 8060); aura()
at(8120); WoW.auras[RESTED] = WoW.Secret("aura"); aura()
at(8121); rested(2, 8120); WoW.advance(0); WoW.flushTimers()
eq(bag().time:GetText(), "0:59", "round 3: the retry's time 120 anchors")
at(8170); frame()
eq(CF.DigitText(), "10", "  the first digit at 170")
clear()

-- Round 4: absent at 0, unknown through 60 and 120, 2 at 145 with no duration: waiting;
-- the retry at 146 with time 120 restores 180.
at(9000); aura(); track(101); aura()
WoW.spellAuraSecret[RESTED] = true
at(9060); aura(); at(9120); aura()
WoW.spellAuraSecret[RESTED] = nil
at(9145); rested(2, nil, true); aura()
eq(bag().time:GetText(), "...", "round 4: a witnessed application without a time: waiting")
at(9146); rested(2, 9120); WoW.advance(0); WoW.flushTimers()
eq(bag().time:GetText(), "0:34", "  the retry's time 120 restores 180")
clear()

-- Round 5: 1 at 60 (time 60), 2 at 120 with no duration: waiting, retry; 121 with time 120.
at(10000); aura(); track(111); aura()
at(10060); rested(1, 10060); aura()
at(10120); rested(2, nil, true); aura()
eq(bag().time:GetText(), "...", "round 5: a count rise without a time: waiting")
check(#WoW.timers > 0, "  a retry pending")
at(10121); rested(2, 10120); WoW.flushTimers()
eq(bag().time:GetText(), "0:59", "  the retry's time 120 restores 180")
at(10170); frame()
eq(CF.DigitText(), "10", "  digit 10 at 170")
clear()

-- Round 6: a reload at 100, 1 stack with no duration through 119, 2 at 120 with none, time 120 at 121.
at(11100); track(121); rested(1, nil, true)
P.Set("camp", false); P.Set("camp", true)
at(11110); aura()
at(11120); rested(2, nil, true); aura()
at(11121); rested(2, 11120); WoW.flushTimers()
eq(bag().time:GetText(), "0:59", "round 6: the deadline 180")
clear()

-- Round 7: a reload at 119.75 with 1 stack, 2 at 120 with no time, time 120 at 121 (inside the margin).
at(12119.75); track(131); rested(1, 12060)
P.Set("camp", false); P.Set("camp", true)
at(12120); rested(2, nil, true); aura()
at(12121); rested(2, 12120); WoW.flushTimers()
at(12170); frame()
eq(CF.DigitText(), "10", "round 7: a witnessed rise anchors inside the margin: digit 10 at 170")
clear()
CF.Digit(nil)
-- ... and the rise with its time in the same read.
at(13119.75); track(141); rested(1, 13060)
P.Set("camp", false); P.Set("camp", true)
at(13120); rested(2, 13120); aura()
at(13170); frame()
eq(CF.DigitText(), "10", "round 8: the rise and its time in one read: digit 10 at 170")
clear()
CF.Digit(nil)

--------------------------------------------------------------------------------
-- The countdown's guards: Well-Rested expiring before the tick, overdue.
at(14000); aura(); track(151); WoW.auras[RESTED] = { expirationTime = 14062, duration = 7200, applications = 2 }
aura()
at(14055); frame()
eq(CF.DigitText(), nil, "two stacks that end before the tick: no countdown (it would give stack 1)")
clear()
at(15000); aura(); track(161); aura()
at(15063.1); frame()
eq(bag().time:GetText(), "...", "overdue by more than 3 s: waiting")
clear()

-- Settings mid-countdown.
at(16000); aura(); track(171); rested(2, 15990); aura()
at(16052); frame()
eq(CF.DigitText(), "8", "counting down")
P.SetSetting("camp", "countdown", false)
eq(CF.DigitText(), nil, "countdown off: the digit goes at once")
P.SetSetting("camp", "countdown", true)
P.SetSetting("camp", "sound", false)
ticks = played(TICK)
at(16053.1); frame()
eq(CF.DigitText(), "7", "sound off: the digits go on")
eq(played(TICK), ticks, "  silently")
P.SetSetting("camp", "sound", true)
P.SetSetting("camp", "bag", false)
eq(bag(), nil, "bag off: its bar goes")
eq(CF.DigitText(), nil, "  and its countdown")
P.SetSetting("camp", "bag", true)
clear()

--------------------------------------------------------------------------------
-- Sounds: a refused kit falls back and the one that plays is kept; both refused is recorded.
C.state.kits = {}
WoW.soundRefused[TICK] = true
eq(C.Play("tick"), true, "the newer tick refused: the older one plays")
eq(C.state.kits.tick, 25477, "  and is kept")
WoW.soundRefused[25477] = true
eq(C.Play("tick"), false, "both refused: nothing plays")
check(GP.failures["camp sound tick"] ~= nil, "  recorded")
WoW.soundRefused[TICK], WoW.soundRefused[25477] = nil, nil
eq(C.Play("tick"), true, "  a later tick tries again")
eq(C.state.kits.tick, TICK, "  the newer one, when it plays")

--------------------------------------------------------------------------------
-- The campfire.
at(17000); WoW.auras[FIRE] = { expirationTime = 17060, duration = 60 }; aura()
r = rows()[1]
eq(r and r.view.kind, "camp", "the campfire's bar")
eq(r.label:GetText(), "Einladendes Lagerfeuer", "  the client's name")
eq(r.time:GetText(), "1:00", "  the time to its benefits")
at(17055); WoW.auras[FIRE] = WoW.Secret("aura"); aura()
eq(rows()[1].time:GetText(), "0:05", "  unknown: the last plain time kept")
at(17060.1); frame()
eq(#rows(), 0, "  its time over: gone")
at(17100); WoW.auras[FIRE] = { expirationTime = 17160, duration = 60 }; aura()
P.SetSetting("camp", "campfire", false)
eq(#rows(), 0, "campfire off: its bar goes")
P.SetSetting("camp", "campfire", true)
WoW.auras[FIRE] = nil; aura()
eq(#rows(), 0, "plainly absent: gone")

-- While you sit it comes back; once it gave the benefits, what follows is a refresh.
local function fire(app) WoW.auras[FIRE] = { expirationTime = app + 60, duration = 60 } end
local function benefits(app) WoW.auras[BENEFITS] = { expirationTime = app + 3600, duration = 3600 } end
at(17200); fire(17200); benefits(17000 - 1800); aura()
eq(#rows(), 1, "old benefits: the campfire's bar")
at(17260); fire(17260); benefits(17260); aura()
eq(#rows(), 0, "the benefits given with the next campfire: no bar")
WoW.auras[BENEFITS] = WoW.Secret("aura"); aura()
eq(#rows(), 0, "  the benefits unknown: the last plain one kept")
WoW.auras[BENEFITS] = nil; aura()
eq(#rows(), 1, "  plainly absent: the bar again")
at(17320); fire(17320); benefits(17318.5); aura()
eq(#rows(), 0, "the benefits a moment before the campfire: given")
at(17380); fire(17380); benefits(17377.5); aura()
eq(#rows(), 1, "  more than 2 s before: not this campfire's")
at(17381); benefits(17381); aura()
eq(#rows(), 0, "the benefits a second after the campfire: given")
WoW.auras[FIRE], WoW.auras[BENEFITS] = nil, nil; aura()

--------------------------------------------------------------------------------
-- The generation: disable then re-enable before a queued check fires.
local checks = 0
local real = C.Check
C.Check = function() checks = checks + 1; return real() end
WoW.fire("UNIT_AURA", "player")
P.Set("camp", false)
P.Set("camp", true)
checks = 0
WoW.advance(0)
eq(checks, 0, "a check queued before a disable and re-enable does nothing")
WoW.fire("UNIT_AURA", "player"); WoW.advance(0)
eq(checks, 1, "  and a new UNIT_AURA queues again")
C.Check = real

-- Off: nothing registered, nothing shown.
at(18000); track(181); rested(1, 17990)
P.Set("camp", false)
aura()
eq(#rows(), 0, "off: no bar")
check(not C._test.events:IsEventRegistered("PLAYER_ENTERING_WORLD"), "  its events unregistered")
P.Set("camp", true)
clear()

--------------------------------------------------------------------------------
-- AA.Read's new returns, each read apart (a throwing field spoils nothing).
local function throwing(key, base)
    return setmetatable(base, { __index = function(_, k) if k == key then error("boom") end end })
end
WoW.auras[RESTED] = throwing("applications", { expirationTime = 50, duration = 40, auraInstanceID = 7 })
local res, exp, dur, src, count, inst = AA.Read(RESTED)
eq(res, "present", "a throwing count: still present")
eq(exp, 50, "  the expiration kept"); eq(dur, 40, "  the duration kept")
eq(count, nil, "  the count nil"); eq(inst, 7, "  the instance ID kept")
WoW.auras[RESTED] = throwing("auraInstanceID", { expirationTime = 50, duration = 40, applications = 2 })
res, exp, dur, src, count, inst = AA.Read(RESTED)
eq(res, "present", "a throwing instance ID: still present")
eq(count, 2, "  the count kept"); eq(inst, nil, "  the instance ID nil")
WoW.auras[RESTED] = { expirationTime = 50, duration = 40, applications = WoW.Secret("n"), auraInstanceID = 2.5 }
res, exp, dur, src, count, inst = AA.Read(RESTED)
eq(count, nil, "a secret count: nil"); eq(inst, nil, "an odd instance ID: nil")
WoW.auras[RESTED] = nil

--------------------------------------------------------------------------------
-- Commands: the report, the test.
newChat()
SlashCmdList.GLASSPEARLS("camp")
check(chatHas("429960"), "/gpearls camp: the tracking aura's read")
check(chatHas("Not in a sleeping bag"), "  the bag's state")
at(19000)
SlashCmdList.GLASSPEARLS("camp test")
eq(#rows(), 2, "/gpearls camp test: both bars")
check(CF._test.frame():IsMouseEnabled(), "  draggable during the test")
ticks = played(TICK)
at(19010); frame()
eq(CF.DigitText(), "10", "  the digits at its end")
eq(played(TICK), ticks, "  without a sound")
WoW.advance(10.1)
eq(#rows(), 0, "  gone after 20 s")
check(not CF._test.frame():IsMouseEnabled(), "  click-through again")

done("test_camp")
