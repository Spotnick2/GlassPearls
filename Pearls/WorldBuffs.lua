-- Pearls/WorldBuffs.lua: world buff announcer (#104). When a world buff's
-- turn-in NPC speaks, "<buff> may drop in about N s"; when the buff then lands
-- on you, "<buff> is on you". Only what this client hears and sees: nothing is
-- sent to anyone.
--
-- Hearing: CHAT_MSG_MONSTER_YELL / _SAY, only the payload's 12th value (the
-- sender's GUID) is read, for the NPC ID in it; never the text, the name or
-- the language. A listed (event, NPC) pair opens its buff's window when none
-- is open: a fixed bound (the longest delay plus a grace) inside which later
-- lines are ignored and one receipt may be announced. The bound is checked
-- against GetTime() on every use, whatever its timer did. A line whose sender
-- can't be read goes into the ring with why (never the value), for day one.
--
-- Receiving: UNIT_AURA (payload untouched) queues one check a frame later,
-- never in combat. Per watched spell ID: uninitialized, absent, or present
-- with its expiration (0: none) and whether an unknown read came since. A
-- baseline (Enable, a switch turned on, a loading screen, combat's end) makes
-- every ID uninitialized; the first readable answer sets it silently. A buff
-- is received when one of its IDs goes absent -> present, or stays present
-- with a positive expiration at least REFRESH s later than the last positive
-- one with no unknown read between. Announced inside its window, once, and
-- also without one (the line unheard: out of range, an unreadable sender, a
-- delay longer than listed), at most once per QUIET s per buff, a window's
-- announcement included (#106). Receipt is observed, never attributed to a
-- turn-in.
--
-- The NPC IDs and delays are game facts from a reference addon and Wowhead
-- Forever (database evidence); the 1304xxx spell IDs are Forever's copies.
-- Unmeasured: docs/PLAN.md, day one; /gpearls worldbuffs shows the record.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local WB = {}
GP.WorldBuffs = WB

WB.KEY = "worldbuffs"
WB.REFRESH = 60          -- a refresh moves the expiration at least this far
WB.QUIET = 600           -- a window-less announcement's gap
WB.LOG_MAX = 10
WB.RING_MAX, WB.RING_AGE = 8, 90
WB.SOUND_WARN = "Interface\\AddOns\\GlassPearls\\Media\\WorldBuffYell.ogg"
WB.SOUND_DROP = "Interface\\AddOns\\GlassPearls\\Media\\WorldBuffDrop.ogg"
WB.EVENTS = { CHAT_MSG_MONSTER_YELL = "yell", CHAT_MSG_MONSTER_SAY = "say" }

-- speakers: { event, npcID, soonest, latest } in seconds from that line.
WB.BUFFS = {
    { key = "dragonslayer", fallback = "Rallying Cry of the Dragonslayer", ids = { 22888, 355363, 1304452 },
      grace = 20, speakers = {
          { "yell", 14392, 14 },        -- Orgrimmar, Onyxia's head
          { "yell", 14394, 14 },        -- Stormwind, Onyxia's head
          { "yell", 14720, 14 },        -- Orgrimmar, Nefarian's head
          { "yell", 14721, 12 },        -- Stormwind, Nefarian's head
      } },
    { key = "rend", fallback = "Warchief's Blessing", ids = { 16609, 355366, 1304594 },
      grace = 20, speakers = {
          { "yell", 4949, 6 },          -- Orgrimmar
          { "yell", 10719, 6 },         -- the Crossroads herald
      } },
    { key = "zandalar", fallback = "Spirit of Zandalar", ids = { 24425, 355365 },
      grace = 30, speakers = {
          { "yell", 15076, 30, 50 },    -- Yojamba Isle about 30 s, Booty Bay about 50 s
          { "say", 14875, 50 },         -- Yojamba Isle
      } },
    -- The turn-in NPC is 466; who speaks, and when, is unmeasured.
    { key = "stormwind", fallback = "Might of Stormwind", ids = { 460939, 460940, 1304678 },
      grace = 0, speakers = {} },
}

local AA = GP.AuraAlert
local events = CreateFrame("Frame")
local byKey, bySpeaker, byID = {}, {}, {}
for _, b in ipairs(WB.BUFFS) do
    byKey[b.key] = b
    for _, s in ipairs(b.speakers) do bySpeaker[s[1] .. ":" .. s[2]] = { buff = b, soonest = s[3], latest = s[4] or s[3] } end
    for _, id in ipairs(b.ids) do byID[id] = b end
end
WB.byKey = byKey

local state = {
    pending = false,     -- an aura check is queued (one at most)
    ids = {},            -- [spellID] = { s = "absent" } | { s = "present", exp, gap } (nil: uninitialized)
    windows = {},        -- [buff key] = { token, heardAt, endsAt, event, npc, received }
    seq = 0,
    ring = {},           -- the last RING_MAX lines heard: { event, npc, at }
    quiet = {},          -- [buff key] = GetTime() of its last window-less announcement
    counts = { unreadable = 0, ignored = 0, heard = 0 },
}
WB.state = state

local function setting(name) return GP.Pearls.Setting(WB.KEY, name) end

local function db()
    local d = GP.db
    if not d then return { log = {} } end
    d.worldbuffs = type(d.worldbuffs) == "table" and d.worldbuffs or {}
    local w = d.worldbuffs
    if type(w.log) ~= "table" then w.log = {} end
    while #w.log > WB.LOG_MAX do table.remove(w.log, 1) end
    return w
end

local function record(entry)
    local log = db().log
    local ok, t = pcall(GetServerTime)
    entry.t = (ok and not API.IsSecret(t) and type(t) == "number") and t or 0
    log[#log + 1] = entry
    while #log > WB.LOG_MAX do table.remove(log, 1) end
end

-- The client's name for the buff, else the English fallback.
function WB.Name(b)
    local ok, name = pcall(C_Spell.GetSpellName, b.ids[1])
    if ok and not API.IsSecret(name) and type(name) == "string" and name ~= "" then return name end
    return b.fallback
end

local function play(path)
    if setting("sound") then pcall(PlaySoundFile, path, "Master") end
end

local function announce(line, path)
    API.Print(line)
    GP.Notice.Show(line)
    play(path)
end

-- The NPC ID in a creature's GUID ("Creature-0-<server>-<instance>-<zone>-<npc>-<spawn>"), or nil.
function WB.NpcID(guid)
    if API.IsSecret(guid) or type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)%-%x+$")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    return id
end

-- Why a sender can't be read, for the ring: a short fixed word or the GUID's
-- leading letters (its kind, "Player"), never the value itself.
function WB.Unreadable(guid)
    if API.IsSecret(guid) then return "secret" end
    if guid == nil then return "missing" end
    if type(guid) ~= "string" then return "not a string" end
    if guid == "" then return "empty" end
    local kind = guid:match("^(%a+)%-")
    if kind and kind ~= "Creature" and kind ~= "Vehicle" then return kind:sub(1, 16) end
    return "malformed"
end

-- The open window of a buff, or nil (a bound passed is closed, timer or not).
local function window(key)
    local w = state.windows[key]
    if w and GetTime() >= w.endsAt then
        state.windows[key] = nil
        if not w.received then
            record({ buff = key, event = w.event, npc = w.npc, outcome = "unconfirmed" })
        end
        return nil
    end
    return w
end
WB.Window = window

local function eta(sp)
    if sp.latest > sp.soonest then return ("in %d-%d s"):format(sp.soonest, sp.latest) end
    return ("in about %d s"):format(sp.soonest)
end

-------------------------------------------------------------------------------
-- Hearing

-- The ring: any line, for day one (which NPC spoke before Might of Stormwind
-- landed; whether a buff's line came with a sender we couldn't read).
local function remember(entry)
    local ring = state.ring
    ring[#ring + 1] = entry
    while #ring > WB.RING_MAX do table.remove(ring, 1) end
end

local function heard(event, npc)
    local now = GetTime()
    remember({ event = event, npc = npc, at = now })
    local sp = bySpeaker[event .. ":" .. npc]
    if not sp then return end
    state.counts.heard = state.counts.heard + 1
    local b = sp.buff
    if not setting(b.key) or window(b.key) then
        state.counts.ignored = state.counts.ignored + 1
        return
    end
    state.seq = state.seq + 1
    local token = state.seq
    local w = { token = token, heardAt = now, endsAt = now + sp.latest + b.grace, event = event, npc = npc }
    state.windows[b.key] = w
    announce(("%s may drop %s."):format(WB.Name(b), eta(sp)), WB.SOUND_WARN)
    C_Timer.After(sp.latest + b.grace, function()
        if state.windows[b.key] == w then window(b.key) end
    end)
end

function WB.OnLine(event, ...)
    local kind = WB.EVENTS[event]
    if not kind then return end
    local guid = select(12, ...)           -- the sender's GUID: the only value read
    local npc = WB.NpcID(guid)
    if not npc then
        state.counts.unreadable = state.counts.unreadable + 1
        remember({ event = kind, why = WB.Unreadable(guid), at = GetTime() })
        return
    end
    heard(kind, npc)
end

-------------------------------------------------------------------------------
-- Receiving

local function ringCopy(now)
    local lines = {}
    for _, r in ipairs(state.ring) do
        if now - r.at <= WB.RING_AGE then
            lines[#lines + 1] = { event = r.event, npc = r.npc, why = r.why, before = math.floor(now - r.at + 0.5) }
        end
    end
    return lines
end

function WB.Received(b, id)
    local now = GetTime()
    local w = window(b.key)
    if w then
        if w.received then return end
        w.received = true
        record({ buff = b.key, event = w.event, npc = w.npc, spell = id, after = math.floor(now - w.heardAt + 0.5),
            outcome = "received" })
        if setting(b.key) then
            state.quiet[b.key] = now
            announce(("%s is on you."):format(WB.Name(b)), WB.SOUND_DROP)
        end
        return
    end
    record({ buff = b.key, spell = id, outcome = "nowindow", lines = ringCopy(now) })
    if not setting(b.key) then return end
    local last = state.quiet[b.key]
    if last and now - last < WB.QUIET then return end
    state.quiet[b.key] = now
    announce(("%s is on you."):format(WB.Name(b)), WB.SOUND_DROP)
end

local function check()
    state.pending = false
    if not WB.enabled or API.InCombat() then return end
    local got = {}
    for id, b in pairs(byID) do
        local result, exp = AA.Read(id)
        local was = state.ids[id]
        if result == "present" then
            if was and was.s == "absent" then
                got[b] = got[b] or id
            elseif was and was.s == "present" and not was.gap and was.exp > 0 and exp > 0
                and exp >= was.exp + WB.REFRESH then
                got[b] = got[b] or id
            end
            state.ids[id] = { s = "present", exp = exp }
        elseif result == "absent" then
            state.ids[id] = { s = "absent" }
        elseif was and was.s == "present" then
            was.gap = true                   -- unknown: the next expiration proves no refresh
        end
    end
    for _, b in ipairs(WB.BUFFS) do
        if got[b] then WB.Received(b, got[b]) end
    end
end

local function queue()
    if state.pending then return end
    state.pending = true
    C_Timer.After(0, check)
end

local function baseline()
    state.ids = {}
    queue()
end

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if WB.EVENTS[event] then
        WB.OnLine(event, ...)
    elseif event == "UNIT_AURA" then
        queue()                              -- no argument read: UNIT_AURA's can be secret
    elseif event == "PLAYER_LEAVING_WORLD" then
        state.windows, state.ring = {}, {}
    elseif event ~= "PLAYER_REGEN_DISABLED" then   -- PLAYER_ENTERING_WORLD, PLAYER_REGEN_ENABLED
        baseline()
    end
end)

-------------------------------------------------------------------------------
-- The report

local function report(arg)
    if arg == "test" then
        local b = byKey.dragonslayer
        announce(("%s may drop in about 14 s."):format(WB.Name(b)), WB.SOUND_WARN)
        C_Timer.After(3, function() announce(("%s is on you."):format(WB.Name(b)), WB.SOUND_DROP) end)
        API.Print("World buffs: an example warning, and the receipt 3 s later.")
        return
    end
    local parts = {}
    for _, b in ipairs(WB.BUFFS) do parts[#parts + 1] = b.key .. " " .. (setting(b.key) and "on" or "off") end
    API.Print(("World buffs: %s; %s; sound %s."):format(WB.enabled and "on" or "off", table.concat(parts, ", "),
        setting("sound") and "on" or "off"))
    API.Print(("  Lines: %d from listed speakers (%d ignored), %d unreadable."):format(state.counts.heard,
        state.counts.ignored, state.counts.unreadable))
    for _, b in ipairs(WB.BUFFS) do
        local w = window(b.key)
        if w then
            API.Print(("  Open: %s, %s by NPC %d %d s ago%s."):format(b.key, w.event, w.npc,
                math.floor(GetTime() - w.heardAt), w.received and ", received" or ""))
        end
    end
    local log = db().log
    if #log == 0 then API.Print("  Nothing recorded yet.") end
    for _, e in ipairs(log) do
        local s = ("  %s: %s"):format(tostring(e.buff), tostring(e.outcome))
        if e.npc then s = s .. (", %s by NPC %d"):format(tostring(e.event), e.npc) end
        if e.spell then s = s .. (", spell %d"):format(e.spell) end
        if e.after then s = s .. (", %d s after the line"):format(e.after) end
        if type(e.lines) == "table" and #e.lines > 0 then
            local heardBefore = {}
            for _, l in ipairs(e.lines) do
                local who = l.npc and tostring(l.npc) or ("unreadable (%s)"):format(tostring(l.why))
                heardBefore[#heardBefore + 1] = ("%s %s %ds"):format(tostring(l.event), who, l.before or 0)
            end
            s = s .. "; heard before: " .. table.concat(heardBefore, ", ")
        end
        API.Print(s .. ".")
    end
end

-------------------------------------------------------------------------------
-- The pearl

local LABELS = {
    { "dragonslayer", "Rallying Cry of the Dragonslayer" },
    { "rend", "Warchief's Blessing" },
    { "zandalar", "Spirit of Zandalar" },
    { "stormwind", "Might of Stormwind", "Who announces it isn't known yet: only \"is on you\", when it lands." },
}

local function configure(panel, refreshers)
    local KEY, P = WB.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "Announce these world buffs")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local anchor, first = head, true
    for _, l in ipairs(LABELS) do
        local key = l[1]
        local cb, refresh = GP.UI.Check(panel, l[2], function() return P.Setting(KEY, key) end,
            function(on) P.SetSetting(KEY, key, on) end, l[3] and { tip = l[3] } or nil)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", first and 6 or 0, first and -10 or -2)
        refreshers[#refreshers + 1] = refresh
        anchor, first = cb, false
    end
    local sound, refreshSound = GP.UI.Check(panel, "Play a sound", function() return P.Setting(KEY, "sound") end,
        function(on) P.SetSetting(KEY, "sound", on) end, { tip = "One when it may drop, another when it's on you." })
    sound:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    refreshers[#refreshers + 1] = refreshSound
    local test = GP.UI.Button(panel, "Test", 80, function() report("test") end)
    test:SetPoint("TOPLEFT", sound, "BOTTOMLEFT", 4, -10)
    local note = GP.UI.Label(panel,
        "Only what you hear: the turn-in NPC's line in its city, then the buff landing on you. The NPC is recognized by "
            .. "its ID, never its words, so another line of theirs can warn for nothing. Unverified until checked in game.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -12)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

local function enable()
    WB.enabled = true
    local ok, registered = pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    if not ok then API.Fail("pearl worldbuffs UNIT_AURA", registered)
    elseif registered == false then API.Fail("pearl worldbuffs UNIT_AURA", "refused") end
    API.RegisterEvents(events, { "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_SAY", "PLAYER_ENTERING_WORLD",
        "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    baseline()
end

local function disable()
    WB.enabled = false
    events:UnregisterAllEvents()
    state.windows, state.ring = {}, {}
end

local function settingChanged(name, value)
    if not byKey[name] then return end
    if value then
        if WB.enabled then baseline() end
    else
        state.windows[name] = nil            -- its timer finds another window, or none
    end
end

GP.Pearls.Register({
    key = WB.KEY,
    name = "World buff announcer",
    desc = "Tells you when a world buff may be about to drop, and when it's on you.",
    help = "When the NPC who takes Onyxia's or Nefarian's head, Rend's head or Hakkar's heart speaks: \"<buff> may "
        .. "drop in about 14 s\" (6 s for Warchief's Blessing, 30-50 s for Spirit of Zandalar), then \"<buff> is on "
        .. "you\" once it lands on you. A line in your chat, a short text in the middle of the screen and a sound. "
        .. "Only what your client hears: you must be in the city (or Booty Bay, Yojamba Isle, the Crossroads); "
        .. "nothing is sent to anyone. The NPC is recognized by its ID, never its words: another line of theirs can "
        .. "warn for nothing, and two turn-ins close together are one warning. A buff that lands without its line "
        .. "heard (out of range, a delay longer than expected) still says \"is on you\", at most once in 10 minutes, "
        .. "so a restored buff can say it too. Might of Stormwind only says \"is on you\" for now (who announces it "
        .. "isn't known yet). /gpearls worldbuffs "
        .. "shows what it heard. Unverified until checked in game.",
    default = true,
    category = "Combat",
    section = "Alerts",
    defaults = { dragonslayer = true, rend = true, zandalar = true, stormwind = true, sound = true },
    Enable = enable,
    Disable = disable,
    configure = configure,
    onSettingChanged = settingChanged,
    commands = { worldbuffs = { help = "[test] - what the world buff announcer heard, or an example",
        run = report } },
})

WB._test = { events = events, check = check, state = state }
