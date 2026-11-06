-- Pearls/WhisperInvite.lua: invite from whispers (#77). Someone you know
-- whispers you "inv" or "invite" (the whole message; case and the spaces
-- around it ignored), and you send them a group invite.
--
-- Known, by GUID: a Battle.net friend (GetAccountInfoByGUID's isFriend), a
-- friend (C_FriendList.IsFriend), a guild member (IsGuildMember), and, with
-- the recentAllies option, a Recent Ally (C_RecentAllies.IsRecentAllyByGUID,
-- Blizzard's chat ally icon's own call, ChatFrameOverrides.lua:84). Your group
-- doesn't count: it is in your group already.
--
-- A character whisper invites the payload's own name (C_PartyInfo.InviteUnit,
-- "Name Surname" verbatim, never rebuilt). A Battle.net whisper invites the
-- one game account Blizzard's friends list would (FriendsFrame.lua:2155,
-- :2313): WoW, online, this project, a realm, this region, your faction; none
-- or several (dual-boxing) is left to you. C_BattleNet.InviteFriend, as
-- FriendsFrame_InviteOrRequestToJoin (:2139).
--
-- Every gate needs positive evidence, read right before the invite: solo, or
-- your group's leader (or a raid assistant); room (a party plainly not full:
-- never a conversion to a raid, LFGUtil.lua:113; a raid under 40);
-- C_PartyInfo.CanInvite; no battleground queue (and no LFG mode where the
-- client defines its categories; Forever's group finder is a listing tool,
-- not a queue). Unreadable is "can't tell": no invite.
--
-- One handled request per sender per 10 s, consumed as soon as a known
-- sender's keyword is recognized, before any gate (a skip says why once, not
-- at every whisper). The character's GUID is shared by both paths;
-- "bn:<id>" covers a Battle.net request that resolves to no character.
-- Nothing is ever whispered back. Unmeasured in game.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local WI = {}
GP.WhisperInvite = WI

WI.KEY = "whisperinvite"
WI.KEYWORDS = { inv = true, invite = true }
WI.COOLDOWN = 10
WI.RAID_MAX = 40
WI.REPORT_MAX = 10
WI.EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }

local events = CreateFrame("Frame")
local state = {
    last = {},   -- sender key -> GetTime() of its last handled request
    log = {},    -- the last REPORT_MAX requests, for /gpearls whisperinvite
}
WI.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(WI.KEY, name) end

