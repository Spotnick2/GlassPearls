-- Low-rank buffs (#42): the opt-in whisper. Only to people you know (party,
-- raid, guild, friend), once per caster a session, 10 s apart, never in
-- combat, dead, in an instance, under chat lockdown or unless the chat
-- restriction is plainly Inactive; never queued; consumed at the attempt.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local LB, P = GP.LowBuffs, GP.Pearls
local function tick() WoW.flushTimers(0) end
WoW.spells[10937] = { name = "Power Word: Fortitude" }
WoW.playerLevel = 60

local n = 0
-- A new 60 priest in `token`, `rel` = "party" | "raid" | "guild" | "friend" | nil.
local function caster(rel, opts)
    opts = opts or {}
    n = n + 1
    local token = opts.token or "party1"
    local guid = "Player-1-W" .. n
    WoW.units[token] = { id = "W" .. n, guid = guid }
    WoW.players[token], WoW.unitLevels[token], WoW.unitClasses[token] = true, 60, "PRIEST"
    WoW.fullNames[token] = opts.name or ("Kaelith Dawnsong" .. n)
    WoW.partyMembers[token], WoW.raidIndex[token], WoW.guildMembers[token] = nil, nil, nil
    if rel == "party" then WoW.partyMembers[token] = true
    elseif rel == "raid" then WoW.raidIndex[token] = 3
    elseif rel == "guild" then WoW.guildMembers[token] = true
    elseif rel == "friend" then WoW.friends[guid] = true end
    return token, guid
end
-- A rank-5 Fortitude from `token` lands; returns the whispers sent by it.
local function land(token)
    WoW.auras[10937] = nil
    WoW.fire("UNIT_AURA", "player")
    tick()
    local before = #WoW.sentChat
    WoW.auras[10937] = { expirationTime = 0, duration = 1800, sourceUnit = token }
    WoW.fire("UNIT_AURA", "player")
    tick()
    return #WoW.sentChat - before
end
local function later() WoW.advance(11) end

-- Off by default.
eq(P.Setting("lowbuffs", "whisper"), false, "the whisper is off by default")
newChat()
eq(land(caster("party")), 0, "off: no whisper")
check(chatHas("is rank 5"), "  the chat line says it")

