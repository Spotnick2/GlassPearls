-- Pearls/Sparkle.lua: quest loot sparkle (#44). The client shows its sparkle
-- on lootable quest items only while the outline mode is off and
-- outlineModeShowLootEffectWhenDisabled is on (a reference addon's facts, no
-- code); a graphics preset puts the outline back. So, while on, these CVars
-- are set to WANTED at Enable, at each loading screen and 1 s after any
-- CVAR_UPDATE or GX_RESTARTED (one token: a newer trigger replaces the timer),
-- out of combat only.
--
-- The player's own values are remembered once (GlassPearlsDB.sparkle.before)
-- and put back at Disable: only where the CVar still reads our value (a value
-- the player changed since stays theirs), a CVar at a time, each set needing
-- a plain true. In combat the restore waits for PLAYER_REGEN_ENABLED (that
-- one event stays registered, also while off); switching back on first
-- cancels it. Whatever couldn't be restored stays remembered, and
-- `/gpearls sparkle restore` (while off) finishes it.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local SP = {}
GP.Sparkle = SP

SP.KEY = "sparkle"
SP.DELAY = 1
SP.ORDER = { "outlineModeShowLootEffectWhenDisabled", "graphicsOutlineMode", "OutlineEngineMode",
    "raidGraphicsOutlineMode", "RAIDOutlineEngineMode" }
SP.WANTED = {
    outlineModeShowLootEffectWhenDisabled = "1",
    graphicsOutlineMode = "0", OutlineEngineMode = "0",
    raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0",
}

local events = CreateFrame("Frame")
local state = { token = 0, applyPending = false, restorePending = false }
SP.state = state

local function say(msg) API.Print(msg) end

local function db()
    local d = GP.db
    if not d then return { before = {} } end
    d.sparkle = type(d.sparkle) == "table" and d.sparkle or {}
    if type(d.sparkle.before) ~= "table" then d.sparkle.before = {} end
    return d.sparkle
end

-- A CVar's value: a plain string, or nil (unknown to the client, a throw, a secret).
local function read(name)
    local ok, v = pcall(C_CVar.GetCVar, name)
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- Set a CVar: true only on a plain true.
local function write(name, value)
    local ok, done = pcall(C_CVar.SetCVar, name, value)
    if ok and not API.IsSecret(done) and done == true then return true end
    API.Fail("pearl sparkle " .. name, ok and "refused" or done)
    return false
end

-- Called only while on (Enable, its events, a current token).
function SP.Apply()
    if API.InCombat() then
        state.applyPending = true
        return
    end
    state.applyPending = false
    local before = db().before
    for _, name in ipairs(SP.ORDER) do
        local now, want = read(name), SP.WANTED[name]
        if now and now ~= want then
            if before[name] == nil then before[name] = now end      -- the player's own, once
            write(name, want)
        end
    end
end

-- Put the player's values back where the CVar still reads ours. Returns how
-- many are still remembered.
function SP.Restore()
    if API.InCombat() then
        state.restorePending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return nil
    end
    state.restorePending = false
    local before, left = db().before, 0
    for _, name in ipairs(SP.ORDER) do
        local old = before[name]
        if old ~= nil then
            local now = read(name)
            if now == nil then
                left = left + 1                                 -- unreadable: kept
            elseif now ~= SP.WANTED[name] then
                before[name] = nil                              -- changed since: theirs stays
            elseif write(name, old) then
                before[name] = nil
            else
                left = left + 1
            end
        end
    end
    return left
end

local function schedule()
    state.token = state.token + 1
    local token = state.token
    C_Timer.After(SP.DELAY, function()
        if state.token == token then SP.Apply() end
    end)
end

events:SetScript("OnEvent", function(_, event)
    API.NoteCombat(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if SP.enabled then
            if state.applyPending then SP.Apply() end
        elseif state.restorePending then
            SP.Restore()
            events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        SP.Apply()
    elseif event == "CVAR_UPDATE" or event == "GX_RESTARTED" then
        schedule()                                              -- the payload isn't read
    end
end)

function SP.Report()
    say(("Quest loot sparkle: %s%s."):format(SP.enabled and "on" or "off",
        state.restorePending and "; your outline comes back after the fight" or ""))
    local before = db().before
    for _, name in ipairs(SP.ORDER) do
        say(("  %s: %s now, %s wanted%s."):format(name, read(name) or "unreadable", SP.WANTED[name],
            before[name] and (", yours was " .. before[name]) or ""))
    end
end

local function command(arg)
    if (arg or ""):match("^%s*restore%s*$") then
        if SP.enabled then return say("Quest loot sparkle is on: switch it off to get your outline back.") end
        local left = SP.Restore()
        if left == nil then return say("Quest loot sparkle: your outline comes back after the fight.") end
        if left == 0 then return say("Quest loot sparkle: your outline settings are back.") end
        return say(("Quest loot sparkle: %d setting(s) couldn't be put back; try again later."):format(left))
    end
    SP.Report()
end

local function enable()
    SP.enabled = true
    state.restorePending = false                                -- back on: the baseline stays
    API.RegisterEvents(events, { "PLAYER_ENTERING_WORLD", "CVAR_UPDATE", "GX_RESTARTED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    SP.Apply()
end

local function disable()
    SP.enabled = false
    state.token = state.token + 1                               -- no pending apply runs
    state.applyPending = false
    events:UnregisterAllEvents()
    local left = SP.Restore()
    if left and left > 0 then
        say(("Quest loot sparkle: %d outline setting(s) couldn't be put back: /gpearls sparkle restore."):format(left))
    end
end

GP.Pearls.Register({
    key = SP.KEY,
    name = "Quest loot sparkle",
    desc = "Turns the outline mode off so the game's sparkle shows on quest loot, and keeps it off after "
        .. "graphics changes while on. Switched off, your own outline settings come back where they still read "
        .. "ours (the game may need a restart to show the outline again). Don't use it with another addon that "
        .. "does the same.",
    default = false,
    category = "Loot & Bags",
    section = "Loot",
    Enable = enable,
    Disable = disable,
    commands = { sparkle = { help = "[restore] - the outline settings, or put yours back (while off)",
        run = command } },
})

SP._test = { events = events }
