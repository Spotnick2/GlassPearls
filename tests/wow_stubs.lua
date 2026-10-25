-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
-- Lifted from GlassMail's stubs (GlassChat's generic part: secrets, events,
-- widgets, strict globals), plus GlassChat's Battle.net stubs for the
-- embedded LibAccountSync-1.0.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump; defining
--   something Forever lacks is how a missing API survives into a build.
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare
--   (tests/events-70532.txt when the dump is absent, as on CI).
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GLASSPEARLS_API_DUMP") or "C:/Projects/WoW/References/Forever/api/forever-api-1.60.1.70532.md"
WoW.DUMP = DUMP

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end

-- Mark an existing value secret for issecretvalue. The client's secrets keep
-- their type (a secret string is still type "string"), which a proxy can't
-- model; use this to reach `type(x) == "string"` branches.
function WoW.MarkSecret(v, label) secrets[v] = label or "marked" end

--------------------------------------------------------------------------------
-- Known events (from the dump when present, else the checked-in fixture)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
WoW.dumpAvailable = false
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
        WoW.dumpAvailable = next(WoW.KNOWN_EVENTS) ~= nil
    end
    if not WoW.dumpAvailable then
        -- No dump (CI): the list generated from it, so validation stays
        -- exactly as strict. test_toc fails if the two ever drift.
        local fixture = io.open("tests/events-70532.txt", "r")
        assert(fixture, "tests/events-70532.txt missing: event validation needs the dump or the fixture")
        for line in fixture:lines() do
            local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
            if name then WoW.KNOWN_EVENTS[name] = true end
        end
        fixture:close()
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = {}
    WoW.combat = false
    WoW.timers = {}
    -- A template named here is missing on the client: CreateFrame returns a
    -- bare frame without its fields, as the client does.
    WoW.missingTemplates = WoW.missingTemplates or {}
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- shared implementations, by method name

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end  -- fields read as nil
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    return setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                          _scripts = {}, _events = {},
                          _level = parent and parent._level and (parent._level + 1) or 1,
                          _width = 0, _height = 0, _name = name }, widgetMT)
end
WoW.newWidget = newWidget

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    -- The template's bar, shown by default as on the client.
    if template == "UIPanelScrollFrameTemplate" then w.ScrollBar = newWidget("Slider", w) end
    -- The radio template's own label (CheckButtonTemplates.xml: parentKey "text").
    if template == "UIRadioButtonTemplate" then w.text = Methods.CreateFontString(w) end
    -- DialogTemplates.xml: the dark dialog border's background (parentKey Bg).
    if template == "DialogBorderDarkTemplate" and not WoW.missingTemplates[template] then
        w.Bg = Methods.CreateTexture(w)
    end
    -- InputBoxTemplates.xml:209: the search box's instruction text.
    if template == "SearchBoxTemplate" and not WoW.missingTemplates[template] then
        w.Instructions = Methods.CreateFontString(w)
    end
    table.insert(WoW.frames, w)
    if parent then
        parent._children = parent._children or {}
        table.insert(parent._children, w)
    end
    if name then rawset(_G, name, w) end
    return w
end
function Methods.GetChildren(w) return unpack(w._children or {}) end

function Methods.Show(w) w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end end
function Methods.Hide(w)
    local was = w._shown
    w._shown = false
    if was and w._scripts.OnHide then w._scripts.OnHide(w) end
end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
function Methods.SetAlpha(w, a) w._alpha = a end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.GetParent(w) return w._parent end
function Methods.SetParent(w, p) w._parent = p end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.EnableMouse(w, v) w._mouse = v end
-- A button's enabled state (enabled until told otherwise).
function Methods.Enable(b) b._disabled = false end
function Methods.Disable(b) b._disabled = true end
function Methods.SetEnabled(b, v) b._disabled = not v end
function Methods.IsEnabled(b) return not b._disabled end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.GetName(w) return w._name end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.IsForbidden(w) return false end

-- Attributes: recorded; like the client, refused on a protected frame in
-- combat.
function Methods.SetAttribute(w, k, v)
    if WoW.combat and w._protected then return end
    w._attrs = w._attrs or {}
    w._attrs[k] = v
end
function Methods.GetAttribute(w, k) return w._attrs and w._attrs[k] end
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end
function Methods.IsEventRegistered(w, e) return w._events[e] == true end

-- Regions: listed in creation order for GetRegions, as the client lists a
-- frame's textures and font strings.
local function addRegion(w, r)
    w._regions = w._regions or {}
    table.insert(w._regions, r)
    return r
