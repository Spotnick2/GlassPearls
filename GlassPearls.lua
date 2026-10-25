-- GlassPearls.lua: bootstrap, saved settings and the /gpearls command. Loads
-- last: every module and pearl is defined by now.

local ADDON = ...
GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Pearls = GP.Pearls
local say = API.Print

-- Account-wide (GlassPearlsDB): settings, the same on every character;
-- pearls[key] holds each pearl's on/off where the player chose, settings[key]
-- a pearl's own settings (Pearls.lua).
-- Per character (GlassPearlsCharDB): for a pearl that needs it.
-- Own-account sync (GlassPearlsSyncDB): the library's store (AccountSync.lua).
local DEFAULTS = {
    useGlassUI = true,   -- follow Glass UI's look when it's here (Theme.lua); a /reload applies a change
}
GP.DEFAULTS = DEFAULTS

-- Only what the player SET is saved: everything else falls through to
-- DEFAULTS, so a changed default reaches everyone. Saved keys equal to the
-- default are dropped. Nothing may REQUIRE a value to have survived
-- (GlassChat's rule).
local function ensureDefaults()
    if type(GlassPearlsDB) ~= "table" then GlassPearlsDB = {} end
    local db = GlassPearlsDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    if db.useGlassUI ~= nil and type(db.useGlassUI) ~= "boolean" then db.useGlassUI = nil end
    if type(db.pearls) ~= "table" then db.pearls = {} end
    Pearls.Clean(db.pearls)
    if type(db.settings) ~= "table" then db.settings = {} end
    Pearls.CleanSettings(db.settings)
    -- Settings sync's stamps, sets and relayed keys (SettingsSync.lua).
    if type(db.sync) ~= "table" then db.sync = {} end
    GP.SettingsSync.Core.Clean(db.sync)
    setmetatable(db, { __index = DEFAULTS })
    if type(GlassPearlsCharDB) ~= "table" then GlassPearlsCharDB = {} end
    if type(GlassPearlsSyncDB) ~= "table" then GlassPearlsSyncDB = {} end
    return db, GlassPearlsCharDB
end

-- A dev build, by its version: "dev" from the deploy script, or the
-- packager's token left unreplaced (matched as a pattern, never written whole:
-- the packager would replace it here too). Unreadable is NOT dev.
function GP.IsDev()
    local v = API.AddOnVersion(ADDON or "GlassPearls")
    return v ~= nil and (v == "dev" or v:find("@project%-version@") ~= nil)
end

function GP.VersionText()
    local v = API.AddOnVersion(ADDON or "GlassPearls")
    if v == nil or v == "" or GP.IsDev() then return "dev" end
    return v
end

local function failures()
    local any = false
    for key, err in pairs(GP.failures) do
        any = true
        say(key .. ": " .. err)
    end
    for _, line in ipairs(GP.eventFailures) do
        any = true
        say("event " .. line)
    end
    if not any then say("no failures recorded") end
end

local function onoff(v) return v and "on" or "off" end

local function list()
    local defs = Pearls.List()
    if #defs == 0 then return say("no pearls yet") end
    for _, def in ipairs(defs) do
        local state = onoff(Pearls.IsOn(def.key))
        if Pearls.NeedsReload(def.key) then state = state .. " (after /reload)" end
        say(def.key .. " - " .. def.name .. " (" .. state .. ")")
    end
end

-- Every setting goes through here: /gpearls and the options window.
local Settings = {}
GP.Settings = Settings

-- Follow Glass UI's look; applies after a /reload (the look is fixed once a session).
function Settings.SetUseGlassUI(on)
    local was = GP.db.useGlassUI ~= false
    GP.db.useGlassUI = on == true
    if GP.db.useGlassUI ~= was then GP.SettingsSync.Touch("core.glassui") end
    return true
end

-- The command list: /gpearls help prints it.
local function helpLines()
    local lines = {
        "/gpearls - open the options window",
        "/gpearls list - every pearl and whether it is on",
        "/gpearls <pearl> on/off - switch one pearl",
        "/gpearls sync - your other accounts: the link's state (sync on/off to switch it)",
        "/gpearls failures - what failed to build or register",
        "/gpearls version - client build vs the measured one",
    }
    -- The pearls' own commands (def.commands).
    for _, c in ipairs(Pearls.Commands()) do lines[#lines + 1] = "/gpearls " .. c.name .. " - " .. c.help end
    return lines
end
GP.HelpLines = helpLines

local ONOFF = { on = true, off = false }

local function slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        GP.Options.Toggle()
    elseif cmd == "options" then
        GP.Options.Open()
    elseif cmd == "list" then
        list()
    elseif cmd == "sync" then
        if ONOFF[arg] ~= nil then
            if GP.AccountSync.SetEnabled(ONOFF[arg]) then say("account sync " .. arg)
            else say("account sync is not available") end
            GP.Options.Refresh()
            return
        end
        for _, line in ipairs(GP.AccountSync.Lines()) do say(line) end
        for _, line in ipairs(GP.SettingsSync.Lines()) do say(line) end
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("version " .. GP.VersionText() .. ", client " .. API.ClientBuild()
            .. ", measured on " .. GP.MEASURED_ON_BUILD .. ", look " .. GP.Theme.Active())
    elseif Pearls.Get(cmd) and (ONOFF[arg] ~= nil or not Pearls.Command(cmd)) then
        -- A pearl's key switches it; a pearl command of the same name takes
        -- every other argument (/gpearls fixate, /gpearls fixate test).
        local def = Pearls.Get(cmd)
        if ONOFF[arg] == nil then
            return say(def.name .. " is " .. onoff(Pearls.IsOn(cmd)) .. ". /gpearls " .. cmd .. " on/off")
        end
        Pearls.Set(cmd, ONOFF[arg])
        local note = Pearls.NeedsReload(cmd) and " (after /reload)" or ""
        say(def.name .. " " .. arg .. note)
        GP.Options.Refresh()
    elseif Pearls.Command(cmd) then
        local c, def = Pearls.Command(cmd)
        local ok, err = pcall(c.run, arg)
        if not ok then API.Fail("pearl " .. def.key .. " command " .. cmd, err) end
    else
        for _, line in ipairs(helpLines()) do say(line) end
    end
end

SLASH_GLASSPEARLS1 = "/gpearls"
SLASH_GLASSPEARLS2 = "/glasspearls"
SlashCmdList.GLASSPEARLS = slash

local function start(key, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail(key, err) end
end

-- The look is fixed once, at our ADDON_LOADED: `## OptionalDeps: GlassUI` has
-- Glass UI ready by then, and nothing has been drawn yet.
local function load()
    GP.db, GP.charDB = ensureDefaults()
    start("theme", function()
        GP.Theme.Init(GP.db.useGlassUI ~= false, function() return GP.Options.Open() end)
    end)
end

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then load() end
    elseif event == "PLAYER_LOGIN" then
        -- SavedVariables are read here at the latest (porting guide: not at file scope).
        if not GP.db then load() end
        start("options", GP.Options.Register)
        start("pearls", Pearls.StartAll)
        start("settings sync", GP.SettingsSync.Start)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin. The build warning asks the developer to
        -- re-measure; a player can't act on it, and /reload never repeats it.
        if arg1 and GP.IsDev() and API.ClientBuild() ~= GP.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " differs from the one this addon was measured on ("
                .. GP.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" })

GP._test = { ensureDefaults = ensureDefaults, slash = slash }
