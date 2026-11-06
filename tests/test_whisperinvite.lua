-- Invite from whispers (#77): off by default; the keyword (the whole message,
-- "inv" or "invite"); who is known (Battle.net friend, friend, guild, and
-- Recent Allies by option; never a stranger, the group or yourself); the
-- gates, each needing positive evidence (leader, room, CanInvite, queues:
-- a plain nil differs from an unreadable read); the cooldown, consumed before
-- any gate and shared by both paths; the Battle.net game account (one valid,
-- none, several, secret fields); a failed invite; the report and the panel.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Blizzard's constants (ProjectConstants.lua, Constants): set here only.
rawset(_G, "WOW_PROJECT_ID", 18)
rawset(_G, "BNET_CLIENT_WOW", "WoW")

local GP = loadAddon()
local WI, P = GP.WhisperInvite, GP.Pearls

local FRIEND, GUILDIE, STRANGER, ALLY = "Player-1-F00D", "Player-1-6111", "Player-1-5777", "Player-1-A111"
WoW.friends[FRIEND] = true
WoW.guildGUIDs[GUILDIE] = true
WoW.recentAllies[ALLY] = true

local function whisper(msg, name, guid)
    WoW.fire("CHAT_MSG_WHISPER", msg, name, "", "", name, "", 0, 0, "", 0, 1, guid, 0, false, false)
end
local function bnWhisper(msg, bnID)
    WoW.fire("CHAT_MSG_BN_WHISPER", msg, "Friend", "", "", "", "", 0, 0, "", 0, 1, nil, bnID, false, false)
