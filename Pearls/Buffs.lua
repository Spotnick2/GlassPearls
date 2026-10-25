-- Pearls/Buffs.lua: buff alerts (#21). An alert when a useful buff lands on
-- you, from yourself or another player, with its time left: Clearcasting,
-- Innervate, Power Infusion and the paladin's Blessings of Protection,
-- Sacrifice and Freedom. Its frame and panel are Pearls/BuffsFrame.lua; the
-- aura read, the client sounds and the evidence rules are Core/AuraAlert.lua.
--
-- Every client language: spell IDs only (Forever's SpellName table), the
-- client's own names and icons. The game hides auras in combat, so each ID
-- gathers two kinds of evidence, kept apart: the aura read (present / absent /
-- unknown) and Blizzard's proc overlay (SPELL_ACTIVATION_OVERLAY_SHOW / _HIDE
-- with a plain listed spell ID; a HIDE without one hides every overlay). An
-- entry shows while any ID is present and clears once every ID that made it
-- show is gone; expiry is evidence, never a forced clear.
--
-- Time left: exact from a plain aura read (it keeps counting through unknown
-- reads); approximate ("~12") from the client's spell duration
-- (Data/AuraDurations.lua) when only an overlay says it's there; none for a
-- buff without a duration. "from <name>" when the aura names its source.
-- Unverified in combat until 2026-11-04.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local AA = GP.AuraAlert
local B = {}
GP.Buffs = B

B.KEY = "buffs"
B.SOUND_FILE = 567397          -- Sound\Interface\RaidWarning.ogg (checked by ear on day one)
B.THROTTLE = 1
B.RECHECK = 0.5
B.TEST_SECONDS = 10
-- The entries, from Forever's SpellName table (build 70532).
B.ENTRIES = {
    { key = "clearcasting", ids = { 12536, 16246, 16870, 457342, 467735 }, sound = false },   -- frequent: off
    { key = "innervate", ids = { 29166, 456195 }, sound = true },
    { key = "powerinfusion", ids = { 10060 }, sound = true },
    { key = "protection", ids = { 1022, 5599, 10278, 442948 }, sound = true },
    { key = "sacrifice", ids = { 6940, 20729 }, sound = true },
    { key = "freedom", ids = { 1044 }, sound = true },
}

local events = CreateFrame("Frame")
local sounds = AA.Sounds.New("pearl buffs sound")
local byID = {}                 -- [spellID] = entry
for _, e in ipairs(B.ENTRIES) do
    e.ev = AA.Entry.New(e.ids)
    for _, id in ipairs(e.ids) do byID[id] = e end
end
B.state = { sounds = sounds, lastRead = {}, queued = false, test = false }
local state = B.state

local function setting(name) return GP.Pearls.Setting(B.KEY, name) end
local function Frame() return GP.BuffsFrame end
local function now() return GetTime() end
local function on(e) return setting(e.key) == true end

local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

--------------------------------------------------------------------------------
-- What an entry shows

-- The view of a shown entry: { key, id, expiration, approximate, from }.
function B.View(e)
    local t = now()
    local exp, overlayOnly = e.ev:Expiration()
    local v = { key = e.key, id = e.ids[1], expiration = 0, approximate = false }
    for _, id in ipairs(e.ids) do
        if e.ev:Resolve(id) == "present" then v.id = id break end
    end
    if exp > 0 then
        v.expiration = exp
    elseif overlayOnly then
        local full = GP.AuraDurations and GP.AuraDurations[v.id] or 0
        if full > 0 then v.expiration, v.approximate = (e.ev.since or t) + full, true end
    end
    local src = e.ev:SourceUnit()
    if src and src ~= "player" then v.from = AA.Source(src) end
    return v
end

local function render()
    if state.test then return end
    local views = {}
    for _, e in ipairs(B.ENTRIES) do
        if on(e) and e.ev.shown then views[#views + 1] = B.View(e) end
    end
    if setting("alert") and #views > 0 then Frame().Show(views) else Frame().Hide() end
end

-- Reconcile every entry; play nothing (the client's sounds play on their own).
local looping = false
local function settle()
    local t, any = now(), false
    for _, e in ipairs(B.ENTRIES) do
        if on(e) then
            for _, id in ipairs(e.ev:ExpiredIDs(t)) do e.ev:Expire(id) end
            e.ev:Update(t)
            if e.ev.shown then any = true end
        end
    end
    render()
    if any and not looping then
        looping = true
        local function step()
            if not B.enabled then looping = false; return end
            B.Evaluate()
            local still = false
            for _, e in ipairs(B.ENTRIES) do if on(e) and e.ev.shown then still = true end end
            if still then C_Timer.After(B.RECHECK, step) else looping = false end
        end
        C_Timer.After(B.RECHECK, step)
    end
end
B.Settle = settle

-- Read every enabled entry's IDs, then reconcile.
function B.Evaluate()
    state.queued = false
    if not B.enabled then return end
    for _, e in ipairs(B.ENTRIES) do
        if on(e) then
            for _, id in ipairs(e.ids) do
                local r, exp, _, src = AA.Read(id)
                state.lastRead[id] = r
                e.ev:SetAura(id, r, exp, src)
            end
        end
    end
    settle()
end

local function queue()
    if state.queued then return end
    state.queued = true
    C_Timer.After(0, B.Evaluate)
end

-- Blizzard's proc overlay: a plain listed ID is evidence; a HIDE without an
-- ID hides every overlay. A secret ID is ignored.
function B.Overlay(shown, spellID)
    if API.IsSecret(spellID) then return end
    if spellID == nil then
        if shown then return end
        for _, e in ipairs(B.ENTRIES) do e.ev:HideAllOverlays() end
        return settle()
    end
    local id = plainNumber(spellID)
    local e = id and byID[id]
    if not (e and on(e)) then return end
    e.ev:SetOverlay(id, shown and "shown" or "hidden")
    settle()
end

--------------------------------------------------------------------------------
-- The client's sounds: one per ID of each entry switched on with its sound on

local function soundIDs()
    local ids = {}
    for _, e in ipairs(B.ENTRIES) do
        if on(e) and setting(e.key .. "Sound") then
            for _, id in ipairs(e.ids) do ids[#ids + 1] = id end
        end
    end
    return ids
end

local function allIDs()
    local ids = {}
    for _, e in ipairs(B.ENTRIES) do for _, id in ipairs(e.ids) do ids[#ids + 1] = id end end
    return ids
end

local function resetSounds()
    if not B.enabled then return end
    if API.InCombat() then sounds.pending = true; return end
    sounds:Remove(allIDs(), "off")
    sounds:Register(soundIDs(), { fileID = B.SOUND_FILE, throttle = B.THROTTLE })
end

--------------------------------------------------------------------------------
-- Commands

local LABEL = { registered = "the client plays it", refused = "refused by the client", off = "off" }

function B.Report()
    API.Print("Buff alerts: what the client allowed (by spell ID, any language).")
    for _, e in ipairs(B.ENTRIES) do
        local ok, name = pcall(C_Spell.GetSpellName, e.ids[1])
        name = ok and not API.IsSecret(name) and type(name) == "string" and name or e.key
        local parts = {}
        for _, id in ipairs(e.ids) do
            local secrecy = "?"
            local okS, v = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
            if okS and not API.IsSecret(v) then secrecy = v and "secret" or "readable" end
            local overlay = "?"
            local SAO = rawget(_G, "C_SpellActivationOverlay")
            if SAO and SAO.IsSpellOverlayed then
                local okO, o = pcall(SAO.IsSpellOverlayed, id)
                if okO and not API.IsSecret(o) then overlay = o and "overlay" or "no overlay" end
            end
            parts[#parts + 1] = ("%d: aura %s, %s, last read %s, sound %s"):format(id, secrecy, overlay,
                state.lastRead[id] or "none", LABEL[sounds.status[id]] or "not registered")
        end
        API.Print("  " .. name .. (on(e) and "" or " (off)") .. ": " .. table.concat(parts, "; "))
    end
end

function B.Test()
    if not B.enabled then return API.Print("Buff alerts are off: /gpearls buffs on.") end
    local views, t = {}, now()
    for _, e in ipairs(B.ENTRIES) do
        if on(e) then
            views[#views + 1] = { key = e.key, id = e.ids[1], expiration = t + B.TEST_SECONDS }
        end
    end
    if #views == 0 then return API.Print("Every buff is switched off in the gear.") end
    state.test = true
    Frame().Show(views, { test = true })
    Frame().Unlock()
    C_Timer.After(B.TEST_SECONDS, function()
        state.test = false
        Frame().Hide()
        if B.enabled then render() end
    end)
    API.Print("Test alerts for " .. B.TEST_SECONDS .. " s: drag them where you want them.")
end

local function command(arg)
    if arg == "test" then return B.Test() end
    B.Report()
end

--------------------------------------------------------------------------------
-- The pearl

events:SetScript("OnEvent", function(_, event, ...)
    -- UNIT_AURA's arguments are never read (they can be secret).
    API.NoteCombat(event)
    if event == "UNIT_AURA" then
        queue()
    elseif event == "SPELL_ACTIVATION_OVERLAY_SHOW" then
        B.Overlay(true, (...))
    elseif event == "SPELL_ACTIVATION_OVERLAY_HIDE" then
        B.Overlay(false, (...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        if sounds.pending then resetSounds() end
        queue()
    end
end)

local function enable()
    B.enabled = true
    local ok, registered = pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    if not ok then API.Fail("pearl buffs UNIT_AURA", registered)
    elseif registered == false then API.Fail("pearl buffs UNIT_AURA", "refused") end
    API.RegisterEvents(events, { "SPELL_ACTIVATION_OVERLAY_SHOW", "SPELL_ACTIVATION_OVERLAY_HIDE",
                                 "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    resetSounds()
    B.Evaluate()
end

local function disable()
    B.enabled = false
    events:UnregisterAllEvents()
    sounds:Remove(allIDs(), "off")
    for _, e in ipairs(B.ENTRIES) do e.ev:Reset() end
    state.test = false
    Frame().Hide()
end

local defaults = { alert = true, pulse = true, size = "normal" }
for _, e in ipairs(B.ENTRIES) do
    defaults[e.key] = true
    defaults[e.key .. "Sound"] = e.sound
end

GP.Pearls.Register({
    key = B.KEY,
    name = "Buff alerts",
    desc = "An alert when Clearcasting, Innervate, Power Infusion or a paladin's Blessing lands on you, with its time left.",
    help = "When one of these buffs lands on you, from yourself or another player: its icon, its name in your game's "
        .. "language, who gave it when the game says, and its time left (\"~\" when only estimated). Each buff has "
        .. "its own switch and sound in the gear. The game hides most aura details in combat; Blizzard's proc "
        .. "animation and the game's own sound still work there when it allows them. /gpearls buffs says what the "
        .. "game allowed; /gpearls buffs test shows the alerts to place them. Unverified in combat until the game is live.",
    default = true,
    category = "Combat",
    section = "Alerts",
    defaults = defaults,
    choices = { size = { "small", "normal", "large" } },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.BuffsFrame.Configure(panel, refreshers) end,
    onSettingChanged = function(name)
        if not B.enabled then return end
        if name == "alert" or name == "size" or name == "pulse" then return render() end
        for _, e in ipairs(B.ENTRIES) do
            if name == e.key and not on(e) then e.ev:Reset() end
        end
        resetSounds()
        B.Evaluate()
    end,
    commands = { buffs = { help = "[test] - what the game allowed the buff alerts, or show them to place them", run = command } },
})

B._test = { events = events, byID = byID }
