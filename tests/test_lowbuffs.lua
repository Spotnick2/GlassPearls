-- Low-rank buffs (#42): the data, the rule (the downrank cap by your level,
-- the grace, trainer ranks only), the caster's checks (GUID identity, the
-- sticky level rise, minLevel), detection (uninitialized / absent / present,
-- baselines, generations, never in combat) and the chat line. The whisper is
-- test_lowbuffs_whisper.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local LB, P = GP.LowBuffs, GP.Pearls
local D = GlassPearls.SpellRankData
local function tick() WoW.flushTimers(0) end

local PWF = { 1243, 1244, 1245, 2791, 10937, 10938 }      -- Power Word: Fortitude, ranks 1-6
WoW.spells[1245] = { name = "Power Word: Fortitude" }
WoW.spells[2791] = { name = "Power Word: Fortitude" }
WoW.spells[10937] = { name = "Power Word: Fortitude" }

local n = 0
local function caster(token, opts)
    opts = opts or {}
    n = n + 1
    WoW.units[token] = { id = opts.id or ("C" .. n), guid = opts.guid or ("Player-1-" .. (opts.id or ("C" .. n))) }
    WoW.players[token] = true
    WoW.unitLevels[token] = opts.level or 60
    WoW.unitClasses[token] = opts.class or "PRIEST"
    WoW.fullNames[token] = opts.name or "Kaelith Dawnsong"
end
-- A buff from `token` lands (or is taken away with nil).
local function buff(id, token)
    WoW.auras[id] = token and { expirationTime = 0, duration = 1800, sourceUnit = token } or nil
    WoW.fire("UNIT_AURA", "player")
    tick()
end
local function said() return #newChat() end
-- Reads of the watched IDs only: other pearls read their own auras.
local function reads()
    local t = 0
    for id in pairs(LB.watched) do t = t + (WoW.auraReads[id] or 0) end
    return t
end
local function fresh()
    for id in pairs(LB.watched) do WoW.auras[id] = nil end
    WoW.fire("PLAYER_ENTERING_WORLD", false, false)
    tick()
    newChat()
end

