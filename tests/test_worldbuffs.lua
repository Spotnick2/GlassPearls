-- World buff announcer (#104): hearing a speaker by (event, NPC ID) only, the
-- window (one warning, a fixed bound checked by time, suppression after
-- receipt), receipt (absent -> present, a readable refresh, never across an
-- unknown read or from 0), baselines, combat, the window-less buff (Might of
-- Stormwind) and its quiet gap, the switches (sync included), sounds, leaving
-- the world, Disable, the day-one log and ring.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local WB, P = GP.WorldBuffs, GP.Pearls
local S = WB._test.state
local KEY = WB.KEY

WoW.now = 1000
for _, b in ipairs(WB.BUFFS) do WoW.spells[b.ids[1]] = { name = b.fallback } end
local function step(dt) WoW.advance(dt or 0) end
local function guid(npc, kind) return ("%s-0-5250-0-12-%d-00002A3B4C"):format(kind or "Creature", npc) end
-- A line by `npc`; the text, the name and the language are secrets that throw if touched.
local function line(event, npc, g)
    WoW.fire(event == "say" and "CHAT_MSG_MONSTER_SAY" or "CHAT_MSG_MONSTER_YELL",
        WoW.Secret("text"), WoW.Secret("name"), WoW.Secret("language"), "", "", "", 0, 0, "", 0, 7,
        g or guid(npc))
    step()
end
local function aura(id, exp)
    WoW.auras[id] = exp and { expirationTime = exp, duration = 7200 } or nil
    WoW.fire("UNIT_AURA", "player")
    step()
end
local function unreadable(id)
    WoW.auras[id] = WoW.Secret("aura")
    WoW.fire("UNIT_AURA", "player")
    step()
end
local function said() return #newChat() end
local function sounds() local n = #WoW.soundsPlayed; WoW.soundsPlayed = {}; return n end
local function lastLog() local log = GP.db.worldbuffs.log; return log[#log] end
local function clean()
    for id in pairs(WoW.auras) do WoW.auras[id] = nil end
    WoW.spellAuraSecret = {}
    for k in pairs(S.quiet) do S.quiet[k] = nil end
    WoW.fire("PLAYER_LEAVING_WORLD")
    WoW.fire("PLAYER_ENTERING_WORLD", false, false)
    step()
    newChat()
    sounds()
end
clean()

-- The GUID: creatures and vehicles, nothing else, plain only.
eq(WB.NpcID(guid(14392)), 14392, "a creature's NPC ID")
eq(WB.NpcID(guid(14392, "Vehicle")), 14392, "a vehicle's")
eq(WB.NpcID("Player-5250-0A1B2C3D"), nil, "a player: none")
eq(WB.NpcID(guid(14392, "Pet")), nil, "a pet: none")
eq(WB.NpcID("Creature-0-1-2-3-x-ABC"), nil, "malformed: none")
eq(WB.NpcID(WoW.Secret("guid")), nil, "a secret: none, untouched")
eq(WB.NpcID(nil), nil, "missing: none")
eq(WB.NpcID(14392), nil, "a number: none")

-- Every listed speaker is an (event, NPC) pair of one buff.
for _, b in ipairs(WB.BUFFS) do
    check(#b.ids >= 2, b.key .. " has its spell IDs")
    eq(P.Setting(KEY, b.key), true, b.key .. " is on by default")
end
eq(P.Setting(KEY, "sound"), true, "the sound is on by default")

-- A yell from Orgrimmar's Onyxia herald: one warning, chat, centre text, the yell sound.
line("yell", 14392)
local chat = newChat()
eq(#chat, 1, "the first line: one chat line")
check(chat[1] and chat[1]:find("Rallying Cry of the Dragonslayer may drop in about 14 s.", 1, true),
    "  \"may drop in about 14 s\"")
eq(GP.Notice.Text(), "Rallying Cry of the Dragonslayer may drop in about 14 s.", "  the centre text")
eq(WoW.soundsPlayed[1] and WoW.soundsPlayed[1][1], WB.SOUND_WARN, "  the yell sound")
eq(WoW.soundsPlayed[1] and WoW.soundsPlayed[1][2], "Master", "  on the Master channel")
sounds()
check(WB.Window("dragonslayer") ~= nil, "  its window is open")

-- Its next lines (and the other dragonslayer speakers) inside the window: ignored.
line("yell", 14392)
line("yell", 14720)
eq(said(), 0, "later lines inside the window: no second warning")
eq(sounds(), 0, "  and no sound")
-- Pairs that aren't listed: nothing.
line("say", 14392)
line("yell", 14875)
line("say", 4949)
eq(said(), 0, "the herald's say, Molthor's yell, Thrall's say: unlisted pairs, nothing")
check(WB.Window("zandalar") == nil and WB.Window("rend") == nil, "  no window opened")

-- The buff lands: "is on you", the drop sound, the log.
step(12)
aura(355363, WoW.now + 7200)
chat = newChat()
eq(#chat, 1, "the buff lands inside the window: one line")
check(chat[1] and chat[1]:find("Rallying Cry of the Dragonslayer is on you.", 1, true), "  \"is on you\"")
eq(WoW.soundsPlayed[1] and WoW.soundsPlayed[1][1], WB.SOUND_DROP, "  the drop sound")
sounds()
local e = lastLog()
eq(e.outcome, "received", "  logged as received")
eq(e.spell, 355363, "  with the spell ID that landed")
eq(e.npc, 14392, "  the NPC")
eq(e.event, "yell", "  the event")
eq(e.after, 12, "  and the seconds after the line")
-- Receipt doesn't close the window: the turn-in's next line stays quiet.
line("yell", 14392)
eq(said(), 0, "a line after receipt, inside the bound: no new warning")
-- Another of its IDs appearing inside the same window: not announced twice.
aura(1304452, WoW.now + 7200)
eq(said(), 0, "another ID inside a window already received: once per window")

-- The bound passes (14 + 20 s from the line): the window closes itself.
step(30)
check(WB.Window("dragonslayer") == nil, "the bound passed: the window is closed")
eq(said(), 0, "  silently")

-- A refresh: the same ID present again with an expiration 60 s+ later, inside a new window.
line("yell", 14394)
newChat()
sounds()
aura(355363, WoW.now + 7200 - 20)       -- moved less than REFRESH (it was set 30 s ago): not a refresh
eq(said(), 0, "an expiration moved by under 60 s: not a refresh")
step(5)
aura(355363, WoW.now + 7200 + 100)
eq(said(), 1, "an expiration 60 s+ later: a refresh, announced")
step(40)

-- Across an unknown read, a later expiration proves nothing.
clean()
aura(22888, WoW.now + 1000)
line("yell", 14720)
newChat()
unreadable(22888)
aura(22888, WoW.now + 7200)
eq(said(), 0, "present -> unknown -> present later: not a refresh")
step(40)
-- From 0 (no expiration), a positive one is not a refresh.
clean()
aura(22888, 0)
line("yell", 14720)
newChat()
aura(22888, WoW.now + 7200)
eq(said(), 0, "an expiration of 0 then a real one: not a refresh")
step(40)

-- Outside a window (#106: its line unheard): "is on you" all the same, once per QUIET s, and logged.
clean()
line("yell", 0, WoW.Secret("guid"))     -- Thrall's yell, its sender unreadable
step(3)
aura(16609, WoW.now + 3600)
chat = newChat()
eq(#chat, 1, "Warchief's Blessing with no window: said once")
check(chat[1] and chat[1]:find("Warchief's Blessing is on you.", 1, true), "  is on you")
eq(sounds(), 1, "  with its sound")
e = lastLog()
eq(e.outcome, "nowindow", "  logged without a window")
eq(e.lines and e.lines[1] and e.lines[1].why, "secret", "  with the unreadable line before it, and why")
eq(e.lines[1].npc, nil, "  no NPC for it")
eq(e.lines[1].before, 3, "  and how long before")
aura(16609, nil)
aura(355366, WoW.now + 3600)
eq(said(), 0, "again within 10 minutes: quiet")
step(WB.QUIET)
aura(355366, nil)
aura(16609, WoW.now + 3600)
eq(said(), 1, "after 10 minutes: said again")
-- A window's announcement starts the quiet gap too: a late copy isn't said twice.
clean()
line("yell", 4949)
newChat()
aura(16609, WoW.now + 3600)
eq(said(), 1, "inside the window: said")
step(30)                                -- the window has closed
aura(16609, nil)
aura(1304594, WoW.now + 3600)
eq(said(), 0, "  another copy after the window, within 10 minutes: quiet")
eq(lastLog().outcome, "nowindow", "  but logged")
-- Switched off: logged, not said.
clean()
P.SetSetting(KEY, "rend", false)
aura(16609, WoW.now + 3600)
eq(said(), 0, "a buff switched off, no window: nothing said")
eq(lastLog().outcome, "nowindow", "  but logged")
P.SetSetting(KEY, "rend", true)

-- Rend: about 6 s; the bound is 6 + 20.
clean()
line("yell", 4949)
check(newChat()[1]:find("Warchief's Blessing may drop in about 6 s.", 1, true), "Thrall: about 6 s")
step(25)
check(WB.Window("rend") ~= nil, "  still open at 25 s")
step(1)
check(WB.Window("rend") == nil, "  closed at 26 s")
eq(lastLog().outcome, "unconfirmed", "  nothing received: logged unconfirmed, nothing said")
eq(said(), 0, "  silently")

-- The bound is checked by time, whatever the timer did.
clean()
line("yell", 10719)
newChat()
local first = S.windows.rend
WoW.now = WoW.now + 27                  -- the clock moves, no timer runs
WoW.fire("CHAT_MSG_MONSTER_YELL", "", "", "", "", "", "", 0, 0, "", 0, 7, guid(10719))
eq(said(), 1, "past the bound with its timer not run yet: a new line opens a new window")
check(S.windows.rend ~= first, "  a new one")
step()                                  -- now the old timer runs
check(WB.Window("rend") ~= nil and S.windows.rend ~= first, "  the old window's timer leaves the new one alone")
step(30)

-- Zandalar: the emissary's yell and Molthor's say.
clean()
line("yell", 15076)
check(newChat()[1]:find("Spirit of Zandalar may drop in 30-50 s.", 1, true), "the emissary: in 30-50 s")
line("say", 14875)
eq(said(), 0, "  Molthor's say inside the window: ignored")
step(80)
line("say", 14875)
check(newChat()[1]:find("Spirit of Zandalar may drop in about 50 s.", 1, true), "Molthor's say alone: about 50 s")
step(80)

-- Might of Stormwind: no speaker mapped, announced without a window, once per 10 minutes.
clean()
line("say", 466)                        -- an unlisted NPC: only the ring keeps it
step(4)
aura(460939, WoW.now + 3600)
chat = newChat()
check(chat[1] and chat[1]:find("Might of Stormwind is on you.", 1, true), "Might of Stormwind, no window: announced")
e = lastLog()
eq(e.outcome, "nowindow", "  logged without a window")
eq(e.lines and e.lines[1] and e.lines[1].npc, 466, "  with the line heard before (the ring)")
eq(e.lines and e.lines[1] and e.lines[1].before, 4, "  and how long before")
eq(e.lines[1].event, "say", "  and its event")
aura(460939, nil)
aura(1304678, WoW.now + 3600)
eq(said(), 0, "again within 10 minutes: quiet")
aura(1304678, nil)
step(WB.QUIET)
aura(460940, WoW.now + 3600)
eq(said(), 1, "after 10 minutes: said again")
-- The ring: at most 8 lines, none older than 90 s.
clean()
for i = 1, 10 do line("yell", 100 + i) end
eq(#S.ring, WB.RING_MAX, "the ring keeps the last 8 lines")
eq(S.ring[1].npc, 103, "  the oldest dropped")
step(WB.RING_AGE + 1)
line("yell", 200)
aura(460939, WoW.now + 3600)
eq(#lastLog().lines, 1, "lines older than 90 s aren't copied")
WoW.fire("PLAYER_LEAVING_WORLD")
eq(#S.ring, 0, "leaving the world clears the ring")

-- Baselines: a buff present at a loading screen or reload is never announced.
clean()
WoW.auras[22888] = { expirationTime = WoW.now + 5000, duration = 7200 }
line("yell", 14392)
newChat()
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
step()
eq(said(), 0, "a baseline with the buff present: silent")
step(40)
-- An unknown baseline never establishes absence.
clean()
WoW.spellAuraSecret[22888] = true
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
step()
line("yell", 14392)
newChat()
WoW.spellAuraSecret[22888] = nil
aura(22888, WoW.now + 7200)
eq(said(), 0, "unknown at the baseline, then present: not announced")
step(40)

-- Combat: no reads; the baseline at its end absorbs what landed.
clean()
line("yell", 14392)
newChat()
WoW.fire("PLAYER_REGEN_DISABLED")
local reads = WoW.auraReads[22888] or 0
aura(22888, WoW.now + 7200)
eq(WoW.auraReads[22888] or 0, reads, "in combat: no aura read")
WoW.fire("PLAYER_REGEN_ENABLED")
step()
eq(said(), 0, "landed in combat: absorbed by the baseline at its end")
step(40)

-- A secret GUID: counted, nothing else.
clean()
local before = S.counts.unreadable
line("yell", 0, WoW.Secret("guid"))
eq(S.counts.unreadable, before + 1, "a secret GUID: counted as unreadable")
eq(said(), 0, "  nothing said")
line("yell", 0, "Player-5250-0A1B2C3D")
eq(S.counts.unreadable, before + 2, "a player's GUID: unreadable too")
eq(S.ring[#S.ring - 1].why, "secret", "  the ring keeps the secret one's why")
eq(S.ring[#S.ring].why, "Player", "  and the player's kind, never the GUID")
eq(WB.Unreadable(nil), "missing", "why: missing")
eq(WB.Unreadable(7), "not a string", "why: not a string")
eq(WB.Unreadable(""), "empty", "why: empty")
eq(WB.Unreadable("Creature-0-1-2-3-x-ABC"), "malformed", "why: a creature's malformed GUID")
eq(WB.Unreadable("Pet-0-1-2-3-4-5"), "Pet", "why: a pet")

-- Leaving the world closes the windows.
clean()
line("yell", 14392)
newChat()
WoW.fire("PLAYER_LEAVING_WORLD")
check(WB.Window("dragonslayer") == nil, "leaving the world closes the window")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
step()
aura(22888, WoW.now + 7200)
eq(lastLog().outcome, "nowindow", "  so a later buff is window-less")

-- A buff switched off: its lines ignored; switching it off mid-window cancels it.
clean()
P.SetSetting(KEY, "rend", false)
line("yell", 4949)
eq(said(), 0, "rend off: Thrall's line ignored")
P.SetSetting(KEY, "rend", true)
line("yell", 4949)
newChat()
P.SetSetting(KEY, "rend", false)
check(WB.Window("rend") == nil, "switched off mid-window: the window is cancelled")
aura(16609, WoW.now + 3600)
eq(said(), 0, "  and the buff landing says nothing")
P.SetSetting(KEY, "rend", true)
step(40)
-- A switch read off at receipt, however it got there (written behind the pearl's back): nothing said.
clean()
line("yell", 4949)
newChat()
GP.db.settings[KEY] = GP.db.settings[KEY] or {}
GP.db.settings[KEY].rend = false
aura(16609, WoW.now + 3600)
eq(said(), 0, "the switch reads off at receipt: nothing said")
eq(lastLog().outcome, "received", "  still logged")
GP.db.settings[KEY].rend = nil
step(40)

-- The sound switch.
clean()
P.SetSetting(KEY, "sound", false)
line("yell", 14392)
step(5)
aura(22888, WoW.now + 7200)
eq(said(), 2, "sound off: the warning and the receipt are still said")
eq(sounds(), 0, "  without a sound")
P.SetSetting(KEY, "sound", true)
step(40)

-- Two buffs, two windows.
clean()
line("yell", 14392)
line("yell", 4949)
eq(said(), 2, "two buffs' speakers: two warnings")
aura(16609, WoW.now + 3600)
aura(22888, WoW.now + 7200)
eq(said(), 2, "  and two receipts")
step(40)

-- The log keeps 10.
for _ = 1, 12 do line("yell", 4949); step(30) end
eq(#GP.db.worldbuffs.log, WB.LOG_MAX, "the log keeps the last 10")

-- The report and the test.
clean()
P.Command("worldbuffs").run("")
check(chatHas("World buffs: on;") and chatHas("unconfirmed"), "/gpearls worldbuffs: the switches and the log")
newChat()
P.Command("worldbuffs").run("test")
step(3)
check(chatHas("may drop in about 14 s") and chatHas("is on you"), "/gpearls worldbuffs test: both examples")

-- Disable: nothing heard or read.
clean()
P.Set(KEY, false)
line("yell", 14392)
aura(22888, WoW.now + 7200)
eq(said(), 0, "switched off: nothing")
check(WB.Window("dragonslayer") == nil, "  no window")

done("test_worldbuffs")
