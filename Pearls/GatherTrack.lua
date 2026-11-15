-- Pearls/GatherTrack.lua: gathering tracking (#110). On a character that knows
-- Find Herbs or Find Minerals, turn it back on by itself at login and after a
-- death, never fighting a tracking the player turns off afterwards.
--
-- Measured (NodeRadar's probe, 70450; porting guide): C_Minimap.SetTracking(i,
-- true) from addon code casts the tracking spell, out of combat, no blocked
-- action, and costs a global cooldown. Tracking is multi-select here.
--
-- The arm (one at most): made at the first PLAYER_ENTERING_WORLD of a login,
-- at a revival after a death seen this session (PLAYER_DEAD; then
-- PLAYER_ALIVE, PLAYER_UNGHOST or PLAYER_ENTERING_WORLD with the player
-- plainly alive), or by switching the pearl on after the login.
-- Per kind: pending, satisfied (seen active once: permanent for the arm, so a
-- later off is the player's) or gave up; a kind is dropped only when its
-- spells are plainly not known. Ended when nothing is pending, after 10
-- minutes, by a death or Disable; a loading screen
-- keeps it and gates every step until the world is back.
--
-- One scheduler: nextAt (the earliest next call, authoritative for every
-- wakeup) and one pending wakeup with a token. A step scans the tracking list
-- again (indexes shift), waits while anything says no (combat, dead, feign
-- death, taxi, control, vehicle, stealth, a cast, NodeRadar's experiment, the
-- tracking spell's cooldown) without spending an attempt, then makes one call,
-- recorded in flight before it, checked 1.5 s later; at most 3 per kind.
-- Codex, three rounds (#110). Unmeasured until checked in game.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local GT = {}
GP.GatherTrack = GT

GT.KEY = "gathertrack"
GT.KINDS = { herbs = { 2383, 8387 }, minerals = { 2580, 8388 } }   -- SpellName, 70938: two IDs per name
GT.ORDER = { "herbs", "minerals" }
GT.FALLBACK = { herbs = "Find Herbs", minerals = "Find Minerals" }
GT.FIRST = { login = 3, revival = 1, switched = 1 }   -- the first wakeup after an arm
GT.DEADLINE = 600      -- an arm still waiting after this is dropped
GT.TRIES = 3           -- calls per kind per arm
GT.CHECK = 1.5         -- a call is judged this long after it
GT.GCD = 1.6           -- the global cooldown a call costs: the next call no sooner
GT.POLL = 5            -- while something says no
GT.LOG_MAX = 10

local byID = {}
for kind, ids in pairs(GT.KINDS) do for _, id in ipairs(ids) do byID[id] = kind end end

local events = CreateFrame("Frame")
local state = {
    arm = nil,           -- { reason, deadline, kinds = { [kind] = "pending" | "satisfied" | "gaveup" }, attempts, waiting }
    flight = nil,        -- { kind, at }: our call, until seen on or judged
    died = false,        -- a death seen this session, until a plain revival
    loading = false,     -- between PLAYER_LEAVING_WORLD and PLAYER_ENTERING_WORLD
    loggedIn = false,    -- the login's PLAYER_ENTERING_WORLD came
    started = false,     -- the registry's Start ran (a later Enable is a switch, not a reload)
    nextAt = 0,
    token = 0,
    wakeAt = nil,
}
GT.state = state

-- No settings: every kind the character knows (#110: a per-kind choice would be
-- a synced key, and the sync registry is near its 160).

-- f(...) in a pcall: the first value and true when it is plain, else nil, false.
local function read(f, ...)
    if type(f) ~= "function" then return nil, false end
    local ok, v = pcall(f, ...)
    if not ok or API.IsSecret(v) then return nil, false end
    return v, true
end

local function is(f, want, ...)
    local v, ok = read(f, ...)
    return ok and v == want
end

local function log()
    local db = GP.charDB
    if not db then return {} end
    if type(db.gathertrack) ~= "table" then db.gathertrack = {} end
    return db.gathertrack
end

local function note(kind, outcome)
    local l = log()
    local ok, t = pcall(GetServerTime)
    l[#l + 1] = { kind = kind, outcome = outcome, reason = state.arm and state.arm.reason or nil,
        t = (ok and not API.IsSecret(t) and type(t) == "number") and t or 0 }
    while #l > GT.LOG_MAX do table.remove(l, 1) end
end

function GT.Name(kind)
    local name, ok = read(C_Spell.GetSpellName, GT.KINDS[kind][1])
    if ok and type(name) == "string" and name ~= "" then return name end
    return GT.FALLBACK[kind]
end

--------------------------------------------------------------------------------
-- What the client says

-- Per kind { index, spellID, active (true | false | nil: unreadable) } for the
-- first entry of that kind, and whether the whole list read plainly.
function GT.Scan()
    local found, complete = {}, true
    local n, ok = read(C_Minimap.GetNumTrackingTypes)
    if not ok or type(n) ~= "number" or n < 0 or n ~= math.floor(n) then return found, false end
    for i = 1, n do
        local okc, info = pcall(C_Minimap.GetTrackingInfo, i)
        if not okc or API.IsSecret(info) or (info ~= nil and type(info) ~= "table") then
            complete = false
        elseif info then
            local id = info.spellID
            if API.IsSecret(id) or (id ~= nil and type(id) ~= "number") then
                complete = false
            elseif id and byID[id] and not found[byID[id]] then
                local a = info.active
                local active = nil
                if not API.IsSecret(a) and type(a) == "boolean" then active = a end
                found[byID[id]] = { index = i, spellID = id, active = active }
            end
        end
    end
    return found, complete
end

-- true: one of the kind's spells is known; false: all plainly not; nil: can't tell.
function GT.Known(kind)
    local unsure = false
    for _, id in ipairs(GT.KINDS[kind]) do
        local v, ok = read(IsPlayerSpell, id)
        if ok and v == true then return true end
        if not ok or type(v) ~= "boolean" then unsure = true end
    end
    if unsure then return nil end
    return false
end

-- Why a call can't be made now, or nil.
function GT.Blocked(spellID)
    if API.InCombat() then return "combat" end
    if not is(UnitIsDeadOrGhost, false, "player") then return "dead" end
    if not is(UnitIsFeignDeath, false, "player") then return "feign death" end
    if not is(UnitOnTaxi, false, "player") then return "taxi" end
    if not is(HasFullControl, true) then return "control" end
    if not is(UnitInVehicle, false, "player") or not is(UnitHasVehicleUI, false, "player") then return "vehicle" end
    if not is(IsStealthed, false) then return "stealth" end
    local cast, okc = read(UnitCastingInfo, "player")
    local chan, okh = read(UnitChannelInfo, "player")
    if not okc or cast ~= nil or not okh or chan ~= nil then return "casting" end
    local nr = rawget(_G, "NodeRadar")
    if type(nr) == "table" and type(nr.Learn) == "table" and type(nr.Learn.Busy) == "function" then
        if not is(nr.Learn.Busy, false) then return "NodeRadar" end
    end
    local cd, okd = read(C_Spell.GetSpellCooldown, spellID)
    if not okd or type(cd) ~= "table" or API.IsSecret(cd.isActive) or type(cd.isActive) ~= "boolean" then
        return "cooldown unreadable"
    end
    if cd.isActive then return "cooldown" end
    return nil
end

--------------------------------------------------------------------------------
-- The arm

local function finishIfDone()
    local arm = state.arm
    if not arm then return true end
    for _, st in pairs(arm.kinds) do if st == "pending" then return false end end
    state.arm, state.flight = nil, nil
    return true
end

-- Any pending kind seen active is satisfied, for good (never while loading).
local function observe(found)
    local arm = state.arm
    if not arm or state.loading then return end
    for kind, st in pairs(arm.kinds) do
        if st == "pending" and found[kind] and found[kind].active == true then
            arm.kinds[kind] = "satisfied"
            note(kind, (arm.attempts[kind] or 0) > 0 and "on" or "already on")
            if state.flight and state.flight.kind == kind then state.flight = nil end
        end
    end
    finishIfDone()
end
GT.Observe = observe

local function cancelWake()
    state.token = state.token + 1
    state.wakeAt = nil
end

function GT.Wake(delay)
    if not state.arm or state.loading then return end
    local now = GetTime()
    local at = math.max(now + (delay or 0), state.nextAt)
    if state.wakeAt and state.wakeAt <= at then return end   -- an earlier one is pending
    state.token = state.token + 1
    local token = state.token
    state.wakeAt = at
    C_Timer.After(math.max(0, at - now), function()
        if token ~= state.token then return end
        state.wakeAt = nil
        GT.Step()
    end)
end

local function plainlyDead() return is(UnitIsDeadOrGhost, true, "player") end

-- A new arm.
function GT.Arm(reason)
    if not GT.enabled then return end
    local now = GetTime()
    local arm = { reason = reason, deadline = now + GT.DEADLINE, kinds = {}, attempts = {} }
    state.arm, state.flight = arm, nil
    state.nextAt = math.max(state.nextAt, now + GT.FIRST[reason])
    cancelWake()
    for _, kind in ipairs(GT.ORDER) do
        if GT.Known(kind) == false then
            arm.kinds[kind] = nil
        else
            arm.kinds[kind], arm.attempts[kind] = "pending", 0
        end
    end
    if not state.loading then observe(GT.Scan()) end
    GT.Wake(0)
end

local function revival()
    if state.died and is(UnitIsDeadOrGhost, false, "player") then
        state.died = false
        GT.Arm("revival")
    end
end

function GT.Step()
    local arm = state.arm
    if state.loading or not arm or not GT.enabled then return end
    local now = GetTime()
    if now >= arm.deadline then
        for kind, st in pairs(arm.kinds) do if st == "pending" then note(kind, "dropped after waiting") end end
        state.arm, state.flight = nil, nil
        return
    end
    if now < state.nextAt then GT.Wake(0) return end
    local found = GT.Scan()
    observe(found)
    if not state.arm then return end
    local fl = state.flight
    if fl then
        if now < fl.at + GT.CHECK then GT.Wake(fl.at + GT.CHECK - now) return end
        state.flight = nil                    -- judged: its attempt counted already
    end
    local cand
    for _, kind in ipairs(GT.ORDER) do
        if arm.kinds[kind] == "pending" then
            local e = found[kind]
            if e then
                if e.active == false then
                    if arm.attempts[kind] >= GT.TRIES then
                        arm.kinds[kind] = "gaveup"
                        note(kind, ("gave up after %d"):format(GT.TRIES))
                    elseif not cand then
                        cand = kind
                    end
                end
            elseif GT.Known(kind) == false then
                arm.kinds[kind] = nil
            end
        end
    end
    if finishIfDone() then return end
    if not cand then
        arm.waiting = "the tracking list"
        GT.Wake(GT.POLL)
        return
    end
    local e = found[cand]
    local blocked = GT.Blocked(e.spellID)
    if blocked then
        arm.waiting = blocked
        GT.Wake(GT.POLL)
        return
    end
    arm.waiting = nil
    arm.attempts[cand] = arm.attempts[cand] + 1
    state.flight = { kind = cand, at = now }
    state.nextAt = now + GT.GCD
    local ok, err = pcall(C_Minimap.SetTracking, e.index, true)
    if not ok then
        API.Fail("pearl gathertrack SetTracking", err)
        note(cand, "refused")
    end
    GT.Wake(GT.CHECK)
end

--------------------------------------------------------------------------------
-- Events

local WAKERS = {
    PLAYER_REGEN_ENABLED = true, UPDATE_STEALTH = true, PLAYER_CONTROL_GAINED = true,
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_FLAGS = true, UNIT_AURA = true,
}

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if event == "PLAYER_ENTERING_WORLD" then
        state.loading = false
        local initial = ...
        if not state.loggedIn and not API.IsSecret(initial) and initial == true then
            state.loggedIn = true
            if plainlyDead() then state.died = true else GT.Arm("login") end
        else
            revival()
        end
        GT.Wake(0)                            -- resumes an arm the loading screen held
    elseif event == "PLAYER_LEAVING_WORLD" then
        state.loading = true
        cancelWake()
    elseif event == "PLAYER_DEAD" then
        state.died = true
        state.arm, state.flight = nil, nil
        cancelWake()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        revival()
    elseif event == "MINIMAP_UPDATE_TRACKING" then
        if not state.loading then observe(GT.Scan()) end
        GT.Wake(0)
    elseif WAKERS[event] then
        GT.Wake(0)                            -- payloads never read
    end
end)

local function enable()
    GT.enabled = true
    state.loading = false
    API.RegisterEvents(events, { "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE",
        "PLAYER_UNGHOST", "MINIMAP_UPDATE_TRACKING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "UPDATE_STEALTH", "PLAYER_CONTROL_GAINED" })
    for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_FLAGS", "UNIT_AURA" }) do
        local ok, registered = pcall(events.RegisterUnitEvent, events, e, "player")
        if not ok then API.Fail("pearl gathertrack " .. e, registered)
        elseif registered == false then API.Fail("pearl gathertrack " .. e, "refused") end
    end
    -- Switched on after the login (a reload's Enable comes before Start, and arms nothing).
    if state.started and not plainlyDead() then GT.Arm("switched") end
end

local function disable()
    GT.enabled = false
    events:UnregisterAllEvents()
    state.arm, state.flight, state.died = nil, nil, false
    cancelWake()
end

--------------------------------------------------------------------------------
-- The report and the panel

local function report()
    local found, complete = GT.Scan()
    API.Print(("Gathering tracking: %s; tracking list %s."):format(GT.enabled and "on" or "off",
        complete and "read" or "partly unreadable"))
    for _, kind in ipairs(GT.ORDER) do
        local e = found[kind]
        local known = GT.Known(kind)
        API.Print(("  %s: %s, %s."):format(GT.Name(kind),
            e and ("entry %d, spell %d, %s"):format(e.index, e.spellID,
                e.active == nil and "unreadable" or (e.active and "active" or "inactive")) or "no entry",
            known == nil and "known: can't tell" or (known and "known" or "not known")))
    end
    local arm = state.arm
    if arm then
        local parts = {}
        for _, kind in ipairs(GT.ORDER) do
            if arm.kinds[kind] then
                parts[#parts + 1] = ("%s %s (%d)"):format(kind, arm.kinds[kind], arm.attempts[kind] or 0)
            end
        end
        API.Print(("  Armed (%s): %s%s; %d s left."):format(arm.reason, table.concat(parts, ", "),
            arm.waiting and ("; waiting for " .. arm.waiting) or "", math.max(0, math.floor(arm.deadline - GetTime()))))
    else
        API.Print("  Not armed" .. (state.died and " (a death seen: waiting for the revival)." or "."))
    end
    local l = log()
    if #l == 0 then API.Print("  Nothing recorded yet.") end
    for _, e in ipairs(l) do
        API.Print(("  %s: %s%s."):format(tostring(e.kind), tostring(e.outcome), e.reason and (" (" .. e.reason .. ")") or ""))
    end
end

GP.Pearls.Register({
    key = GT.KEY,
    name = "Gathering tracking",
    desc = "Turns Find Herbs and Find Minerals back on at login and after a death, on characters that know them.",
    help = "At login and when you come back to life, Find Herbs and Find Minerals are "
        .. "turned back on if your character knows them and they're off. It casts the tracking as the minimap's menu "
        .. "does, which costs a global cooldown, so it never acts in combat and waits while you cast, are stealthed, "
        .. "on a taxi or feigning death. If you turn one off afterwards, it stays off until your next login or death. "
        .. "/gpearls gathertrack shows what it sees and did. Unverified until checked in game.",
    default = true,
    category = "Professions",
    section = "Gathering",
    Enable = enable,
    Disable = disable,
    Start = function() state.started = true end,
    commands = { gathertrack = { help = "- what gathering tracking sees, and what it did", run = report } },
})

GT._test = { state = state, events = events }
