-- Pearls/Fishing.lua: easy fishing (#64). Never click the bobber: one key
-- casts Fishing, and while you fish the game's own Interact Key (soft
-- targeting, Controls > "Enable Interact Key": softTargetInteract =
-- Enum.SoftTargetEnableFlags.Any, Blizzard_SettingsDefinitions_Frame/
-- Controls.lua:72) is on with a range that reaches the bobber, so the same key
-- reels in. Optionally, while fishing, the sounds are focused on the splash and
-- NPC names hidden. A reference addon's behaviour, nothing copied.
--
-- A session is a Fishing channel of the player's (from our key or a bar):
-- UNIT_SPELLCAST_CHANNEL_START / _STOP with a plain ID of F.CHANNEL, a watchdog
-- reading UnitChannelInfo each second, and F.Adopt for a channel that was
-- already running (switched on mid-cast, a /reload mid-cast).
--
-- Everything changed while fishing is a TEMP CVar (C_CVar.SetTempCVar /
-- RemoveTempCVar): nothing of the player's is remembered or written back. One
-- reconciler compares `held` (every name we set without a throw and haven't
-- removed: the cleanup marker) with F.Wanted() (current state only) and
-- removes or sets the difference. The temp functions return nothing and their
-- preconditions fail SILENTLY (CVarDocumentation.lua:111-122, 170-183,
-- 211-226), so a name is set only when GetCVarInfo says it is plain, not
-- secure and not read-only, and the readback after a set only labels it
-- (applied, refused, unverified): it is held for cleanup whatever it says. A
-- removal can't be read back (the player's own value may equal ours).
-- Limitation: a temp CVar has no owner, so removing one of ours also removes
-- another addon's temp of the same name.
--
-- Gamepad: Blizzard_Gamepad (this client only) sets the same soft-target
-- temps itself in gamepad style and removes them in mouse-and-keyboard style
-- (Blizzard_Gamepad/Core.lua:1-42, 81-99). So the interact group is wanted only
-- while the style plainly reads Mkb, and at every style transition its names
-- are dropped from `held` WITHOUT removing them, then a frame later the
-- reconciler reads the style again.
--
-- The key: priority override bindings on an owner frame for every key bound to
-- GLASSPEARLS_FISH: a click on our secure button when idle, INTERACTTARGET
-- while a session runs; changed only out of combat. The button
-- (SecureActionButtonTemplate, hidden, both edges, no typerelease, no
-- snippets: porting guide) is disarmed whenever no click is in progress: its
-- PreClick arms the highest known rank, type last; PostClick disarms, never
-- under lockdown.
-- Unmeasured until 2026-11-04: all of it (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local F = {}
GP.Fishing = F

F.KEY = "fishing"
F.NAME = "Easy fishing"
F.BINDING = "GLASSPEARLS_FISH"
F.BUTTON = "GlassPearlsFishButton"
-- The casting ladder, highest first (SkillLineAbility 356, SupercedesSpell;
-- each summons the bobber, SpellEffect 50 object 35591). Forever's other
-- "Fishing" ladder, 1240948-1240983, is its crafting line (a tradeskill), never
-- cast.
F.RANKS = { 18248, 7732, 7731, 7620 }
-- Channels that are fishing: the ladder, and 1229271 (also named Fishing, the
-- same channel settings; unknown: recognised, never cast).
F.CHANNEL = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [1229271] = true }
F.WATCH = 1             -- seconds between the watchdog's reads
F.UNREADABLE_MAX = 35   -- seconds of unreadable channel before a session ends
F.ADOPT_TRIES = 3       -- one a second, when the channel can't be read at Enable

local VOLUME = {}       -- marks the value that is the volume setting
F.GROUPS = {
    { setting = "interact", mkbOnly = true, cvars = {
        { "SoftTargetInteract", "3" }, { "SoftTargetInteractRange", "60" }, { "SoftTargetInteractArc", "2" },
        { "SoftTargetIconGameObject", "1" }, { "SoftTargetIconInteract", "1" } } },
    { setting = "sounds", cvars = {
        { "Sound_EnableAllSound", "1" }, { "Sound_EnableSFX", "1" }, { "Sound_EnableSoundWhenGameIsInBG", "1" },
        { "Sound_SFXVolume", VOLUME }, { "Sound_MasterVolume", VOLUME }, { "Sound_MusicVolume", "0" },
        { "Sound_EnableAmbience", "0" }, { "Sound_EnablePetSounds", "0" } } },
    { setting = "names", cvars = {
        { "UnitNameNPC", "0" }, { "UnitNameNonCombatCreatureName", "0" }, { "UnitNameInteractiveNPC", "0" },
        { "UnitNameFriendlySpecialNPCName", "0" } } },
}
F.INTERACT = {}
for _, c in ipairs(F.GROUPS[1].cvars) do F.INTERACT[c[1]] = true end