end
function Methods.CreateTexture(w, name, layer, template, sublevel)
    local t = addRegion(w, newWidget("Texture", w, name))
    t._layer, t._sublevel = layer, sublevel
    if name then rawset(_G, name, t) end
    return t
end
function Methods.CreateMaskTexture(w) return newWidget("MaskTexture", w) end
function Methods.CreateFontString(w, name)
    local fs = addRegion(w, newWidget("FontString", w, name))
    if name then rawset(_G, name, fs) end
    return fs
end
function Methods.GetRegions(w) return unpack(w._regions or {}) end
function Methods.GetObjectType(w) return w._type end
-- A button's state textures: Set*Texture(file) makes one, Get*Texture reads it.
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked", "Disabled" }) do
    local key = "_" .. state:lower() .. "Texture"
    Methods["Set" .. state .. "Texture"] = function(b, file)
        b[key] = b[key] or newWidget("Texture", b)
        b[key]._file = file
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b[key] end
end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.SetDesaturated(t, on) t._desaturated = on == true end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2) t._gradient = { orientation, c1, c2 } end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
-- Animations: groups record whether they play.
function Methods.CreateAnimationGroup(w) return newWidget("AnimationGroup", w) end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.Play(ag) ag._playing = true end
function Methods.Stop(ag) ag._playing = false end
function Methods.IsPlaying(ag) return ag._playing == true end

-- FontString: the client formats natively and accepts secrets. With any
-- secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
-- An EditBox runs its OnTextChanged on SetText, as the client does.
function Methods.SetText(fs, text)
    fs._text = text
    if fs._type == "EditBox" and fs._scripts.OnTextChanged then fs._scripts.OnTextChanged(fs, false) end
end
-- A SimpleHTML colours per text type ("P", "H1", ...), its first argument.
function Methods.SetTextColor(fs, ...)
    if fs._type == "SimpleHTML" then
        local textType, r, g, b, a = ...
        assert(type(textType) == "string", "SimpleHTML:SetTextColor needs a text type first")
        fs._htmlColor = fs._htmlColor or {}
        fs._htmlColor[textType] = { r, g, b, a }
        return
    end
    local r, g, b, a = ...
    fs._textColor = { r, g, b, a }
end
function Methods.GetTextColor(fs, textType)
    local c
    if fs._type == "SimpleHTML" then
        assert(type(textType) == "string", "SimpleHTML:GetTextColor needs a text type")
        c = fs._htmlColor and fs._htmlColor[textType]
    else
        c = fs._textColor
    end
    c = c or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.GetFontObject(fs) return fs._fontObject end
-- An EditBox's selection colour.
function Methods.SetHighlightColor(e, r, g, b, a) e._highlight = { r, g, b, a } end
function Methods.GetHighlightColor(e)
    local c = e._highlight or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.GetText(fs) return fs._text end
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end
function Methods.SetFontObject(fs, obj) fs._fontObject = obj end
function Methods.GetFont(fs)
    local f = fs._font or { "Fonts\FRIZQT__.TTF", 10, "" }
    return f[1], f[2], f[3]
end
function Methods.GetFontString(b) return b._fontString end
-- CheckButton.
function Methods.SetChecked(b, v) b._checked = v and true or false end
function Methods.GetChecked(b) return b._checked == true end
-- StatusBar.
function Methods.SetMinMaxValues(b, lo, hi) b._min, b._max = lo, hi end
function Methods.SetStatusBarColor(b, r, g, bl, a) b._color = { r, g, bl, a } end
function Methods.GetValue(b) return b._value end
function Methods.SetValue(b, v) b._value = v end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end