-- The data: positional triples, and every watched group with trainer ranks.
local r = D.ranks[10937]
check(r[2] == 5 and r[3] == 48, "ranks[id] is { group, rank, level }: Fortitude rank 5, level 48")
local groups = 0
for g, ids in pairs(LB.groups) do
    groups = groups + 1
    check(#ids >= 2, "watched group " .. g .. " has several ranks")
end
eq(groups, #LB.WATCH, "every watched ID makes a group")
for _, id in ipairs(LB.WATCH) do
    eq(D.groups[D.ranks[id][1]][1], id, "watched " .. id .. " is its group's first rank")
end
eq(LB.TrainerRanks("DEATHKNIGHT"), nil, "a class the trainer data doesn't know: no ranks")
for _, class in ipairs({ "PRIEST", "MAGE", "DRUID", "PALADIN" }) do
    check(LB.TrainerRanks(class) ~= nil, class .. "'s trainer ranks are known")
end

-- The rule, a level-60 priest's Fortitude, by your level.
local g = D.ranks[1243][1]
local function expected(my, casterLevel, class)
    local id = LB.Expected(g, class or "PRIEST", casterLevel or 60, my)
    return id and LB.watched[id].rank
end
eq(expected(37), 4, "you at 37: rank 4 (level 36) lands")
eq(expected(38), 5, "you at 38: rank 5 (level 48)")
eq(expected(49), 5, "you at 49: rank 5")
eq(expected(50), 6, "you at 50: rank 6 (level 60)")
-- The grace.
eq(LB.Grace(5), 0, "grace below 10: 0")
eq(LB.Grace(15), 3, "10-19: 3")
eq(LB.Grace(30), 2, "20-49: 2")
eq(LB.Grace(49), 2, "  49: 2")
eq(LB.Grace(50), 1, "50-59: 1")
eq(LB.Grace(59), 1, "  59: 1")
eq(LB.Grace(60), 0, "60: 0")
eq(expected(60, 59), 5, "a caster at 59 (grace 1): rank 5 expected, not rank 6")
eq(expected(60, 49), 4, "a caster at 49 (grace 2, cap 47): rank 4")
eq(expected(60, 14), 1, "a caster at 14 (grace 3, cap 11): rank 1, not rank 2 (level 12)")
eq(expected(60, 15), 2, "  at 15 (cap 12): rank 2")
-- Book ranks are never expected: Blessing of Might's trainer top is 19838.
local might = D.ranks[19740][1]
local mightTop = LB.Expected(might, "PALADIN", 60, 60)
eq(mightTop, 19838, "Blessing of Might: the trainer's 19838, never the book's 25291")
eq(LB.Expected(g, "DEATHKNIGHT", 60, 60), nil, "a class the trainer data doesn't know: nothing expected")
eq(LB.Expected(g, "WARRIOR", 60, 60), nil, "a class that doesn't teach it: nothing expected")
local ds = LB.Expected(D.ranks[14752][1], "PRIEST", 60, 60)
eq(ds and LB.watched[ds].rank, 4, "Divine Spirit: rank 4 at 60")
local sp = LB.Expected(D.ranks[976][1], "PRIEST", 60, 60)
eq(sp and LB.watched[sp].rank, 3, "Shadow Protection: rank 3 at 60")

-- Detection and the line.
WoW.playerLevel = 60
fresh()
caster("party1")
buff(10937, "party1")
local lines = newChat()
eq(#lines, 1, "a rank-5 Fortitude from a 60 on a 60: said")
check(lines[1] and lines[1]:find("Kaelith Dawnsong's Power Word: Fortitude is rank 5; rank 6 is theirs at level 60.", 1, true),
    "  the line: the full name, the client's spell name, the ranks")
buff(10937, nil)
buff(10937, "party1")
eq(said(), 0, "the same caster and buff again: once per session")
caster("party2", { id = "C2b" })
buff(10937, nil)
buff(10937, "party2")
eq(said(), 1, "another caster (another GUID), same first name: said for them too")
WoW.units.target = { id = "C2b", guid = WoW.units.party2.guid }
WoW.players.target, WoW.unitLevels.target, WoW.unitClasses.target = true, 60, "PRIEST"
buff(10937, nil)
buff(10937, "target")
eq(said(), 0, "the same GUID through another token: the same caster")
-- The right rank: nothing.
fresh()
caster("party1")
buff(10938, "party1")
eq(said(), 0, "rank 6 from a 60: nothing")
-- The downrank cap: you at 37 get rank 4 from a 60.
fresh()
WoW.playerLevel = 37
caster("party1")
buff(2791, "party1")
eq(said(), 0, "you at 37, rank 4 from a 60: the game's rule, nothing")
caster("party1")
buff(2791, nil)
buff(1245, "party1")
eq(said(), 1, "  rank 3 though: said")
WoW.playerLevel = 60

-- The caster's checks.
local function judged(setup, id)
    fresh()
    caster("party1")
    setup()
    buff(id or 10937, "party1")
    return said() > 0
end
check(not judged(function() WoW.players.party1 = false end), "not a player (a pet, an NPC): not judged")
check(not judged(function() WoW.players.party1 = WoW.Secret("isPlayer") end), "UnitIsPlayer secret: not judged")
check(not judged(function() WoW.units.party1.id = "me" end), "yourself through another token: not judged")
check(not judged(function() WoW.units.party1.guid = WoW.Secret("guid") end), "a secret GUID: not judged")
check(not judged(function() WoW.unitLevels.party1 = WoW.Secret("level") end), "a secret level: not judged")
check(not judged(function() WoW.unitLevels.party1 = 0 end), "level 0 (unknown): not judged")
check(not judged(function() WoW.unitClasses.party1 = WoW.Secret("class") end), "a secret class: not judged")
check(not judged(function() WoW.unitClasses.party1 = "DEATHKNIGHT" end), "a class the data doesn't know: not judged")
check(judged(function() end, 2791), "a 60's rank 4 (rank 5 expected, and more): judged")
check(not judged(function() WoW.unitLevels.party1 = 59 end, 2791), "a caster at 59 (minLevel 60), rank 4 where 5 is theirs: not judged")
check(not judged(function() WoW.unitIsUnitSecret = true end), "UnitIsUnit secret: not judged")
WoW.unitIsUnitSecret = nil
check(not judged(function() WoW.playerLevel = WoW.Secret("mine") end), "your level secret: not judged")
WoW.playerLevel = 60
P.SetSetting("lowbuffs", "minLevel", 50)
check(judged(function() WoW.unitLevels.party1 = 55 end, 2791), "minLevel 50: a 55's rank 4 is judged (rank 5 expected)")
P.ResetSettings("lowbuffs")
check(judged(function() WoW.fullNames.party1 = WoW.Secret("name") end), "a secret name: still said, as someone")
fresh()
caster("party1", { name = "" })
buff(10937, "party1")
check(chatHas("Someone's Power Word: Fortitude is rank 5"), "an empty name: Someone")
-- A level that can't be told (-1) is never recorded as a level.
fresh()
caster("party4", { id = "Q", level = -1 })
buff(10937, "party4")
WoW.unitLevels.party4 = 60
buff(10937, nil)
buff(10937, "party4")
eq(said(), 1, "seen at -1 (??), then at 60: judged, not 'levelled'")
fresh()
WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = "player" }
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "your own buff: not judged")
fresh()
WoW.auras[10937] = { expirationTime = 0, duration = 1800 }
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "no source (a stranger with no token): not judged")
fresh()
WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = WoW.Secret("src") }
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "a secret source: not judged")
-- Seen at 59, then 60, then 60 again: suppressed (sticky).
fresh()
caster("party3", { id = "LV", level = 59 })
buff(10937, "party3")
eq(said(), 0, "seen at 59: below the level")
WoW.unitLevels.party3 = 60
buff(10937, nil)
buff(10937, "party3")
eq(said(), 0, "  then at 60: levelled this session, not judged")
buff(10937, nil)
buff(10937, "party3")
eq(said(), 0, "  and again at 60: still not")