end
local function invites() return #WoW.invites end
local function last() return WoW.invites[#WoW.invites] end
-- Past every cooldown, the gates open, a fresh chat.
local function reset()
    WoW.advance(WI.COOLDOWN + 1)
    WoW.invites = {}
    WoW.group = { party = false, raid = false, leader = false, assistant = false }
    WoW.canInvite, WoW.partyFull, WoW.groupSize, WoW.battlefieldMax, WoW.inviteThrows = nil, nil, nil, nil, nil
    WoW.battlefields, WoW.lfgModes, WoW.units = {}, {}, {}
    rawset(_G, "NUM_LE_LFG_CATEGORYS", nil)
    newChat()
end

--------------------------------------------------------------------------------
-- Off by default

check(not P.IsOn("whisperinvite"), "off by default")
check(next(WI._test.events._events) == nil, "  no event registered")
whisper("inv", "Ami Friend", FRIEND)
eq(invites(), 0, "  off: a friend's inv does nothing")
P.Set("whisperinvite", true)
check(WI._test.events._events.CHAT_MSG_WHISPER and WI._test.events._events.CHAT_MSG_BN_WHISPER, "on: both whispers")
eq(P.Setting("whisperinvite", "recentAllies"), false, "  Recent Allies off inside")

--------------------------------------------------------------------------------
-- The keyword and the invite

reset()
whisper("inv", "Ami Friend", FRIEND)
eq(invites(), 1, "a friend whispers inv: invited")
check(last().kind == "unit" and last().target == "Ami Friend", "  by the whisper's own name, surname and all")
check(chatHas('Inviting Ami Friend %(whispered "inv"%)%.'), "  said")
for _, msg in ipairs({ "invite", "INV", "  Invite  ", "Inv\n" }) do
    reset()
    whisper(msg, "Ami Friend", FRIEND)
    eq(invites(), 1, ("%q is the keyword"):format(msg))
end
for _, msg in ipairs({ "inv pls", "invite me", "inv?", "", "i n v", "invites" }) do
    reset()
    whisper(msg, "Ami Friend", FRIEND)
    eq(invites(), 0, ("%q is not"):format(msg))
end
reset()
local logged = #WI.state.log
whisper("hello", "Ami Friend", FRIEND)
eq(#WI.state.log, logged, "ordinary chat isn't logged")
reset()
whisper(WoW.Secret("text"), "Ami Friend", FRIEND)
eq(invites(), 0, "a secret message: nothing")

--------------------------------------------------------------------------------
-- Who is known

reset()
whisper("inv", "Gil Guild", GUILDIE)
eq(invites(), 1, "a guild member: invited")
reset()
local BNPAL = "Player-1-B0B0"
WoW.bnetFriends[BNPAL] = true
whisper("inv", "Bea Bnet", BNPAL)
eq(invites(), 1, "a Battle.net friend (isFriend): invited")
reset()
WoW.bnetFriends[BNPAL] = { accountName = "Someone#1", bnetAccountID = 9 }
whisper("inv", "Bea Bnet", BNPAL)
eq(invites(), 0, "a Battle.net account that isn't a friend: not known")
reset()
WoW.bnetFriends[BNPAL] = { isFriend = WoW.Secret("isFriend") }
whisper("inv", "Bea Bnet", BNPAL)
eq(invites(), 0, "  isFriend secret: not known")
WoW.bnetFriends[BNPAL] = nil
reset()
whisper("inv", "Stan Ger", STRANGER)
eq(invites(), 0, "a stranger: no invite")
eq(#newChat(), 0, "  and nothing said")
check(WI.state.log[#WI.state.log] == "Stan Ger: not someone you know", "  only noted for the report")
reset()
whisper("inv", "Al Ally", ALLY)
eq(invites(), 0, "a Recent Ally, option off: no invite")
P.SetSetting("whisperinvite", "recentAllies", true)
reset()
whisper("inv", "Al Ally", ALLY)
eq(invites(), 1, "  option on: invited")
WoW.recentAllies[ALLY] = "throw"
reset()
whisper("inv", "Al Ally", ALLY)
eq(invites(), 0, "  the Recent Allies read throwing: not known")
WoW.recentAllies[ALLY] = true
P.SetSetting("whisperinvite", "recentAllies", false)
reset()
WoW.guildGUIDs[STRANGER] = WoW.Secret("guild")
whisper("inv", "Stan Ger", STRANGER)
eq(invites(), 0, "a secret guild answer: not known")
WoW.guildGUIDs[STRANGER] = nil
reset()
WoW.friends[WoW.playerGUID] = true
whisper("inv", "Me Myself", WoW.playerGUID)
eq(invites(), 0, "a whisper from yourself: nothing")
WoW.friends[WoW.playerGUID] = nil
reset()
WoW.group.party, WoW.group.leader = true, true
WoW.units.party1 = { guid = STRANGER }
whisper("inv", "Stan Ger", STRANGER)
eq(invites(), 0, "a group member who is no friend: not known (the group doesn't count)")
reset()
whisper("inv", WoW.Secret("name"), FRIEND)
whisper("inv", "Ami Friend", WoW.Secret("guid"))
eq(invites(), 0, "a secret sender name or GUID: nothing")

--------------------------------------------------------------------------------
-- The gates: positive evidence only

local function gated(label, setup, said)
    reset()
    setup()
    whisper("inv", "Ami Friend", FRIEND)
    eq(invites(), 0, label .. ": no invite")
    if said then
        check(chatHas('Ami Friend whispered "inv": ' .. said .. ', so no invite%.'), "  said: " .. said)
    end
end
local function allowed(label, setup)
    reset()
    setup()
    whisper("inv", "Ami Friend", FRIEND)
    eq(invites(), 1, label .. ": invited")
end
gated("in a party you don't lead", function() WoW.group.party = true end, "you aren't the party's leader")
allowed("leading a party with room", function() WoW.group.party, WoW.group.leader = true, true end)
gated("leading a full party", function()
    WoW.group.party, WoW.group.leader, WoW.partyFull = true, true, true
end, "your party is full")
gated("the party's room unreadable (throws)", function()
    WoW.group.party, WoW.group.leader, WoW.partyFull = true, true, "throw"
end, "your party's room can't be read")
gated("the party's room secret", function()
    WoW.group.party, WoW.group.leader, WoW.partyFull = true, true, WoW.Secret("full")
end, "your party's room can't be read")
gated("a party member who is no assistant (no assistants in a party)", function()
    WoW.group.party, WoW.group.assistant = true, true
end, "you aren't the party's leader")
allowed("a raid assistant with room", function()
    WoW.group.raid, WoW.group.assistant, WoW.groupSize = true, true, 12
end)
gated("in a raid neither leader nor assistant", function()
    WoW.group.raid, WoW.groupSize = true, 12
end, "you aren't the raid's leader or an assistant")
gated("a full raid", function()
    WoW.group.raid, WoW.group.leader, WoW.groupSize = true, true, 40
end, "your raid is full")
gated("the raid's size secret", function()
    WoW.group.raid, WoW.group.leader, WoW.groupSize = true, true, WoW.Secret("size")
end, "your group can't be read")
gated("the raid's size not a number", function()
    WoW.group.raid, WoW.group.leader, WoW.groupSize = true, true, false
end, "your group can't be read")
gated("CanInvite false", function() WoW.canInvite = false end, "the game doesn't allow an invite now")
gated("CanInvite throws", function() WoW.canInvite = "throw" end, "the game doesn't allow an invite now")
reset()
WoW.group.party, WoW.group.leader = true, true
WoW.units.party2 = { guid = FRIEND }
whisper("inv", "Ami Friend", FRIEND)
eq(invites(), 0, "already in your group: no invite")
eq(#newChat(), 0, "  and nothing said")

-- Queues.
gated("queued for a battleground", function() WoW.battlefields = { "queued" } end, "you're in a battleground queue")
gated("a battleground ready to enter", function() WoW.battlefields = { "confirm" } end,
    "you're in a battleground queue")
gated("a later battleground slot queued", function() WoW.battlefields = { "none", "queued" } end,
    "you're in a battleground queue")
gated("queued while leading a party", function()
    WoW.group.party, WoW.group.leader, WoW.battlefields = true, true, { "queued" }
end, "you're in a battleground queue")
allowed("inside a battleground's status 'active' or 'none'", function() WoW.battlefields = { "none", "active" } end)
gated("the battleground count unreadable", function() WoW.battlefieldMax = "throw" end, "your queues can't be read")
gated("the battleground count secret", function() WoW.battlefieldMax = WoW.Secret("max") end,
    "your queues can't be read")
gated("a battleground status unreadable", function() WoW.battlefields = { "none", "throw" } end,
    "your queues can't be read")
allowed("no LFG categories defined: GetLFGMode never read", function() WoW.lfgModes[1] = "throw" end)
allowed("LFG categories defined, every mode a plain nil", function() rawset(_G, "NUM_LE_LFG_CATEGORYS", 3) end)
gated("an LFG mode set", function()
    rawset(_G, "NUM_LE_LFG_CATEGORYS", 3)
    WoW.lfgModes[3] = "queued"
end, "you're in a group finder queue")
gated("an LFG mode unreadable", function()
    rawset(_G, "NUM_LE_LFG_CATEGORYS", 3)
    WoW.lfgModes[2] = WoW.Secret("mode")
end, "your queues can't be read")

--------------------------------------------------------------------------------
-- The cooldown

reset()
whisper("inv", "Ami Friend", FRIEND)
WoW.advance(5)
whisper("inv", "Ami Friend", FRIEND)
eq(invites(), 1, "a second inv within 10 s: ignored")
WoW.advance(WI.COOLDOWN - 4)
whisper("inv", "Ami Friend", FRIEND)
eq(invites(), 2, "  after 10 s: invited again")
reset()
whisper("inv", "Ami Friend", FRIEND)
whisper("inv", "Gil Guild", GUILDIE)
eq(invites(), 2, "per sender: another friend isn't held back")
reset()
WoW.partyFull, WoW.group.party, WoW.group.leader = true, true, true
whisper("inv", "Ami Friend", FRIEND)
whisper("inv", "Ami Friend", FRIEND)
whisper("invite", "Ami Friend", FRIEND)
local lines = 0
for _, l in ipairs(newChat()) do if l:find("so no invite", 1, true) then lines = lines + 1 end end
eq(lines, 1, "a skip is said once per 10 s, not at every whisper")
WoW.partyFull = false
whisper("inv", "Ami Friend", FRIEND)
eq(invites(), 0, "  and the cooldown it consumed holds after room appears")
reset()
whisper("inv", "Stan Ger", STRANGER)
WoW.friends[STRANGER] = true
whisper("inv", "Stan Ger", STRANGER)
eq(invites(), 1, "a stranger's request consumes nothing: once a friend, invited at once")
WoW.friends[STRANGER] = nil

--------------------------------------------------------------------------------
-- A failed invite

reset()
WoW.inviteThrows = true
whisper("inv", "Ami Friend", FRIEND)
check(chatHas('Ami Friend whispered "inv": the invite failed%.'), "an invite that throws: said")
check(GP.failures["pearl whisperinvite invite"] ~= nil, "  and recorded")
GP.failures["pearl whisperinvite invite"] = nil

--------------------------------------------------------------------------------
-- Battle.net whispers

local BN, GID, CHAR = 70, 701, "Player-1-C4A1"
local function account(t)
    local a = { bnetAccountID = BN, characterName = "Cora Bnet", playerGuid = CHAR, isOnline = true,
                clientProgram = "WoW", wowProjectID = 18, realmID = 5, isInCurrentRegion = true,
                factionName = "Alliance" }
    for k, v in pairs(t or {}) do a[k] = v end
    return a
end
local function setup(accounts)
    WoW.bn.accounts, WoW.bn.friends = {}, { {} }
    for i, a in ipairs(accounts) do
        WoW.bn.accounts[GID + i - 1] = a
        table.insert(WoW.bn.friends[1], GID + i - 1)
    end
    WoW.bnAccounts[BN] = { isFriend = true }
end

reset()
setup({ account() })
bnWhisper("inv", BN)
eq(invites(), 1, "a Battle.net friend whispers inv: invited")
check(last().kind == "bn" and last().target == GID, "  their one game account, by InviteFriend")
check(chatHas('Inviting Cora Bnet %(whispered "inv"%)%.'), "  said with the character's name")
reset()
setup({ account() })
WoW.friends[CHAR] = true
bnWhisper("inv", BN)
whisper("inv", "Cora Bnet", CHAR)
eq(invites(), 1, "the same character through both paths within 10 s: one invite (the GUID's cooldown is shared)")
reset()
setup({ account() })
whisper("inv", "Cora Bnet", CHAR)
bnWhisper("inv", BN)
eq(invites(), 1, "  either order")
WoW.friends[CHAR] = nil

reset()
setup({ account() })
WoW.bnAccounts[BN] = { isFriend = false }
bnWhisper("inv", BN)
eq(invites(), 0, "not a Battle.net friend: nothing")
eq(#newChat(), 0, "  nothing said")
reset()
setup({ account() })
WoW.bnAccounts[BN] = "throw"
bnWhisper("inv", BN)
eq(invites(), 0, "the account read throws: nothing")
reset()
setup({ account() })
bnWhisper("inv", WoW.Secret("bnSenderID"))
eq(invites(), 0, "a secret sender ID: nothing")

local function bnSkip(label, accounts, said, before)
    reset()
    setup(accounts)
    if before then before() end
    bnWhisper("inv", BN)
    eq(invites(), 0, label .. ": no invite")
    check(chatHas(said), "  said: " .. said)
end
bnSkip("two characters online", { account(), account({ playerGuid = "Player-1-C4A2", characterName = "Two" }) },
    "more than one of their characters is online")
bnSkip("offline (or appearing offline)", { account({ isOnline = false }) }, "they aren't on a character you can invite")
bnSkip("another game", { account({ clientProgram = "App" }) }, "they aren't on a character you can invite")
bnSkip("another WoW project", { account({ wowProjectID = 2 }) }, "they aren't on a character you can invite")
bnSkip("no realm", { account({ realmID = 0 }) }, "they aren't on a character you can invite")
bnSkip("another region", { account({ isInCurrentRegion = false }) }, "they aren't on a character you can invite")
bnSkip("the other faction", { account({ factionName = "Horde" }) }, "they aren't on a character you can invite")
bnSkip("a field secret", { account({ wowProjectID = WoW.Secret("project") }) }, "their characters can't be read")
bnSkip("the GUID secret", { account({ playerGuid = WoW.Secret("guid") }) }, "their characters can't be read")
bnSkip("not found on the list", {}, "they can't be found on your friends list")
bnSkip("the index read throws", { account() }, "they can't be found on your friends list",
    function() WoW.bnIndexThrows = true end)
WoW.bnIndexThrows = nil
bnSkip("the project constant missing", { account() }, "this game can't be told apart",
    function() rawset(_G, "WOW_PROJECT_ID", nil) end)
rawset(_G, "WOW_PROJECT_ID", 18)
reset()
setup({ account({ wowProjectID = 2 }), account({ playerGuid = "Player-1-C4A2" }) })
bnWhisper("inv", BN)
eq(invites(), 1, "two game accounts, one of them here: that one")
eq(last() and last().target, GID + 1, "  the valid one")
reset()
setup({ account({ characterName = WoW.Secret("name") }) })
check(WI.GameAccount(BN) == nil, "a secret character name: can't be read (every field used is checked)")
reset()
setup({ account(), account({ playerGuid = "Player-1-C4A2" }) })
bnWhisper("inv", BN)
bnWhisper("inv", BN)
local said = 0
for _, l in ipairs(newChat()) do if l:find("more than one", 1, true) then said = said + 1 end end
eq(said, 1, "an ambiguous request is said once per 10 s (the bn: key)")
reset()
setup({ account() })
WoW.group.party = true
bnWhisper("inv", BN)
eq(invites(), 0, "the gates apply to Battle.net too")
check(chatHas('Cora Bnet whispered "inv": you aren\'t the party\'s leader, so no invite%.'), "  said")

--------------------------------------------------------------------------------
-- Switched off

P.Set("whisperinvite", false)
check(next(WI._test.events._events) == nil, "off: no event registered")
reset()
whisper("inv", "Ami Friend", FRIEND)
eq(invites(), 0, "  a friend's inv does nothing")
P.Set("whisperinvite", true)

--------------------------------------------------------------------------------
-- The report and the panel

newChat()
P.Command("whisperinvite").run()
check(chatHas("Invite from whispers: on; Recent Allies not included%."), "the report")
check(chatHas("  Cora Bnet: you aren't the party's leader"), "  with the last requests")

GP.Options.Open("cat:Social")
local page = GP.Options._test.pages["cat:Social"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "whisperinvite" then row = pl.row end end
check(row ~= nil, "on the Social page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:whisperinvite"].frame._children[1]
local checks = {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
eq(#checks, 1, "one switch")
checks[1]:SetChecked(true)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("whisperinvite", "recentAllies"), true, "  Recent Allies")
P.ResetSettings("whisperinvite")
eq(P.Setting("whisperinvite", "recentAllies"), false, "  reset")

done("test_whisperinvite")