BINDING_NAME_GLASSPEARLS_FISH = "Fish, then reel in"

local state = {
    session = nil,      -- { token, unreadable } while a fishing channel runs
    token = 0,          -- bumped by every session start and end: stale watchdogs stop
    adoptToken = 0,
    held = {},          -- name -> { value, status = "applied" | "refused" | "unverified" }
    ineligible = {},    -- name -> why, for this session
    thrown = {},        -- name -> the last throw
    applied = nil,      -- the override state last applied ("mode:keys")
    syncPending = false,
    disarmPending = false,
    lastEnd = "none yet",
}
F.state = state

local events = CreateFrame("Frame")
local guard, owner, button      -- made at the first Enable
local armed = nil

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(F.KEY, name) end

local function ask(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

--------------------------------------------------------------------------------
-- Reading the client

-- "mkb", "gamepad", or nil (absent, a throw, a secret, another value).
function F.Style()
    if not (C_InputInterfaceStyle and Enum.InputDeviceInterfaceType) then return nil end
    local s = ask(C_InputInterfaceStyle.GetCurrentStyle)
    if s == nil then return nil end
    if s == Enum.InputDeviceInterfaceType.Mkb then return "mkb" end
    if s == Enum.InputDeviceInterfaceType.Gamepad then return "gamepad" end
end

-- The player's channel: its plain spell ID, false when plainly none, nil when
-- it can't be read.
function F.ChannelID()
    local r = { pcall(UnitChannelInfo, "player") }
    if not r[1] then return nil end
    local name, id = r[2], r[9]
    if API.IsSecret(name) or API.IsSecret(id) then return nil end
    if name == nil then return false end
    if type(id) ~= "number" then return nil end
    return id
end

-- The highest rank of the casting ladder plainly known, or nil.
function F.Rank()
    for _, id in ipairs(F.RANKS) do
        if ask(C_SpellBook.IsSpellKnown, id) == true then return id end
    end
end

-- The keys bound to the fishing key, plain and non-empty.
function F.Keys()
    local r = { pcall(GetBindingKey, F.BINDING) }
    local keys = {}
    if not r[1] then return keys end
    for i = 2, table.maxn(r) do
        local k = r[i]
        if not API.IsSecret(k) and type(k) == "string" and k ~= "" then keys[#keys + 1] = k end
    end
    return keys
end

--------------------------------------------------------------------------------
-- Temp CVars

local function volumeText()
    local v = tonumber(setting("volume")) or 100
    return ("%.2f"):format(math.min(math.max(v, 10), 100) / 100)
end

-- The temps wanted now: none unless on with a session; per group switched
-- on, its CVars; the interact group only in mouse-and-keyboard style.
function F.Wanted()
    local want = {}
    if not (F.enabled and state.session) then return want end
    local mkb = F.Style() == "mkb"
    for _, g in ipairs(F.GROUPS) do
        if setting(g.setting) and (not g.mkbOnly or mkb) then
            for _, c in ipairs(g.cvars) do want[c[1]] = (c[2] == VOLUME) and volumeText() or c[2] end
        end
    end
    return want
end

-- May the temp functions act on it? They do nothing, silently, on a CVar that
-- isn't valid and public, or is read-only or secure.
function F.Eligible(name)
    local ok, value, _, _, _, _, isSecure, isReadOnly = pcall(C_CVar.GetCVarInfo, name)
    if not ok then return false, "unreadable" end
    if API.IsSecret(value) or type(value) ~= "string" then return false, "unknown to the client" end
    if API.IsSecret(isSecure) or isSecure ~= false then return false, "secure" end
    if API.IsSecret(isReadOnly) or isReadOnly ~= false then return false, "read-only" end
    return true
end

local function same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and x == y
end

-- What the readback says after a set. It never decides whether we hold it.
local function label(name, value)
    local ok, v = pcall(C_CVar.GetCVar, name)
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return "unverified" end
    return same(v, value) and "applied" or "refused"
end

local function threw(name, err)
    state.thrown[name] = tostring(err)
    API.Fail("pearl fishing " .. name, err)
end

local function remove(name)
    if not F.Eligible(name) then return false end
    local ok, err = pcall(C_CVar.RemoveTempCVar, name)
    if not ok then threw(name, err) return false end
    return true
end

function F.Reconcile()
    local want = F.Wanted()
    for name, h in pairs(state.held) do
        if want[name] ~= h.value and remove(name) then state.held[name] = nil end
    end
    for name, value in pairs(want) do
        if not state.held[name] and not state.ineligible[name] then
            local ok, why = F.Eligible(name)
            if not ok then
                state.ineligible[name] = why
                API.Fail("pearl fishing " .. name, why)
            else
                local done, err = pcall(C_CVar.SetTempCVar, name, value)
                if done then
                    state.held[name] = { value = value, status = label(name, value) }
                else
                    threw(name, err)
                end
            end
        end
    end
end

-- Anything held that isn't wanted, or wanted and not yet tried?
local function tempsPending()
    local want = F.Wanted()
    for name, h in pairs(state.held) do
        if want[name] ~= h.value then return true end
    end
    for name in pairs(want) do
        if not state.held[name] and not state.ineligible[name] then return true end
    end
    return false
end
F.TempsPending = tempsPending

-- The player's own request: every eligible name of ours, the interact ones
-- only in mouse-and-keyboard style. Returns how many were removed.
function F.Reset()
    if state.session then return nil end
    local mkb, n = F.Style() == "mkb", 0
    for _, g in ipairs(F.GROUPS) do
        if not g.mkbOnly or mkb then
            for _, c in ipairs(g.cvars) do
                if remove(c[1]) then
                    state.held[c[1]] = nil
                    n = n + 1
                end
            end
        end
    end
    return n
end

--------------------------------------------------------------------------------
-- The key

local function preClick(self)
    armed = nil
    if InCombatLockdown() or not F.enabled or state.session then return end
    if ask(GetNumLootItems) ~= 0 then return end
    local id = F.Rank()
    if not id then return end
    self:SetAttribute("spell", id)
    self:SetAttribute("type", "spell")       -- last: armed only now
    armed = id
end

local function disarm()
    if InCombatLockdown() then
        state.disarmPending = true
        return
    end
    state.disarmPending = false
    button:SetAttribute("type", nil)
    button:SetAttribute("spell", nil)
end

local function postClick()
    if not armed then return end
    armed = nil
    disarm()
end

local function build()
    owner = CreateFrame("Frame")
    button = CreateFrame("Button", F.BUTTON, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetScript("PreClick", preClick)
    button:SetScript("PostClick", postClick)
    button:Hide()
end

-- The override wanted now: "none", "cast" or "interact", and the keys.
local function wantedBinding()
    if not F.enabled then return "none", {} end
    local keys = F.Keys()
    if #keys == 0 then return "none", keys end
    if state.session then return "interact", keys end
    if F.Rank() then return "cast", keys end
    return "none", keys
end

local function bind(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then API.Fail("pearl fishing binding", err) end
end

-- Apply the wanted override when it differs from the one applied; under
-- lockdown nothing is touched and PLAYER_REGEN_ENABLED computes it again.
function F.Sync()
    if not owner then return end
    local mode, keys = wantedBinding()
    local sig = mode .. ":" .. table.concat(keys, " ")
    if sig == state.applied then
        state.syncPending = false
        return
    end
    if InCombatLockdown() then
        state.syncPending = true
        return
    end
    state.syncPending = false
    state.applied = sig                      -- first: an UPDATE_BINDINGS our calls raise finds it done
    bind(ClearOverrideBindings, owner)
    for _, key in ipairs(keys) do
        if mode == "cast" then
            bind(SetOverrideBindingClick, owner, true, key, F.BUTTON, "LeftButton")
        elseif mode == "interact" then
            bind(SetOverrideBinding, owner, true, key, "INTERACTTARGET")
        end
    end
end

-- The binding's own body (Bindings.xml): runs only when no override took the key.
function F.OnKey()
    if not F.enabled then return say(F.NAME .. " is off: /gpearls fishing on.") end
    if API.InCombat() then
        return say("The fishing key waits until the fight ends; the game's Interact key still reels in.")
    end
    if not F.Rank() then return say("You don't know Fishing yet.") end
    F.Sync()
    say("The fishing key is ready: press it again.")
end

--------------------------------------------------------------------------------
-- Sessions

local function watch(token)
    C_Timer.After(F.WATCH, function()
        local s = state.session
        if not s or s.token ~= token then return end
        local id = F.ChannelID()
        if id == nil then
            s.unreadable = s.unreadable + F.WATCH
            if s.unreadable >= F.UNREADABLE_MAX then return F.End("its channel couldn't be read") end
        elseif not F.CHANNEL[id] then
            return F.End("the channel ended")
        else
            s.unreadable = 0
        end
        watch(token)
    end)
end

-- A fishing channel started (or was found running): a fresh session, or the
-- open one renewed (a new watchdog).
function F.Start()
    if not F.enabled then return end
    if not state.session then state.ineligible = {} end
    state.token = state.token + 1
    state.session = { token = state.token, unreadable = 0 }
    watch(state.token)
    F.Reconcile()
    F.Sync()
end

function F.End(reason)
    if not state.session then return end
    state.session = nil
    state.token = state.token + 1
    state.lastEnd = reason
    F.Reconcile()
    F.Sync()
end

function F.IsFishing() return state.session ~= nil end

-- A fishing channel already running opens a session; unreadable is read
-- again each second, a few times.
function F.Adopt()
    state.adoptToken = state.adoptToken + 1
    local token = state.adoptToken
    local function try(left)
        if not F.enabled or token ~= state.adoptToken or state.session then return end
        local id = F.ChannelID()
        if id and F.CHANNEL[id] then return F.Start() end
        if id == nil and left > 0 then C_Timer.After(1, function() try(left - 1) end) end
    end
    try(F.ADOPT_TRIES)
end

events:SetScript("OnEvent", function(_, event, _unit, _castGUID, spellID)
    API.NoteCombat(event)
    if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if API.IsSecret(spellID) or type(spellID) ~= "number" or not F.CHANNEL[spellID] then return end
        if event == "UNIT_SPELLCAST_CHANNEL_START" then F.Start() else F.End("it stopped") end
    elseif event == "PLAYER_LEAVING_WORLD" then
        F.End("a loading screen")
    elseif event == "PLAYER_ENTERING_WORLD" then
        F.Adopt()
        F.Sync()
    elseif event == "UPDATE_BINDINGS" or event == "SPELLS_CHANGED" then
        F.Sync()
    end
end)

local function onGuard(_, event)
    API.NoteCombat(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if InCombatLockdown() then return end
        if state.disarmPending and button then disarm() end
        if state.syncPending then F.Sync() end
        if tempsPending() then F.Reconcile() end
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- Blizzard's gamepad code sets or removes these very temps in this
        -- transition: they are no longer ours to remove.
        for name in pairs(F.INTERACT) do state.held[name] = nil end
        C_Timer.After(0, F.Reconcile)
    end
end

--------------------------------------------------------------------------------
-- Commands and panel

function F.Report()
    local keys = F.Keys()
    say(("%s: %s; key %s; casts %s; input %s."):format(F.NAME, F.enabled and "on" or "off",
        #keys > 0 and table.concat(keys, ", ") or "not bound (Key Bindings > Glass Pearls)",
        F.Rank() and ("rank " .. F.Rank()) or "nothing (Fishing not known)", F.Style() or "unknown"))
    say("  " .. (state.session and "Fishing now." or ("Not fishing; the last session ended: " .. state.lastEnd .. ".")))
    local names = {}
    for name in pairs(state.held) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local h = state.held[name]
        say(("  %s = %s (%s)."):format(name, h.value, h.status))
    end
    for name, why in pairs(state.ineligible) do say(("  %s: not set, %s."):format(name, why)) end
    for name, err in pairs(state.thrown) do say(("  %s: the client refused (%s)."):format(name, err)) end
    if state.syncPending then say("  The key changes after the fight.") end
end

local function command(arg)
    if (arg or ""):match("^%s*reset%s*$") then
        local n = F.Reset()
        if n == nil then return say("Easy fishing: you are fishing; reset once the cast ends.") end
        return say(("Easy fishing: %d fishing setting(s) removed; your own settings show again."):format(n))
    end
    F.Report()
end

local function configure(panel, refreshers)
    local KEY, P = F.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "While you fish")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local interact, r1 = GP.UI.Check(panel, "The Interact key reels in the bobber",
        function() return P.Setting(KEY, "interact") end, function(on) P.SetSetting(KEY, "interact", on) end,
        { tip = "The game's own Interact Key, on only while you fish, reaching the bobber: the fishing key or the "
            .. "Interact key reels in. With a controller the game already does this." })
    interact:SetPoint("TOPLEFT", head, "BOTTOMLEFT", -4, -8)
    local sounds, r2 = GP.UI.Check(panel, "Hear the splash: music, ambience and pet sounds off, effects up",
        function() return P.Setting(KEY, "sounds") end, function(on) P.SetSetting(KEY, "sounds", on) end)
    sounds:SetPoint("TOPLEFT", interact, "BOTTOMLEFT", 0, -4)
    local volume, r3 = GP.UI.Number(panel, "effects and master volume (%)",
        function() return P.Setting(KEY, "volume") end, function(n) P.SetSetting(KEY, "volume", n) end, 10, 100, 40)
    volume:SetPoint("TOPLEFT", sounds, "BOTTOMLEFT", 30, -4)
    local names, r4 = GP.UI.Check(panel, "Hide NPC names (hostile ones stay)",
        function() return P.Setting(KEY, "names") end, function(on) P.SetSetting(KEY, "names", on) end)
    names:SetPoint("TOPLEFT", volume, "BOTTOMLEFT", -30, -6)
    local keyText = GP.UI.Label(panel, "", "GameFontHighlightSmall")
    keyText:SetPoint("TOPLEFT", names, "BOTTOMLEFT", 4, -12)
    local function refreshKey()
        local keys = F.Keys()
        keyText:SetText("Fishing key: " .. (#keys > 0 and table.concat(keys, ", ")
            or "not bound (Esc > Options > Key Bindings > Glass Pearls)"))
    end
    refreshers[#refreshers + 1] = r1
    refreshers[#refreshers + 1] = r2
    refreshers[#refreshers + 1] = r3
    refreshers[#refreshers + 1] = r4
    refreshers[#refreshers + 1] = refreshKey
    local note = GP.UI.Label(panel, "Everything changed while you fish is put back when you stop. Unverified until "
        .. "the game is live.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", keyText, "BOTTOMLEFT", 0, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

--------------------------------------------------------------------------------
-- The pearl

local function enable()
    F.enabled = true
    if not guard then
        build()
        guard = CreateFrame("Frame")
        guard:SetScript("OnEvent", onGuard)
        API.RegisterEvents(guard, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
            "INPUT_DEVICE_INTERFACE_TRANSITION" })
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        local ok, registered = pcall(events.RegisterUnitEvent, events, e, "player")
        if not ok then API.Fail("pearl fishing " .. e, registered)
        elseif registered == false then API.Fail("pearl fishing " .. e, "refused") end
    end
    API.RegisterEvents(events, { "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "UPDATE_BINDINGS",
        "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED" })
    F.Adopt()
    F.Sync()
end

local function disable()
    F.enabled = false
    state.adoptToken = state.adoptToken + 1      -- no pending adoption reopens anything
    events:UnregisterAllEvents()
    if state.session then F.End("switched off") else F.Reconcile() end
    F.Sync()
end

GP.Pearls.Register({
    key = F.KEY,
    name = F.NAME,
    desc = "One key casts Fishing and, while you fish, reels in the bobber: no clicking on it.",
    help = "Bind a key in Esc > Options > Key Bindings > Glass Pearls (\"Fish, then reel in\"). Press it to cast; when "
        .. "the bobber splashes, press it again to reel in. While you fish, the game's own Interact Key is on and "
        .. "reaches the bobber, so its Interact key works too; with a controller the game already does this. "
        .. "Optionally, while you fish: the splash louder (music, ambience and pet sounds off, effects and master "
        .. "volume up) and NPC names hidden. All of it is put back when you stop; /gpearls fishing reset removes it "
        .. "by hand (and any other addon's temporary change of the same settings). The key changes only out of "
        .. "combat: in a fight, use the Interact key. Unverified until the game is live.",
    default = true,
    category = "Professions",
    section = "Fishing",
    defaults = { interact = true, sounds = false, volume = 100, names = false },
    ranges = { volume = { 10, 100 } },
    Enable = enable,
    Disable = disable,
    configure = configure,
    onSettingChanged = function() F.Reconcile() end,
    commands = { fishing = { help = "[reset] - the fishing key and what it changed, or remove those changes",
        run = command } },
})

F._test = {
    events = events,
    guard = function() return guard end,
    owner = function() return owner end,
    button = function() return button end,
    preClick = preClick,
    postClick = postClick,
}
