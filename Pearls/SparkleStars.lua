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
-- The plate needs three CVars, held as temp CVars (nothing of the player's
-- saved or written), only in mouse-and-keyboard style (Blizzard_Gamepad sets
-- and removes these temps itself), only out of combat:
-- - Effective values decide: a name reading other than ours is set, whoever
--   held it (easy fishing records a silent refusal as held). Read back at
--   once other than ours: refused for this stars session (a session starts
--   each time the stars become wanted; quest <-> all doesn't start one).
--   Ours and later other (fishing's session end or reset removed it):
--   displaced, set again on the next pass out of combat.
-- - A name easy fishing holds (GP.Fishing.state.held, read only) is never
--   removed by us: dropped from our held, left to fishing's cleanup.
-- - Cleanup outlives the switch: off in combat, removed at
--   PLAYER_REGEN_ENABLED; a removal that fails (ineligible, a throw) stays
--   held and is retried each pass; the listeners and the passes stay while
--   anything is held.
-- - INPUT_DEVICE_INTERFACE_TRANSITION drops what we hold unremoved
--   (Blizzard's temps replace them) and reconciles a frame later.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local ST = {}
GP.SparkleStars = ST

ST.MODES = { "off", "quest", "all" }
-- The names easy fishing uses for the same CVars (Pearls/Fishing.lua), so its held table matches.
ST.CVARS = { { "SoftTargetInteract", "3" }, { "SoftTargetInteractRange", "60" }, { "SoftTargetIconGameObject", "1" } }
ST.TICK = 0.5
ST.MEDIA = "Interface\\AddOns\\GlassPearls\\Media\\"
ST.STAR, ST.SPREAD, ST.GLOW, ST.STARS = 48, 30, 96, 4
ST.TEAL = { 0.35, 0.9, 0.75 }

local state = {
    held = {},       -- name -> our value: set by us, to remove when not wanted (the cleanup marker)
    refused = {},    -- name -> why, for this stars session
    wanted = false,  -- the CVars wanted at the last pass (a change to true starts a session)
    bound = nil,     -- { unit, plate }: the plate the stars are on
    active = false,  -- the listeners registered
}
ST.state = state

local events = CreateFrame("Frame")
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

function ST.Wanted() return ST.Mode() ~= "off" and mkb() end

--------------------------------------------------------------------------------
-- The temp CVars

local function read(name)
    local v, how = call(C_CVar.GetCVar, name)
    if how ~= "ok" or type(v) ~= "string" then return nil end
    return v
end
local function same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and x == y
end

-- May the temp functions act on it (they fail silently otherwise)? true, or false and why.
local function eligible(name)
    local ok, value, _, _, _, _, isSecure, isReadOnly = pcall(C_CVar.GetCVarInfo, name)
    if not ok then return false, "unreadable" end
    if API.IsSecret(value) or type(value) ~= "string" then return false, "unknown to the client" end
    if API.IsSecret(isSecure) or isSecure ~= false then return false, "secure" end
    if API.IsSecret(isReadOnly) or isReadOnly ~= false then return false, "read-only" end
    return true
end

local function fishingHolds(name)
    local F = GP.Fishing
    return type(F) == "table" and type(F.state) == "table" and type(F.state.held) == "table"
        and F.state.held[name] ~= nil
end

-- Our temp removed; held kept until that succeeds, so the next pass retries
-- (Codex review, PR #81). A name fishing holds is handed to it, unremoved.
local function release(name)
    if fishingHolds(name) then state.held[name] = nil; return end
    if not eligible(name) then return end
    local ok, err = pcall(C_CVar.RemoveTempCVar, name)
    if not ok then return API.Fail("pearl sparkle stars remove " .. name, err) end
    state.held[name] = nil
end

-- One pass over the CVars: what's wanted against what reads.
function ST.Temps()
    local want = ST.Wanted()
    if want and not state.wanted then state.refused = {} end   -- a new stars session
    state.wanted = want
    if API.InCombat() then return end                         -- PLAYER_REGEN_ENABLED comes back
    if not want then
        for name in pairs(state.held) do release(name) end
        return
    end
    for _, c in ipairs(ST.CVARS) do
        local name, value = c[1], c[2]
        local now = read(name)
        if not state.refused[name] and now ~= nil and not same(now, value) then
            local ok, why = eligible(name)
            if not ok then
                state.refused[name] = why
            else
                local done, err = pcall(C_CVar.SetTempCVar, name, value)
                if not done then
                    state.refused[name] = "the set threw"
                    API.Fail("pearl sparkle stars " .. name, err)
                else
                    state.held[name] = value
                    local back = read(name)
                    if back ~= nil and not same(back, value) then state.refused[name] = "refused by the client" end
                end
            end
        end
    end
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
-- The listeners and the ticker: while the option is on, or anything is held

local EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "INPUT_DEVICE_INTERFACE_TRANSITION",
                 "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

-- The one entry point: the pearl's Enable / Disable, a setting change, the ticker, events.
function ST.Update()
    ST.Temps()
    ST.Reconcile()
    local on = ST.Mode() ~= "off"
    local active = on or next(state.held) ~= nil
    if active and not state.active then
        API.RegisterEvents(events, EVENTS)
    elseif not active and state.active then
        events:UnregisterAllEvents()
    end
    state.active = active
    -- The passes run while on, and while a removal is left to retry.
    driver:SetScript("OnUpdate", active and function(_, elapsed)
        since = since + elapsed
        if since < ST.TICK then return end
        since = 0
        ST.Update()
    end or nil)
end

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        state.held = {}                                     -- Blizzard's temps replace ours: dropped unremoved
        C_Timer.After(0, ST.Update)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        if state.bound and not API.IsSecret(unit) and unit == state.bound.unit then unbind() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ST.Reconcile()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ST.Update()
    end
end)

--------------------------------------------------------------------------------
-- Reports

local function label(fn, ...)
    local v, how = call(fn, ...)
    if how ~= "ok" then return how end
    return tostring(v)
end

-- The CVars' lines for /gpearls sparkle.
function ST.Lines()
    local lines = { ("  Stars: %s%s."):format(ST.Mode(), ST.Mode() ~= "off" and not mkb()
        and " (the CVars wait: not in mouse-and-keyboard style)" or "") }
    for _, c in ipairs(ST.CVARS) do
        local name = c[1]
        local parts = { ("%s now, %s wanted"):format(read(name) or "unreadable", c[2]) }
        if state.held[name] then parts[#parts + 1] = "ours" end
        if state.refused[name] then parts[#parts + 1] = "unavailable: " .. state.refused[name] end
        if fishingHolds(name) then parts[#parts + 1] = "easy fishing holds it" end
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

ST._test = { events = events, driver = driver, root = function() return root end, stars = function() return stars end }
