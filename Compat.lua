-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassPearls.API. Nothing is injected into _G.
--
-- A subset of GlassMail's Compat.lua (itself GlassChat's, same measured
-- rules); lift more from those, or from GlassRaidFrames', when a pearl needs
-- it rather than rewriting.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = {}
GP.API = API

-- The build the notes in docs/ were measured on. Bump only after re-measuring
-- in game; tests/test_toc.lua pins the same literal. Nothing is measured yet:
-- this is the newest API dump when the repo was made.
GP.MEASURED_ON_BUILD = "1.60.1.70532"

function API.Print(msg)
    print("|cff7fd4ffGlassPearls|r " .. msg)
end

-- True for a Retail secret value. Such a value may be handed back to the
-- client (SetText) but never compared, concatenated, tostring'd,
-- pattern-matched or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- InCombatLockdown() is still false inside the PLAYER_REGEN_DISABLED handler
-- (porting guide). A handler of the combat events passes them here first,
-- then asks InCombat(). Every handler does, since the order frames get an
-- event in isn't promised.
local combat = false
function API.NoteCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then combat = true
    elseif event == "PLAYER_REGEN_ENABLED" then combat = false end
end
function API.InCombat() return combat or InCombatLockdown() end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent.
GP.eventFailures = {}

local function report(name, why)
    table.insert(GP.eventFailures, name .. ": " .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
end

function API.RegisterEvents(frame, events)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterEvent, frame, name)
        if not ok then report(name, tostring(registered))
        elseif registered == false then report(name, "refused") end
    end
end

-- The one place failures are recorded (first error per key), read by
-- /gpearls failures and the tests.
GP.failures = GP.failures or {}
function API.Fail(key, err)
    if GP.failures[key] == nil then GP.failures[key] = tostring(err) end
end

-- An addon's TOC Version, or nil (absent API, error, secret, not a string).
function API.AddOnVersion(addon)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, "Version")
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end