WoW.reset()

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
date = os.date
time = os.time
function GetTime() return WoW.now or 0 end
function GetServerTime() return time() end
function GetBuildInfo() return "1.60.1", "70532", "Oct 20 2026", 16001 end
function InCombatLockdown() return WoW.combat == true end
-- The player: GUID, and the name split across UnitName's two returns, one of
-- the two shapes the client has used (AltStable #56).
WoW.playerGUID = "Player-1-AAA"
function UnitGUID(unit) if unit == "player" then return WoW.playerGUID end end
function UnitName(unit) if unit == "player" then return WoW.playerName or "Karuzo", "Morphisto" end end
function GetRealmName() return "Doomhowl" end

WoW.addonVersion = "dev"
C_AddOns = {
    GetAddOnMetadata = function(name, field) if field == "Version" then return WoW.addonVersion end end,
}

-- The Settings framework (Blizzard_Settings): canvas categories, recorded.
WoW.categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local c = { frame = frame, name = name, id = #WoW.categories + 1 }
        function c:GetID() return self.id end
        table.insert(WoW.categories, c)
        return c
    end,
    RegisterAddOnCategory = function(c) c.registered = true end,
    OpenToCategory = function(id) WoW.openedCategory = id end,
}

-- UIParentPanelManager.lua:21: the frames Esc closes (a table; addons insert).
UISpecialFrames = { "SettingsPanel" }
WoW.uiSpecialFrames = UISpecialFrames   -- the original table, to prove it was never replaced

-- ReloadUI (dump _G walk): recorded; WoW.reloadForbidden makes it behave as a
-- protected call from addon code does: nothing happens and
-- ADDON_ACTION_FORBIDDEN fires (porting guide section 3).
WoW.reloads = 0
function ReloadUI()
    if WoW.reloadForbidden then
        WoW.fire("ADDON_ACTION_FORBIDDEN", "GlassPearls", "ReloadUI()")
        return
    end
    WoW.reloads = WoW.reloads + 1
end

-- The player's class (UnitClass, documented) and its colour (C_ClassColor).
WoW.class = "MAGE"
function UnitClass(unit) if unit == "player" then return "Mage", WoW.class, 8 end end
C_ClassColor = { GetClassColor = function(class)
    if class == "MAGE" then return { r = 0.25, g = 0.78, b = 0.92 } end
end }

-- GameTooltip: its owner and lines, as text. SetOwner starts it over.
GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
GameTooltip._lines = {}
function Methods.SetOwner(t, owner) t._owner, t._lines = owner, {} end
function Methods.AddLine(t, text) table.insert(t._lines, text) end
local plainSetText = Methods.SetText
function Methods.SetText(w, text, ...)
    if w._type == "GameTooltip" then w._lines = { text } else plainSetText(w, text, ...) end
end

-- Glass UI's suite (GlassUI\docs\SUITE.md), scriptable per test:
-- WoW.installGlassUI({ theme = answer or function, look = {...}, body = {...} })
-- puts a GlassUI global with Suite API 1; WoW.suiteReports records Report calls.
WoW.suiteReports = {}
function WoW.installGlassUI(opts)
    opts = opts or {}
    local S = { API = opts.api or 1 }
    S.Theme = function(addon)
        WoW.suiteAsked = addon
        if type(opts.theme) == "function" then return opts.theme(addon) end
        if opts.theme == nil then return { name = "pearl", preset = "pearl" } end
        return opts.theme
    end
    S.Report = function(addon, state) table.insert(WoW.suiteReports, { addon = addon, state = state }) end
    if opts.look then S.Look = function() return opts.look end end
    if opts.body then S.Body = function() return opts.body end end
    if opts.accent then S.Accent = function() return opts.accent end end
    rawset(_G, "GlassUI", { Suite = S })
    return S
end

-- The client's secure hook replaces t[name] with a wrapper: the sanctioned way
-- to hook a Blizzard method. WoW.hooked records it, so the "no field written"
-- checks can tell it from a field the addon wrote.
WoW.hooked = {}
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    WoW.hooked[t] = WoW.hooked[t] or {}
    WoW.hooked[t][name] = true
    local orig = rawget(t, name) or t[name]
    rawset(t, name, function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end)
end

-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo
-- seconds (all when nil) and keeps the rest.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn }) end }
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do t.fn() end
end
--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- Every event any frame registered, fired once with no payload: strict
-- globals only catch code that actually runs.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
    end
    for e in pairs(seen) do WoW.fire(e) end
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

--------------------------------------------------------------------------------
-- Battle.net, for the embedded LibAccountSync-1.0 (GlassChat's stubs, ported
-- from the library's own tests/wow_stubs.lua: game account ids are local
-- handles, an unknown id is TargetRequired (6), an offline one TargetOffline
-- (12), BN_CHAT_MSG_ADDON delivers (prefix, text, "WHISPER", senderID)).
-- WoW.bn.accounts[id] = { characterName, playerGuid, isOnline, clientProgram,
--   wowProjectID, regionID, isInCurrentRegion, factionName, realmName,
--   bnetAccountID } declares an account this client can see.
--------------------------------------------------------------------------------

WoW.bn = { me = 1, myId = 2, project = 18, region = 90, tag = "Owner#1", connected = true,
           accounts = {}, friends = {} }
WoW.prefixes, WoW.bnSent, WoW.sendResults = {}, {}, {}
WoW.player = { faction = "Alliance" }

local function bnSelf()
    return { gameAccountID = WoW.bn.myId, characterName = (UnitName("player")), playerGuid = UnitGUID("player"),
             isOnline = true, clientProgram = "WoW", wowProjectID = WoW.bn.project, regionID = WoW.bn.region,
             isInCurrentRegion = true, factionName = WoW.player.faction, realmName = GetRealmName() }
