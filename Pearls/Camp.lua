-- Pearls/Camp.lua: camp timers (#149). Bars for the Cozy Sleeping Bag (the time
-- to its next Well-Rested stack) and the Welcoming Campfire (the time to its
-- camp benefits), and a 10 s countdown before the bag tops you up. Its bars,
-- digits and panel are Pearls/CampFrame.lua; the aura read is
-- Core/AuraAlert.lua's.
--
-- The client's tables (builds 70862 / 70938): the bag puts 429960 "Well-Rested
-- Tracking Aura" on you (no duration, PERIODIC_TRIGGER_SPELL every 60 s), which
-- adds a stack of 429959 "Well-Rested" (2 h, up to 3 stacks, each refreshing
-- it) every 60 s, the first 60 s after it landed. 1229739 "Welcoming Campfire"
-- lasts 1 min and then grants 1229741 "Camp Benefits"; while you sit it comes
-- back (seen 2026-11-21: 50 s left with the benefits fresh). At 3 stacks the
-- bag's tick refreshes Well-Rested to its full 2 h (the owner, 2026-11-21: 1 h
-- left, back to 2 h). IDs only, never a name.
--
-- The bag's timer (Codex, eight rounds to consensus):
-- - One check reads the four auras together, a frame after UNIT_AURA (its
--   payload never read), and at Enable, PLAYER_ENTERING_WORLD and
--   PLAYER_REGEN_ENABLED. Every callback carries the generation (Enable and
--   Disable bump it): a stale one does nothing.
-- - A presence is one bag visit as far as this client can tell: it starts at
--   the check that first reads 429960 plainly present after anything else, at a
--   plain present whose instance ID isn't plainly equal to the previous check's
--   plain one, and at every PLAYER_ENTERING_WORLD. `since` is that check's time;
--   `entered` = `since` only on evidence of a fresh visit (a plain absent
--   before, or two plain, different IDs), else the phase is unknown.
-- - One anchoring rule: a Well-Rested application time (expiration - duration,
--   both positive) later than `since` by more than MARGIN anchors, the latest
--   such; else `entered`; else none ("waiting", no time). A witnessed
--   application (a plain count rise, or plainly absent -> present) without a
--   usable time drops the anchor and is pending: the first usable time then
--   anchors whatever its margin. A check's time never anchors.
-- - Unresolved reads (the tracking aura unknown; Well-Rested unknown, or present
--   with no count or no usable time while in the bag) keep what is known and
--   share one retry a second later (out of combat; RETRY_MAX in a row, then the
--   events drive it). The tracking aura unknown ends the presence at once.
-- - Full (the owner: the goal is 3 stacks at the full 2 h): 3 stacks given
--   during this presence, by a witnessed rise to 3 or an application time later
--   than `since` by more than MARGIN (a refresh at 3/3). A presence never starts
--   full; becoming full is said once ("3/3") and ends the bar. Read before the
--   tracking aura, so leaving in the same check still counts.
-- - The countdown: only with an anchor, not overdue, 2 or 3 stacks read now
--   (the next tick fills or refreshes them) with a usable time, and Well-Rested
--   lasting past the next tick. The digit is ceil(time left) in (0, 10], shown
--   and ticked once per change; zero is silent, the finish is the 3/3 above.
-- The campfire: its own plain expiration and duration; an unknown read keeps
-- the last plain one, gone at a plain absent or once that time has passed, and
-- hidden while Camp Benefits' application time is no earlier than this
-- Welcoming Campfire's (less CAMP_SLACK): it already gave them, what follows is
-- a refresh. An unknown Camp Benefits read keeps the last plain one.
-- Unmeasured until checked in game (the plan's day-one list, #149).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local AA = GP.AuraAlert
local C = {}
GP.Camp = C

C.KEY = "camp"
C.TRACK, C.RESTED, C.CAMPFIRE, C.BENEFITS = 429960, 429959, 1229739, 1229741
C.PERIOD = 60          -- the tracking aura's period (SpellEffect 1114589)
C.MAX = 3              -- Well-Rested's stacks (the item's text)
C.MARGIN = 0.5
C.CAMP_SLACK = 2       -- the benefits and the next campfire land together, in either order
C.EPSILON = 1e-6
C.OVERDUE = 3
C.COUNT = 10
C.RETRY, C.RETRY_MAX = 1, 10
C.FRAME_STEP = 0.05
C.TEST_SECONDS = 20
-- The client's countdown sounds (SoundKitConstants.lua): /countdown's, then the
-- older battleground ones; the first the client plays is kept.
C.SOUNDS = { tick = { 158565, 25477 }, finish = { 158566, 25478 } }

