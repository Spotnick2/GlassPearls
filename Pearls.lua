-- Pearls.lua: the registry. Each quality-of-life feature is a pearl: one small
-- file in Pearls\, listed in the TOC after this one, that registers itself at
-- file scope and touches nothing until it is enabled:
--
--   GlassPearls.Pearls.Register({
--       key = "autorepair",          -- 1-24 lower-case letters or digits, permanent (it's the saved key)
--       name = "Auto repair",        -- the options page and /gpearls list
--       desc = "Repairs at a vendor that can.",
--       default = false,             -- on or off for someone who never chose
--       category = "Loot & Bags",    -- the options window's page (CATEGORIES below)
--       section = "Bags",            -- the header it sits under on that page
--       Enable = function() end,     -- at login when on, and when switched on
--       Disable = function() end,    -- when switched off (optional: then the change waits for /reload)
--       defaults = { key = value },  -- optional: its own settings (Pearls.Setting)
--       choices = { key = { ... } }, -- a string setting's allowed values (settings sync needs them)
--       ranges = { key = { lo, hi } },  -- optional: an integer setting's range (synced values are checked)
--       configure = function(panel, refreshers) end,  -- optional: builds its Configuration Panel
--       help = "...",                -- optional: the panel's Help text
--       onReset = function() end,    -- optional: after Reset put its settings back
--       onSettingChanged = function(name, value) end,  -- optional: after any change of its settings,
--                                    -- local or from settings sync (a pearl that must rebuild)
--   })
--
-- Only what the player chose is saved (GlassPearlsDB.pearls[key], a boolean,
-- and only when it differs from the pearl's default; a pearl's own settings in
-- GlassPearlsDB.settings[key], likewise only the non-defaults). Enable and
-- Disable run protected: a pearl that throws is recorded in /gpearls failures
-- and leaves every other pearl running.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Pearls = {}
GP.Pearls = Pearls

-- The options window's pages, in this order; a page shows only once a pearl
-- is on it. A category not listed here goes after them, alphabetically.
Pearls.CATEGORIES = { "Loot & Bags", "Interface", "Social", "Chat", "Automation", "System" }
Pearls.DEFAULT_CATEGORY, Pearls.DEFAULT_SECTION = "Miscellaneous", "General"

local byKey, order = {}, {}
local live = {}   -- key -> true while enabled

function Pearls.Register(def)
    assert(type(def) == "table", "Pearls.Register: a table")
    assert(type(def.key) == "string" and def.key:match("^[a-z0-9]+$") and #def.key <= 24,
        "Pearls.Register: key must be 1-24 lower-case letters or digits")
    assert(not byKey[def.key], "Pearls.Register: duplicate key " .. def.key)
    assert(type(def.name) == "string" and def.name ~= "", "Pearls.Register: a name")
    assert(type(def.Enable) == "function", "Pearls.Register: an Enable function")
    assert(def.configure == nil or type(def.configure) == "function", "Pearls.Register: configure is a function")
    assert(def.defaults == nil or type(def.defaults) == "table", "Pearls.Register: defaults is a table")
    def.default = def.default == true
    def.category = type(def.category) == "string" and def.category ~= "" and def.category or Pearls.DEFAULT_CATEGORY
    def.section = type(def.section) == "string" and def.section ~= "" and def.section or Pearls.DEFAULT_SECTION
    def.defaults = def.defaults or {}
    byKey[def.key] = def
    order[#order + 1] = def
    table.sort(order, function(a, b) return a.name:lower() < b.name:lower() end)
    return def
end

function Pearls.Get(key) return byKey[key] end

-- A pearl's slash command (def.commands[name] = { help, run(arg) }) by name.
function Pearls.Command(name)
    for _, def in ipairs(order) do
        local c = type(def.commands) == "table" and def.commands[name]
        if type(c) == "table" and type(c.run) == "function" then return c, def end
    end
end

-- Every pearl command, by name: { { name, help }, ... }.
function Pearls.Commands()
    local list = {}
    for _, def in ipairs(order) do
        for name, c in pairs(type(def.commands) == "table" and def.commands or {}) do
            list[#list + 1] = { name = name, help = c.help or "" }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

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

-- Switched off but still running: a pearl without Disable waits for a
-- /reload (the window's `*` and Reload button).
function Pearls.NeedsReload(key) return Pearls.IsLive(key) and not Pearls.IsOn(key) end

function Pearls.PendingReload()
    for _, def in ipairs(order) do
        if Pearls.NeedsReload(def.key) then return true end
    end
    return false
end

-- The pages that have pearls, in CATEGORIES order, then the rest by name.
function Pearls.Categories()
    local present, list, rank = {}, {}, {}
    for _, def in ipairs(order) do present[def.category] = true end
    for i, c in ipairs(Pearls.CATEGORIES) do rank[c] = i end
    for c in pairs(present) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        local ra, rb = rank[a] or math.huge, rank[b] or math.huge
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return list
end

-- The pearls on one page, by name.
function Pearls.InCategory(category)
    local list = {}
    for _, def in ipairs(order) do
        if def.category == category then list[#list + 1] = def end
    end
    return list
end

-- The pearls whose name or description contains `text` (plain, case-insensitive).
function Pearls.Search(text)
    local list = {}
    text = type(text) == "string" and text:lower():match("^%s*(.-)%s*$") or ""
    if text == "" then return list end
    for _, def in ipairs(order) do
        local hay = (def.name .. " " .. (def.desc or "")):lower()
        if hay:find(text, 1, true) then list[#list + 1] = def end
    end
    return list
end

-- A pearl's own setting: the saved value, else its default.
function Pearls.Setting(key, name)
    local def = byKey[key]
    local t = GP.db and GP.db.settings and GP.db.settings[key]
    local v = t and t[name]
    if v == nil and def then return def.defaults[name] end
    return v
end

-- Save a pearl's setting; nothing is saved when it equals the default. False
-- for an unknown pearl or setting.
-- A change for settings sync to stamp and send (it ignores its own applies).
local function touch(id)
    local SS = GP.SettingsSync
    if SS then SS.Touch(id) end
end

-- Tell the pearl a setting changed (any route: options, slash, sync, Reset).
local function changed(def, name, value)
    if not def.onSettingChanged then return end
    local ok, err = pcall(def.onSettingChanged, name, value)
    if not ok then API.Fail("pearl " .. def.key .. " setting", err) end
end

function Pearls.SetSetting(key, name, value)
    local def = byKey[key]
    if not def or def.defaults[name] == nil or not GP.db then return false end
    if type(value) ~= type(def.defaults[name]) then return false end
    local was = Pearls.Setting(key, name)
    local all = GP.db.settings
    if value == def.defaults[name] then
        if all[key] then
            all[key][name] = nil
            if next(all[key]) == nil then all[key] = nil end
        end
    else
        all[key] = all[key] or {}
        all[key][name] = value
    end
    if value ~= was then
        touch(key .. "." .. name)
        changed(def, name, value)
    end
    return true
end

-- Reset: every setting of the pearl back to its default, then its onReset.
function Pearls.ResetSettings(key)
    local def = byKey[key]
    if not def or not GP.db then return false end
    local was = {}
    for name in pairs(def.defaults) do was[name] = Pearls.Setting(key, name) end
    GP.db.settings[key] = nil
    for name, d in pairs(def.defaults) do
        if was[name] ~= d then
            touch(key .. "." .. name)
            changed(def, name, d)
        end
    end
    if def.onReset then
        local ok, err = pcall(def.onReset)
        if not ok then API.Fail("pearl " .. key .. " reset", err) end
    end
    return true
end

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
    local was = Pearls.IsOn(key)
    if on == def.default then GP.db.pearls[key] = nil else GP.db.pearls[key] = on end
    if on then enable(def) else disable(def) end
    if on ~= was then touch("on." .. key) end
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

-- The same for the pearls' own settings: a pearl's table that isn't a table
-- goes; for a known pearl, a setting it doesn't declare, of another type than
-- its default, or equal to it, goes. An unknown pearl's table stays.
function Pearls.CleanSettings(all)
    for key, t in pairs(all) do
        local def = byKey[key]
        if type(t) ~= "table" then
            all[key] = nil
        elseif def then
            for name, v in pairs(t) do
                local d = def.defaults[name]
                if d == nil or type(v) ~= type(d) or v == d then t[name] = nil end
            end
            if next(t) == nil then all[key] = nil end
        end
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
