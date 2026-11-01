-- Social automation (#37): off by default; each behaviour answers only
-- Blizzard's ordinary popup, through the API its own button calls, once, and
-- only while that offer's token, the switch, Shift and the popup still hold.
-- Popups are modelled with behaviour: shown in either handler order, answered
-- by hand (gone), replaced. Nothing ever hides or writes one (the stubs have no
-- StaticPopup_Hide: a call would fail the test on strict globals).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local S, P = GP.Social, GP.Pearls
local function frame() WoW.advance(0) end
local function calls(name)
    local n = 0
    for _, c in ipairs(WoW.socialCalls) do if c == name then n = n + 1 end end
    return n
end
local function reset()
    WoW.socialCalls, WoW.popups, WoW.unitCombat = {}, {}, {}
    WoW.shift, WoW.dead, WoW.summon, WoW.resOffer, WoW.canTeleport = nil, nil, nil, nil, nil
    WoW.hardcore, WoW.queueRemoval, WoW.popupThrows = nil, nil, nil
    WoW.group.party = false
    newChat()
end

--------------------------------------------------------------------------------
-- Off by default

check(not P.IsOn("social"), "off by default")
check(next(S._test.events._events) == nil, "  no event registered")
P.Set("social", true)
check(S._test.events._events.CONFIRM_SUMMON and S._test.events._events.PARTY_INVITE_REQUEST, "on: its events")
eq(P.Setting("social", "summons"), true, "  summons on inside")
eq(P.Setting("social", "resurrect"), true, "  resurrections on inside")
eq(P.Setting("social", "invites"), true, "  invites on inside")
eq(P.Setting("social", "duels"), false, "  declining duels off inside")

--------------------------------------------------------------------------------
-- 1. Summons

local function offerSummon(opts)
    opts = opts or {}
    WoW.summon = { left = opts.left or 100, area = opts.area or "Ironforge" }
    if opts.popup ~= false then WoW.popups.CONFIRM_SUMMON = true end
    local skipping = opts.skipping
    if skipping == nil then skipping = false end
    WoW.fire("CONFIRM_SUMMON", 0, skipping)
    frame()
end

reset()
offerSummon()
check(chatHas("Summon to Ironforge: accepting in 2 s %(hold Shift to stay%)"), "summon: announced")
WoW.advance(1.9)
eq(calls("ConfirmSummon"), 0, "  nothing before 2 s")
WoW.advance(0.2)
eq(calls("ConfirmSummon"), 1, "  accepted at 2 s")
check(chatHas("Accepting the summon to Ironforge%."), "  said")
WoW.advance(5)
eq(calls("ConfirmSummon"), 1, "  once")

-- Blizzard's popup shown after our handler (we look a frame later).
reset()
WoW.summon = { left = 100, area = "Ironforge" }
WoW.fire("CONFIRM_SUMMON", 0, false)
WoW.popups.CONFIRM_SUMMON = true
frame()
WoW.advance(2)
eq(calls("ConfirmSummon"), 1, "summon: popup shown after our handler: accepted")

local function noSummon(label, setup, offerOpts)
    reset()
    if offerOpts ~= "manual" then offerSummon(offerOpts) end
    if setup then setup() end
    WoW.advance(2)
    WoW.fire("PLAYER_REGEN_ENABLED")
    WoW.advance(2)
    eq(calls("ConfirmSummon"), 0, "summon: " .. label .. ": not accepted")
end
noSummon("Shift held", function() WoW.shift = true end)
reset()
offerSummon()
WoW.shift = true
WoW.advance(2)
WoW.shift = nil
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.advance(5)
eq(calls("ConfirmSummon"), 0, "summon: Shift skips for good")
noSummon("can't teleport", function() WoW.canTeleport = false end)
noSummon("teleport unreadable", function() WoW.canTeleport = WoW.Secret("tp") end)
noSummon("dead", function() WoW.dead = true end)
noSummon("time left gone", function() WoW.summon.left = 0 end)
noSummon("time left secret", function() WoW.summon.left = WoW.Secret("left") end)
noSummon("cancelled", function() WoW.fire("CANCEL_SUMMON") end)
noSummon("answered by hand", function() WoW.popups.CONFIRM_SUMMON = nil end)
noSummon("switched off", function() P.SetSetting("social", "summons", false) end)
P.SetSetting("social", "summons", true)
noSummon("the pearl off mid-delay", function() P.Set("social", false); P.Set("social", true) end)
noSummon("a replaced offer (left to you)", function() WoW.fire("CONFIRM_SUMMON", 0, WoW.Secret("skip")); frame() end)
noSummon("a scenario popup", nil, { popup = false })
reset()
WoW.summon = { left = 100 }
WoW.popups.CONFIRM_SUMMON_SCENARIO = true
WoW.fire("CONFIRM_SUMMON", 2, false)
frame()
WoW.advance(3)
eq(calls("ConfirmSummon"), 0, "summon: the scenario popup alone: never")
local quiet = true
for _, line in ipairs(newChat()) do if line:find("accepting in", 1, true) then quiet = false end end
check(quiet, "  not even announced")
noSummon("the scenario popup beside it", function() WoW.popups.CONFIRM_SUMMON_SCENARIO = true end)
noSummon("the starting area (skipping)", nil, { skipping = true })
noSummon("the starting-area popup", function() WoW.popups.CONFIRM_SUMMON_STARTING_AREA = true end)
noSummon("a secret popup read", function() WoW.popups.CONFIRM_SUMMON = WoW.Secret("popup") end)
noSummon("a popup read that throws", function() WoW.popupThrows = true end)
-- Announced only for Blizzard's ordinary popup alone.
local function announced(label, setup, expect)
    reset()
    WoW.summon = { left = 100, area = "Ironforge" }
    setup()
    WoW.fire("CONFIRM_SUMMON", 0, false)
    frame()
    local said = false
    for _, line in ipairs(newChat()) do if line:find("accepting in", 1, true) then said = true end end
    eq(said, expect, "summon: " .. label)
    WoW.advance(3)
end
announced("no popup at all: not announced", function() end, false)
announced("the scenario popup beside it: not announced", function()
    WoW.popups.CONFIRM_SUMMON, WoW.popups.CONFIRM_SUMMON_SCENARIO = true, true
end, false)
announced("the ordinary popup: announced", function() WoW.popups.CONFIRM_SUMMON = true end, true)
-- With the switch off, nothing is even noted.
P.SetSetting("social", "summons", false)
reset()
S.state.log = {}
WoW.summon = { left = 100 }
WoW.popups.CONFIRM_SUMMON = true
WoW.fire("CONFIRM_SUMMON", 0, false)
frame()
eq(#S.state.log, 0, "summon: switched off: nothing noted")
P.SetSetting("social", "summons", true)

-- Combat holds it; accepted after the fight.
reset()
offerSummon()
WoW.unitCombat.player = true
WoW.advance(2)
eq(calls("ConfirmSummon"), 0, "summon: in combat: held")
WoW.unitCombat.player = nil
WoW.fire("PLAYER_REGEN_ENABLED")
eq(calls("ConfirmSummon"), 1, "  accepted after the fight")
reset()
offerSummon()
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.advance(2)
eq(calls("ConfirmSummon"), 0, "summon: lockdown noted: held")
WoW.summon.left = 0
WoW.fire("PLAYER_REGEN_ENABLED")
eq(calls("ConfirmSummon"), 0, "  expired by the fight's end: not accepted")
reset()
offerSummon()
WoW.unitCombat.player = WoW.Secret("combat")
WoW.advance(2)
WoW.unitCombat.player = nil
WoW.fire("PLAYER_REGEN_ENABLED")
eq(calls("ConfirmSummon"), 0, "summon: combat unreadable: left to you")

--------------------------------------------------------------------------------
-- 2. Resurrections

local function offerRes(opts)
    opts = opts or {}
    WoW.dead = true
    WoW.resOffer = { offerer = opts.offerer or "Kaelith Dawnsong", delay = opts.delay or 0, sickness = opts.sickness }
    if opts.popup ~= false then WoW.popups[opts.popup or "RESURRECT_NO_SICKNESS"] = true end
    WoW.fire("RESURRECT_REQUEST", "Kaelith Dawnsong")
    frame()
end

reset()
offerRes()
eq(calls("AcceptResurrect"), 1, "resurrection: accepted")
check(S.state.res == nil, "  the offer dropped")
check(chatHas("Accepting the resurrection from Kaelith Dawnsong%."), "  said")
WoW.advance(5)
eq(calls("AcceptResurrect"), 1, "  once")
reset()
offerRes({ popup = "RESURRECT_NO_TIMER" })
eq(calls("AcceptResurrect"), 1, "resurrection: the no-timer popup too")
-- The popup shown after our handler.
reset()
WoW.dead = true
WoW.resOffer = { offerer = "Kaelith Dawnsong", delay = 0 }
WoW.fire("RESURRECT_REQUEST", "Kaelith Dawnsong")
WoW.popups.RESURRECT_NO_SICKNESS = true
frame()
eq(calls("AcceptResurrect"), 1, "resurrection: popup shown after our handler: accepted")

local function noRes(label, setup, opts)
    reset()
    offerRes(opts)
    if setup then setup() end
    if WoW.resOffer then WoW.resOffer.delay = 0 end   -- the condition is the only thing in the way
    for _ = 1, 70 do WoW.advance(1) end               -- one poll a second
    eq(calls("AcceptResurrect"), 0, "resurrection: " .. label .. ": not accepted")
end
reset()
WoW.hardcore = true
offerRes()
WoW.advance(5)
eq(calls("AcceptResurrect"), 0, "resurrection: hardcore: never")
reset()
WoW.hardcore = WoW.Secret("hc")
offerRes()
WoW.advance(5)
eq(calls("AcceptResurrect"), 0, "resurrection: hardcore unreadable: never")
noRes("with sickness", nil, { sickness = true })
noRes("the sickness popup", nil, { popup = "RESURRECT", sickness = true })
noRes("sickness appearing on a re-read", function() WoW.resOffer.sickness = true end, { delay = 3 })
noRes("not dead", function() WoW.dead = false end, { delay = 3 })
noRes("declined by hand", function() WoW.popups.RESURRECT_NO_SICKNESS = nil end, { delay = 3 })
noRes("the offerer changed", function() WoW.resOffer.offerer = "Someone Else" end, { delay = 3 })
noRes("the offerer unreadable", nil, { offerer = WoW.Secret("name") })
noRes("skinned", function() WoW.fire("PLAYER_SKINNED", 0) end, { delay = 3 })
noRes("alive", function() WoW.fire("PLAYER_ALIVE") end, { delay = 3 })
noRes("unghost", function() WoW.fire("PLAYER_UNGHOST") end, { delay = 3 })
reset()
WoW.dead = true
WoW.resOffer = { offerer = "Kaelith Dawnsong", delay = 0 }
WoW.popups.RESURRECT_NO_SICKNESS = true
WoW.fire("RESURRECT_REQUEST", "Kaelith Dawnsong")
WoW.fire("PLAYER_ALIVE")
frame()
eq(calls("AcceptResurrect"), 0, "resurrection: alive before the first check: not accepted")
noRes("Shift held", function() WoW.shift = true end, { delay = 3 })
noRes("switched off", function() P.SetSetting("social", "resurrect", false) end, { delay = 3 })
P.SetSetting("social", "resurrect", true)
-- The corpse delay, then accepted.
reset()
offerRes({ delay = 3 })
eq(calls("AcceptResurrect"), 0, "resurrection: the corpse delay: waits")
WoW.resOffer.delay = 0
WoW.advance(1)
eq(calls("AcceptResurrect"), 1, "  accepted once it is over")
-- You in combat, lockdown false (a reload mid-fight).
reset()
WoW.unitCombat.player = true
offerRes()
WoW.advance(3)
eq(calls("AcceptResurrect"), 0, "resurrection: you in combat, solo, lockdown false: waits")
WoW.unitCombat.player = nil
WoW.advance(1)
eq(calls("AcceptResurrect"), 1, "  accepted once out of combat")
-- Combat noted (lockdown), you and the group read calm: still waits.
reset()
offerRes({ delay = 3 })
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.resOffer.delay = 0
WoW.advance(3)
eq(calls("AcceptResurrect"), 0, "resurrection: combat noted: waits")
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.advance(1)
eq(calls("AcceptResurrect"), 1, "  accepted after it")
-- A group member in combat.
reset()
WoW.units.party1 = { id = "P1", guid = "Player-1-P1" }
WoW.unitCombat.party1 = true
offerRes()
WoW.advance(3)
eq(calls("AcceptResurrect"), 0, "resurrection: a group member in combat: waits")
WoW.unitCombat.party1 = WoW.Secret("busy")
WoW.advance(3)
eq(calls("AcceptResurrect"), 0, "  unreadable: still waits")
WoW.unitCombat.party1 = nil
WoW.advance(1)
eq(calls("AcceptResurrect"), 1, "  accepted once the group is out of combat")
WoW.units.party1 = nil
-- The window's end.
reset()
WoW.unitCombat.player = true
offerRes()
for _ = 1, 61 do WoW.advance(1) end
WoW.unitCombat.player = nil
WoW.advance(5)
eq(calls("AcceptResurrect"), 0, "resurrection: past Blizzard's window: never")
check(S.state.res == nil, "  the offer ended")

--------------------------------------------------------------------------------
-- 3. Duels (off by default)

local function challenger(name, guid)
    WoW.units.target = { id = "T", guid = guid or "Player-1-T" }
    WoW.players.target = true
    WoW.fullNames.target = name
end
local function duel(name)
    WoW.popups.DUEL_REQUESTED = true
    WoW.fire("DUEL_REQUESTED", name)
end

reset()
challenger("Zoruka Mortalis")
duel("Zoruka Mortalis")
frame()
eq(calls("CancelDuel"), 0, "duel: the switch off: never declined")
S.state.log = {}
reset()
duel("Zoruka Mortalis")
frame()
eq(#S.state.log, 0, "duel: switched off: nothing noted")
P.SetSetting("social", "duels", true)
reset()
duel("Zoruka Mortalis")
frame()
eq(calls("CancelDuel"), 1, "duel: a stranger declined")
check(chatHas("Declined a duel from Zoruka Mortalis%."), "  said")
frame()
eq(calls("CancelDuel"), 1, "  once")

local function notDeclined(label, setup, name)
    reset()
    if setup then setup() end
    duel(name or "Zoruka Mortalis")
    frame()
    eq(calls("CancelDuel"), 0, "duel: " .. label .. ": not declined")
end
notDeclined("a friend", function() WoW.friends["Player-1-T"] = true end)
WoW.friends["Player-1-T"] = nil
notDeclined("a Battle.net friend", function() WoW.bnetFriends["Player-1-T"] = true end)
WoW.bnetFriends["Player-1-T"] = nil
notDeclined("a guild mate", function() WoW.guildGUIDs["Player-1-T"] = true end)
WoW.guildGUIDs["Player-1-T"] = nil
notDeclined("your group", function() WoW.units.party2 = { id = "T", guid = "Player-1-T" } end)
WoW.units.party2 = nil
notDeclined("a secret name", nil, WoW.Secret("name"))
-- Same first name, another surname: never matched to the friend.
reset()
challenger("Zoruka Othername", "Player-1-F")
WoW.friends["Player-1-F"] = true
duel("Zoruka Mortalis")
frame()
eq(calls("CancelDuel"), 1, "duel: a friend sharing the first name isn't the challenger")
WoW.friends["Player-1-F"] = nil
challenger("Zoruka Mortalis")
-- An NPC of the same name earlier in the scan never shadows the player.
reset()
WoW.units.target = { id = "N", guid = "Creature-0-1-2-3-4-N" }
WoW.players.target, WoW.fullNames.target = false, "Zoruka Mortalis"
WoW.units.nameplate1 = { id = "T", guid = "Player-1-T" }
WoW.players.nameplate1, WoW.fullNames.nameplate1 = true, "Zoruka Mortalis"
WoW.friends["Player-1-T"] = true
duel("Zoruka Mortalis")
frame()
eq(calls("CancelDuel"), 0, "duel: a friend on a nameplate, an NPC of that name targeted: left")
WoW.units.nameplate1, WoW.players.nameplate1, WoW.fullNames.nameplate1, WoW.friends["Player-1-T"] = nil, nil, nil, nil
-- Not found anywhere: not positively known, declined.
reset()
WoW.units.target, WoW.players.target, WoW.fullNames.target = nil, nil, nil
duel("Someone Faraway")
frame()
eq(calls("CancelDuel"), 1, "duel: not found: declined")
challenger("Zoruka Mortalis")
-- Stale before the decline.
local function staleDuel(label, between)
    reset()
    duel("Zoruka Mortalis")
    between()
    frame()
    eq(calls("CancelDuel"), 0, "duel: " .. label .. ": no stale decline")
end
staleDuel("finished first", function() WoW.fire("DUEL_FINISHED") end)
staleDuel("accepted by hand", function() WoW.popups.DUEL_REQUESTED = nil end)
staleDuel("a death duel after", function() WoW.fire("DUEL_TO_THE_DEATH_REQUESTED", "Zoruka Mortalis") end)
staleDuel("a known challenger after", function()
    WoW.friends["Player-1-K"] = true
    WoW.units.focus = { id = "K", guid = "Player-1-K" }
    WoW.players.focus, WoW.fullNames.focus = true, "Known Friend"
    WoW.fire("DUEL_REQUESTED", "Known Friend")
end)
WoW.units.focus, WoW.players.focus, WoW.fullNames.focus, WoW.friends["Player-1-K"] = nil, nil, nil, nil
staleDuel("Shift held", function() WoW.shift = true end)
P.SetSetting("social", "duels", false)

--------------------------------------------------------------------------------
-- 4. Group invites

local function invite(guid, opts)
    opts = opts or {}
    WoW.popups.PARTY_INVITE = true
    WoW.fire("PARTY_INVITE_REQUEST", "Mira Stormwind", opts.tank or false, opts.healer or false, opts.damage or false,
        true, false, guid, opts.quest or false)
end

reset()
WoW.friends["Player-1-F"] = true
invite("Player-1-F")
frame()
eq(calls("AcceptGroup"), 1, "invite: a friend: accepted")
check(chatHas("Accepting Mira Stormwind's group invite%."), "  said")
frame()
eq(calls("AcceptGroup"), 1, "  once")
WoW.friends["Player-1-F"] = nil
reset()
WoW.bnetFriends["Player-1-B"] = true
invite("Player-1-B")
frame()
eq(calls("AcceptGroup"), 1, "invite: a Battle.net friend: accepted")
reset()
WoW.guildGUIDs["Player-1-G"] = true
invite("Player-1-G")
frame()
eq(calls("AcceptGroup"), 1, "invite: a guild mate: accepted")

local function noInvite(label, between, guid, opts)
    reset()
    invite(guid or "Player-1-G", opts)
    if between then between() end
    frame()
    eq(calls("AcceptGroup"), 0, "invite: " .. label .. ": not accepted")
end
noInvite("a stranger", nil, "Player-1-X")
noInvite("a secret GUID", nil, WoW.Secret("guid"))
noInvite("a tank role (group finder)", nil, nil, { tank = true })
noInvite("a healer role", nil, nil, { healer = true })
noInvite("a damage role", nil, nil, { damage = true })
noInvite("a secret role", nil, nil, { tank = WoW.Secret("tank") })
noInvite("a quest session", nil, nil, { quest = true })
noInvite("joined a group meanwhile", function() WoW.group.party = true end)
noInvite("a queue it would remove", function() WoW.queueRemoval = true end)
noInvite("queues unreadable", function() WoW.queueRemoval = WoW.Secret("q") end)
noInvite("answered by hand", function() WoW.popups.PARTY_INVITE = nil end)
noInvite("a popup read that throws", function() WoW.popupThrows = true end)
noInvite("cancelled", function() WoW.fire("PARTY_INVITE_CANCEL") end)
noInvite("an excluded replacement", function() invite("Player-1-X") end)
noInvite("Shift held", function() WoW.shift = true end)
noInvite("no longer known", function() WoW.guildGUIDs["Player-1-G"] = nil end)
WoW.guildGUIDs["Player-1-G"] = true
noInvite("switched off", function() P.SetSetting("social", "invites", false) end)
P.SetSetting("social", "invites", true)
noInvite("a loading screen", function() WoW.fire("PLAYER_LEAVING_WORLD") end)
noInvite("the pearl off", function() P.Set("social", false) end)
P.Set("social", true)

--------------------------------------------------------------------------------
-- The report and the panel

newChat()
P.Command("social").run()
check(chatHas("Social automation: on%. Summons on, resurrections on, invites on, declining duels off%."), "the report")
check(chatHas("invite: switched off") or chatHas("invite: "), "  with the last attempts")

GP.Options.Open("cat:Automation")
local page = GP.Options._test.pages["cat:Automation"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "social" then row = pl.row end end
check(row ~= nil, "on the Automation page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:social"].frame._children[1]
local checks = {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
eq(#checks, 4, "four switches")
checks[4]:SetChecked(true)
checks[4]:GetScript("OnClick")(checks[4])
eq(P.Setting("social", "duels"), true, "  the duel switch")
P.ResetSettings("social")
eq(P.Setting("social", "duels"), false, "  reset")

done("test_social")
