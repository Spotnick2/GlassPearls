-- Pearls/Fixate.lua: the fixate alert (#17). A sound and an on-screen alert
-- when a mob fixates on you. Its alert and panel are Pearls/FixateFrame.lua.
--
-- Every client language: detection is by spell ID only, never by name, and
-- the alert's words are the client's own (C_Spell.GetSpellName / Texture).
-- The IDs are the client's spells named "Fixate" (SpellName, build 70532;
-- three describe the mechanic, 1315448 is a Forever-era variant); a fixate
-- found under another name is added here by ID.
--
-- Forever hides auras in combat, for the player too (porting guide, "Auras go
-- dark for the WHOLE GROUP"). Two paths, each used only as far as the client
-- allows, and /gpearls fixate says which did:
-- 1. The client's own sound: C_UnitAuras.AddAuraSound(Added, { unitToken =
--    "player", spellID, ... }) per ID, registered out of combat, removed when
--    switched off. No secret reaches Lua. Flagged HasRestrictions: whether an
--    addon may register it, and whether it plays in combat, is day one's.
-- 2. The alert, when the aura can be read: UNIT_AURA registered for the
--    player only, its payload never touched (it can be secret, the unit token
--    included); a read of C_UnitAuras.GetPlayerAuraBySpellID inside one pcall
--    answers present (a plain table, every field plain), absent (a nil AND
--    C_Secrets.ShouldSpellAuraBeSecret(id) plainly false: this aura is
--    readable now; a spell can be always secret), or unknown (anything else).
--    The alert shows on present, clears on absent or when its own countdown
--    ends; unknown never shows or clears it.
-- Unverified in combat until 2026-11-04.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local F = {}
GP.Fixate = F

F.KEY = "fixate"
F.SPELLS = { 12021, 463171, 1222688, 1315448 }
F.SOUND_FILE = 567397          -- Sound\Interface\RaidWarning.ogg (checked by ear on day one)
F.THROTTLE = 1                 -- AddAuraSound: 0-5 s (UnitConstantsDocumentation.lua:52)
F.RECHECK = 0.5                -- while the alert is shown
F.TEST_SECONDS = 5

local events = CreateFrame("Frame")
local state = {
    sounds = {},        -- [spellID] = the client's sound ID
    soundStatus = {},   -- [spellID] = "registered" | "refused" | "off"
    lastRead = {},      -- [spellID] = "present" | "absent" | "unknown"
    alert = nil,        -- { id, expiration (0: none), duration, test }
    pendingSounds = false,
    queued = false,
}
F.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(F.KEY, name) end
local function Frame() return GP.FixateFrame end

--------------------------------------------------------------------------------
-- Reading one aura: present / absent / unknown

local function tryRead(id)
    local a = C_UnitAuras.GetPlayerAuraBySpellID(id)
    if API.IsSecret(a) then return "unknown" end
    if a == nil then
        local per = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
        if not per then return "unknown" end
        local secret = per(id)
        if API.IsSecret(secret) then return "unknown" end
        if secret == false then return "absent" end
        return "unknown"
    end
    if type(a) ~= "table" then return "unknown" end
    local exp, dur = a.expirationTime, a.duration
    if API.IsSecret(exp) or API.IsSecret(dur) then return "unknown" end
    return "present", type(exp) == "number" and exp or 0, type(dur) == "number" and dur or 0
end

function F.Read(id)
    local ok, result, exp, dur = pcall(tryRead, id)
    if not ok then return "unknown" end
    return result, exp, dur
end

--------------------------------------------------------------------------------
-- The alert

-- While shown: re-evaluate every RECHECK seconds (one loop at a time).
local looping = false
local function recheck()
    if looping then return end
    looping = true
    local function step()
        if not (F.enabled and state.alert) then looping = false; return end
        if not state.alert.test then F.Evaluate() end
        C_Timer.After(F.RECHECK, step)
    end
    C_Timer.After(F.RECHECK, step)
end

local function show(id, exp, dur, test)
    local fresh = state.alert == nil or state.alert.id ~= id
    state.alert = { id = id, expiration = exp, duration = dur, test = test }
    if setting("alert") then Frame().Show(state.alert) end
    recheck()
    -- Our own sound only when the client's isn't registered (and not for a test).
    if fresh and not test and setting("sound") and state.soundStatus[id] ~= "registered" then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
end

local function clear()
    state.alert = nil
    Frame().Hide()
end
F.Clear = clear

-- Read every fixate ID and settle the alert by the three answers.
function F.Evaluate()
    state.queued = false
    if not F.enabled then return end
    local presentID, pExp, pDur
    for _, id in ipairs(F.SPELLS) do
        local r, exp, dur = F.Read(id)
        state.lastRead[id] = r
        if r == "present" and not presentID then presentID, pExp, pDur = id, exp, dur end
    end
    local a = state.alert
    if a and a.test then return end
    if presentID then
        show(presentID, pExp, pDur)
    elseif a and state.lastRead[a.id] == "absent" then
        clear()
    end