P.SetSetting("lowbuffs", "whisper", true)
later()
local t = caster("party", { name = "Kaelith Dawnsong" })
eq(land(t), 1, "on, a party member: whispered")
local w = WoW.sentChat[#WoW.sentChat]
eq(w.chatType, "WHISPER", "  a whisper")
eq(w.target, "Kaelith Dawnsong", "  to the full name, spaces kept")
eq(w.lang, nil, "  no language")
eq(w.msg, "Thanks for the Power Word: Fortitude! FYI, rank 6 is yours to learn at level 60 (this one was rank 5).",
    "  the text")
later()
eq(land(caster("raid")), 1, "a raid member (an index): whispered")
later()
eq(land(caster("guild")), 1, "a guild member: whispered")
later()
eq(land(caster("friend")), 1, "a friend (by GUID): whispered")
later()
newChat()
eq(land(caster(nil)), 0, "a stranger: never")
check(chatHas("is rank 5"), "  the chat line still says it")
later()
local s = caster(nil)
WoW.partyMembers[s] = WoW.Secret("party")
WoW.guildMembers[s] = WoW.Secret("guild")
eq(land(s), 0, "an unknown relationship (secret answers): never")
later()
s = caster(nil)
WoW.raidIndex[s] = 0
eq(land(s), 0, "UnitInRaid 0: not a raid member")

-- Once per caster (whatever the spell), and 10 s apart.
later()
local tok, guid = caster("party")
eq(land(tok), 1, "a party member")
later()
WoW.auras[10937] = nil
WoW.spells[10156] = { name = "Arcane Intellect" }
WoW.unitClasses[tok] = "MAGE"
WoW.fire("UNIT_AURA", "player")
tick()
WoW.auras[10156] = { expirationTime = 0, duration = 1800, sourceUnit = tok }
local before = #WoW.sentChat
newChat()
WoW.fire("UNIT_AURA", "player")
tick()
check(chatHas("Arcane Intellect is rank 4"), "the same caster, another buff: said")
eq(#WoW.sentChat - before, 0, "  but never whispered twice")
WoW.auras[10156] = nil
later()
eq(land(caster("party", { token = "party2" })), 1, "one caster")
eq(land(caster("party", { token = "party3" })), 0, "another within 10 s: not whispered")
WoW.advance(11)
eq(#WoW.sentChat - before - 1, 0, "  and never sent later")

-- The gates.
local function gated(setup, undo)
    later()
    local token = caster("party")
    setup()
    local sent = land(token)
    undo()
    return sent
end
eq(gated(function() WoW.dead = true end, function() WoW.dead = nil end), 0, "dead: not whispered")
eq(gated(function() WoW.inInstance = true end, function() WoW.inInstance = nil end), 0, "in an instance: not")
eq(gated(function() WoW.inInstance = WoW.Secret("instance") end, function() WoW.inInstance = nil end), 0,
    "  IsInInstance secret: not")
eq(gated(function() WoW.chatLockdown = true end, function() WoW.chatLockdown = nil end), 0, "chat lockdown: not")
eq(gated(function() WoW.chatLockdown = WoW.Secret("lock") end, function() WoW.chatLockdown = nil end), 0,
    "  lockdown secret: not")
local AS = Enum.AddOnRestrictionState
eq(gated(function() WoW.chatRestriction = AS.Activating end, function() WoW.chatRestriction = nil end), 0,
    "chat restriction Activating: not")
eq(gated(function() WoW.chatRestriction = AS.Active end, function() WoW.chatRestriction = nil end), 0,
    "chat restriction Active: not")
eq(gated(function() WoW.chatRestriction = WoW.Secret("state") end, function() WoW.chatRestriction = nil end), 0,
    "  restriction secret: not")
local RA = C_RestrictedActions
eq(gated(function() C_RestrictedActions = nil end, function() C_RestrictedActions = RA end), 0,
    "  restriction API missing: not")
local get = RA.GetAddOnRestrictionState
eq(gated(function() RA.GetAddOnRestrictionState = function() error("nope") end end,
    function() RA.GetAddOnRestrictionState = get end), 0, "  restriction API throws: not")
eq(gated(function() WoW.fullNames.party1 = WoW.Secret("name") end, function() end), 0, "a secret name: not")
eq(gated(function() WoW.fullNames.party1 = "" end, function() end), 0, "an empty name: not")
-- In combat nothing is judged at all; a whisper is also gated on it directly.
later()
check(LB.MayWhisper({ guid = "x", known = true, target = "X" }), "MayWhisper: all clear")
WoW.fire("PLAYER_REGEN_DISABLED")
local ok, why = LB.MayWhisper({ guid = "x", known = true, target = "X" })
check(not ok and why == "in combat", "MayWhisper in combat: no")
WoW.fire("PLAYER_REGEN_ENABLED")
tick()

-- A throwing send is recorded and still consumes the throttle.
later()
WoW.chatSendThrows = true
local tt = caster("party")
eq(land(tt), 0, "a throwing send: nothing sent")
check(GP.failures["pearl lowbuffs whisper"] ~= nil, "  recorded")
WoW.chatSendThrows = nil
check(not LB.MayWhisper({ guid = "y", known = true, target = "Y" }), "  and the 10 s gap is consumed")
newChat()
P.Command("lowbuffs").run("")
check(chatHas("whisper failed") and chatHas("whisper no %(chat restricted%)") and chatHas("whisper no %(chat lockdown%)"),
    "/gpearls lowbuffs: failed, and why not")
local rows = 0
for _, line in ipairs(WoW.chat) do if line:find("expected%); whisper") then rows = rows + 1 end end
eq(rows, LB.REPORT_MAX, "  the last 10 only")

done("test_lowbuffs_whisper")
