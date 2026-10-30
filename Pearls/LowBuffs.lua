-- Pearls/LowBuffs.lua: low-rank buffs (#42). When another player buffs you
-- with a lower rank than they could cast, say so in chat; optionally, a
-- polite whisper to them (only to people you know: group, guild, friends).
--
-- Forever gives addons no combat log, so this only sees buffs on you, out of
-- combat, from your own auras (AA.Read, by spell ID). Single-target buffs
-- only (WATCH): the downrank rule below is established for them, not for the
-- group versions.
--
-- The rule. A single-target buff lands at the caster's best rank, capped at
-- the highest rank whose level is at most the target's level + 10. So the
-- expected rank is the highest one that (a) the caster's class trainer
-- teaches (Data/Training.lua: book ranks are never expected), (b) is at most
-- the caster's level minus a grace for freshly reachable ranks, and (c) is at
-- most your level + 10. Lower than that is said, once per caster and buff per
-- session, only for casters at or above `minLevel` (the owner: 60 by default)
-- who haven't been seen levelling this session.
--
-- The grace table and the levelled-this-session rule are a reference addon's
-- (MIT licence; the logic, no code): thanks to its author.
--
-- Detection: each watched ID is uninitialized, absent or present. A baseline
-- (at Enable, a loading screen, combat's end) makes every ID uninitialized;
-- the first readable answer sets it without judging. Only absent -> present is
-- a new buff, judged with everything about the caster read in that same
-- check (tokens are reused). Identity is the caster's GUID, never a name.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local LB = {}
GP.LowBuffs = LB

LB.KEY = "lowbuffs"
LB.MAX_LEVEL = 60
LB.WHISPER_GAP = 10
LB.REPORT_MAX = 10
-- The first rank of each watched single-target buff.
LB.WATCH = { 1243, 1459, 1126, 467, 19740, 19742, 19977, 14752, 976 }

local AA = GP.AuraAlert
local events = CreateFrame("Frame")
local state = {
    pending = false,     -- a check is queued (one at most)
    ids = {},            -- [spellID] = "absent" | "present" (nil: uninitialized)
    casters = {},        -- [guid] = { level, levelled }
    told = {},           -- ["guid:group"] = true
    whispered = {},      -- [guid] = true
    lastWhisper = nil,
    flags = {},          -- the last REPORT_MAX flags
    skips = {},          -- [reason] = count
}
LB.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(LB.KEY, name) end

local function plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

-- One client call's first value, plain; nil when it threw or is secret.
local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return plain(v)
end

local function level(v)
    return type(v) == "number" and v >= 1 and v or nil
end

--------------------------------------------------------------------------------
-- The data: watched groups, ranks, trainer ranks

local watched = {}       -- [spellID] = { group = g, rank = n, level = l }
local groups = {}        -- [g] = { IDs, lowest rank first }
do
    local D = GlassPearls.SpellRankData
    for _, first in ipairs(LB.WATCH) do
        local r = D and D.ranks[first]
        local g = r and r[1]
        local ids = g and D.groups[g]
        if ids then                    -- test_lowbuffs pins each a first rank of several
            groups[g] = ids
            for _, id in ipairs(ids) do
                local e = D.ranks[id]
                watched[id] = { group = g, rank = e[2], level = e[3] }
            end
        end
    end
end
LB.watched, LB.groups = watched, groups

local trainer = {}       -- [classFile] = { [spellID] = true }
function LB.TrainerRanks(class)
    if trainer[class] then return trainer[class] end
    local T = GlassPearls.TrainingData
    local c = T and T.classes and T.classes[class]
    if not c then return nil end
    local set = {}
    for _, s in ipairs(c.spells or {}) do set[s.id] = true end
    trainer[class] = set
    return set
end

-- The grace for a newly reachable rank, by the caster's level.
function LB.Grace(casterLevel)
    local max = LB.MAX_LEVEL
    if casterLevel < 10 then return 0 end
    if casterLevel < 20 then return 3 end
    if casterLevel <= max - 11 then return 2 end
    if casterLevel < max then return 1 end
    return 0
end

-- The rank a caster of `class` at `casterLevel` lands on you at `myLevel`,
-- in group `g`: its spell ID, or nil.
function LB.Expected(g, class, casterLevel, myLevel)
    local taught = LB.TrainerRanks(class)
    if not taught then return nil end
    local cap = math.min(casterLevel - LB.Grace(casterLevel), myLevel + 10)
    local best
    for _, id in ipairs(groups[g] or {}) do
        if taught[id] and watched[id].level <= cap then best = id end
    end
    return best
end

--------------------------------------------------------------------------------
-- Telling

local function spellName(id)
    local n = ask(C_Spell.GetSpellName, id)
    if type(n) == "string" and n ~= "" then return n end
end

local function skip(reason)
    state.skips[reason] = (state.skips[reason] or 0) + 1
end

-- May we whisper this caster now? true, or false and why not.
function LB.MayWhisper(c)
    if not setting("whisper") then return false, "off" end
    if not c.known then return false, "not someone you know" end
    if not c.target then return false, "no name to whisper" end
    if state.whispered[c.guid] then return false, "already whispered" end
    if state.lastWhisper and GetTime() - state.lastWhisper < LB.WHISPER_GAP then return false, "too soon" end
    if API.InCombat() then return false, "in combat" end
    if ask(UnitIsDeadOrGhost, "player") ~= false then return false, "dead" end
    if ask(IsInInstance) ~= false then return false, "in an instance" end
    if ask(C_ChatInfo.InChatMessagingLockdown) ~= false then return false, "chat lockdown" end
    local RA, E = rawget(_G, "C_RestrictedActions"), Enum
    local kind = E and E.AddOnRestrictionType and E.AddOnRestrictionType.Chat
    local inactive = E and E.AddOnRestrictionState and E.AddOnRestrictionState.Inactive
    if not (RA and kind and inactive) then return false, "chat restriction unknown" end
    if ask(RA.GetAddOnRestrictionState, kind) ~= inactive then return false, "chat restricted" end
    return true
end

local function tell(c, id, expected)
    local w, e = watched[id], watched[expected]
    local buff = spellName(id)
    say(("%s's %s is rank %d; rank %d is theirs at level %d."):format(c.name or "Someone", buff or "a buff",
        w.rank, e.rank, e.level))
    local flag = { name = c.name, buff = buff, rank = w.rank, expected = e.rank, whisper = "no" }
    local ok, why = LB.MayWhisper(c)
    if ok then
        -- Consumed at the attempt: the API says nothing of delivery.
        state.whispered[c.guid] = true
        state.lastWhisper = GetTime()
        local text = ("Thanks for the %s! FYI, rank %d is yours to learn at level %d (this one was rank %d).")
            :format(buff or "buff", e.rank, e.level, w.rank)
        local sent, err = pcall(C_ChatInfo.SendChatMessage, text, "WHISPER", nil, c.target)
        if sent then flag.whisper = "attempted" else API.Fail("pearl lowbuffs whisper", err); flag.whisper = "failed" end
    else
        flag.whisper = "no (" .. why .. ")"
    end
    table.insert(state.flags, flag)
    if #state.flags > LB.REPORT_MAX then table.remove(state.flags, 1) end
end

--------------------------------------------------------------------------------
-- Judging one new buff, from `source`, read in this same check

function LB.Judge(id, source)
    if API.IsSecret(source) or type(source) ~= "string" or source == "" then return skip("no readable source") end
    if source == "player" or ask(UnitIsUnit, source, "player") ~= false then return skip("yourself") end
    if ask(UnitIsPlayer, source) ~= true then return skip("not a player") end
    local guid = ask(UnitGUID, source)
    if type(guid) ~= "string" or guid == "" then return skip("unreadable") end
    local lvl = level(ask(UnitLevel, source))
    if not lvl then return skip("unreadable") end
    -- The level is recorded before any other exit: a rise seen once is kept.
    local rec = state.casters[guid]
    if not rec then
        rec = { level = lvl }
        state.casters[guid] = rec
    elseif lvl > rec.level then
        rec.level, rec.levelled = lvl, true
    end
    if rec.levelled then return skip("levelled this session") end
    if lvl < (setting("minLevel") or LB.MAX_LEVEL) then return skip("below the level") end
    local okC, _, class = pcall(UnitClass, source)
    class = okC and plain(class)
    if type(class) ~= "string" or not LB.TrainerRanks(class) then return skip("unreadable") end
    local mine = level(ask(UnitLevel, "player"))
    if not mine then return skip("unreadable") end
    local w = watched[id]
    local key = guid .. ":" .. w.group
    if state.told[key] then return end
    local expected = LB.Expected(w.group, class, lvl, mine)
    if not expected or watched[expected].rank <= w.rank then return end
    state.told[key] = true
    local name = ask(GetUnitName, source, false)
    if type(name) ~= "string" or name == "" then name = nil end
    local known = ask(UnitInParty, source) == true
    if not known then
        local raid = ask(UnitInRaid, source)
        known = type(raid) == "number" and raid > 0
    end
    known = known or ask(UnitIsInMyGuild, source) == true
    known = known or ask(C_FriendList.IsFriend, guid) == true
    tell({ guid = guid, name = name, target = name, known = known }, id, expected)
end

--------------------------------------------------------------------------------
-- Detection

-- Never a read in combat or while off. A check queued before a baseline
-- serves as its read: the states it finds are uninitialized.
local function check()
    state.pending = false
    if not LB.enabled or API.InCombat() then return end
    for id in pairs(watched) do
        local result, _, _, source = AA.Read(id)
        local was = state.ids[id]
        if result == "present" then
            state.ids[id] = "present"
            if was == "absent" then LB.Judge(id, source) end
        elseif result == "absent" then
            state.ids[id] = "absent"
        end
        -- "unknown" keeps the state, uninitialized included
    end
end

local function queue()
    if state.pending then return end
    state.pending = true
    C_Timer.After(0, check)
end

-- A new baseline: every ID uninitialized, then read at once.
local function baseline()
    state.ids = {}
    queue()
end

events:SetScript("OnEvent", function(_, event)
    -- No argument is read: UNIT_AURA's can be secret.
    API.NoteCombat(event)
    if event == "UNIT_AURA" then
        queue()
    elseif event ~= "PLAYER_REGEN_DISABLED" then   -- PLAYER_REGEN_ENABLED, PLAYER_ENTERING_WORLD
        baseline()
    end
end)

--------------------------------------------------------------------------------
-- The report

function LB.Report()
    say(("Low-rank buffs: %s; casters from level %d; whisper %s."):format(LB.enabled and "on" or "off",
        setting("minLevel") or LB.MAX_LEVEL, setting("whisper") and "on (people you know)" or "off"))
    if #state.flags == 0 then say("  Nothing said this session.") end
    for _, f in ipairs(state.flags) do
        say(("  %s: %s rank %d (rank %d expected); whisper %s."):format(f.name or "someone", f.buff or "a buff",
            f.rank, f.expected, f.whisper))
    end
    local parts = {}
    for reason, n in pairs(state.skips) do parts[#parts + 1] = reason .. " " .. n end
    table.sort(parts)
    if #parts > 0 then say("  Not judged: " .. table.concat(parts, ", ") .. ".") end
end

--------------------------------------------------------------------------------
-- The pearl

local function configure(panel, refreshers)
    local KEY, P = LB.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "When someone buffs you with a lower rank")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local box, refreshLevel = GP.UI.Number(panel, "only casters from this level",
        function() return P.Setting(KEY, "minLevel") end, function(n) P.SetSetting(KEY, "minLevel", n) end, 1, 60, 40)
    box:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 6, -10)
    refreshers[#refreshers + 1] = refreshLevel
    local whisper, refreshWhisper = GP.UI.Check(panel, "Whisper them a polite note",
        function() return P.Setting(KEY, "whisper") end, function(on) P.SetSetting(KEY, "whisper", on) end,
        { tip = "Only to people you know (your group, guild or friends), once per person a session, never in combat "
            .. "or an instance." })
    whisper:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -10, -8)
    refreshers[#refreshers + 1] = refreshWhisper
    local note = GP.UI.Label(panel,
        "A buff lands at a lower rank on a lower-level player by design (the game's rule): that is never said. Only "
            .. "ranks a class trainer teaches are expected, never a book's. Unverified until the game is live.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", whisper, "BOTTOMLEFT", 4, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

local function enable()
    LB.enabled = true
    local ok, registered = pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    if not ok then API.Fail("pearl lowbuffs UNIT_AURA", registered)
    elseif registered == false then API.Fail("pearl lowbuffs UNIT_AURA", "refused") end
    API.RegisterEvents(events, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    baseline()
end

local function disable()
    LB.enabled = false
    events:UnregisterAllEvents()
end

GP.Pearls.Register({
    key = LB.KEY,
    name = "Low-rank buffs",
    desc = "Tells you when someone buffs you with a lower rank than they could.",
    help = "When another player's Power Word: Fortitude, Arcane Intellect, Mark of the Wild, Thorns, Blessing, Divine "
        .. "Spirit or Shadow Protection lands on you at a lower rank than their level allows, a line in your chat says "
        .. "so, once per person and buff a session. A lower rank on a lower-level player is the game's rule and never "
        .. "said; book ranks are never expected. Only casters from level 60 by default. Optionally, a polite whisper to "
        .. "them, only if you know them (group, guild, friends). /gpearls lowbuffs shows what was said. Unverified "
        .. "until the game is live.",
    default = true,
    category = "Social",
    section = "Group",
    defaults = { minLevel = 60, whisper = false },
    ranges = { minLevel = { 1, 60 } },
    Enable = enable,
    Disable = disable,
    configure = configure,
    commands = { lowbuffs = { help = "- what low-rank buffs said this session, and what it didn't judge",
        run = function() LB.Report() end } },
})

LB._test = { events = events, check = check }