-- Detection.
fresh()
caster("party1")
WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = "party1" }
P.Set("lowbuffs", false)
P.Set("lowbuffs", true)
tick()
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "a buff already on at Enable: not judged")
fresh()
caster("party1")
WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = "party1" }
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
tick()
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "a buff on at a loading screen: not judged")
-- Gained in combat: never judged after it.
fresh()
caster("party1")
WoW.fire("PLAYER_REGEN_DISABLED")
local before = reads()
buff(10937, "party1")
eq(reads(), before, "in combat: no aura read at all")
WoW.fire("PLAYER_REGEN_ENABLED")
tick()
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "gained in combat: not judged after it")
-- A queued check, then combat: nothing.
fresh()
caster("party1")
WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = "party1" }
WoW.fire("UNIT_AURA", "player")
WoW.fire("PLAYER_REGEN_DISABLED")
before = reads()
tick()
eq(reads(), before, "a check queued before combat: does nothing in it")
WoW.fire("PLAYER_REGEN_ENABLED")
tick()
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "  and the buff isn't judged after it")
-- One check at most queued: several aura events read each watched ID once.
local watchedCount = 0
for _ in pairs(LB.watched) do watchedCount = watchedCount + 1 end
before = reads()
WoW.fire("UNIT_AURA", "player")
WoW.fire("UNIT_AURA", "player")
WoW.fire("UNIT_AURA", "player")
tick()
eq(reads() - before, watchedCount, "three aura events, one check")
-- Unknown at a baseline, then present: not judged. Unknown, absent, present: judged.
WoW.auras[10937] = nil
WoW.auras[10938] = WoW.Secret("aura")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
tick()
caster("party1")
WoW.auras[10938] = { expirationTime = 0, duration = 1800, sourceUnit = "party1" }
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "unknown at the baseline, then present: not judged")
WoW.auras[10938] = nil
for id in pairs(LB.watched) do WoW.auras[id] = nil end
WoW.auras[10937] = WoW.Secret("aura")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
tick()
WoW.auras[10937] = nil
WoW.fire("UNIT_AURA", "player")
tick()
caster("party1")
buff(10937, "party1")
eq(said(), 1, "unknown at the baseline, then absent, then present: judged")
-- Unknown reads keep the state (present stays present: no second judgment).
WoW.auras[10937] = WoW.Secret("aura")
WoW.fire("UNIT_AURA", "player")
tick()
caster("party1")
WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = "party1" }
WoW.fire("UNIT_AURA", "player")
tick()
eq(said(), 0, "present, unknown, present: not a new buff")
-- Switching off and on with a check queued: the old one does nothing, the new one works.
fresh()
WoW.fire("UNIT_AURA", "player")
P.Set("lowbuffs", false)
P.Set("lowbuffs", true)
tick()
caster("party1")
buff(10937, "party1")
eq(said(), 1, "switched off and on with a check queued: the next buff is still judged")
-- A queued check, then switched off: nothing.
fresh()
caster("party1")
WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = "party1" }
WoW.fire("UNIT_AURA", "player")
P.Set("lowbuffs", false)
before = reads()
tick()
eq(reads(), before, "a check queued, then switched off: nothing read")
check(not LB._test.events:IsEventRegistered("UNIT_AURA"), "  and its events released")
P.Set("lowbuffs", true)
tick()
check(LB._test.events:IsEventRegistered("UNIT_AURA"), "on again: registered")

-- The report.
newChat()
P.Command("lowbuffs").run("")
check(chatHas("rank 5 %(rank 6 expected%)") and chatHas("Not judged:"), "/gpearls lowbuffs: what was said and what wasn't judged")

done("test_lowbuffs")
