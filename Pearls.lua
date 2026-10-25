-- Pearls.lua: the registry. Each quality-of-life feature is a pearl: one small
-- file in Pearls\, listed in the TOC after this one, that registers itself at
-- file scope and touches nothing until it is enabled:
--
--   GlassPearls.Pearls.Register({
--       key = "autorepair",          -- 1-24 lower-case letters or digits, permanent (it's the saved key)
--       name = "Auto repair",        -- the options page and /gpearls list
--       desc = "Repairs at a vendor that can.",
--       default = false,             -- on or off for someone who never chose
--       Enable = function() end,     -- at login when on, and when switched on
--       Disable = function() end,    -- when switched off (optional: then the change waits for /reload)
--   })
--
-- Only what the player chose is saved (GlassPearlsDB.pearls[key], a boolean,
-- and only when it differs from the pearl's default). Enable and Disable run
-- protected: a pearl that throws is recorded in /gpearls failures and leaves
-- every other pearl running.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Pearls = {}
GP.Pearls = Pearls

local byKey, order = {}, {}
local live = {}   -- key -> true while enabled

function Pearls.Register(def)
    assert(type(def) == "table", "Pearls.Register: a table")
    assert(type(def.key) == "string" and def.key:match("^[a-z0-9]+$") and #def.key <= 24,
        "Pearls.Register: key must be 1-24 lower-case letters or digits")
    assert(not byKey[def.key], "Pearls.Register: duplicate key " .. def.key)
    assert(type(def.name) == "string" and def.name ~= "", "Pearls.Register: a name")
    assert(type(def.Enable) == "function", "Pearls.Register: an Enable function")
    def.default = def.default == true
    byKey[def.key] = def
    order[#order + 1] = def
    table.sort(order, function(a, b) return a.name:lower() < b.name:lower() end)
    return def
end

function Pearls.Get(key) return byKey[key] end

-- The registered pearls, by name.
function Pearls.List()
    local list = {}
    for i, def in ipairs(order) do list[i] = def end
    return list
end

local function saved() return GP.db and GP.db.pearls end

function Pearls.IsOn(key)
    local def = byKey[key]
    if not def then return false end
    local s = saved()
    local v = s and s[key]
    if v == nil then return def.default end
    return v
end

function Pearls.IsLive(key) return live[key] == true end

local function run(def, fnName)
    local fn = def[fnName]
    if not fn then return false end
    local ok, err = pcall(fn)
    if not ok then API.Fail("pearl " .. def.key .. " " .. fnName:lower(), err) end
    return ok
end

local function enable(def)
    if live[def.key] then return end
    if run(def, "Enable") then live[def.key] = true end
end

local function disable(def)
    if not live[def.key] then return end
    if def.Disable and run(def, "Disable") then live[def.key] = nil end
end

-- Switch a pearl on or off: saved, then applied. False for an unknown key.
-- A pearl without Disable stays live until /reload (IsLive says so).
function Pearls.Set(key, on)
    local def = byKey[key]
    if not def or not GP.db then return false end
    on = on == true
    if on == def.default then GP.db.pearls[key] = nil else GP.db.pearls[key] = on end
    if on then enable(def) else disable(def) end
    return true
end

-- Drop what isn't a choice: a non-boolean, or a value equal to a known
-- pearl's default. A key no pearl claims stays (a dev build's pearl, or one
-- from a newer version on another account's copy).
function Pearls.Clean(t)
    for key, v in pairs(t) do
        if type(v) ~= "boolean" or (byKey[key] and v == byKey[key].default) then t[key] = nil end
    end
end

-- At PLAYER_LOGIN, from GlassPearls.lua: every pearl that is on.
function Pearls.StartAll()
    for _, def in ipairs(order) do
        if Pearls.IsOn(def.key) then enable(def) end
    end
end

Pearls._test = {
    reset = function()
        for k in pairs(byKey) do byKey[k] = nil end
        for i = #order, 1, -1 do order[i] = nil end
        for k in pairs(live) do live[k] = nil end
    end,
}