local events = CreateFrame("Frame")
local ticker = CreateFrame("Frame")
C.state = { gen = 0, queued = false, retry = false, retries = 0, prevTrack = nil, prevID = nil,
            presence = nil, camp = nil, benefits = nil, digit = nil, digitPreview = nil, kits = {}, soundFailed = {}, test = nil, reads = {} }
local state = C.state

local function setting(name) return GP.Pearls.Setting(C.KEY, name) end
local function Frame() return GP.CampFrame end

local function spellName(id, fallback)
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and not API.IsSecret(n) and type(n) == "string" and n ~= "" then return n end
    return fallback
end

--------------------------------------------------------------------------------
-- Sounds: only when due; the first kit whose willPlay is plainly true is kept.

function C.Play(kind)
    local list = C.SOUNDS[kind]
    local kept = state.kits[kind]
    local order = {}
    if kept then order[1] = kept end
    for _, kit in ipairs(list) do if kit ~= kept then order[#order + 1] = kit end end
    for _, kit in ipairs(order) do
        local ok, willPlay = pcall(PlaySound, kit, "Master")
        if ok and not API.IsSecret(willPlay) and willPlay == true then
            state.kits[kind] = kit
            return true
        end
    end
    state.kits[kind] = nil
    if not state.soundFailed[kind] then
        state.soundFailed[kind] = true
        API.Fail("camp sound " .. kind, "refused: " .. table.concat(list, ", "))
    end
    return false
end

--------------------------------------------------------------------------------
-- The bag

local function finish()
    if not setting("bag") then return end
    GP.Notice.Show(("%s %d/%d"):format(spellName(C.RESTED, "Well-Rested"), C.MAX, C.MAX))
    if setting("sound") then C.Play("finish") end
end

-- Well-Rested's read against a presence (a new one included: nothing then
-- anchors, every application time being before its `since`).
local function applyRested(p, wr, wexp, wdur, wcount)
    local usable = wr == "present" and wexp > 0 and wdur > 0
    local app = usable and (wexp - wdur) or nil
    local count
    if wr == "absent" then count = 0 elseif wr == "present" then count = wcount end
    local witnessed = wr == "present" and (p.rested == "absent" or (count and p.count and count > p.count))
    if witnessed then
        p.pending, p.entered = true, nil      -- a stack landed: `entered` is over
    end
    -- Full: 3 stacks given during this presence (a rise, or a refresh at 3/3).
    if count and count >= C.MAX and not p.full and (witnessed or (app and app > p.since + C.MARGIN)) then
        p.full = true
        finish()
    end
    -- While pending, the anchor is ignored (C.BagView) until a usable time comes.
    if app then
        if p.pending then
            p.anchor, p.pending = app, false
        elseif app > p.since + C.MARGIN and (not p.anchor or app > p.anchor) then
            p.anchor = app
        end
    end
    if wr == "absent" or wr == "present" then p.rested = wr end
    if count ~= nil then p.count = count end
    p.countNow = count
    p.usableNow = usable
    p.restedEnds = usable and wexp or nil
    return wr == "unknown" or (wr == "present" and (wcount == nil or not usable))
end

local function newPresence(t, entered)
    return { since = t, entered = entered, anchor = nil, pending = false, rested = nil, count = nil,
             countNow = nil, usableNow = false, restedEnds = nil, full = false }
end

-- The bag bar's view, or nil: { id, count, max, endsAt, span } (endsAt nil: waiting).
function C.BagView(t)
    local p = state.presence
    if not p or not setting("bag") then return nil end
    if p.full then return nil end
    local v = { kind = "bag", id = C.RESTED, count = p.countNow, max = C.MAX, span = C.PERIOD }
    local anchor = p.anchor or p.entered
    if anchor and not p.pending then
        local nextAt = anchor + C.PERIOD
        if t <= nextAt + C.OVERDUE then v.endsAt = nextAt end
    end
    return v
end

-- The next tick's time when it will make the stacks full and may be counted
-- down, else nil.
function C.CountdownDeadline(t)
    if not setting("countdown") then return nil end
    local v = C.BagView(t)
    if not (v and v.endsAt) then return nil end
    local p = state.presence
    if not (p.countNow and p.countNow >= C.MAX - 1 and p.usableNow) then return nil end
    if not (p.restedEnds and p.restedEnds > v.endsAt + C.OVERDUE) then return nil end
    return v.endsAt
end

--------------------------------------------------------------------------------
-- The check

local render

local function scheduleRetry()
    if state.retry or API.InCombat() or state.retries >= C.RETRY_MAX then return end
    state.retry, state.retries = true, state.retries + 1
    local gen = state.gen
    C_Timer.After(C.RETRY, function()
        if gen ~= state.gen then return end
        state.retry = false
        C.Check()
    end)
end