end

-- The countdown ran out (FixateFrame's OnUpdate): the alert ends with it.
function F.Expired()
    if state.alert then clear() end
end

local function queue()
    if state.queued then return end
    state.queued = true
    C_Timer.After(0, F.Evaluate)
end

--------------------------------------------------------------------------------
-- The client's sound

local function registerSounds()
    if not (setting("sound") and F.enabled) then return end
    if API.InCombat() then state.pendingSounds = true; return end
    state.pendingSounds = false
    local trigger = Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
    for _, id in ipairs(F.SPELLS) do
        if not state.sounds[id] then
            local ok, soundID = pcall(C_UnitAuras.AddAuraSound, trigger, {
                unitToken = "player", spellID = id, soundFileID = F.SOUND_FILE,
                outputChannel = "Master", throttleSeconds = F.THROTTLE,
            })
            if ok and not API.IsSecret(soundID) and type(soundID) == "number" then
                state.sounds[id], state.soundStatus[id] = soundID, "registered"
            else
                state.soundStatus[id] = "refused"
                API.Fail("pearl fixate sound", ok and "no sound ID" or tostring(soundID))
            end
        end
    end
end

local function removeSounds(status)
    for id, soundID in pairs(state.sounds) do
        pcall(C_UnitAuras.RemoveAuraSound, soundID)
        state.sounds[id] = nil
    end
    for _, id in ipairs(F.SPELLS) do state.soundStatus[id] = status end
end

--------------------------------------------------------------------------------
-- Commands

local LABEL = { registered = "the client plays it", refused = "refused by the client", off = "off" }

function F.Report()
    say("Fixate alert: what the client allowed (detection by spell ID, any language).")
    for _, id in ipairs(F.SPELLS) do
        local ok, name = pcall(C_Spell.GetSpellName, id)
        name = ok and not API.IsSecret(name) and type(name) == "string" and name or ("spell " .. id)
        local secrecy = "unknown"
        if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
            local okS, v = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
            if okS and not API.IsSecret(v) then secrecy = v and "secret now" or "readable now" end
        end
        say(("  %s (%d): sound %s; aura %s; last read %s"):format(name, id,
            LABEL[state.soundStatus[id]] or "not registered", secrecy, state.lastRead[id] or "none yet"))
    end
end

function F.Test()
    if not F.enabled then return say("The fixate alert is off: /gpearls fixate on.") end
    local id = F.SPELLS[1]
    show(id, GetTime() + F.TEST_SECONDS, F.TEST_SECONDS, true)
    Frame().Unlock()
    say("Test alert for " .. F.TEST_SECONDS .. " s: drag it where you want it.")
end

local function command(arg)
    if arg == "test" then return F.Test() end
    F.Report()
end

--------------------------------------------------------------------------------
-- The pearl

events:SetScript("OnEvent", function(_, event)
    -- No argument is read: UNIT_AURA's (unit and update info) can be secret.
    API.NoteCombat(event)
    if event == "UNIT_AURA" then
        queue()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.pendingSounds then registerSounds() end
        queue()   -- combat over: a fresh read re-evaluates the alert
    end
end)

local function enable()
    F.enabled = true
    local ok, err = pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    if not ok then API.Fail("pearl fixate UNIT_AURA", err) end
    API.RegisterEvents(events, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    registerSounds()
    F.Evaluate()
end

local function disable()
    F.enabled = false
    events:UnregisterAllEvents()
    removeSounds("off")
    clear()
end

GP.Pearls.Register({
    key = F.KEY,
    name = "Fixate alert",
    desc = "A sound and an alert when a mob fixates on you, in any client language.",
    help = "When a mob fixates on you, a sound and an alert with the spell's icon, its name in your client's "
        .. "language and a countdown. The game hides most aura details during combat; the alert shows only when "
        .. "the game says the fixate is there, and the sound is played by the game itself if it allows it. "
        .. "/gpearls fixate says what the game allowed; /gpearls fixate test shows the alert to place it. "
        .. "Unverified in combat until the game is live.",
    default = true,
    category = "Combat",
    section = "Alerts",
    defaults = { sound = true, alert = true, size = "normal" },
    choices = { size = { "small", "normal", "large" } },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.FixateFrame.Configure(panel, refreshers) end,
    onSettingChanged = function(name)
        if not F.enabled then return end
        if name == "sound" then
            if setting("sound") then registerSounds() else removeSounds("off") end
        elseif name == "alert" then
            if not setting("alert") then Frame().Hide() elseif state.alert then Frame().Show(state.alert) end
        elseif name == "size" and state.alert then
            Frame().Show(state.alert)
        end
    end,
    commands = { fixate = { help = "[test] - what the game allowed for the fixate alert, or show a test alert", run = command } },
})

F._test = { events = events, recheck = recheck }