-- One client call's first value: true, value; or false when absent, it threw
-- or the value is secret (so a plain nil answer differs from "can't tell").
local function read(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return false end
    return true, v
end

-- A client boolean: true / false, or nil when it can't be told.
local function flag(fn, ...)
    local ok, v = read(fn, ...)
    if ok and type(v) == "boolean" then return v end
    return nil
end

local function text(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

local function number(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- A plain table's fields, each checked: nil when any of them is secret.
local function fields(t, ...)
    if API.IsSecret(t) or type(t) ~= "table" then return nil end
    local out = {}
    for i = 1, select("#", ...) do
        local k = select(i, ...)
        local v = t[k]
        if API.IsSecret(v) then return nil end
        out[k] = v
    end
    return out
end

local function note(line)
    table.insert(state.log, line)
    while #state.log > WI.REPORT_MAX do table.remove(state.log, 1) end
end

local function api(ns, name)
    local t = rawget(_G, ns)
    return type(t) == "table" and t[name] or nil
end

--------------------------------------------------------------------------------
-- The keyword and who you know

-- The keyword the message is, lower-cased, or nil.
function WI.Keyword(msg)
    msg = text(msg)
    if not msg then return nil end
    local word = msg:match("^%s*(.-)%s*$"):lower()
    return WI.KEYWORDS[word] and word or nil
end

-- A Battle.net friend's account info: the plain isFriend field is true.
local function bnFriend(info)
    local f = fields(info, "isFriend")
    return f ~= nil and f.isFriend == true
end

-- Someone you know, by GUID: true, or false (not known, or can't tell).
function WI.Known(guid)
    guid = text(guid)
    if not guid then return false end
    local ok, info = read(api("C_BattleNet", "GetAccountInfoByGUID"), guid)
    if ok and bnFriend(info) then return true end
    if flag(api("C_FriendList", "IsFriend"), guid) == true then return true end
    if flag(rawget(_G, "IsGuildMember"), guid) == true then return true end
    if setting("recentAllies") and flag(api("C_RecentAllies", "IsRecentAllyByGUID"), guid) == true then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- The Battle.net game account

local GAME_FIELDS = { "clientProgram", "isOnline", "wowProjectID", "realmID", "isInCurrentRegion",
                      "factionName", "gameAccountID", "playerGuid", "characterName" }

-- The one game account of Battle.net account `bnID` that can be invited:
-- { id, guid, name }, or nil and why.
function WI.GameAccount(bnID)
    local client, project = rawget(_G, "BNET_CLIENT_WOW"), rawget(_G, "WOW_PROJECT_ID")
    if type(client) ~= "string" or type(project) ~= "number" then return nil, "this game can't be told apart" end
    local faction = text((select(2, read(UnitFactionGroup, "player"))))
    if not faction then return nil, "your faction can't be read" end
    local okI, index = read(rawget(_G, "BNGetFriendIndex"), bnID)
    if not okI or not number(index) then return nil, "they can't be found on your friends list" end
    local okN, n = read(api("C_BattleNet", "GetFriendNumGameAccounts"), index)
    if not okN or not number(n) then return nil, "their characters can't be read" end
    local found, count = nil, 0
    for i = 1, n do
        local ok, info = read(api("C_BattleNet", "GetFriendGameAccountInfo"), index, i)
        if not ok then return nil, "their characters can't be read" end
        if info ~= nil then
            local g = fields(info, unpack(GAME_FIELDS))
            if not g then return nil, "their characters can't be read" end
            if g.clientProgram == client and g.isOnline == true and g.wowProjectID == project
                and type(g.realmID) == "number" and g.realmID > 0 and g.isInCurrentRegion == true
                and g.factionName == faction then
                local id, guid = number(g.gameAccountID), text(g.playerGuid)
                if not (id and guid) then return nil, "their characters can't be read" end
                count = count + 1
                found = { id = id, guid = guid, name = text(g.characterName) }
            end
        end
    end
    if count == 0 then return nil, "they aren't on a character you can invite" end
    if count > 1 then return nil, "more than one of their characters is online: invite the one you want" end
    return found
end

--------------------------------------------------------------------------------
-- The gates

local GROUP = {}
for i = 1, 4 do GROUP[#GROUP + 1] = "party" .. i end
for i = 1, WI.RAID_MAX do GROUP[#GROUP + 1] = "raid" .. i end

local function inGroup(guid)
    for _, unit in ipairs(GROUP) do
        local ok, g = read(UnitGUID, unit)
        if ok and g == guid then return true end
    end
    return false
end

-- A queue an invite could disturb: nil (none), or why.
function WI.Queued()
    local okMax, max = read(rawget(_G, "GetMaxBattlefieldID"))
    if not okMax or not number(max) then return "your queues can't be read" end
    for i = 1, max do
        local ok, status = read(GetBattlefieldStatus, i)
        if not ok then return "your queues can't be read" end
        if status == "queued" or status == "confirm" then return "you're in a battleground queue" end
    end
    local categories = number(rawget(_G, "NUM_LE_LFG_CATEGORYS"))
    if categories then
        for c = 1, categories do
            local ok, mode = read(rawget(_G, "GetLFGMode"), c)
            if not ok then return "your queues can't be read" end
            if mode ~= nil then return "you're in a group finder queue" end
        end
    end
    return nil
end

-- May `guid` be invited now? nil, or why and whether to say it.
function WI.Gate(guid)
    local grouped = flag(IsInGroup)
    if grouped == nil then return "your group can't be read" end
    if grouped then
        local raid = flag(IsInRaid)
        if raid == nil then return "your group can't be read" end
        local lead = flag(UnitIsGroupLeader, "player") == true
            or (raid and flag(UnitIsGroupAssistant, "player") == true)
        if not lead then return raid and "you aren't the raid's leader or an assistant" or "you aren't the party's leader" end
        if raid then
            local ok, n = read(GetNumGroupMembers)
            if not ok or not number(n) then return "your group can't be read" end
            if n >= WI.RAID_MAX then return "your raid is full" end
        else
            local full = flag(api("C_PartyInfo", "IsPartyFull"))
            if full == nil then return "your party's room can't be read" end
            if full then return "your party is full" end
        end
        if inGroup(guid) then return "already in your group", true end
    end
    if flag(api("C_PartyInfo", "CanInvite")) ~= true then return "the game doesn't allow an invite now" end
    return WI.Queued()
end

--------------------------------------------------------------------------------
-- The requests

-- One handled request per key per COOLDOWN: true when this one may go on.
local function take(key)
    local now = GetTime()
    for k, t in pairs(state.last) do
        if now - t >= WI.COOLDOWN then state.last[k] = nil end
    end
    if state.last[key] then return false end
    state.last[key] = now
    return true
end

local function skipped(who, word, why, quiet)
    note(who .. ": " .. why)
    if not quiet then say(("%s whispered \"%s\": %s, so no invite."):format(who:gsub("^%l", string.upper), word, why)) end
end

local function invited(who, word, ok, err)
    if not ok then
        API.Fail("pearl whisperinvite invite", err)
        note(who .. ": the invite failed")
        say(("%s whispered \"%s\": the invite failed."):format(who:gsub("^%l", string.upper), word))
        return
    end
    note(who .. ": invited")
    say(("Inviting %s (whispered \"%s\")."):format(who, word))
end

function WI.OnWhisper(msg, name, guid)
    local word = WI.Keyword(msg)
    if not word then return end
    name, guid = text(name), text(guid)
    if not (name and guid) then return note("a whisper whose sender can't be read") end
    local okMe, me = read(UnitGUID, "player")
    if okMe and me == guid then return end
    if not WI.Known(guid) then return note(name .. ": not someone you know") end
    if not take(guid) then return end
    local why, quiet = WI.Gate(guid)
    if why then return skipped(name, word, why, quiet) end
    invited(name, word, pcall(C_PartyInfo.InviteUnit, name))
end

function WI.OnBNWhisper(msg, bnID)
    local word = WI.Keyword(msg)
    if not word then return end
    bnID = number(bnID)
    if not bnID then return note("a Battle.net whisper whose sender can't be read") end
    local ok, info = read(api("C_BattleNet", "GetAccountInfoByID"), bnID)
    if not (ok and bnFriend(info)) then return note("a Battle.net whisper: not a Battle.net friend") end
    if not take("bn:" .. bnID) then return end
    local account, why = WI.GameAccount(bnID)
    if not account then return skipped("your Battle.net friend", word, why) end
    if not take(account.guid) then return end
    local who = account.name or "your Battle.net friend"
    local gate, quiet = WI.Gate(account.guid)
    if gate then return skipped(who, word, gate, quiet) end
    invited(who, word, pcall(C_BattleNet.InviteFriend, account.id))
end

-- Registered only while on (Disable unregisters both).
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_WHISPER" then
        local msg, name = ...
        WI.OnWhisper(msg, name, (select(12, ...)))
    elseif event == "CHAT_MSG_BN_WHISPER" then
        WI.OnBNWhisper((...), (select(13, ...)))
    end
end)

--------------------------------------------------------------------------------
-- The report and the pearl

function WI.Report()
    say(("Invite from whispers: %s; Recent Allies %s."):format(WI.enabled and "on" or "off",
        setting("recentAllies") and "included" or "not included"))
    if #state.log == 0 then say("  No \"inv\" or \"invite\" whisper yet.") end
    for _, line in ipairs(state.log) do say("  " .. line) end
end

local function configure(panel, refreshers)
    local KEY, P = WI.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "Who can ask")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local who = GP.UI.Label(panel, "Your Battle.net friends, your friends and your guild.", "GameFontHighlightSmall")
    who:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    local check, refresh = GP.UI.Check(panel, "Also your Recent Allies",
        function() return P.Setting(KEY, "recentAllies") end,
        function(on) P.SetSetting(KEY, "recentAllies", on) end,
        { tip = "The players the game lists under Recent Allies in your friends list: people you recently "
            .. "grouped or fought with." })
    check:SetPoint("TOPLEFT", who, "BOTTOMLEFT", -4, -6)
    refreshers[#refreshers + 1] = refresh
    local note = GP.UI.Label(panel,
        "Only the whole message \"inv\" or \"invite\" counts. No invite when you're in a group you don't lead, "
            .. "when it's full or in a battleground queue; one request per person every 10 seconds.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

local function enable()
    WI.enabled = true
    API.RegisterEvents(events, WI.EVENTS)
end

local function disable()
    WI.enabled = false
    events:UnregisterAllEvents()
end

GP.Pearls.Register({
    key = WI.KEY,
    name = "Invite from whispers",
    desc = "Sends a group invite to a friend or guild mate who whispers you \"inv\" or \"invite\".",
    help = "When a Battle.net friend, a friend or a guild member (and, by option, a Recent Ally) whispers you "
        .. "\"inv\" or \"invite\", Glass Pearls invites them: a game whisper invites that character, a Battle.net "
        .. "whisper the character they're playing here. Only when you're on your own, or lead the group (or "
        .. "assist in a raid), the group has room and you're not in a battleground queue; it never turns a "
        .. "party into a raid. One request per person every 10 seconds. Nothing is whispered back. "
        .. "/gpearls whisperinvite shows the last requests.",
    default = false,
    category = "Social",
    section = "Group",
    defaults = { recentAllies = false },
    Enable = enable,
    Disable = disable,
    configure = configure,
    commands = { whisperinvite = { help = "- the last \"inv\" whispers and what was done",
        run = function() WI.Report() end } },
})

WI._test = { events = events }
