-- AccountSync.lua: GlassPearls' link to your other WoW accounts, through the
-- embedded LibAccountSync-1.0 (Spotnick2/LibAccountSync; the TOC loads its
-- XML first). GlassChat's AccountSync.lua is the model: same store rule, same
-- kind dispatch.
--
-- One snapshot instance, tag "GlassPearls" (wire-visible and permanent: never
-- change it). Each send replaces the last from the same sender. A pearl that
-- needs a second kind of snapshot, or independent messages (requests,
-- replies), gets its own instance on its own tag over the same store, as
-- GlassChat does with "GlassChatST" (LibAccountSync#17).
--
-- The store is GlassPearlsSyncDB, account-wide, declared in the TOC on its own
-- so the household key it holds never sits beside settings that might be
-- shared. GlassPearls.lua creates it at ADDON_LOADED; until then the getter
-- returns nil and the library fails closed (it asks again on every access).
--
-- A payload is "<kind>\n<body>", and the kind alone picks the handler. The
-- library gives the sender from Blizzard's own sender id, never from the
-- payload, and the payload is data: handlers validate it and never run it.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local AS = {}
GP.AccountSync = AS

AS.TAG = "GlassPearls"
AS.REPORTS = 20
-- The wire ceiling (as GlassChat): the settings snapshot's budget is sized
-- to it (SettingsSync.lua). The library's default is 16 KB.
AS.MAX = 32768

local handlers = {}
local reports = {}
AS.reports = reports

local function report(text, kind)
    if API.IsSecret(text) or type(text) ~= "string" then return end
    reports[#reports + 1] = { text = text, kind = kind }
    if #reports > AS.REPORTS then table.remove(reports, 1) end
    if kind == "error" then API.Fail("account sync", text) end
    if kind == "error" or (GP.IsDev and GP.IsDev()) then API.Print("account sync: " .. text) end
end

local function store()
    local t = rawget(_G, "GlassPearlsSyncDB")
    return type(t) == "table" and t or nil
end

local function dispatch(payload, sender, sid)
    if API.IsSecret(payload) or type(payload) ~= "string" then return end
    local kind, body = payload:match("^(%w+)\n(.*)$")
    local fn = kind and handlers[kind]
    if not fn then return end   -- a kind this copy doesn't know: ignored
    local ok, err = pcall(fn, body, sender, sid)
    if not ok then API.Fail("account sync " .. kind, err) end
end

local lib = rawget(_G, "LibStub") and LibStub("LibAccountSync-1.0", true)
if lib then
    local ok, inst = pcall(lib.New, lib, { addon = AS.TAG, store = store, report = report, maxPayload = AS.MAX })
    if ok and inst then
        AS.inst = inst
        inst.OnMessage(dispatch)
    else
        API.Fail("account sync", inst or "no instance")
    end
else
    API.Fail("account sync", "LibAccountSync-1.0 not loaded")
end

-- A pearl's handler for one payload kind (letters or digits): fn(body, sender, sid).
function AS.On(kind, fn)
    assert(type(kind) == "string" and kind:match("^%w+$"), "AccountSync.On: kind must be letters or digits")
    assert(type(fn) == "function", "AccountSync.On: a function")
    handlers[kind] = fn
end

-- Send one kind's snapshot to every proven own account. Returns the library's
-- count, why ("disabled", "no-peers", "too-large", ...), or nil, "no-instance".
function AS.Send(kind, body, onResult)
    if not AS.inst then return nil, "no-instance" end
    return AS.inst.Send(kind .. "\n" .. body, onResult)
end

function AS.IsEnabled() return AS.inst ~= nil and AS.inst.IsEnabled() end

function AS.SetEnabled(on)
    if not AS.inst then return false end
    AS.inst.SetEnabled(on == true)
    return true
end

-- The library's readout, then this addon's recent reports.
function AS.Lines()
    local lines = {}
    if not AS.inst then
        lines[1] = "LibAccountSync-1.0 is not loaded"
        return lines
    end
    for line in AS.inst.Diagnostics() do lines[#lines + 1] = line end
    for _, r in ipairs(reports) do lines[#lines + 1] = "report (" .. tostring(r.kind) .. "): " .. r.text end
    return lines
end

AS._test = { dispatch = dispatch }
