-- Pearls/Social.lua: social automation (#37). Answers four of Blizzard's
-- popups for you, each with its own switch: a summon (accepted), a
-- resurrection (accepted once you and your group are out of combat), a duel
-- from someone not positively known (declined, off by default), a group
-- invite from someone you know (accepted).
--
-- Each answer is the API the popup's own button calls (C_SummonInfo
-- .ConfirmSummon, AcceptResurrect, CancelDuel, AcceptGroup); Blizzard's own
-- events close the popup. The popups are only read (StaticPopup_Visible,
-- which Blizzard runs through securecallfunction), never shown, hidden,
-- clicked or written: the invite's in particular is left to Blizzard, since
-- hiding it from addon code would mutate the shared dialog table and run its
-- OnHide's DeclineGroup().
--
-- Every offer carries a token per kind. A new event of that kind replaces it
-- before any filtering, so an offer left to the player still stales the one
-- before it; its cancel events, a loading screen and Disable stale it too.
-- Every deferred step checks, right before acting, the token, the switch,
-- Shift (held: that offer is left to you) and that Blizzard's popup for it is
-- still shown (answered by hand, it is gone). Each offer is tried once (a
-- resurrection is polled until it can be accepted, then dropped).
--
-- "Someone you know" is by GUID, as Blizzard's SocialQueueUtil does: a
-- Battle.net friend, a friend, a guild member, or your group. Names are never
-- saved (a synced set holds IDs only), so the issue's exception lists are
-- this rule instead.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local S = {}
GP.Social = S

S.KEY = "social"
S.SUMMON_DELAY = 2
S.RES_POLL = 1
S.RES_WINDOW = 60                 -- Blizzard's own: GetCorpseRecoveryDelay() + 60 (GameDialogDefs.lua:1170)
S.REPORT_MAX = 10
S.NAMEPLATES = 40
S.SUMMON_POPUP = "CONFIRM_SUMMON"
S.SUMMON_SPECIAL = { "CONFIRM_SUMMON_SCENARIO", "CONFIRM_SUMMON_STARTING_AREA" }
S.RES_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }
S.DUEL_POPUP = "DUEL_REQUESTED"
S.INVITE_POPUP = "PARTY_INVITE"
S.EVENTS = {
    "CONFIRM_SUMMON", "CANCEL_SUMMON",
    "RESURRECT_REQUEST", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_SKINNED",
    "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED", "DUEL_FINISHED",
    "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LEAVING_WORLD",
}
-- The switch each kind of offer answers to.
S.SWITCH = { summon = "summons", res = "resurrect", duel = "duels", invite = "invites" }

local events = CreateFrame("Frame")
local state = {
    tokens = { summon = 0, res = 0, duel = 0, invite = 0 },
    summonRetry = nil,   -- the summon token held for combat
    res = nil,           -- { token, offerer, deadline, name }
    log = {},            -- the last REPORT_MAX attempts and skips
}
S.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(S.KEY, name) end

-- One client call's first value, plain; nil when absent, it threw or is secret.
local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

-- A client boolean: true / false, or nil when it can't be told.
local function flag(fn, ...)
    local v = ask(fn, ...)
    if type(v) == "boolean" then return v end
    return nil
end

local function text(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

local function note(kind, what)
    table.insert(state.log, kind .. ": " .. what)
    while #state.log > S.REPORT_MAX do table.remove(state.log, 1) end
end

-- A new offer of `kind`: every earlier step of that kind goes stale.
local function bump(kind)
    state.tokens[kind] = state.tokens[kind] + 1
    return state.tokens[kind]
end

-- Disable and a loading screen stale every token, so a current one is live.
local function current(kind, token)
    return state.tokens[kind] == token
end

-- Blizzard's popup `which` shown: true / false / nil (can't tell).
local function shown(which)
    local fn = rawget(_G, "StaticPopup_Visible")
    if type(fn) ~= "function" then return nil end
    local ok, name = pcall(fn, which)
    if not ok or API.IsSecret(name) then return nil end
    return name ~= nil
end

local function anyShown(list)
    local any = false
    for _, which in ipairs(list) do
        local v = shown(which)
        if v == nil then return nil end
        any = any or v
    end
    return any
end