end
local function bnCopy(t, id)
    if not t then return nil end
    local c = {}
    for k, v in pairs(t) do if k ~= "bnetAccountID" and k ~= "battleTag" then c[k] = v end end
    c.gameAccountID = id
    return c
end
C_BattleNet = {}
function C_BattleNet.GetGameAccountInfoByID(id)
    if id == WoW.bn.myId then return bnSelf() end
    return bnCopy(WoW.bn.accounts[id], id)
end
function C_BattleNet.GetGameAccountInfoByGUID(guid)
    if guid == UnitGUID("player") then return bnSelf() end
    for id, a in pairs(WoW.bn.accounts) do
        if a.playerGuid == guid then return bnCopy(a, id) end
    end
end
function C_BattleNet.GetAccountInfoByGUID(guid)
    if guid == UnitGUID("player") then
        return { bnetAccountID = WoW.bn.me, battleTag = WoW.bn.tag, gameAccountInfo = bnSelf() }
    end
    for id, a in pairs(WoW.bn.accounts) do
        if a.playerGuid == guid then
            local tag = (a.bnetAccountID == WoW.bn.me) and WoW.bn.tag or ("Other#" .. tostring(a.bnetAccountID))
            return { bnetAccountID = a.bnetAccountID, battleTag = tag, gameAccountInfo = bnCopy(a, id) }
        end
    end
end
function C_BattleNet.SendGameData(id, prefix, text)
    local result = table.remove(WoW.sendResults, 1)
    if result == nil then
        local a = (id == WoW.bn.myId) and bnSelf() or WoW.bn.accounts[id]
        result = (a == nil) and 6 or (a.isOnline and 0 or 12)
    end
    if result ~= 0 then return result end
    table.insert(WoW.bnSent, { prefix = prefix, text = text, target = id })
    return 0
end
function C_BattleNet.GetFriendNumGameAccounts(i) return #(WoW.bn.friends[i] or {}) end
function C_BattleNet.GetFriendGameAccountInfo(i, j)
    local id = (WoW.bn.friends[i] or {})[j]
    if not id then return nil end
    return C_BattleNet.GetGameAccountInfoByID(id) or { gameAccountID = id }
end
function BNFeaturesEnabledAndConnected() return WoW.bn.connected ~= false end
function BNGetNumFriends() return #WoW.bn.friends, #WoW.bn.friends end
function BNGetInfo() return WoW.bn.me, WoW.bn.tag end

C_ChatInfo = {}
function C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    WoW.prefixes[prefix] = true
    return 0
end
function UnitFactionGroup(unit) if unit == "player" then return WoW.player.faction, WoW.player.faction end end
function IsLoggedIn() return WoW.loggedIn == true end
function debugprofilestop() return (GetTime() or 0) * 1000 end
function fastrandom(a, b) return math.random(a, b) end
WoW.errors = {}
function geterrorhandler() return function(err) table.insert(WoW.errors, err) end end
function securecallfunction(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then geterrorhandler()(r[2]); return end
    return unpack(r, 2, table.maxn(r))
end
function C_Timer.NewTicker(seconds, fn)
    local t = { s = seconds, fn = fn, every = seconds }
    table.insert(WoW.timers, t)
    return { Cancel = function() t.cancelled = true end }
end

-- ChatThrottleLib as a stub (version 10000, so the library's vendored v32
-- steps aside), with v32's checks: a known priority, WHISPER, at most 255
-- bytes, and the callback (arg, didSend, result).
local CTL_PRIORITIES = { BULK = true, NORMAL = true, ALERT = true }
ChatThrottleLib = {
    version = 10000,
    BNSendGameData = function(self, prio, prefix, text, chattype, gameAccountID, q, callbackFn, callbackArg)
        if not CTL_PRIORITIES[prio] or not gameAccountID or chattype ~= "WHISPER" then
            error("ChatThrottleLib:BNSendGameData(): bad arguments", 2)
        end
        if #text > 255 then error("ChatThrottleLib:BNSendGameData(): message length cannot exceed 255 bytes", 2) end
        local ok, r = pcall(C_BattleNet.SendGameData, gameAccountID, prefix, text)
        if not ok then geterrorhandler()(r); r = 9 end
        if callbackFn then securecallfunction(callbackFn, callbackArg, r == 0, r) end
    end,
}

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded libraries' loaders read _G.LibStub before creating it.
local allowNil = { GlassPearls = true, GlassPearlsDB = true, GlassPearlsCharDB = true, GlassPearlsSyncDB = true, GlassUI = true,
    LibStub = true }
-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
