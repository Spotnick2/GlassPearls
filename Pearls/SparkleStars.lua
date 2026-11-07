-- Pearls/SparkleStars.lua: the quest loot sparkle's experimental stars (#79):
-- NodeRadar's twinkling stars (its Marker.lua, MIT, the same owner; the look
-- follows Final Fantasy XIV's gathering sparkle) on a quest object.
--
-- Where: the nameplate the game gives its soft-interact target, on the object
-- at its real height, one at a time, the selected object only, within about
-- 15 yards (porting guide, measured with NodeRadar). A frame of ours on
-- UIParent is anchored to that plate's BOTTOM while its unit is a game object
-- and the soft-interact target, and, for "quest", related to an active quest
-- (C_QuestLog.UnitIsRelatedToActiveQuest: unmeasured for a game object;
-- `/gpearls sparkle target` tells). "all" ignores the quest test.
--
-- The plate needs three of the player's CVars (#90): the client reports two of
-- them secure (measured 2026-11-06), so temps never reached them; they are
-- claimed like NodeRadar's marker does, persistently, with SetCVar (Codex,
-- four rounds). GlassPearlsDB.sparkle:
--   soft[name] = { old, ours, st }, st:
--     owned        confirmed ours (wanted)
--     unconfirmed  set, the read-back unreadable (wanted)
--     release      to put back to old (not wanted)
--     retained     our put-back may have happened (a logout, or turned on
--                  again before a put-back was confirmed): the next read decides
--     cancelled    someone else changed it while wanted: theirs stands until
--                  the stars go off and on (no old kept)
--   softActive     set while wanted: a reload isn't a turn-on
--   softPending    first claims of this activation not run yet
-- Edges (no CVar access): on (wanted, softActive unset) and off. Every read and
-- write happens in a pass, per name, right after a plain read; nothing writes
-- from an event. Gates: no pass while unsettled (until SETTLE seconds after
-- the first PLAYER_ENTERING_WORLD: the client's synced CVars arrive late,
-- NodeRadar measured) or logging out; a name in the gamepad UI or held as a
-- temp by easy fishing is masked (its saved value can't be read); combat
-- blocks writes, not judgments. A name already at ours is the player's: never
-- claimed, never put back. NodeRadar claims the same names: whoever wrote one
-- puts it back, and the other's stars may stop until switched off and on.
-- At logout, best effort, ours is put back (the record kept, retained) so
-- removing Glass Pearls leaves the player's values; the next login reapplies.
-- A whole-pearl-off login finishes a put-back: Start (the registry's, every
-- pearl at login) arms the passes.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local ST = {}
GP.SparkleStars = ST

ST.MODES = { "off", "quest", "all" }
-- The names easy fishing uses for the same CVars (Pearls/Fishing.lua), so its held table matches.
ST.CVARS = { { "SoftTargetInteract", "3" }, { "SoftTargetInteractRange", "60" }, { "SoftTargetIconGameObject", "1" } }
ST.TICK = 0.5
ST.SETTLE = 5
ST.MEDIA = "Interface\\AddOns\\GlassPearls\\Media\\"
ST.STAR, ST.SPREAD, ST.GLOW, ST.STARS = 48, 30, 96, 4
ST.TEAL = { 0.35, 0.9, 0.75 }

local STATES = { owned = true, unconfirmed = true, release = true, retained = true, cancelled = true }

local state = {
    bound = nil,       -- { unit, plate }: the plate the stars are on
    active = false,    -- the listeners registered
    started = false,   -- Start ran (the lifecycle frame registered)
    settleAt = nil,    -- GetTime() from which the client's synced CVars are in
    loggingOut = false,
    notes = {},        -- name -> what the last first claim found, for the report
}
ST.state = state

local events = CreateFrame("Frame")
local life = CreateFrame("Frame")
local driver = CreateFrame("Frame")
local since = 0

--------------------------------------------------------------------------------
-- Reading the client

-- One call's first value, labelled: value, "ok" | "secret" | "error" | "absent".
local function call(fn, ...)
    if type(fn) ~= "function" then return nil, "absent" end
    local ok, v = pcall(fn, ...)
    if not ok then return nil, "error" end
    if API.IsSecret(v) then return nil, "secret" end
    return v, "ok"
end
local function yes(fn, ...) local v, how = call(fn, ...); return how == "ok" and v == true end
local function api(ns, name)
    local t = rawget(_G, ns)
    return type(t) == "table" and t[name] or nil
end
local function text(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

-- The option, while the pearl is on: "off", "quest" or "all".
function ST.Mode()
    if not (GP.Sparkle and GP.Sparkle.enabled) then return "off" end
    local m = GP.Pearls.Setting("sparkle", "stars")
    return (m == "quest" or m == "all") and m or "off"
end

local function mkb()
    local E = rawget(_G, "Enum")
    local types = E and E.InputDeviceInterfaceType
    local s, how = call(api("C_InputInterfaceStyle", "GetCurrentStyle"))
    return how == "ok" and types ~= nil and s == types.Mkb
end

function ST.Wanted() return ST.Mode() ~= "off" end

--------------------------------------------------------------------------------
-- The CVars (#90)

local function read(name)
    local v, how = call(C_CVar.GetCVar, name)
    if how ~= "ok" or type(v) ~= "string" then return nil end
    return v
end
-- CVars can read back reformatted ("60.000000" for 60).
local function same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and x == y
end

-- The store, its records checked (a saved file can hold anything): nil before the saved variables.
local function store()
    local d = GP.db
    if type(d) ~= "table" then return nil end
    if type(d.sparkle) ~= "table" then d.sparkle = {} end
    local s = d.sparkle
    if type(s.soft) ~= "table" then s.soft = {} end
    if type(s.softPending) ~= "table" then s.softPending = {} end
    for name, r in pairs(s.soft) do
        local ok = type(r) == "table" and STATES[r.st]
            and (r.st == "cancelled" or (type(r.old) == "string" and type(r.ours) == "string"))
        if not ok then s.soft[name] = nil end
    end
    return s
end

local function fishingHolds(name)
    local F = GP.Fishing
    return type(F) == "table" and type(F.state) == "table" and type(F.state.held) == "table"
        and F.state.held[name] ~= nil
end

-- Why a name can't be judged now (its saved value hidden behind a temp), or nil.
local function masked(name)
    if not mkb() then return "the gamepad UI" end
    if fishingHolds(name) then return "easy fishing" end
end
local function unsettled() return state.settleAt == nil or GetTime() < state.settleAt end

-- SetCVar in a pcall: true when the call returned (its result is judged by a read).
local function set(name, value)
    local ok, err = pcall(C_CVar.SetCVar, name, value)
    if not ok then API.Fail("pearl sparkle stars " .. name, err) end
    return ok
end

-- The edges, from Update (no CVar access).
local function edges(s)
    local want = ST.Wanted()
    if want and not s.softActive then
        s.softActive, s.softPending, state.notes = true, {}, {}
        for _, c in ipairs(ST.CVARS) do
            local r = s.soft[c[1]]
            if r == nil then s.softPending[c[1]] = true
            elseif r.st == "release" then r.st = "retained" end      -- its put-back may have happened
        end
    elseif not want and s.softActive then
        s.softActive, s.softPending = nil, {}
        for name, r in pairs(s.soft) do
            if r.st == "cancelled" then s.soft[name] = nil
            elseif r.st == "owned" or r.st == "unconfirmed" then r.st = "release" end
        end
    end
end

-- One name, one plain read, then at most one write and its read-back.
local function step(s, name, ours, want, blocked)
    if masked(name) then return end
    local v = read(name)
    if v == nil then return end
    local r = s.soft[name]
    if r == nil then
        if not s.softPending[name] then return end
        if same(v, ours) then
            s.softPending[name], state.notes[name] = nil, "yours"   -- already at ours: never put back
            return
        end
        if blocked then return end
        s.softPending[name] = nil
        if not set(name, ours) then state.notes[name] = "the set threw"; return end
        local b = read(name)
        if b == nil then s.soft[name] = { old = v, ours = ours, st = "unconfirmed" }
        elseif same(b, ours) then s.soft[name] = { old = v, ours = ours, st = "owned" }
        elseif same(b, v) then state.notes[name] = "the set didn't take"
        else state.notes[name] = "changed meanwhile" end
    elseif r.st == "cancelled" then
        return                                                     -- theirs, until off and on
    elseif r.st == "owned" or r.st == "unconfirmed" then
        if same(v, r.ours) then r.st = "owned" else s.soft[name] = { st = "cancelled" } end
    elseif r.st == "release" then
        if not same(v, r.ours) then s.soft[name] = nil; return end   -- put back, or theirs now
        if blocked or not set(name, r.old) then return end
        local b = read(name)
        if b ~= nil and not same(b, r.ours) then s.soft[name] = nil end
    elseif r.st == "retained" then
        if same(v, r.ours) then r.st = want and "owned" or "release"; return end
        if not same(v, r.old) then s.soft[name] = want and { st = "cancelled" } or nil; return end
        if not want then s.soft[name] = nil; return end               -- already the player's
        if blocked or not set(name, r.ours) then return end
        local b = read(name)
        if b == nil then r.st = "unconfirmed"
        elseif same(b, r.ours) then r.st = "owned"
        elseif not same(b, r.old) then s.soft[name] = { st = "cancelled" } end
    end
end

-- One pass over the CVars.
function ST.Claims()
    local s = store()
    if not s then return end
    edges(s)
    if state.loggingOut or unsettled() then return end
    local want, blocked = ST.Wanted(), API.InCombat()
    for _, c in ipairs(ST.CVARS) do step(s, c[1], c[2], want, blocked) end
end

-- Best effort at logout: ours put back so removing Glass Pearls leaves the
-- player's values; the record kept (retained) for the next login to decide.
local function atLogout()
    state.loggingOut = true
    local s = store()
    if not s or unsettled() or API.InCombat() then return end
    for _, c in ipairs(ST.CVARS) do
        local name = c[1]
        local r = s.soft[name]
        if r and (r.st == "owned" or r.st == "unconfirmed") and not masked(name) then
            local v = read(name)
            if v ~= nil and same(v, r.ours) and set(name, r.old) then
                local b = read(name)
                if b == nil or not same(b, r.ours) then r.st = "retained" end
            end
        end
    end
end

-- Anything left to do: a claim to keep, a put-back, a first claim.
local function pending()
    local s = store()
    return s ~= nil and (next(s.soft) ~= nil or next(s.softPending) ~= nil)
end

--------------------------------------------------------------------------------
-- The stars (NodeRadar's Marker.lua: the same art and timings)

local root, glow, vapor, stars

local function part(file, size, layer, tint)
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(size, size)
    f:SetPoint("CENTER", root, "CENTER")
    f:EnableMouse(false)
    local t = f:CreateTexture(nil, layer)
    t:SetTexture(ST.MEDIA .. file)
    t:SetBlendMode("ADD")
    t:SetAllPoints(f)
    t:SetVertexColor(tint[1], tint[2], tint[3])
    f.tex = t
    return f
end

local function anim(group, kind, from, to, duration, order, delay)
    local a = group:CreateAnimation(kind)
    if kind == "Alpha" then a:SetFromAlpha(from); a:SetToAlpha(to)
    else a:SetScaleFrom(from, from); a:SetScaleTo(to, to) end
    a:SetDuration(duration)
    a:SetOrder(order)
    if delay then a:SetStartDelay(delay) end
    return a
end

-- Three staggered wisps expand and dissolve; only the engine animates them.
local function newVapor()
    local cloud = CreateFrame("Frame", nil, root)
    cloud:SetSize(1, 1)
    cloud:EnableMouse(false)
    cloud:SetPoint("CENTER", root, "CENTER", 0, 0)
    cloud.wisps = {}
    local playing = false
    local function placeWisp(w, delay)
        w:ClearAllPoints()
        w:SetPoint("CENTER", cloud, "CENTER", math.random(-10, 10), math.random(-12, -4))
        w.tex:SetRotation(math.random() * 0.8 - 0.4)
        w.wait:SetStartDelay(delay or math.random() * 0.2)
        w.drift:SetOffset(math.random(-12, 12), 18 + math.random() * 12)
    end
    for i = 1, 3 do
        local w = CreateFrame("Frame", nil, cloud)
        w:SetSize(112, 70)
        w:EnableMouse(false)
        w:SetAlpha(0)
        w.tex = w:CreateTexture(nil, "ARTWORK")
        w.tex:SetTexture(ST.MEDIA .. "MarkerVapor")
        w.tex:SetAllPoints(w)
        w.tex:SetBlendMode("ADD")
        w.tex:SetVertexColor(0.4, 0.9, 0.75)
        local ag = w:CreateAnimationGroup()
        w.wait = anim(ag, "Alpha", 0, 0, 0.01, 1)
        anim(ag, "Alpha", 0, 0.38, 0.65, 2):SetSmoothing("OUT")
        anim(ag, "Alpha", 0.38, 0, 1.6, 2, 0.65):SetSmoothing("IN")
        anim(ag, "Scale", 0.65, 1.2, 2.25, 2)
        w.drift = ag:CreateAnimation("Translation")
        w.drift:SetDuration(2.25)
        w.drift:SetOrder(2)
        ag:SetScript("OnFinished", function() if playing then placeWisp(w); ag:Play() end end)
        w.anim = ag
        cloud.wisps[i] = w
    end
    function cloud.Play()
        playing = true
        for i, w in ipairs(cloud.wisps) do placeWisp(w, (i - 1) * 0.75); w.anim:Play() end
    end
    function cloud.Stop()
        playing = false
        for _, w in ipairs(cloud.wisps) do w.anim:Stop() end
    end
    return cloud
end

-- Diagonal flares of different sizes, a little upward drift, independent pauses.
local function place(s, delay)
    local r, a = ST.SPREAD * math.sqrt(math.random()), math.random() * 2 * math.pi
    s:ClearAllPoints()
    s:SetPoint("CENTER", root, "CENTER", r * math.cos(a), r * math.sin(a) * 0.6)
    local size = ST.STAR * (0.7 + 0.5 * math.random())
    s:SetSize(size, size)
    s.drift:SetOffset(-2 - 5 * math.random(), 3 + 5 * math.random())
    s.wait:SetStartDelay(delay or (0.08 + 0.22 * math.random()))
end

local function build()
    if root then return end
    root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(1, 1)
    root:EnableMouse(false)
    root:SetFrameStrata("BACKGROUND")
    root:Hide()
    glow = part("SonarGlow", ST.GLOW, "ARTWORK", ST.TEAL)
    local g = glow:CreateAnimationGroup()
    anim(g, "Alpha", 0.06, 0.14, 1.6, 1)
    g:SetLooping("BOUNCE")
    glow.anim = g
    vapor = newVapor()
    stars = {}
    for i = 1, ST.STARS do
        local s = part("MarkerStar", ST.STAR, "OVERLAY", { 1, 1, 1 })
        s:SetAlpha(0)
        local ag = s:CreateAnimationGroup()
        s.wait = anim(ag, "Alpha", 0, 0, 0.01, 1, 0)
        anim(ag, "Alpha", 0, 1, 0.12, 2):SetSmoothing("OUT")
        anim(ag, "Scale", 0.2, 1, 0.12, 2):SetSmoothing("OUT")
        anim(ag, "Alpha", 1, 0, 0.54, 3):SetSmoothing("OUT")
        anim(ag, "Scale", 1, 0.25, 0.54, 3):SetSmoothing("IN")
        s.drift = ag:CreateAnimation("Translation")
        s.drift:SetDuration(0.54)
        s.drift:SetOrder(3)
        ag:SetScript("OnFinished", function() if root:IsShown() then place(s); ag:Play() end end)
        s.anim = ag
        stars[i] = s
    end
end

local function play(on)
    for i, s in ipairs(stars) do
        if on then place(s, (i - 1) * 0.82 / ST.STARS); s.anim:Play() else s.anim:Stop() end
    end
    if on then glow.anim:Play(); vapor.Play() else glow.anim:Stop(); vapor.Stop() end
end

-- The stars off their plate: hidden, still, unanchored.
local function unbind()
    if root and (state.bound or root:IsShown()) then
        root:Hide()
        play(false)
        root:ClearAllPoints()
    end
    state.bound = nil
end
ST.Unbind = unbind

--------------------------------------------------------------------------------
-- The plate

-- A plate's unit token, or nil.
local function unitOf(plate)
    if type(plate) ~= "table" then return nil end
    local u = text(plate.namePlateUnitToken)
    if u then return u end
    local uf = plate.UnitFrame
    return type(uf) == "table" and text(uf.unit) or nil
end

local function shownPlate(plate) return yes(plate.IsShown, plate) end

-- The soft-interact game object's plate, by its two identifying reads.
local function selected(unit)
    return yes(UnitIsGameObject, unit) and yes(UnitIsUnit, unit, "softinteract")
end

local function qualifies(unit, mode)
    if not selected(unit) then return false end
    return mode == "all" or yes(api("C_QuestLog", "UnitIsRelatedToActiveQuest"), unit)
end

local function plates()
    local list, how = call(api("C_NamePlate", "GetNamePlates"))
    if how ~= "ok" or type(list) ~= "table" then return nil, how end
    return list
end

-- What should be against what is: the bound plate checked again (a plate is
-- reused for another unit), then a new one looked for.
function ST.Reconcile()
    local mode = ST.Mode()
    if mode == "off" then return unbind() end
    local b = state.bound
    if b and not (shownPlate(b.plate) and unitOf(b.plate) == b.unit and qualifies(b.unit, mode)) then unbind() end
    if state.bound then return end
    local list = plates()
    if not list then return end
    for _, plate in ipairs(list) do
        local unit = unitOf(plate)
        if unit and shownPlate(plate) and qualifies(unit, mode) then
            build()
            root:ClearAllPoints()
            if pcall(root.SetPoint, root, "CENTER", plate, "BOTTOM", 0, 0) then
                state.bound = { unit = unit, plate = plate }
                root:Show()
                play(true)
            end
            return
        end
    end
end

--------------------------------------------------------------------------------
-- The listeners and the ticker: while the option is on, or anything is left to do

local EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

-- The one entry point: the pearl's Enable / Disable, a setting change, Start, the ticker, events.
function ST.Update()
    ST.Claims()
    ST.Reconcile()
    local active = ST.Mode() ~= "off" or pending()
    if active and not state.active then
        API.RegisterEvents(events, EVENTS)
    elseif not active and state.active then
        events:UnregisterAllEvents()
    end
    state.active = active
    -- The passes run while on, and while a claim is left to keep, put back or make.
    driver:SetScript("OnUpdate", active and function(_, elapsed)
        since = since + elapsed
        if since < ST.TICK then return end
        since = 0
        ST.Update()
    end or nil)
end

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        if state.bound and not API.IsSecret(unit) and unit == state.bound.unit then ST.Unbind() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ST.Reconcile()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ST.Update()
    end
end)

-- The settle window and the logout put-back, from the first login on, whatever the pearl.
life:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if state.settleAt == nil then state.settleAt = GetTime() + ST.SETTLE end
        ST.Update()
    elseif event == "PLAYER_LOGOUT" then
        atLogout()
    end
end)

-- At login, for the pearl on or off (Pearls.StartAll): the lifecycle frame,
-- then a first Update, which applies a due off edge and arms the passes.
function ST.Start()
    if state.started then return end
    state.started = true
    API.RegisterEvents(life, { "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT" })
    ST.Update()
end

--------------------------------------------------------------------------------
-- Reports

local function label(fn, ...)
    local v, how = call(fn, ...)
    if how ~= "ok" then return how end
    return tostring(v)
end

local WHAT = {
    owned = "ours (yours was %s)",
    unconfirmed = "ours, not confirmed yet (yours was %s)",
    release = "to put back to yours, %s",
    retained = "put back to yours (%s) at logout, decided at the next read",
    cancelled = "changed since: yours stands",
}

-- The CVars' lines for /gpearls sparkle.
function ST.Lines()
    local s = store() or { soft = {}, softPending = {} }
    local wait
    if state.loggingOut then wait = "logging out"
    elseif unsettled() then wait = "the login settling"
    elseif API.InCombat() then wait = "combat" end
    local lines = { ("  Stars: %s%s."):format(ST.Mode(), wait and (" (the settings wait: " .. wait .. ")") or "") }
    for _, c in ipairs(ST.CVARS) do
        local name = c[1]
        local parts = { ("%s now, %s wanted"):format(read(name) or "unreadable", c[2]) }
        local r = s.soft[name]
        if r then
            local old = tonumber(r.old) and ("%g"):format(tonumber(r.old)) or tostring(r.old)   -- "10.000000": 10
            parts[#parts + 1] = WHAT[r.st]:format(old)
        elseif s.softPending[name] then
            parts[#parts + 1] = "to set"
        elseif state.notes[name] == "yours" then
            parts[#parts + 1] = "yours, already at ours"
        elseif state.notes[name] then
            parts[#parts + 1] = state.notes[name]
        end
        local m = masked(name)
        if m and (r or s.softPending[name]) then parts[#parts + 1] = "waiting: " .. m end
        lines[#lines + 1] = ("    %s: %s."):format(name, table.concat(parts, ", "))
    end
    return lines
end

-- /gpearls sparkle target: the soft-interact object's plate, found without the
-- quest test, and what the client says about it.
function ST.Target()
    local list, how = plates()
    if not list then return { "Nameplates can't be read (" .. tostring(how) .. ")." } end
    local blocked
    for _, plate in ipairs(list) do
        local unit = unitOf(plate)
        if unit and shownPlate(plate) then
            local object = label(UnitIsGameObject, unit)
            local soft = object == "true" and label(UnitIsUnit, unit, "softinteract") or nil
            if object == "true" and soft == "true" then
                local name = text((call(UnitName, unit))) or "(name unreadable)"
                local quest = label(api("C_QuestLog", "UnitIsRelatedToActiveQuest"), unit)
                local lines = {
                    ("Soft-interact object: %s."):format(name),
                    ("  UnitIsGameObject true, UnitIsUnit(softinteract) true, UnitIsRelatedToActiveQuest %s, "
                        .. "UnitIsQuestBoss %s."):format(quest, label(UnitIsQuestBoss, unit)),
                }
                local mode = ST.Mode()
                if state.bound and state.bound.unit == unit then
                    lines[#lines + 1] = "  The stars are on it."
                elseif mode == "off" then
                    lines[#lines + 1] = "  The stars are off."
                elseif mode == "quest" and quest ~= "true" then
                    lines[#lines + 1] = ("  No stars: the quest test read %s."):format(quest)
                else
                    lines[#lines + 1] = "  No stars yet (the next pass binds them)."
                end
                return lines
            end
            if object == "secret" or object == "error" then
                blocked = blocked or { unit = unit, read = "UnitIsGameObject", how = object }
            elseif object == "true" and (soft == "secret" or soft == "error") then
                blocked = blocked or { unit = unit, read = "UnitIsUnit(softinteract)", how = soft }
            end
        end
    end
    if blocked then
        local name = text((call(UnitName, blocked.unit)))
        return { ("Could not determine the soft-interact object plate: %s read %s%s."):format(
            blocked.read, blocked.how, name and (" on " .. name) or "") }
    end
    return { "No soft-interact object plate (one selected object at a time, within about 15 yards: "
        .. "none observed, which doesn't prove an object isn't interactable)." }
end

ST._test = { events = events, life = life, driver = driver, root = function() return root end,
    stars = function() return stars end, store = store }