function C.Check()
    if not C.enabled then return end
    local t = GetTime()
    local tr, _, _, _, _, tid = AA.Read(C.TRACK)
    local wr, wexp, wdur, _, wcount = AA.Read(C.RESTED)
    local cf, cexp, cdur = AA.Read(C.CAMPFIRE)
    local cb, bexp, bdur = AA.Read(C.BENEFITS)
    state.reads = { track = tr, trackID = tid, rested = wr, restedCount = wcount, campfire = cf, benefits = cb }
    local unresolved = tr == "unknown"
    local p = state.presence
    -- Well-Rested first, against the presence it belongs to: the third stack and
    -- leaving the bag in one check still finish.
    if p and tr ~= "unknown" then
        local open = applyRested(p, wr, wexp, wdur, wcount)
        unresolved = unresolved or (open and tr == "present")
    end
    if tr == "present" then
        local fresh, entered = p == nil, nil
        if fresh then
            if state.prevTrack == "absent" then entered = t end
        elseif state.prevID ~= nil and tid ~= state.prevID then
            fresh = true
            if tid ~= nil then entered = t end
        end
        if fresh then
            p = newPresence(t, entered)
            state.presence = p
            unresolved = applyRested(p, wr, wexp, wdur, wcount) or unresolved
        end
    else
        state.presence = nil       -- absent: left; unknown: lost (its countdown ends)
    end
    state.prevTrack, state.prevID = tr, tr == "present" and tid or nil
    -- The campfire.
    if cf == "present" and cexp > 0 and cdur > 0 then
        state.camp = { ends = cexp, span = cdur, app = cexp - cdur }
    elseif cf == "absent" then
        state.camp = nil
    end
    if cb == "present" and bexp > 0 and bdur > 0 then
        state.benefits = bexp - bdur
    elseif cb == "absent" then
        state.benefits = nil
    end
    if unresolved then scheduleRetry() else state.retries = 0 end
    render(t)
end

local function queue()
    if state.queued then return end
    state.queued = true
    local gen = state.gen
    C_Timer.After(0, function()
        if gen ~= state.gen then return end
        state.queued = false
        C.Check()
    end)
end

--------------------------------------------------------------------------------
-- What is shown

local function testViews(t)
    local ends = state.test.ends
    return { { kind = "bag", id = C.RESTED, count = C.MAX - 1, max = C.MAX, span = C.PERIOD, endsAt = ends },
             { kind = "camp", id = C.CAMPFIRE, span = C.PERIOD, endsAt = ends } }
end