-- The checks every deferred step makes right before acting: true, or false
-- and why. Shift held leaves that offer to the player for good.
local function common(kind, token, popups)
    if not current(kind, token) then return false, "stale" end
    if not setting(S.SWITCH[kind]) then return false, "switched off" end
    local shift = flag(IsShiftKeyDown)
    if shift ~= false then return false, shift and "Shift held: left to you" or "Shift unreadable: left to you" end
    if anyShown(popups) ~= true then return false, "the popup is gone" end
    return true
end

--------------------------------------------------------------------------------
-- Who you know, and the group

local function groupUnits()
    local list = {}
    for i = 1, 4 do list[#list + 1] = "party" .. i end
    for i = 1, 40 do list[#list + 1] = "raid" .. i end
    return list
end
local GROUP = groupUnits()

-- Someone you know, by GUID: true, or false (not known, or can't tell).
function S.Known(guid)
    guid = text(guid)
    if not guid then return false end
    local BN = rawget(_G, "C_BattleNet")
    if BN and type(ask(BN.GetAccountInfoByGUID, guid)) == "table" then return true end
    if flag(C_FriendList and C_FriendList.IsFriend, guid) == true then return true end
    if flag(rawget(_G, "IsGuildMember"), guid) == true then return true end
    for _, unit in ipairs(GROUP) do
        if ask(UnitGUID, unit) == guid then return true end
    end
    return false
end

-- You or your group in combat: true, false, or nil when it can't be told.
local function fighting()
    if API.InCombat() then return true end
    local me = flag(UnitAffectingCombat, "player")
    if me ~= false then return me end
    for _, unit in ipairs(GROUP) do
        local exists = flag(UnitExists, unit)
        if exists == nil then return nil end
        if exists then
            local busy = flag(UnitAffectingCombat, unit)
            if busy ~= false then return busy end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- 1. Summons

local function summonTry(token)
    state.summonRetry = nil
    local ok, why = common("summon", token, { S.SUMMON_POPUP })
    if not ok then return note("summon", why) end
    if anyShown(S.SUMMON_SPECIAL) ~= false then return note("summon", "not the ordinary summon") end
    if API.InCombat() or flag(UnitAffectingCombat, "player") == true then
        state.summonRetry = token                  -- tried again after the fight
        return note("summon", "held for combat")
    end
    if flag(UnitAffectingCombat, "player") ~= false then return note("summon", "combat unreadable: left to you") end
    if flag(PlayerCanTeleport) ~= true then return note("summon", "can't teleport now: left to you") end
    if flag(UnitIsDeadOrGhost, "player") ~= false then return note("summon", "dead: left to you") end
    local left = ask(C_SummonInfo.GetSummonConfirmTimeLeft)
    if type(left) ~= "number" or left <= 0 then return note("summon", "expired") end
    local done, err = pcall(C_SummonInfo.ConfirmSummon)
    if not done then
        API.Fail("pearl social summon", err)
        return note("summon", "the accept failed")
    end
    local area = text(ask(C_SummonInfo.GetSummonConfirmAreaName))
    say(area and ("Accepting the summon to %s."):format(area) or "Accepting the summon.")
    note("summon", "accepted")
end

local function summonOffer(token, skipping)
    if not current("summon", token) or not setting("summons") then return end
    if API.IsSecret(skipping) or skipping ~= false then return note("summon", "not the ordinary summon") end
    if shown(S.SUMMON_POPUP) ~= true or anyShown(S.SUMMON_SPECIAL) ~= false then
        return note("summon", "not Blizzard's ordinary summon popup")
    end
    local left = ask(C_SummonInfo.GetSummonConfirmTimeLeft)
    if type(left) ~= "number" or left <= 0 then return note("summon", "no time left") end
    local area = text(ask(C_SummonInfo.GetSummonConfirmAreaName))
    say(("Summon%s: accepting in %d s (hold Shift to stay)."):format(area and (" to " .. area) or "",
        S.SUMMON_DELAY))
    C_Timer.After(S.SUMMON_DELAY, function() summonTry(token) end)
end

--------------------------------------------------------------------------------
-- 2. Resurrections

local resCheck
local function resLater(token)
    C_Timer.After(S.RES_POLL, function() resCheck(token) end)
end

resCheck = function(token)
    local r = state.res
    if not (r and r.token == token) then return end
    local ok, why = common("res", token, S.RES_POPUPS)
    if not ok then
        state.res = nil
        return note("resurrect", why)
    end
    if GetTime() > r.deadline then
        state.res = nil
        return note("resurrect", "the offer's time ran out")
    end
    local stop
    if text(ask(ResurrectGetOfferer)) ~= r.offerer then stop = "another offer"
    elseif flag(ResurrectHasSickness) ~= false then stop = "with resurrection sickness: left to you"
    elseif flag(UnitIsDeadOrGhost, "player") ~= true then stop = "not dead"
    end
    if stop then
        state.res = nil
        return note("resurrect", stop)
    end
    local delay = ask(GetCorpseRecoveryDelay)
    if delay ~= 0 or fighting() ~= false then return resLater(token) end   -- wait
    state.res = nil                                -- one answer per offer
    local done, err = pcall(AcceptResurrect)
    if not done then
        API.Fail("pearl social resurrect", err)
        return note("resurrect", "the accept failed")
    end
    say(("Accepting the resurrection from %s."):format(r.name or r.offerer))
    note("resurrect", "accepted")
end

local function resFirst(token, name)
    if not current("res", token) or not setting("resurrect") then return end
    local offerer = text(ask(ResurrectGetOfferer))
    if not offerer then return note("resurrect", "the offerer unreadable: left to you") end
    local delay = ask(GetCorpseRecoveryDelay)
    if type(delay) ~= "number" or delay < 0 then return note("resurrect", "the corpse delay unreadable: left to you") end
    state.res = { token = token, offerer = offerer, name = text(name), deadline = GetTime() + delay + S.RES_WINDOW }
    resCheck(token)
end

local function hardcore()
    local rules = rawget(_G, "C_GameRules")
    local fn = rules and rules.IsHardcoreActive
    if type(fn) ~= "function" then return false end      -- Blizzard: no rule, no hardcore
    local v = flag(fn)
    if v == nil then return true end                      -- can't tell: as hardcore, nothing done
    return v
end

--------------------------------------------------------------------------------
-- 3. Duels

local function scanUnits()
    local list = { "target", "mouseover", "focus" }
    for _, u in ipairs(GROUP) do list[#list + 1] = u end
    for i = 1, S.NAMEPLATES do list[#list + 1] = "nameplate" .. i end
    return list
end
local SCAN = scanUnits()

-- The challenger's unit: a player whose first name and surname (GetUnitName
-- on Forever) plainly equal the event's name. No first-name fallback.
function S.Challenger(name)
    for _, unit in ipairs(SCAN) do
        if flag(UnitIsPlayer, unit) == true and text(ask(GetUnitName, unit, false)) == name then return unit end
    end
    return nil
end

local function duelTry(token, name)
    local ok, why = common("duel", token, { S.DUEL_POPUP })
    if not ok then return note("duel", why) end
    local done, err = pcall(CancelDuel)
    if not done then
        API.Fail("pearl social duel", err)
        return note("duel", "the decline failed")
    end
    say(("Declined a duel from %s."):format(name))
    note("duel", "declined " .. name)
end

--------------------------------------------------------------------------------
-- 4. Group invites

local function inviteTry(token, guid, name)
    local ok, why = common("invite", token, { S.INVITE_POPUP })
    if not ok then return note("invite", why) end
    if flag(IsInGroup) ~= false then return note("invite", "already in a group: left to you") end
    if flag(rawget(_G, "WillAcceptInviteRemoveQueues")) ~= false then
        return note("invite", "it would take you out of a queue: left to you")
    end
    if not S.Known(guid) then return note("invite", "not someone you know: left to you") end
    local done, err = pcall(AcceptGroup)
    if not done then
        API.Fail("pearl social invite", err)
        return note("invite", "the accept failed")
    end
    say(name and ("Accepting %s's group invite."):format(name) or "Accepting the group invite.")
    note("invite", "accepted")
end

--------------------------------------------------------------------------------
-- Events

local function plainFalse(v) return not API.IsSecret(v) and v == false end

local function staleAll()
    for kind in pairs(state.tokens) do bump(kind) end
    state.res, state.summonRetry = nil, nil
end

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if event == "CONFIRM_SUMMON" then
        local token = bump("summon")
        state.summonRetry = nil
        local _, skipping = ...
        C_Timer.After(0, function() summonOffer(token, skipping) end)
    elseif event == "CANCEL_SUMMON" then
        bump("summon")
        state.summonRetry = nil
    elseif event == "RESURRECT_REQUEST" then
        local token = bump("res")
        state.res = nil
        if not setting("resurrect") then return end
        if hardcore() then return note("resurrect", "hardcore: left to you") end
        local name = ...
        C_Timer.After(0, function() resFirst(token, name) end)
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "PLAYER_SKINNED" then
        bump("res")
        state.res = nil
    elseif event == "DUEL_REQUESTED" then
        local token = bump("duel")
        if not setting("duels") then return end
        local name = text((...))
        if not name then return note("duel", "the name unreadable: left to you") end
        local unit = S.Challenger(name)
        if unit and S.Known(ask(UnitGUID, unit)) then return note("duel", "someone you know: left to you") end
        C_Timer.After(0, function() duelTry(token, name) end)
    elseif event == "DUEL_TO_THE_DEATH_REQUESTED" or event == "DUEL_FINISHED" then
        bump("duel")
    elseif event == "PARTY_INVITE_REQUEST" then
        local token = bump("invite")
        if not setting("invites") then return end
        local name, tank, healer, damage, _, _, guid, quest = ...
        if not (plainFalse(tank) and plainFalse(healer) and plainFalse(damage)) then
            return note("invite", "a group finder invite: left to you")
        end
        if not plainFalse(quest) then return note("invite", "a quest session: left to you") end
        name = text(name)
        C_Timer.After(0, function() inviteTry(token, guid, name) end)
    elseif event == "PARTY_INVITE_CANCEL" then
        bump("invite")
    elseif event == "PLAYER_REGEN_ENABLED" then
        local token = state.summonRetry
        if token then summonTry(token) end
    elseif event == "PLAYER_LEAVING_WORLD" then
        staleAll()
    end
end)

--------------------------------------------------------------------------------
-- The report

function S.Report()
    local function on(name) return setting(name) and "on" or "off" end
    say(("Social automation: %s. Summons %s, resurrections %s, invites %s, declining duels %s."):format(
        S.enabled and "on" or "off", on("summons"), on("resurrect"), on("invites"), on("duels")))
    if #state.log == 0 then say("  Nothing answered or skipped yet.") end
    for _, line in ipairs(state.log) do say("  " .. line) end
end

--------------------------------------------------------------------------------
-- The pearl

local function configure(panel, refreshers)
    local KEY, P = S.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "Answer for me")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local rows = {
        { "summons", "Accept a summon", "After 2 seconds, out of combat; hold Shift to stay where you are." },
        { "resurrect", "Accept a resurrection",
            "Once you and your group are out of combat; never with resurrection sickness. From anyone." },
        { "invites", "Accept group invites from people you know",
            "Your Battle.net and game friends, your guild and your group; never a group finder invite." },
        { "duels", "Decline duels from people not positively known",
            "Known means a friend, a guild mate or your group whom the game shows you (targeted, grouped or on "
                .. "a nameplate): anyone else is declined, a friend out of sight too." },
    }
    local anchor, dy = head, -10
    for _, r in ipairs(rows) do
        local name = r[1]
        local check, refresh = GP.UI.Check(panel, r[2], function() return P.Setting(KEY, name) end,
            function(on) P.SetSetting(KEY, name, on) end, { tip = r[3] })
        check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == head and 0 or 0, dy)
        refreshers[#refreshers + 1] = refresh
        anchor, dy = check, -4
    end
    local note = GP.UI.Label(panel,
        "Each popup is still Blizzard's: it is answered through its own action, and Shift held when the answer is "
            .. "due leaves that one to you. Unverified until the game is live.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

local function enable()
    S.enabled = true
    API.RegisterEvents(events, S.EVENTS)
end

local function disable()
    S.enabled = false
    events:UnregisterAllEvents()
    staleAll()
end

GP.Pearls.Register({
    key = S.KEY,
    name = "Social automation",
    desc = "Accepts summons, resurrections and invites from people you know; can decline duels.",
    help = "Answers Blizzard's popups for you, each with its own switch: accepts a summon after 2 seconds (hold "
        .. "Shift to stay), a resurrection once you and your group are out of combat, and a group invite from a "
        .. "friend, a guild mate or your group; optionally declines duels from anyone not positively known. It "
        .. "never answers a group finder invite, a summon into a scenario or a resurrection with sickness. "
        .. "/gpearls social shows what it did. Unverified until the game is live.",
    default = false,
    category = "Automation",
    section = "Players",
    defaults = { summons = true, resurrect = true, invites = true, duels = false },
    Enable = enable,
    Disable = disable,
    configure = configure,
    commands = { social = { help = "- what social automation answered or left to you",
        run = function() S.Report() end } },
})

S._test = { events = events }