function C.Views(t)
    if state.test then return testViews(t) end
    local views = {}
    local bag = C.BagView(t)
    if bag then views[#views + 1] = bag end
    local camp = state.camp
    if camp and camp.ends <= t then state.camp, camp = nil, nil end
    -- The benefits given at (or just before) this campfire's start: only a refresh is left.
    local given = camp and state.benefits and state.benefits >= camp.app - C.CAMP_SLACK
    if camp and not given and setting("campfire") then
        views[#views + 1] = { kind = "camp", id = C.CAMPFIRE, span = camp.span, endsAt = camp.ends }
    end
    return views
end

local function digitAt(deadline, t)
    if not deadline then return nil end
    local left = deadline - t
    -- EPSILON: a float a hair over a whole second (60.0000001) is that second.
    if left > 0 and left <= C.COUNT + C.EPSILON then return math.ceil(left - C.EPSILON) end
end

local function onUpdate(self, elapsed)
    self.wait = (self.wait or 0) - (elapsed or 0)
    if self.wait > 0 then return end
    self.wait = C.FRAME_STEP
    render(GetTime())
end

render = function(t)
    if not C.enabled then return end
    t = t or GetTime()
    local views = C.Views(t)
    local d
    if state.test then
        d = digitAt(state.test.ends, t)
    else
        d = digitAt(C.CountdownDeadline(t), t)
    end
    -- A new digit, or the same one handed between a test and a live countdown
    -- (its strata, and a live one's tick).
    local preview = state.test ~= nil
    if d ~= state.digit or (d and preview ~= state.digitPreview) then
        state.digit, state.digitPreview = d, preview
        Frame().Digit(d, preview)
        if d and not preview and setting("sound") then C.Play("tick") end
    end
    if #views > 0 then
        Frame().Show(views, t)
        if not ticker:GetScript("OnUpdate") then ticker:SetScript("OnUpdate", onUpdate) end
    else
        Frame().Hide()
        ticker:SetScript("OnUpdate", nil)
    end
end
C.Render = render

--------------------------------------------------------------------------------
-- Commands

local function fmt(v) return v == nil and "-" or type(v) == "number" and ("%.1f"):format(v) or tostring(v) end

function C.Report()
    local r, t = state.reads, GetTime()
    API.Print("Camp timers: what the game answers (by spell ID).")
    API.Print(("  %d %s: %s, instance %s"):format(C.TRACK, spellName(C.TRACK, "tracking"), fmt(r.track), fmt(r.trackID)))
    API.Print(("  %d %s: %s, stacks %s"):format(C.RESTED, spellName(C.RESTED, "Well-Rested"), fmt(r.rested),
        fmt(r.restedCount)))
    API.Print(("  %d %s: %s"):format(C.CAMPFIRE, spellName(C.CAMPFIRE, "campfire"), fmt(r.campfire)))
    API.Print(("  %d %s: %s"):format(C.BENEFITS, spellName(C.BENEFITS, "benefits"), fmt(r.benefits)))
    local p = state.presence
    if p then
        local v = C.BagView(t)
        API.Print(("  In the bag since %s s ago; entered %s, anchor %s, pending %s, stacks %s, full %s, next tick in %s s."):format(
            fmt(t - p.since), p.entered and "seen" or "not seen", p.anchor and fmt(t - p.anchor) .. " s ago" or "none",
            tostring(p.pending), fmt(p.count), tostring(p.full), v and v.endsAt and fmt(v.endsAt - t) or "?"))
    else
        API.Print("  Not in a sleeping bag.")
    end
    API.Print(("  Sounds: tick %s, finish %s."):format(fmt(state.kits.tick), fmt(state.kits.finish)))
end

function C.Test()
    if not C.enabled then return API.Print("Camp timers are off: /gpearls camp on.") end
    local t = GetTime()
    local test = { ends = t + C.TEST_SECONDS }
    state.test = test
    local gen = state.gen
    render(t)
    Frame().Unlock()
    C_Timer.After(C.TEST_SECONDS, function()
        -- Only this test's own end: a test started again runs its full time.
        if gen ~= state.gen or state.test ~= test then return end
        state.test = nil
        Frame().Lock()
        render()
    end)
    API.Print("Test bars for " .. C.TEST_SECONDS .. " s, with the countdown at the end: drag them where you want them.")
end

local function command(arg)
    if arg == "test" then return C.Test() end
    C.Report()
end

--------------------------------------------------------------------------------
-- The pearl

events:SetScript("OnEvent", function(_, event)
    -- UNIT_AURA's arguments are never read (they can be secret).
    API.NoteCombat(event)
    if event == "UNIT_AURA" then
        queue()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A loading screen breaks every visit: the next one is a new presence.
        state.presence, state.prevTrack, state.prevID = nil, nil, nil
        C.Check()
    elseif event == "PLAYER_REGEN_ENABLED" then
        C.Check()
    end
end)

local function reset()
    state.gen = state.gen + 1
    state.queued, state.retry, state.retries = false, false, 0
    state.presence, state.prevTrack, state.prevID, state.camp, state.test = nil, nil, nil, nil, nil
    state.benefits = nil
end

local function enable()
    reset()
    C.enabled = true
    local ok, registered = pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    if not ok then API.Fail("pearl camp UNIT_AURA", registered)
    elseif registered == false then API.Fail("pearl camp UNIT_AURA", "refused") end
    API.RegisterEvents(events, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    C.Check()
end

local function disable()
    C.enabled = false
    reset()
    events:UnregisterAllEvents()
    ticker:SetScript("OnUpdate", nil)
    state.digit, state.digitPreview = nil, nil
    Frame().Digit(nil)
    Frame().Lock()
    Frame().Hide()
end

GP.Pearls.Register({
    key = C.KEY,
    name = "Camp timers",
    desc = "Bars for the sleeping bag's next Well-Rested stack and the campfire's benefits, with a countdown before the bag tops you up.",
    help = "While you rest in a Cozy Sleeping Bag: a bar with your Well-Rested stacks and the time to the next one (a "
        .. "stack every minute, up to 3), and a 10 second countdown before the third, with the game's countdown "
        .. "sound. Already at 3 stacks, it counts down to the minute that puts them back to their full 2 hours. "
        .. "Leave the bag when it says 3/3. Next to a campfire: a bar with the time left until its camp "
        .. "benefits, gone once they're given. The bag's time shows only once the game has given a stack or seen you lie down (after a "
        .. "/reload it waits for the next stack). /gpearls camp says what the game answers; /gpearls camp test "
        .. "shows the bars to place them. Unmeasured until checked in game.",
    default = true,
    category = "Interface",
    section = "Timers",
    defaults = { bag = true, campfire = true, countdown = true, sound = true },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.CampFrame.Configure(panel, refreshers) end,
    onSettingChanged = function()
        if C.enabled then render() end
    end,
    commands = { camp = { help = "[test] - what the game answers the camp timers, or show the bars to place them",
                          run = command } },
})

C._test = { events = events, ticker = ticker }
