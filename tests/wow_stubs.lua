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
    -- SecureTemplates.xml:4: protected, with Blizzard's OnClick (WoW.secureActionClick).
    if template and template:find("SecureActionButtonTemplate", 1, true) then
        w._protected = true
        w._scripts.OnClick = function(...) return WoW.secureActionClick(...) end
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

-- A protected frame (a secure template's) refuses to show, hide or move in
-- combat, as the client does: nothing happens and the call is recorded in
-- WoW.blocked (porting guide, "Secure click-casting works").
WoW.blocked = {}
local function refused(w, what)
    if WoW.combat and w._protected then table.insert(WoW.blocked, (w._name or w._type) .. ":" .. what); return true end
end
function Methods.Show(w)
    if refused(w, "Show") then return end
    w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end
end
function Methods.Hide(w)
    if refused(w, "Hide") then return end
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
function Methods.SetPoint(w, ...) if refused(w, "SetPoint") then return end; table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) if refused(w, "ClearAllPoints") then return end; w._points = {} end
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
function Methods.UnregisterAllEvents(w) w._events = {} end
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
function Methods.SetTexture(t, file) t._file, t._atlas = file, nil; return true end
function Methods.SetDesaturated(t, on) t._desaturated = on == true end
-- No return value (the dump declares none): ask C_Texture.GetAtlasInfo first.
function Methods.SetAtlas(t, name) t._atlas, t._file = name, nil end
function Methods.SetMouseClickEnabled(w, on) w._clicks = on == true end
function Methods.SetMouseMotionEnabled(w, on) w._motion = on == true end
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
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 },
         LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 } }   -- LootConstantsDocumentation.lua:41
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
-- checks can tell it from a field the addon wrote; the value counts the hooks.
WoW.hooked = {}
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    WoW.hooked[t] = WoW.hooked[t] or {}
    WoW.hooked[t][name] = (WoW.hooked[t][name] or 0) + 1
    local orig = rawget(t, name) or t[name]
    rawset(t, name, function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end)
end

-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo
-- seconds (all when nil) and keeps the rest.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn, at = (WoW.now or 0) + s }) end }
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do t.fn() end
end
-- A clock instead: move WoW.now on by dt and run the timers due by then, in
-- order of when they fall due (timers they schedule count from the new now).
function WoW.advance(dt)
    WoW.now = (WoW.now or 0) + dt
    while true do
        local due, at
        for i, t in ipairs(WoW.timers) do
            local tAt = t.at or t.s or 0      -- a timer made without a clock: due from 0
            if tAt <= WoW.now and (not at or tAt < at) then due, at = i, tAt end
        end
        if not due then return end
        local t = table.remove(WoW.timers, due)
        t.fn()
    end
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

--------------------------------------------------------------------------------
-- Bags, items, the cursor and the loot window, for the bags-full helper (#6).
-- Every function below is in the 70532 dump (documented, or its _G walk:
-- LootSlot, GetLootSlotInfo, DeleteCursorItem, ...); shapes follow the dump's
-- structures (ContainerItemInfo, ItemQuestInfo) and Blizzard's callers
-- (LootFrame.lua:228 for GetLootSlotInfo's returns).
--
--   WoW.bags[bag] = { size = n, family = 0, items = { [slot] = { id, count } } }
--   WoW.items[id] = { name, price, quality, classID, subclassID, maxStack,
--                     family, spell, icon, level }    -- nil: not in the item cache
--   WoW.quest["bag:slot"] = { isQuestItem, questID }   (WoW.questUnreadable)
--   WoW.loot = { { id, qty, isQuest, questID } }        WoW.openLoot / closeLoot
--   WoW.sets[setID] = { itemIDs }
-- Calls are recorded in WoW.calls (PickupContainerItem, DeleteCursorItem,
-- ClearCursor, LootSlot). WoW.deleteForbidden: DeleteCursorItem raises
-- ADDON_ACTION_FORBIDDEN at once and deletes nothing; WoW.deleteSilent:
-- nothing happens (the item stays on the cursor); WoW.pickupFails: the pickup
-- does nothing.
--------------------------------------------------------------------------------

function WoW.resetBags()
    WoW.bags, WoW.items, WoW.quest, WoW.loot, WoW.sets = {}, {}, {}, {}, {}
    WoW.cursor, WoW.calls, WoW.lootOpen = nil, {}, false
    WoW.deleteForbidden, WoW.deleteSilent, WoW.pickupFails, WoW.questUnreadable = false, false, false, false
end
WoW.resetBags()

local function itemLink(id)
    local it = WoW.items[id]
    return "|cffffffff|Hitem:" .. id .. "::::::::16:::::|h[" .. (it and it.name or ("item " .. id)) .. "]|h|r"
end
WoW.itemLink = itemLink
local function idOf(x)
    if type(x) == "number" then return x end
    if type(x) == "string" then return tonumber(x:match("item:(%d+)")) end
end
local function call(name, ...) table.insert(WoW.calls, { name, ... }) end

C_Container = {}
function C_Container.GetContainerNumSlots(bag) return WoW.bags[bag] and WoW.bags[bag].size or 0 end
function C_Container.GetContainerNumFreeSlots(bag)
    local b = WoW.bags[bag]
    if not b then return 0, 0 end
    local used = 0
    for _ in pairs(b.items) do used = used + 1 end
    if b.familySecret then return b.size - used, WoW.Secret("family") end
    return b.size - used, b.family or 0
end
function C_Container.GetContainerItemInfo(bag, slot)
    local b = WoW.bags[bag]
    local s = b and b.items[slot]
    if not s then return nil end
    local it = WoW.items[s.id]
    local onCursor = WoW.cursor and WoW.cursor.bag == bag and WoW.cursor.slot == slot
    local locked = onCursor or s.locked == true
    if s.lockSecret then locked = WoW.Secret("isLocked") end
    return { iconFileID = it and it.icon or 134400, stackCount = s.count or 1, isLocked = locked,
             quality = s.quality or (it and it.quality), isReadable = false, hasLoot = false,
             hyperlink = itemLink(s.id), isFiltered = false, hasNoValue = s.noValue == true or (it and it.price == 0) or false,
             itemID = s.id, isBound = false, itemName = it and it.name or "" }
end
function C_Container.GetContainerItemQuestInfo(bag, slot)
    if WoW.questUnreadable then return nil end
    local q = WoW.quest[bag .. ":" .. slot] or {}
    return { isQuestItem = q.isQuestItem == true, questID = q.questID, isActive = false }
end
function C_Container.PickupContainerItem(bag, slot)
    call("PickupContainerItem", bag, slot)
    if WoW.pickupFails then return end
    local s = WoW.bags[bag] and WoW.bags[bag].items[slot]
    if s and not WoW.cursor then WoW.cursor = { bag = bag, slot = slot, id = s.id } end
end
-- The cursor holds an item ({ bag, slot, id }), or a spell / macro / other
-- ({ kind = "spell", id }): a spell's ID is GetCursorInfo's 4th return, as
-- Blizzard reads it (SharedUIPanelTemplates.lua:1955).
function GetCursorInfo()
    local c = WoW.cursor
    if not c then return end
    if c.kind == "spell" then return "spell", 1, "spell", c.id end
    if c.kind then return c.kind, c.id end
    return "item", c.id, itemLink(c.id)
end
function CursorHasItem() return WoW.cursor ~= nil and WoW.cursor.kind == nil end
function ClearCursor() call("ClearCursor"); WoW.cursor = nil end
function DeleteCursorItem()
    call("DeleteCursorItem")
    if WoW.deleteForbidden then
        WoW.fire("ADDON_ACTION_FORBIDDEN", "GlassPearls", "DeleteCursorItem()")
        return
    end
    if WoW.deleteSilent or not WoW.cursor then return end
    WoW.bags[WoW.cursor.bag].items[WoW.cursor.slot] = nil
    WoW.cursor = nil
end

C_Item = {}
function C_Item.GetItemInfo(x)
    local id = idOf(x)
    local it = id and WoW.items[id]
    if not it then return end   -- a cache miss returns nothing (porting guide)
    return it.name, itemLink(id), it.quality, it.level or 10, 1, "Type", "Subtype", it.maxStack or 20, "", it.icon or 134400,
        it.price or 0, it.classID or 15, it.subclassID or 0, 0, 0, nil, false, ""
end
function C_Item.GetItemInfoInstant(x)
    local id = idOf(x)
    if not id then return end
    local it = WoW.items[id] or {}
    return id, "Type", "Subtype", "", it.icon or 134400, it.classID or 15, it.subclassID or 0
end
function C_Item.GetItemSpell(x)
    local it = WoW.items[idOf(x)]
    if it and it.spell then return "Use", 1234 end
end
function C_Item.GetItemMaxStackSizeByID(x)
    local it = WoW.items[idOf(x)]
    return it and (it.maxStack or 20)
end
function C_Item.GetItemFamily(x)
    local it = WoW.items[idOf(x)]
    return it and (it.family or 0)
end
function C_Item.GetItemQualityColor(q) return 1, 1, 1, "ffffffff" end
function C_Item.GetItemNameByID(x)
    local it = WoW.items[idOf(x)]
    return it and it.name
end
function C_Item.RequestLoadItemDataByID(x) call("RequestLoadItemDataByID", idOf(x)) end

C_EquipmentSet = {
    GetEquipmentSetIDs = function()
        local ids = {}
        for id in pairs(WoW.sets) do ids[#ids + 1] = id end
        return ids
    end,
    GetItemIDs = function(setID) return WoW.sets[setID] or {} end,
}
C_CurrencyInfo = { GetCoinTextureString = function(c) return tostring(c) .. "c" end }
-- The client's bit library (Lua 5.1 has none): band over non-negative ints.
bit = { band = function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end }

-- GlobalStrings: the client's own text for a full inventory.
ERR_INV_FULL = "Inventory is full."
-- GetGameMessageInfo(errorType) -> errorName (GameErrorDocumentation.lua:10).
WoW.errorNames = { [3] = "ERR_INV_FULL", [50] = "ERR_SPELL_COOLDOWN" }
function GetGameMessageInfo(errorType) return WoW.errorNames[errorType] end

-- Blizzard's loot window (Blizzard_UIPanels_Game, LootFrame.xml:116).
LootFrame = newWidget("Frame", UIParent, "LootFrame")
LootFrame._shown = false
-- opts (faster loot, #36): autoloot = the events' payload (default false;
-- WoW.NIL for nil), noReady (only LOOT_OPENED), emptyReady (no slots yet at
-- LOOT_READY, LootDocumentation.lua:229), noOpened.
WoW.NIL = {}
function WoW.openLoot(rows, opts)
    opts = opts or {}
    WoW.loot = rows or WoW.loot
    WoW.lootOpen = true
    LootFrame._shown = true
    local auto = opts.autoloot
    if auto == nil then auto = false elseif auto == WoW.NIL then auto = nil end
    if not opts.noReady then
        WoW.lootEmpty = opts.emptyReady
        WoW.fire("LOOT_READY", auto)
        WoW.lootEmpty = nil
    end
    if not opts.noOpened then WoW.fire("LOOT_OPENED", auto, false) end
end
function WoW.closeLoot()
    WoW.lootOpen = false
    LootFrame._shown = false
    WoW.fire("LOOT_CLOSED")
end
function GetNumLootItems()
    if WoW.lootEmpty then return 0 end
    return WoW.lootOpen and #WoW.loot or 0
end
function GetLootSlotType(i)
    local r = WoW.lootOpen and WoW.loot[i]
    if not r then return Enum.LootSlotType.None end
    return r.kind or Enum.LootSlotType.Item
end
function LootSlotHasItem(i)
    local r = WoW.lootOpen and WoW.loot[i]
    return r ~= nil and not r.taken
end
-- A row: { id, qty, kind (Enum.LootSlotType), quality, locked, isQuest, questID }.
function GetLootSlotInfo(i)
    local r = WoW.lootOpen and WoW.loot[i]
    if not r or r.taken then return end
    local it = WoW.items[r.id] or {}
    local quality = r.quality
    if quality == nil then quality = it.quality or 1 end
    local locked = r.locked
    if locked == nil then locked = false end
    return it.icon or 134400, it.name or "", r.qty or 1, nil, quality, locked, r.isQuest == true, r.questID, false,
        r.kind == Enum.LootSlotType.Money
end
function GetLootSlotLink(i)
    local r = WoW.lootOpen and WoW.loot[i]
    if r and not r.taken then return itemLink(r.id) end
end
-- Recorded; WoW.takeLoot(i) applies it (the row empties: LOOT_SLOT_CLEARED).
function LootSlot(i) call("LootSlot", i) end
function WoW.takeLoot(i)
    WoW.loot[i].taken = true
    WoW.fire("LOOT_SLOT_CLEARED", i)
end
--------------------------------------------------------------------------------
-- Maps, for the map landmarks (#10). C_Map / C_TaxiMap / C_Texture /
-- GetLFGDungeonInfo / UnitLevel are in the 70532 dump; WorldMapFrame, its
-- dataProviders and the area label provider's Label are Blizzard's
-- (Blizzard_MapCanvas.lua:191, AreaLabelDataProvider.lua:8);
-- GetQuestDifficultyColor (DifficultyUtil.lua:68) and QuestDifficultyColors
-- (Constants.lua:195) are FrameXML's.
--   WoW.cursorMap = { mapID, x, y, focus } where the world map's cursor is
--   WoW.mapAt[mapID] = { mapID, name }  (C_Map.GetMapInfoAtPosition, any x/y)
--   WoW.mapLevels[mapID] = { lo, hi }   (C_Map.GetMapLevels; absent = 0, 0)
--   WoW.taxi[uiMapID] = { nodes }; WoW.taxiShown[uiMapID] = true (Blizzard draws them)
--   WoW.atlases[name] = true            (C_Texture.GetAtlasInfo)
--   WoW.lfgNames[id] = "name"           (GetLFGDungeonInfo)
--------------------------------------------------------------------------------

WoW.cursorMap = { mapID = 1414, x = 0.5, y = 0.5, focus = true }
WoW.mapAt, WoW.mapLevels, WoW.taxi, WoW.taxiShown, WoW.atlases, WoW.lfgNames = {}, {}, {}, {}, {}, {}
WoW.playerLevel = 30
WorldMapFrame = newWidget("Frame", UIParent, "WorldMapFrame")
WorldMapFrame._shown = false
-- AreaLabelFrameTemplate (AreaLabelDataProvider.xml:5): a 400x128 frame, Name
-- at TOP -20, Description under Name ("" when the label has none). Another
-- provider with a Label of a different shape must not be taken for it.
local areaLabelProvider = { Label = newWidget("Frame", WorldMapFrame) }
local areaLabel = areaLabelProvider.Label
areaLabel:SetSize(400, 128)
areaLabel.Name = areaLabel:CreateFontString(nil, "OVERLAY", "WorldMapTextFont")
areaLabel.Name:SetPoint("TOP", 0, -20)
areaLabel.Description = areaLabel:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
areaLabel.Description:SetPoint("TOP", areaLabel.Name, "BOTTOM", 0, -10)
areaLabel.Description:SetText("")
WorldMapFrame.dataProviders = { [{ Label = newWidget("Frame", WorldMapFrame) }] = true, [areaLabelProvider] = true }
WoW.areaLabel = areaLabel
function Methods.IsCanvasMouseFocus(w) return WoW.cursorMap.focus == true end
function Methods.GetMapID(w) return WoW.cursorMap.mapID end
function Methods.GetNormalizedCursorPosition(w) return WoW.cursorMap.x, WoW.cursorMap.y end
C_Map = C_Map or {}
function C_Map.GetMapInfoAtPosition(mapID, x, y) return WoW.mapAt[mapID] end
function C_Map.GetMapLevels(mapID)
    local l = WoW.mapLevels[mapID]
    if l then return l[1], l[2], 0, 0 end
    return 0, 0, 0, 0
end
C_TaxiMap = {
    GetTaxiNodesForMap = function(uiMapID) return WoW.taxi[uiMapID] or {} end,
    ShouldMapShowTaxiNodes = function(uiMapID) return WoW.taxiShown[uiMapID] == true end,
}
-- WoW.atlases[name] = true (16x16) or { width = w, height = h }.
C_Texture = { GetAtlasInfo = function(name)
    local a = WoW.atlases[name]
    if type(a) == "table" then return { width = a.width, height = a.height } end
    if a then return { width = 16, height = 16 } end
end }
function GetLFGDungeonInfo(id) return WoW.lfgNames[id] end
function UnitLevel(unit) if unit == "player" then return WoW.playerLevel end end
QuestDifficultyColors = { difficult = { r = 1, g = 0.5, b = 0.25 }, standard = { r = 1, g = 0.82, b = 0 } }
function GetQuestDifficultyColor(level)
    if level > WoW.playerLevel + 4 then return { r = 1, g = 0.1, b = 0.1 } end
    if level < WoW.playerLevel - 4 then return { r = 0.5, g = 0.5, b = 0.5 } end
    return QuestDifficultyColors.standard
end

-- HereBeDragons-2.0 + Pins as a recording fake (the vendored copy needs the
-- client's whole map system). It keeps the API our code calls:
-- Add{WorldMap,Minimap}Icon{World,Map}, RemoveAll{WorldMap,Minimap}Icons.
-- WoW.hbd.calls records each; WoW.hbdFail makes the adds return false.
function WoW.installFakeHBD()
    local stub = rawget(_G, "LibStub")
    if not stub or stub("HereBeDragons-Pins-2.0", true) then return end
    stub:NewLibrary("HereBeDragons-2.0", 35)
    local P = stub:NewLibrary("HereBeDragons-Pins-2.0", 17)
    WoW.hbd = { calls = {}, world = {}, mini = {} }
    local function add(display, kind)
        return function(self, ref, icon, ...)
            table.insert(WoW.hbd.calls, { display = display, kind = kind, ref = ref, icon = icon, args = { ... } })
            WoW.hbd[display][icon] = { ref = ref, kind = kind, args = { ... } }
            return not WoW.hbdFail
        end
    end
    P.AddWorldMapIconWorld, P.AddWorldMapIconMap = add("world", "World"), add("world", "Map")
    P.AddMinimapIconWorld, P.AddMinimapIconMap = add("mini", "World"), add("mini", "Map")
    function P:RemoveAllWorldMapIcons(ref)
        for icon, r in pairs(WoW.hbd.world) do if r.ref == ref then WoW.hbd.world[icon] = nil end end
    end
    function P:RemoveAllMinimapIcons(ref)
        for icon, r in pairs(WoW.hbd.mini) do if r.ref == ref then WoW.hbd.mini[icon] = nil end end
    end
end
function WoW.hbdCount(display)
    local n = 0
    for _ in pairs(WoW.hbd[display]) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- Spells and action slots, for the low spell ranks pearl (#12). In the 70532
-- dump: C_Spell.* / C_SpellBook.IsSpellKnown / C_ActionBar.* documented;
-- GetActionInfo, HasAction, PlaceAction, GetMacroSpell, GetMacroInfo,
-- IsPlayerSpell, IsTradeskillTrainer in its _G walk. NUM_ACTIONBAR_PAGES,
-- MultiActionBar_GetBarForPage and RANK are Blizzard's (ActionButtonUtil.lua:2,
-- MultiActionBars.lua:131, GlobalStrings).
--   WoW.actions[slot] = { kind = "spell" | "macro" | "item", id }
--   WoW.macros[id] = { name, spell }      WoW.known[spellID] = true
--   WoW.overrides[id] = otherID           WoW.spells[id] = { name, icon }
--   WoW.pages = { vehicle, override, temp, extra, multicast }  (pages)
--   WoW.multiBars[page] = true            stance bars: slots 73-120
-- Calls are recorded (PickupSpell, PlaceAction). WoW.pickupSpellFails: the
-- pickup does nothing; WoW.placeForbidden: PlaceAction raises
-- ADDON_ACTION_FORBIDDEN and does nothing; WoW.placeHook(slot): runs instead
-- of the swap when it returns true (a test's own outcome).
--------------------------------------------------------------------------------

WoW.actions, WoW.macros, WoW.known, WoW.overrides, WoW.spells = {}, {}, {}, {}, {}
WoW.pages = { vehicle = 16, temp = 17, override = 18, extra = 19, multicast = 11 }
WoW.multiBars = { [13] = true, [14] = true, [15] = true }
NUM_ACTIONBAR_PAGES = 6
RANK = "Rank"
function HasAction(slot) return WoW.actions[slot] ~= nil end
function GetActionInfo(slot)
    local a = WoW.actions[slot]
    if a then return a.kind, a.id, a.sub end
end
function GetMacroSpell(id) return WoW.macros[id] and WoW.macros[id].spell end
function GetMacroInfo(id)
    local m = WoW.macros[id]
    if m then return m.name, 134400, "" end
end
function IsPlayerSpell(id) return WoW.known[id] == true end
function IsTradeskillTrainer() return WoW.tradeTrainer == true end
function MultiActionBar_GetBarForPage(page) return WoW.multiBars[page] and {} or nil end
C_SpellBook = { IsSpellKnown = function(id) return WoW.known[id] == true end }
C_Spell = {
    GetSpellName = function(id) return (WoW.spells[id] and WoW.spells[id].name) or ("Spell" .. id) end,
    GetSpellTexture = function(id) return (WoW.spells[id] and WoW.spells[id].icon) or 136000 end,
    GetOverrideSpell = function(id) return WoW.overrides[id] or id end,
    PickupSpell = function(id)
        call("PickupSpell", id)
        if WoW.pickupSpellFails then return end
        WoW.cursor = { kind = "spell", id = id }
    end,
}
function PlaceAction(slot)
    call("PlaceAction", slot)
    if WoW.placeForbidden then
        WoW.fire("ADDON_ACTION_FORBIDDEN", "GlassPearls", "PlaceAction()")
        return
    end
    if WoW.placeHook and WoW.placeHook(slot) then return end
    local c = WoW.cursor
    if not c then return end
    local old = WoW.actions[slot]
    WoW.actions[slot] = { kind = c.kind or "item", id = c.id }
    WoW.cursor = old and { kind = old.kind, id = old.id } or nil
end
C_ActionBar = {
    GetVehicleBarIndex = function() return WoW.pages.vehicle end,
    GetOverrideBarIndex = function() return WoW.pages.override end,
    GetTempShapeshiftBarIndex = function() return WoW.pages.temp end,
    GetExtraBarIndex = function() return WoW.pages.extra end,
    GetMultiCastBarIndex = function() return WoW.pages.multicast end,
    GetBonusBarIndex = function() return WoW.bonusBar or 0 end,
    GetBonusBarIndexForSlot = function(slot)
        if slot >= 73 and slot <= 120 then return math.ceil((slot - 72) / 12) end
    end,
}
function Methods.SetSpellByID(t, id) t._lines = { "spell:" .. tostring(id) } end

--------------------------------------------------------------------------------
-- A merchant, for "Sell junk & repair" (#15). In the 70532 dump: GetMoney,
-- IsShiftKeyDown, IsInGuild, C_Item.CanBeRefunded / IsBound / GetItemGUID,
-- C_Container.UseContainerItem documented; GetNumBuybackItems,
-- GetBuybackItemLink, GetBuybackItemInfo, CanMerchantRepair, GetRepairAllCost,
-- RepairAllItems, CanGuildBankRepair, GetGuildInfoText in its _G walk.
-- ItemLocation:CreateFromBagAndSlot is Blizzard_ObjectAPI's; the buyback page
-- holds 12 (MerchantFrame.lua:2); GetBuybackItemInfo's 4th return is the
-- quantity (MerchantFrame.lua:556).
--   WoW.openMerchant({ repairs = true }) / WoW.closeMerchant()
--   WoW.money (copper); WoW.buyback = { { link, count } } (oldest first)
--   a bag stack's own fields: refundable, bound, guid
--   WoW.repairCost; WoW.guild = { member, mayRepair, info, allowance }
--   WoW.merchantRefuses = errorType: UseContainerItem raises that UI error
--     and sells nothing; WoW.salesAsync: a sale waits for WoW.applySales();
--     WoW.repairSilent: RepairAllItems does nothing
-- RepairAllItems(true) pays from the guild allowance and takes the rest from
-- the player when it can (Blizzard's guild repair tooltip, MerchantFrame.xml:345).
--------------------------------------------------------------------------------

WoW.money, WoW.buyback, WoW.repairCost, WoW.merchant = 0, {}, 0, nil
WoW.guild = { member = false, mayRepair = false, info = "", allowance = 0 }
WoW.pendingSales = {}
ERR_VENDOR_DOESNT_BUY = "The merchant doesn't want that item."
ERR_TOO_MUCH_GOLD = "You have too much gold."
WoW.errorNames[51] = "ERR_VENDOR_DOESNT_BUY"
WoW.errorNames[52] = "ERR_TOO_MUCH_GOLD"
function GetMoney() return WoW.money end
function IsShiftKeyDown() return WoW.shift == true end
function IsInGuild() return WoW.guild.member == true end
function CanGuildBankRepair() return WoW.guild.mayRepair == true end
function GetGuildInfoText() return WoW.guild.info end
ItemLocation = { CreateFromBagAndSlot = function(self, bag, slot) return { bag = bag, slot = slot } end }
local function stackAt(loc)
    local b = loc and WoW.bags[loc.bag]
    return b and b.items[loc.slot]
end
local guidCounter = 0
function C_Item.GetItemGUID(loc)
    local s = stackAt(loc)
    if not s then return nil end
    if not s.guid then guidCounter = guidCounter + 1; s.guid = "Item-0-" .. guidCounter end
    return s.guid
end
function C_Item.CanBeRefunded(loc) local s = stackAt(loc); return s ~= nil and s.refundable == true end
function C_Item.IsBound(loc) local s = stackAt(loc); return s ~= nil and s.bound == true end
function GetNumBuybackItems() return #WoW.buyback end
function GetBuybackItemLink(i) return WoW.buyback[i] and WoW.buyback[i].link end
function GetBuybackItemInfo(i)
    local e = WoW.buyback[i]
    if e then return "name", 134400, 1, e.count, -1, true, false end
end
function WoW.openMerchant(m)
    WoW.merchant = m or { repairs = true }
    WoW.fire("MERCHANT_SHOW")
end
function WoW.closeMerchant()
    WoW.merchant = nil
    WoW.fire("MERCHANT_CLOSED")
end
local function sell(bag, slot)
    local b = WoW.bags[bag]
    local s = b and b.items[slot]
    if not s then return end
    local it = WoW.items[s.id] or {}
    b.items[slot] = nil
    table.insert(WoW.buyback, { link = itemLink(s.id), count = s.count or 1 })
    if #WoW.buyback > 12 then table.remove(WoW.buyback, 1) end
    WoW.money = WoW.money + (it.price or 0) * (s.count or 1)
    WoW.fire("PLAYER_MONEY")
    WoW.fire("BAG_UPDATE_DELAYED")
end
function C_Container.UseContainerItem(bag, slot)
    call("UseContainerItem", bag, slot)
    if not WoW.merchant then return end
    if WoW.merchantRefuses then
        WoW.fire("UI_ERROR_MESSAGE", WoW.merchantRefuses, rawget(_G, WoW.errorNames[WoW.merchantRefuses]) or "?")
        return
    end
    if WoW.salesAsync then table.insert(WoW.pendingSales, { bag, slot }) else sell(bag, slot) end
end
function WoW.applySales()
    local pending = WoW.pendingSales
    WoW.pendingSales = {}
    for _, p in ipairs(pending) do sell(p[1], p[2]) end
end
function CanMerchantRepair() return WoW.merchant ~= nil and WoW.merchant.repairs == true end
function GetRepairAllCost() return WoW.repairCost, WoW.repairCost > 0 end
function RepairAllItems(guild)
    call("RepairAllItems", guild == true)
    if WoW.repairSilent or WoW.repairCost <= 0 then return end
    local cost = WoW.repairCost
    if guild then
        local paid = math.min(cost, WoW.guild.allowance)
        WoW.guild.allowance = WoW.guild.allowance - paid
        cost = cost - paid
    end
    if cost > 0 and WoW.money >= cost then
        WoW.money = WoW.money - cost
        cost = 0
        WoW.fire("PLAYER_MONEY")
    end
    WoW.repairCost = cost
    WoW.fire("UPDATE_INVENTORY_DURABILITY")
end

--------------------------------------------------------------------------------
-- The merchant's goods, for the restock pearl (#14). In the 70532 dump:
-- C_MerchantFrame.GetItemInfo (MerchantItemInfo, MerchantFrameDocumentation.lua:126)
-- and C_AddOns.IsAddOnLoaded documented; GetMerchantNumItems,
-- GetMerchantItemID, GetMerchantItemMaxStack, BuyMerchantItem and
-- GetInventoryItemID in its _G walk. ERR_NOT_ENOUGH_MONEY is Blizzard's
-- global string. Blizzard's "buy multiple" reads price per pack of
-- stackCount and buys in items (MerchantFrame.lua:713).
--   WoW.goods = { { id, price, pack, stock = -1, maxStack, purchasable,
--                   usable, extended, currencyID } }  (a field may be a WoW.Secret)
--   BuyMerchantItem(i, n): n items into the bags (partial stacks first, then
--     empty slots of a matching family, then general ones), price * n / pack
--     taken, PLAYER_MONEY and BAG_UPDATE_DELAYED. WoW.buysAsync: waits for
--     WoW.applyBuys(); WoW.buyRefuses = errorType: that UI error, nothing
--     bought; WoW.buyShort = k: k fewer items arrive. Calls in WoW.calls.
--   WoW.equipped[slot] = itemID; WoW.loadedAddOns[name] = true
--------------------------------------------------------------------------------

WoW.goods, WoW.equipped, WoW.loadedAddOns, WoW.pendingBuys = {}, {}, {}, {}
ERR_NOT_ENOUGH_MONEY = "You don't have enough money."
WoW.errorNames[53] = "ERR_NOT_ENOUGH_MONEY"
C_AddOns.IsAddOnLoaded = function(name)
    local loaded = WoW.loadedAddOns[name] == true
    return loaded, loaded
end
function GetInventoryItemID(unit, slot) if unit == "player" then return WoW.equipped[slot] end end
function GetMerchantNumItems() return WoW.merchant and #WoW.goods or 0 end
function GetMerchantItemID(i) local g = WoW.merchant and WoW.goods[i]; return g and g.id end
function GetMerchantItemMaxStack(i) local g = WoW.goods[i]; return g and (g.maxStack or 20) end
C_MerchantFrame = {}
function C_MerchantFrame.GetItemInfo(i)
    local g = WoW.merchant and WoW.goods[i]
    if not g then return nil end
    local function default(v, d) if v == nil then return d end return v end
    return { name = "item " .. g.id, texture = 134400, price = g.price, stackCount = g.pack or 1,
             numAvailable = g.stock or -1, isPurchasable = default(g.purchasable, true),
             isUsable = default(g.usable, true), hasExtendedCost = g.extended == true,
             currencyID = g.currencyID, isQuestStartItem = false }
end
local function receive(id, n)
    local it = WoW.items[id] or {}
    local max = it.maxStack or 20
    for bag = 0, 4 do
        local b = WoW.bags[bag]
        for _, st in pairs(b and b.items or {}) do
            if n > 0 and st.id == id and st.count < max then
                local k = math.min(n, max - st.count)
                st.count, n = st.count + k, n - k
            end
        end
    end
    for pass = 1, 2 do
        for bag = 0, 4 do
            local b = WoW.bags[bag]
            local fam = b and (b.family or 0) or 0
            local fits = b and ((pass == 1 and fam ~= 0 and it.family and bit.band(fam, it.family) ~= 0)
                or (pass == 2 and fam == 0))
            for slot = 1, fits and b.size or 0 do
                if n > 0 and not b.items[slot] then
                    local k = math.min(n, max)
                    b.items[slot], n = { id = id, count = k }, n - k
                end
            end
        end
    end
end
local function buy(i, n)
    local g = WoW.goods[i]
    receive(g.id, n - (WoW.buyShort or 0))
    WoW.money = WoW.money - g.price * n / (g.pack or 1)
    WoW.fire("PLAYER_MONEY")
    WoW.fire("BAG_UPDATE_DELAYED")
end
function BuyMerchantItem(i, n)
    n = n or ((WoW.goods[i] or {}).pack or 1)
    call("BuyMerchantItem", i, n)
    if not (WoW.merchant and WoW.goods[i]) then return end
    if WoW.buyRefuses then
        WoW.fire("UI_ERROR_MESSAGE", WoW.buyRefuses, rawget(_G, WoW.errorNames[WoW.buyRefuses]) or "?")
        return
    end
    if WoW.buysAsync then table.insert(WoW.pendingBuys, { i, n }) else buy(i, n) end
end
function WoW.applyBuys()
    local pending = WoW.pendingBuys
    WoW.pendingBuys = {}
    for _, b in ipairs(pending) do buy(b[1], b[2]) end
end

--------------------------------------------------------------------------------
-- Player auras and the client's aura sounds, for the fixate alert (#17). In
-- the 70532 dump: C_UnitAuras.GetPlayerAuraBySpellID / AddAuraSound /
-- RemoveAuraSound, C_Secrets.ShouldSpellAuraBeSecret / ShouldAurasBeSecret /
-- GetSpellAuraSecrecy, Frame:RegisterUnitEvent, PlaySound;
-- Enum.UnitAuraSoundTrigger (UnitAuraConstantsDocumentation.lua:6) and
-- UnitAuraSoundInfo (UnitConstantsDocumentation.lua:43) from Blizzard's docs.
--   WoW.auras[spellID] = { expirationTime, duration, icon } (or a WoW.Secret)
--   WoW.spellAuraSecret[spellID] = true | WoW.Secret(...)  (default plain false)
--   WoW.aurasRestricted: ShouldAurasBeSecret() is true
--   WoW.auraSoundRefused: AddAuraSound returns nothing; WoW.auraSounds lists
--   the registered ones { trigger, info }; WoW.soundsPlayed what PlaySound got
-- GetAuraDataBySpellName throws: a name lookup is never what these pearls use.
--------------------------------------------------------------------------------

WoW.auras, WoW.spellAuraSecret, WoW.auraSounds, WoW.soundsPlayed = {}, {}, {}, {}
Enum.UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 }
SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound(kit, channel) table.insert(WoW.soundsPlayed, { kit, channel }) return true end
local auraSoundID = 0
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id) return WoW.auras[id] end,
    GetAuraDataBySpellName = function() error("looked up by name", 2) end,
    AddAuraSound = function(trigger, info)
        if WoW.auraSoundRefused then return nil end
        auraSoundID = auraSoundID + 1
        WoW.auraSounds[auraSoundID] = { trigger = trigger, info = info }
        return auraSoundID
    end,
    RemoveAuraSound = function(id) WoW.auraSounds[id] = nil end,
}
C_Secrets = {
    ShouldAurasBeSecret = function() return WoW.aurasRestricted == true end,
    ShouldSpellAuraBeSecret = function(id)
        local v = WoW.spellAuraSecret[id]
        if v == nil then return false end
        return v
    end,
    GetSpellAuraSecrecy = function(id) return WoW.spellAuraSecret[id] == true and 2 or 0 end,
}
function Methods.RegisterUnitEvent(w, e, ...)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    w._units = w._units or {}
    w._units[e] = { ... }
    return true
end

--------------------------------------------------------------------------------
-- The character panel's stats, for "Uncrushable" (#19). In the 70532 dump:
-- UnitDefenseSkill, GetDodgeChance, GetParryChance, GetBlockChance,
-- GetCombatRatingBonus, C_PaperDollInfo.OffhandHasShield. Blizzard's Camelot
-- paper doll: CharacterStatsPaneScrollBox (CharacterFrame.xml:463),
-- PaperDollFrame_UpdateStats (PaperDollFrame.lua:2403), CR_DEFENSE_SKILL = 2
-- (PaperDollFrame.lua:5); MISS / STAT_DODGE / ... are GlobalStrings.
--   WoW.stats = { defense = { base, mod }, dodge, parry, block, shield, rating }
--------------------------------------------------------------------------------

WoW.stats = { defense = { 300, 0 }, dodge = 5, parry = 5, block = 5, shield = false, rating = 0 }
CR_DEFENSE_SKILL = 2
MISS, STAT_DODGE, STAT_PARRY, STAT_BLOCK, DEFENSE = "Miss", "Dodge", "Parry", "Block", "Defense"
function UnitDefenseSkill(unit) return WoW.stats.defense[1], WoW.stats.defense[2] end
function GetDodgeChance() return WoW.stats.dodge end
function GetParryChance() return WoW.stats.parry end
function GetBlockChance() return WoW.stats.block end
function GetCombatRatingBonus() return WoW.stats.rating end
C_PaperDollInfo = { OffhandHasShield = function() return WoW.stats.shield end }
CharacterStatsPaneScrollBox = newWidget("Frame", UIParent, "CharacterStatsPaneScrollBox")
CharacterStatsPaneScrollBox._shown = false
WoW.statsUpdates = 0
function PaperDollFrame_UpdateStats() WoW.statsUpdates = WoW.statsUpdates + 1 end
function Methods.AddDoubleLine(t, l, r) table.insert(t._lines, tostring(l) .. "|" .. tostring(r)) end

--------------------------------------------------------------------------------
-- Buff alerts (#21): Blizzard's proc overlay and other units' names. In the
-- 70532 dump: C_SpellActivationOverlay.IsSpellOverlayed,
-- SPELL_ACTIVATION_OVERLAY_SHOW(spellID, ...) / _HIDE(optional spellID).
--   WoW.overlayed[spellID] = true; WoW.unitNames[unit] = "name" (or a secret)
--------------------------------------------------------------------------------

WoW.overlayed, WoW.unitNames = {}, {}
C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return WoW.overlayed[id] == true end }
local playerUnitName = UnitName
function UnitName(unit)
    if WoW.unitNames[unit] ~= nil then return WoW.unitNames[unit] end
    return playerUnitName(unit)
end

--------------------------------------------------------------------------------
-- Training, for the training reminder (#27). In the 70532 dump: UnitRace,
-- C_SpellBook.IsSpellInSpellBook, C_ClassTalents.GetActiveConfigID,
-- C_Traits.GetConfigInfo / GetTreeCurrencyInfo,
-- C_SpecializationInfo.GetActiveSpecGroup documented; TooltipDataProcessor in
-- its _G walk (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199).
-- Enum.TooltipDataType.Spell = 1 and Enum.SpellBookSpellBank.Player = 0 are
-- Blizzard's (TooltipInfoSharedDocumentation.lua:97,
-- SpellBookConstantsDocumentation.lua:42).
--   WoW.player.raceID; WoW.knownSecret[id] = true: every known-spell read of
--   id answers a secret; WoW.talentPoints = n | nil (unreadable) | a secret;
--   WoW.specGroup = 1; WoW.tooltipPostCalls[type] = { fn, ... }
--------------------------------------------------------------------------------

WoW.player.raceID = 1
WoW.knownSecret, WoW.specGroup, WoW.tooltipPostCalls = {}, 1, {}
function UnitRace(unit) if unit == "player" then return "Human", "Human", WoW.player.raceID end end
local function knownRead(id, v)
    if WoW.knownSecret[id] then return WoW.Secret("known") end
    return v
end
local plainIsPlayerSpell = IsPlayerSpell
function IsPlayerSpell(id) return knownRead(id, plainIsPlayerSpell(id)) end
local plainIsSpellKnown = C_SpellBook.IsSpellKnown
C_SpellBook.IsSpellKnown = function(id) return knownRead(id, plainIsSpellKnown(id)) end
C_SpellBook.IsSpellInSpellBook = function(id) return knownRead(id, WoW.known[id] == true) end
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }
C_ClassTalents = { GetActiveConfigID = function() return 88388 end }
C_Traits = {
    GetConfigInfo = function(cfg) return { ID = cfg, type = 1, name = "Talents", treeIDs = { 1114 } } end,
    GetTreeCurrencyInfo = function(cfg, tree)
        if WoW.talentPoints == nil then return {} end
        return { { traitCurrencyID = 3820, quantity = WoW.talentPoints, spent = 0 } }
    end,
}
C_SpecializationInfo = { GetActiveSpecGroup = function() return WoW.specGroup end }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    WoW.tooltipPostCalls[kind] = WoW.tooltipPostCalls[kind] or {}
    table.insert(WoW.tooltipPostCalls[kind], fn)
end }
-- A spell tooltip as the client builds it: SetSpellByID, then the post calls.
function WoW.spellTooltip(id)
    GameTooltip:SetOwner(UIParent)
    GameTooltip:SetSpellByID(id)
    for _, fn in ipairs(WoW.tooltipPostCalls[Enum.TooltipDataType.Spell] or {}) do
        fn(GameTooltip, { type = Enum.TooltipDataType.Spell, id = id, lines = {} })
    end
    return table.concat(GameTooltip._lines, "\n")
end

--------------------------------------------------------------------------------
-- The raid mark wheel (#34). In the 70532 dump: UnitExists, UnitIsUnit,
-- CanBeRaidTarget, GetRaidTargetIndex, SetRaidTarget, IsInRaid,
-- UnitIsGroupLeader, UnitIsGroupAssistant, GetCursorPosition documented;
-- GetCVarBool, GetBindingKey in its _G walk; Menu (7 functions) in its
-- namespace list; Line:SetStartPoint / SetEndPoint / SetThickness,
-- Texture:SetRotation, Region:GetEffectiveScale / GetCenter,
-- Button:RegisterForClicks in its widget methods.
-- Blizzard's code, modelled: SecureActionButton_OnClick
-- (Blizzard_FrameXML/SecureTemplates.lua:802) and its raidtarget action
-- (:582); Menu.ModifyMenu (Blizzard_Menu/Menu.lua:2723), which calls a new
-- modifier at once, synchronously, with the description last generated for
-- the tag, open or not.
--   WoW.units[token] = { id = "A", guid = "Creature-1" | a secret, markable = false | a secret }
--     ("player" exists by default); WoW.unitIsUnitSecret: every UnitIsUnit answers a secret
--   WoW.marks[id] = 1..8; WoW.marksSecret: GetRaidTargetIndex answers a secret for a marked unit
--   WoW.raidCalls = { { token, index } } (from the secure action only);
--   WoW.forbidden: SetRaidTarget called from anything else (ADDON_ACTION_FORBIDDEN)
--   WoW.mouse = { x, y } (GetCursorPosition, pixels); WoW.uiScale (effective scale)
--   WoW.cvars[name] = true; WoW.group = { raid, leader, assistant }; WoW.bindings[action] = key
--   WoW.click(button, mouseButton, down, isKeyPress): PreClick, OnClick, PostClick
--   WoW.openMenu(which, contextData) -> the description; WoW.menuButton(d, text) -> its responder
--------------------------------------------------------------------------------

WoW.units, WoW.marks, WoW.raidCalls, WoW.forbidden = {}, {}, {}, {}
WoW.mouse, WoW.cvars, WoW.bindings = { x = 0, y = 0 }, {}, {}
WoW.group = { raid = false, leader = false, assistant = false }
WoW.menuModifiers, WoW.menuCache = {}, {}

local function unitOf(token)
    if WoW.units[token] then return WoW.units[token] end
    if token == "player" then return { id = "me", guid = WoW.playerGUID } end
end
function UnitExists(token) return unitOf(token) ~= nil end
function UnitIsUnit(a, b)
    if WoW.unitIsUnitSecret then return WoW.Secret("UnitIsUnit") end
    local ua, ub = unitOf(a), unitOf(b)
    return ua ~= nil and ub ~= nil and ua.id == ub.id
end
local playerOnlyGUID = UnitGUID
function UnitGUID(token)
    if WoW.units[token] then return WoW.units[token].guid end
    return playerOnlyGUID(token)
end
function CanBeRaidTarget(token)
    local u = unitOf(token)
    if not u then return false end
    if u.markable == nil then return true end
    return u.markable
end
function GetRaidTargetIndex(token)
    local u = unitOf(token)
    local m = u and WoW.marks[u.id]
    if m and WoW.marksSecret then return WoW.Secret("GetRaidTargetIndex") end
    return m
end
-- Protected (porting guide): only Blizzard's secure action may call it.
function SetRaidTarget(token, index)
    if not WoW.inSecureAction then
        table.insert(WoW.forbidden, "SetRaidTarget")
        WoW.fire("ADDON_ACTION_FORBIDDEN", "GlassPearls", "SetRaidTarget()")
        return
    end
    table.insert(WoW.raidCalls, { token, index })
    local u = unitOf(token)
    if u then WoW.marks[u.id] = (index ~= 0) and index or nil end
end
function IsInRaid() return WoW.group.raid == true end
function UnitIsGroupLeader(u) return u == "player" and WoW.group.leader == true end
function UnitIsGroupAssistant(u) return u == "player" and WoW.group.assistant == true end
function GetCursorPosition() return WoW.mouse.x, WoW.mouse.y end
function GetCVarBool(name) return WoW.cvars[name] == true end
function GetBindingKey(action) return WoW.bindings[action] end
function Methods.GetEffectiveScale(w) return WoW.uiScale or 1 end
function Methods.RegisterForClicks(b, ...) b._registeredClicks = { ... } end
function Methods.SetRotation(t, r) t._rotation = r end
function Methods.CreateLine(w) return addRegion(w, newWidget("Line", w)) end
function Methods.SetStartPoint(l, ...) l._start = { ... } end
function Methods.SetEndPoint(l, ...) l._end = { ... } end
-- A frame placed by SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y) is centred there.
function Methods.GetCenter(w)
    local p = w._points[#w._points]
    if p and p[1] == "CENTER" and p[2] == UIParent and p[3] == "BOTTOMLEFT" then return p[4], p[5] end
end

-- SecureActionButton_OnClick: exactly one edge acts. A real mouse press
-- (isKeyPress false, isSecureAction true) always acts on the release.
WoW.secureActions = {}
function WoW.secureActionClick(self, inputButton, down, isKeyPress, isSecureAction)
    local isSecureMousePress = not isKeyPress and isSecureAction
    local pressAndHold = self:GetAttribute("pressAndHoldAction")
    local useOnKeyDown = self:GetAttribute("useOnKeyDown")
    if useOnKeyDown == nil then useOnKeyDown = GetCVarBool("ActionButtonUseKeyDown") end
    useOnKeyDown = not isSecureMousePress and (useOnKeyDown or pressAndHold)
    local clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
    local release = (not down) and (pressAndHold or GetCVarBool("ActionButtonUseKeyHeldSpell"))
    local kind
    if clickAction then kind = self:GetAttribute("type")
    elseif release then kind = self:GetAttribute("typerelease") end
    if kind ~= nil then
        table.insert(WoW.secureActions, { kind = kind, down = down })
        WoW.secureAction(self, kind)
    end
    -- OnActionButtonClick (SecureTemplates.lua:772): after the action, on the
    -- acting edge, whatever the action was (none included), a spell awaiting
    -- an item takes the button's target-bag / target-slot.
    if clickAction and (SpellCanTargetItem() or SpellCanTargetItemID()) then
        local bag, slot = self:GetAttribute("target-bag"), self:GetAttribute("target-slot")
        if slot and bag then C_Container.UseContainerItem(bag, slot) end
    end
end

-- The secure actions modelled: raidtarget (SecureTemplates.lua:582) and
-- spell (:396, by ID).
function WoW.secureAction(self, kind)
    if kind == "spell" then
        WoW.inSecureAction = true
        CastSpellByID(tonumber(self:GetAttribute("spell")), self:GetAttribute("unit"))
        WoW.inSecureAction = false
        return
    end
    if kind ~= "raidtarget" then return end
    local unit = self:GetAttribute("unit") or "target"
    local marker = tonumber(self:GetAttribute("marker")) or 1
    local action = self:GetAttribute("action") or "toggle"
    WoW.inSecureAction = true
    if action == "clear" then
        SetRaidTarget(unit, 0)
    elseif action == "toggle" then
        if GetRaidTargetIndex(unit) == marker then SetRaidTarget(unit, 0) else SetRaidTarget(unit, marker) end
    elseif action == "set" then
        if GetRaidTargetIndex(unit) ~= marker then SetRaidTarget(unit, marker) end
    end
    WoW.inSecureAction = false
end

-- One edge of a click on a shown button: PreClick, OnClick, PostClick. A
-- mouse press by default; isKeyPress for a key bound to it.
function WoW.click(b, mouseButton, down, isKeyPress)
    if not Methods.IsVisible(b) then return false end
    local s = b._scripts
    if s.PreClick then s.PreClick(b, mouseButton, down) end
    if s.OnClick then s.OnClick(b, mouseButton, down, isKeyPress == true, isKeyPress ~= true) end
    if s.PostClick then s.PostClick(b, mouseButton, down) end
    return true
end

local function newDescription(owner, contextData)
    local d = { owner = owner, contextData = contextData, elements = {} }
    function d:CreateTitle(text) table.insert(self.elements, { kind = "title", text = text }) end
    function d:CreateDivider() table.insert(self.elements, { kind = "divider" }) end
    function d:CreateButton(text, fn)
        local e = { kind = "button", text = text, fn = fn }
        table.insert(self.elements, e)
        return e
    end
    return d
end
Menu = {
    ModifyMenu = function(tag, fn)
        local cached = WoW.menuCache[tag]
        if cached then fn(cached.owner, cached, cached.contextData) end
        WoW.menuModifiers[tag] = WoW.menuModifiers[tag] or {}
        local entry = { fn = fn }
        table.insert(WoW.menuModifiers[tag], entry)
        return { Unregister = function() entry.dead = true end }
    end,
}
-- Blizzard building a unit's menu (UnitPopupShared.lua:110): its title, then the modifiers.
function WoW.openMenu(which, contextData)
    local tag = "MENU_UNIT_" .. which
    local d = newDescription(UIParent, contextData)
    d:CreateTitle(which)
    WoW.menuCache[tag] = d
    for _, e in ipairs(WoW.menuModifiers[tag] or {}) do
        if not e.dead then e.fn(d.owner, d, contextData) end
    end
    return d
end
function WoW.menuButton(d, text)
    for _, e in ipairs(d.elements) do
        if e.kind == "button" and e.text == text then return e.fn end
    end
end

--------------------------------------------------------------------------------
-- Auto gossip (#47). In the 70532 dump: C_GossipInfo.GetOptions,
-- GetNumAvailableQuests, GetNumActiveQuests, ForceGossip, SelectOption,
-- SelectOptionByIndex documented; GetFileIDFromPath documented; GossipFrame
-- and ScrollUtil in its namespace list; the GOSSIP_* events. Blizzard's code,
-- modelled: GossipFrameSharedMixin:HandleShow's own lone pick
-- (Blizzard_UIPanels_Game/Shared/GossipFrameShared.lua:191), its option
-- buttons (GossipOptionButtonMixin: SetID(orderIndex), OnClick ->
-- SelectOptionByIndex(self:GetID()), :67-99) pooled in
-- GossipFrame.GreetingPanel.ScrollBox (Mainline/GossipFrame.xml:62), whose
-- frames carry GetElementData (ScrollBoxListView.lua:90) and which tells
-- ScrollUtil.AddInitializedFrameCallback's callbacks of each initialized
-- frame (ScrollUtil.lua:21); Enum.GossipOptionStatus and
-- Enum.PlayerInteractionType from Blizzard's generated docs.
--   WoW.openGossip{ options = { { id, index, status, icon, override, only, name, flags } },
--                   available, active, force, textureKit, npc = false, blizzardFirst, visible }
--     -> Blizzard's lone pick and frame, and GOSSIP_SHOW, in either order
--   WoW.refreshGossip(options), WoW.closeGossip(continuing), WoW.scrollGossip() (frames made later)
--   WoW.playerPicks(orderIndex): a click on that option's button (PreClick, OnClick, the select)
--   WoW.gossipSelects = { { fn, arg, text, confirmed } }; WoW.gossipOnSelect(fn, arg): runs inside a
--     select (synchronous events); WoW.gossipSelectThrows; WoW.fileIDs[path] = id
--------------------------------------------------------------------------------

WoW.gossip, WoW.gossipSelects, WoW.fileIDs = nil, {}, {}
Enum.GossipOptionStatus = { Available = 0, Unavailable = 1, Locked = 2, AlreadyComplete = 3 }
Enum.PlayerInteractionType = { None = 0, TradePartner = 1, Item = 2, Gossip = 3, QuestGiver = 4, Merchant = 5,
    TaxiNode = 6, Trainer = 7, Banker = 8, AlliedRaceDetailsGiver = 9, GuildBanker = 10, Registrar = 11, Vendor = 12,
    PetitionVendor = 13, GuildTabardVendor = 14, TalentMaster = 15, SpecializationMaster = 16, MailInfo = 17,
    SpiritHealer = 18, AreaSpiritHealer = 19, Binder = 20, Auctioneer = 21, StableMaster = 22, BattleMaster = 23 }
GOSSIP_BUTTON_TYPE_OPTION = 3
function GetFileIDFromPath(path) return WoW.fileIDs[path] end
function Methods.SetID(w, id) w._id = id end
function Methods.GetID(w) return w._id or 0 end
function Methods.GetLeft(w) return w._left end
function Methods.GetTop(w) return w._top end

local function gossipOptions()
    local g = WoW.gossip
    local out = {}
    for _, o in ipairs(g and g.options or {}) do
        out[#out + 1] = { gossipOptionID = o.id, orderIndex = o.index, status = o.status or 0, icon = o.icon,
            overrideIconID = o.override, selectOptionWhenOnlyOption = o.only == true, name = o.name, flags = o.flags or 0,
            rewards = {} }
    end
    return out
end
local function gossipSelect(fn, arg, text, confirmed)
    if WoW.gossipSelectThrows then error("select refused") end
    table.insert(WoW.gossipSelects, { fn = fn, arg = arg, text = text, confirmed = confirmed })
    if WoW.gossipOnSelect then WoW.gossipOnSelect(fn, arg) end
end
C_GossipInfo = {
    GetOptions = function() return WoW.gossipOptionsSecret and WoW.Secret("GetOptions") or gossipOptions() end,
    GetNumAvailableQuests = function() return WoW.gossip and WoW.gossip.available or 0 end,
    GetNumActiveQuests = function() return WoW.gossip and WoW.gossip.active or 0 end,
    ForceGossip = function() return WoW.gossip ~= nil and WoW.gossip.force == true end,
    SelectOption = function(id, text, confirmed) gossipSelect("SelectOption", id, text, confirmed) end,
    SelectOptionByIndex = function(index, text, confirmed) gossipSelect("SelectOptionByIndex", index, text, confirmed) end,
}

-- GossipFrame.GreetingPanel.ScrollBox: a pool of option buttons.
local scrollBox = newWidget("Frame", UIParent)
scrollBox._frames, scrollBox._callbacks = {}, {}
GossipFrame = newWidget("Frame", UIParent, "GossipFrame")
GossipFrame.GreetingPanel = newWidget("Frame", GossipFrame)
GossipFrame.GreetingPanel.ScrollBox = scrollBox
WoW.gossipScrollBox = scrollBox
function scrollBox:ForEachFrame(fn)
    for _, frame in ipairs(self._frames) do
        if frame._shown then
            local r = fn(frame, frame:GetElementData())
            if r then return r end
        end
    end
end
ScrollUtil = { AddInitializedFrameCallback = function(sb, callback, owner, iterateExisting)
    if iterateExisting then sb:ForEachFrame(callback) end
    table.insert(sb._callbacks, { fn = callback, owner = owner })
end }
-- Blizzard laying out a page's buttons: `count` of its options get a frame
-- (pooled), each initialized and told to the callbacks.
local function layout(count)
    local opts = WoW.gossip and WoW.gossip.options or {}
    for _, frame in ipairs(scrollBox._frames) do frame._shown = false end
    for i = 1, math.min(count, #opts) do
        local frame = scrollBox._frames[i]
        if not frame then
            frame = newWidget("Button", scrollBox)
            frame._scripts.OnClick = function(self) C_GossipInfo.SelectOptionByIndex(self:GetID()) end
            scrollBox._frames[i] = frame
        end
        local data = { buttonType = GOSSIP_BUTTON_TYPE_OPTION, info = opts[i] }
        frame.GetElementData = function() return data end
        frame:SetID(opts[i].index or 0)
        frame._shown = true
        for _, cb in ipairs(scrollBox._callbacks) do cb.fn(cb.owner, frame, data) end
    end
end
-- HandleShow: Blizzard's own lone pick, else the frame.
local function blizzardShow()
    local g = WoW.gossip
    local opts = g.options
    if (g.available or 0) == 0 and (g.active or 0) == 0 and #opts == 1 and not g.force and opts[1].only then
        C_GossipInfo.SelectOptionByIndex(opts[1].index)
        return
    end
    GossipFrame._shown = true
    layout(g.visible or #opts)
end
function WoW.openGossip(spec)
    WoW.gossip = spec
    spec.options = spec.options or {}
    if spec.npc ~= false then
        WoW.units.npc = WoW.units.npc or { id = "NPC", guid = "Creature-0-1-2-3-4567-0000ABCD" }
    else
        WoW.units.npc = nil
    end
    if spec.blizzardFirst then
        blizzardShow()
        WoW.fire("GOSSIP_SHOW", spec.textureKit)
    else
        WoW.fire("GOSSIP_SHOW", spec.textureKit)
        blizzardShow()
    end
end
function WoW.refreshGossip(options)
    WoW.gossip.options = options
    layout(#options)
    WoW.fire("GOSSIP_OPTIONS_REFRESHED")
end
function WoW.scrollGossip() layout(#(WoW.gossip and WoW.gossip.options or {})) end
function WoW.closeGossip(continuing)
    WoW.gossip = nil
    GossipFrame._shown = false
    for _, frame in ipairs(scrollBox._frames) do frame._shown = false end
    WoW.fire("GOSSIP_CLOSED", continuing)
end
-- A click on the shown button of option `orderIndex`.
function WoW.playerPicks(orderIndex)
    for _, frame in ipairs(scrollBox._frames) do
        if frame._shown and frame:GetID() == orderIndex then
            local s = frame._scripts
            if s.PreClick then s.PreClick(frame, "LeftButton", false) end
            s.OnClick(frame, "LeftButton", false)
            return true
        end
    end
    return false
end


--------------------------------------------------------------------------------
-- Faster loot (#36). In the 70532 dump: GetLootThreshold, IsInGroup,
-- IsModifiedClick (its _G walk), C_PartyInfo.GetLootMethod (documented,
-- three returns); Enum.LootMethod from LootConstantsDocumentation.lua:7.
--   WoW.group.party = true (IsInGroup); WoW.lootMethod (an Enum.LootMethod value, or a secret);
--   WoW.lootThreshold; WoW.modified[action] = true (IsModifiedClick)
--------------------------------------------------------------------------------

Enum.LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 }
WoW.lootMethod, WoW.lootThreshold, WoW.modified = 0, 2, {}
function IsInGroup() return WoW.group.party == true or WoW.group.raid == true end
function GetLootThreshold() return WoW.lootThreshold end
function IsModifiedClick(action) return WoW.modified[action] == true end
C_PartyInfo = C_PartyInfo or {}
function C_PartyInfo.GetLootMethod() return WoW.lootMethod, nil, nil end

--------------------------------------------------------------------------------
-- Low-rank buffs (#42). In the 70532 dump: UnitLevel, UnitClass,
-- UnitIsPlayer, UnitIsDeadOrGhost, IsInInstance, UnitInParty, UnitInRaid
-- (an index), UnitIsInMyGuild, C_FriendList.IsFriend(guid),
-- C_ChatInfo.SendChatMessage / InChatMessagingLockdown,
-- C_RestrictedActions.GetAddOnRestrictionState documented; GetUnitName in its
-- _G walk (UnitFrame.lua:1094: on Camelot the first name and the surname,
-- NameUtil.lua:4); Enum.AddOnRestrictionType / State from
-- RestrictedActionsConstantsDocumentation.lua:6-31.
--   WoW.unitLevels[unit], WoW.unitClasses[unit] = classFile, WoW.players[unit] = true
--   WoW.fullNames[unit] (GetUnitName); WoW.dead; WoW.inInstance
--   WoW.partyMembers[unit] = true, WoW.raidIndex[unit] = n, WoW.guildMembers[unit] = true,
--   WoW.friends[guid] = true
--   WoW.sentChat = { { msg, chatType, lang, target } }; WoW.chatSendThrows; WoW.chatLockdown;
--   WoW.chatRestriction (an Enum.AddOnRestrictionState value; default Inactive)
--   WoW.auraReads[spellID]: GetPlayerAuraBySpellID calls, counted per ID
-- Each value may be set to a WoW.Secret(...) to model a secret answer.
--------------------------------------------------------------------------------

WoW.unitLevels, WoW.unitClasses, WoW.players, WoW.fullNames = {}, {}, {}, {}
WoW.partyMembers, WoW.raidIndex, WoW.guildMembers, WoW.friends, WoW.sentChat = {}, {}, {}, {}, {}
WoW.auraReads = {}
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }

local playerAuraRead = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
    WoW.auraReads[id] = (WoW.auraReads[id] or 0) + 1
    return playerAuraRead(id)
end
local playerLevel = UnitLevel
function UnitLevel(unit)
    if WoW.unitLevels[unit] ~= nil then return WoW.unitLevels[unit] end
    return playerLevel(unit)
end
local playerClass = UnitClass
function UnitClass(unit)
    local c = WoW.unitClasses[unit]
    if c ~= nil then return "Class", c, 1 end
    return playerClass(unit)
end
function UnitIsPlayer(unit)
    if unit == "player" then return true end
    local v = WoW.players[unit]
    if v == nil then return false end
    return v
end
function GetUnitName(unit, showServer)
    local v = WoW.fullNames[unit]
    if v ~= nil then return v end
    return (UnitName(unit))
end
function UnitIsDeadOrGhost(unit) return unit == "player" and WoW.dead == true end
function IsInInstance()
    if WoW.inInstance == nil then return false, "none" end
    return WoW.inInstance, "party"
end
function UnitInParty(unit)
    local v = WoW.partyMembers[unit]
    if v == nil then return false end
    return v
end
function UnitInRaid(unit) return WoW.raidIndex[unit] end
function UnitIsInMyGuild(unit)
    local v = WoW.guildMembers[unit]
    if v == nil then return false end
    return v
end
C_FriendList = { IsFriend = function(guid)
    local v = WoW.friends[guid]
    if v == nil then return false end
    return v
end }
C_ChatInfo.SendChatMessage = function(msg, chatType, lang, target)
    if WoW.chatSendThrows then error("chat refused") end
    table.insert(WoW.sentChat, { msg = msg, chatType = chatType, lang = lang, target = target })
end
C_ChatInfo.InChatMessagingLockdown = function()
    if WoW.chatLockdown == nil then return false end
    return WoW.chatLockdown
end
C_RestrictedActions = { GetAddOnRestrictionState = function(kind)
    if kind ~= Enum.AddOnRestrictionType.Chat then return Enum.AddOnRestrictionState.Inactive end
    if WoW.chatRestriction == nil then return Enum.AddOnRestrictionState.Inactive end
    return WoW.chatRestriction
end }

--------------------------------------------------------------------------------
-- Instance gear reminders (#43). In the 70532 dump: GetInstanceInfo,
-- C_Reputation.GetFactionDataByID (a FactionData struct,
-- ReputationInfoDocumentation.lua:341: reaction 1-8), C_Item.GetItemCount
-- (carried and worn; includeBank adds the character bank,
-- ItemDocumentation.lua:451).
--   WoW.instance = { name, type, id }  (default: the continent outdoors, as
--     the client answers: "none", porting guide)
--   WoW.factions[id] = { name, reaction } (or a WoW.Secret)
--   WoW.itemCounts[id] = { bags = n, bank = n } (either may be a WoW.Secret;
--     the item worn in WoW.equipped counts too); WoW.itemCountThrows[id]
-- Each may be set to a WoW.Secret(...) to model a secret answer.
--------------------------------------------------------------------------------

WoW.factions, WoW.itemCounts, WoW.itemCountThrows = {}, {}, {}
function GetInstanceInfo()
    local i = WoW.instance or { name = "Eastern Kingdoms", type = "none", id = 0 }
    return i.name, i.type, 0, "", 5, 0, false, i.id, 5, nil, false
end
C_Reputation = { GetFactionDataByID = function(id)
    local f = WoW.factions[id]
    if type(f) ~= "table" then return f end
    return { factionID = id, name = f.name, description = "", reaction = f.reaction, currentStanding = 0,
        atWarWith = false, isHeader = false }
end }
function C_Item.GetItemCount(x, includeBank)
    local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
    if WoW.itemCountThrows[id] then error("item count refused") end
    local c = WoW.itemCounts[id] or {}
    local bags, bank = c.bags or 0, c.bank or 0
    if issecretvalue(bags) then return bags end
    if includeBank and issecretvalue(bank) then return bank end
    local n = bags
    for _, worn in pairs(WoW.equipped) do if worn == id then n = n + 1 end end
    if includeBank then n = n + bank end
    return n
end

--------------------------------------------------------------------------------
-- Hunter pet care (#38). In the 70532 dump: C_PetInfo.GetPetHappiness /
-- CanPetEatItem, UnitIsDead, UnitOnTaxi, IsMounted, UnitIsFeignDeath,
-- UnitIsPossessed, HasFullControl, C_Spell.IsSpellUsable,
-- C_Container.GetContainerItemID / UseContainerItem documented; HasPetUI,
-- GetPetActionInfo, SpellIsTargeting, SpellCanTargetItem(ID), CastSpellByID,
-- ContainerFrameCombinedBags in its _G walk. Blizzard's: PET_HAPPINESS1-3
-- (GlobalStrings, PetHappiness.lua:12), NUM_PET_ACTION_SLOTS
-- (PetActionBar.lua:1), ContainerFrameContainer and its ContainerFrames
-- (Mainline/ContainerFrame.xml:229-231), ContainerFrameMixin:UpdateItems
-- (:1191) over EnumerateValidItems (:575), ContainerFrameItemButtonMixin
-- :GetBagID (:1830).
--   WoW.pet = { dead, hunter (default true), happiness, level, guid, possessed } or nil
--     (no pet); any field may be a WoW.Secret; WoW.petExistsSecret
--   WoW.petBar[i] = { name, texture, isToken, isActive } (GetPetActionInfo);
--     WoW.petBarThrows
--   WoW.edible[itemID] = true | false | a secret (CanPetEatItem)
--   WoW.onTaxi, WoW.mounted, WoW.feign, WoW.fullControl (default true)
--   WoW.spellUsable[id] = false (C_Spell.IsSpellUsable; default usable)
--   WoW.spellTargeting = "item" | "unit" | nil: a spell awaiting its target
--   WoW.feedNoTarget: CastSpellByID(6991) doesn't enter item targeting
--   WoW.fed = { { bag, slot, id } }: UseContainerItem while targeting an item
--   WoW.containerFrames[i], ContainerFrameCombinedBags: Blizzard's bag frames;
--     WoW.showBag(frame, bag, size) fills and shows one and runs its UpdateItems
--------------------------------------------------------------------------------

WoW.petBar, WoW.edible, WoW.spellUsable, WoW.fed = {}, {}, {}, {}
PET_HAPPINESS1, PET_HAPPINESS2, PET_HAPPINESS3 = "Unhappy", "Content", "Happy"
NUM_PET_ACTION_SLOTS = 10

local unitExistsBefore = UnitExists
function UnitExists(token)
    if token == "pet" then
        if WoW.petExistsSecret then return WoW.Secret("UnitExists pet") end
        if WoW.pet then return true end
    end
    return unitExistsBefore(token)
end
function UnitIsDead(unit)
    if unit == "pet" then
        if not WoW.pet or WoW.pet.dead == nil then return false end
        return WoW.pet.dead
    end
    return unit == "player" and WoW.dead == true
end
local unitGUIDBefore = UnitGUID
function UnitGUID(token)
    if token == "pet" then return WoW.pet and WoW.pet.guid end
    return unitGUIDBefore(token)
end
local unitLevelBefore = UnitLevel
function UnitLevel(unit)
    if unit == "pet" then return WoW.pet and WoW.pet.level end
    return unitLevelBefore(unit)
end
function HasPetUI()
    if not WoW.pet then return false, false end
    if WoW.pet.hunter == nil then return true, true end
    return true, WoW.pet.hunter
end
C_PetInfo = {
    GetPetHappiness = function()
        if WoW.pet then return WoW.pet.happiness, 0, 0 end
    end,
    CanPetEatItem = function(id)
        local v = WoW.edible[id]
        if v == nil then return false end
        return v
    end,
}
function GetPetActionInfo(i)
    if WoW.petBarThrows then error("pet bar refused") end
    local s = WoW.petBar[i]
    if s then return s.name, s.texture, s.isToken, s.isActive, false, false, nil end
end
function UnitOnTaxi(unit) if unit ~= "player" or WoW.onTaxi == nil then return false end return WoW.onTaxi end
function IsMounted() if WoW.mounted == nil then return false end return WoW.mounted end
function UnitIsFeignDeath(unit) if unit ~= "player" or WoW.feign == nil then return false end return WoW.feign end
function UnitIsPossessed(unit)
    if unit == "pet" and WoW.pet and WoW.pet.possessed ~= nil then return WoW.pet.possessed end
    return false
end
function HasFullControl() if WoW.fullControl == nil then return true end return WoW.fullControl end
C_Spell.IsSpellUsable = function(id)
    local v = WoW.spellUsable[id]
    if v == nil then return true, false end
    return v, false
end
function SpellIsTargeting() return WoW.spellTargeting ~= nil end
function SpellCanTargetItem() return WoW.spellTargeting == "item" end
function SpellCanTargetItemID() return false end
-- Protected: only from a secure action. Feed Pet (6991) waits for an item.
function CastSpellByID(id, unit)
    call("CastSpellByID", id, unit)
    if not WoW.inSecureAction then
        table.insert(WoW.forbidden, "CastSpellByID")
        WoW.fire("ADDON_ACTION_FORBIDDEN", "GlassPearls", "CastSpellByID()")
        return
    end
    if WoW.spellUsable[id] == false then return end   -- the cast fails
    if id == 6991 and not WoW.feedNoTarget then WoW.spellTargeting = "item" end
end
function C_Container.GetContainerItemID(bag, slot)
    local b = WoW.bags[bag]
    local s = b and b.items[slot]
    return s and s.id
end
-- Using an item while a spell awaits one targets it; otherwise the
-- merchant's use (selling) above.
local useAtMerchant = C_Container.UseContainerItem
function C_Container.UseContainerItem(bag, slot)
    if WoW.spellTargeting ~= "item" then return useAtMerchant(bag, slot) end
    local b = WoW.bags[bag]
    local s = b and b.items[slot]
    call("UseContainerItem", bag, slot)
    table.insert(WoW.fed, { bag = bag, slot = slot, id = s and s.id })
    WoW.spellTargeting = nil
end

-- Blizzard's bag frames: buttons with GetBagID / GetID, a frame whose
-- UpdateItems walks its valid buttons (reading them, as Blizzard's does).
local function newBagButton(frame)
    local b = CreateFrame("Button", nil, frame)
    b.GetBagID = function(self) return self._bag end   -- the mixin's method
    return b
end
local function newBagFrame(name)
    local f = CreateFrame("Frame", name, UIParent)
    f._shown = false
    f.Items, f._size = {}, 0
    f.GetBagSize = function(self) return self._size end
    f.EnumerateValidItems = function(self)
        local i = 0
        return function()
            i = i + 1
            if i <= self._size then return i, self.Items[i] end
        end
    end
    f.UpdateItems = function(self)
        for _, b in self:EnumerateValidItems() do C_Container.GetContainerItemInfo(b:GetBagID(), b:GetID()) end
    end
    return f
end
ContainerFrameContainer = CreateFrame("Frame", "ContainerFrameContainer", UIParent)
ContainerFrameContainer.ContainerFrames = {}
for i = 1, 6 do ContainerFrameContainer.ContainerFrames[i] = newBagFrame("ContainerFrame" .. i) end
WoW.containerFrames = ContainerFrameContainer.ContainerFrames
ContainerFrameCombinedBags = newBagFrame("ContainerFrameCombinedBags")
-- Show `frame` holding `slots` ({ { bag, slot }, ... }, pooled buttons reused
-- in order), then run its UpdateItems as Blizzard does on open.
function WoW.showBag(frame, slots)
    for i, s in ipairs(slots) do
        local b = frame.Items[i] or newBagButton(frame)
        frame.Items[i] = b
        b._bag = s[1]
        b:SetID(s[2])
    end
    frame._size = #slots
    frame:Show()
    frame:UpdateItems()
end

--------------------------------------------------------------------------------
-- Social automation (#37). In the 70532 dump: C_SummonInfo.ConfirmSummon /
-- GetSummonConfirmTimeLeft / GetSummonConfirmAreaName, PlayerCanTeleport,
-- UnitAffectingCombat, AcceptResurrect, ResurrectGetOfferer,
-- ResurrectHasSickness, GetCorpseRecoveryDelay, C_GameRules.IsHardcoreActive,
-- C_BattleNet.GetAccountInfoByGUID documented; CancelDuel, AcceptGroup,
-- WillAcceptInviteRemoveQueues, IsGuildMember (SocialQueue.lua:204, with a
-- GUID) in its _G walk; StaticPopup_Visible is Blizzard's (StaticPopup.lua:179:
-- the dialog's name, or nil).
--   WoW.popups[which] = true: Blizzard's popup `which` is shown (WoW.popupThrows)
--   WoW.summon = { left, area }; WoW.canTeleport (default true); WoW.unitCombat[unit] = true
--   WoW.resOffer = { offerer, sickness, delay }; WoW.hardcore
--   WoW.bnetFriends[guid], WoW.guildGUIDs[guid] = true; WoW.queueRemoval
--   WoW.socialCalls = { "ConfirmSummon" | "AcceptResurrect" | "CancelDuel" | "AcceptGroup", ... }
-- Each value may be set to a WoW.Secret(...) to model a secret answer.
--------------------------------------------------------------------------------

WoW.popups, WoW.unitCombat, WoW.bnetFriends, WoW.guildGUIDs, WoW.socialCalls = {}, {}, {}, {}, {}
local function social(name) table.insert(WoW.socialCalls, name) end
function StaticPopup_Visible(which)
    if WoW.popupThrows then error("popup read refused") end
    local v = WoW.popups[which]
    if v == true then return "StaticPopup1", {} end
    if v ~= nil and v ~= false then return v end          -- a secret
    return nil
end
C_SummonInfo = {
    GetSummonConfirmTimeLeft = function() return WoW.summon and WoW.summon.left or 0 end,
    GetSummonConfirmAreaName = function() return WoW.summon and WoW.summon.area or "" end,
    ConfirmSummon = function() social("ConfirmSummon") end,
    CancelSummon = function() social("CancelSummon") end,
}
function PlayerCanTeleport()
    if WoW.canTeleport == nil then return true end
    return WoW.canTeleport
end
function UnitAffectingCombat(unit)
    local v = WoW.unitCombat[unit]
    if v == nil then return false end
    return v
end
function AcceptResurrect() social("AcceptResurrect") end
function ResurrectGetOfferer() return WoW.resOffer and WoW.resOffer.offerer or nil end
function ResurrectHasSickness()
    if not WoW.resOffer or WoW.resOffer.sickness == nil then return false end
    return WoW.resOffer.sickness
end
function GetCorpseRecoveryDelay() return WoW.resOffer and WoW.resOffer.delay or 0 end
C_GameRules = { IsHardcoreActive = function()
    if WoW.hardcore == nil then return false end
    return WoW.hardcore
end }
C_BattleNet.GetAccountInfoByGUID = function(guid)
    local v = WoW.bnetFriends[guid]
    if v == true then return { accountName = "Friend#1234", bnetAccountID = 1 } end
    return v
end
function IsGuildMember(guid)
    local v = WoW.guildGUIDs[guid]
    if v == nil then return false end
    return v
end
function CancelDuel() social("CancelDuel") end
function AcceptGroup() social("AcceptGroup") end
function WillAcceptInviteRemoveQueues()
    if WoW.queueRemoval == nil then return false end
    return WoW.queueRemoval
end

--------------------------------------------------------------------------------
-- Easy delete (#40). In the 70532 dump: DELETE_ITEM_CONFIRM(itemName,
-- qualityID, bonding, questWarn, itemGUID), C_Cursor.GetCursorItem,
-- C_Item.GetItemLinkByGUID documented. Blizzard's: StaticPopup_FindVisible
-- (StaticPopup.lua:156), the DELETE_GOOD_ITEM dialog's edit box and its
-- EditBoxOnTextChanged -> StaticPopup_StandardConfirmationTextHandler
-- (GameDialogDefs.lua:572, StaticPopup.lua:140), DELETE_ITEM_CONFIRM_STRING
-- (GlobalStrings), InputUtil.IsGamepadUIEnabled.
--   WoW.showDeleteDialog(which, guid) -> the dialog (its data and fields read-only: a
--     write is an error); dialog.editBox:GetText(); dialog.yes (Button1 enabled)
--   WoW.gamepad; WoW.itemLinks[guid] = "|cff...|h[...]|h|r" (GetItemLinkByGUID)
--------------------------------------------------------------------------------

DELETE_ITEM_CONFIRM_STRING = "DELETE"
WoW.dialogs, WoW.itemLinks = {}, {}
InputUtil = { IsGamepadUIEnabled = function()
    if WoW.gamepad == nil then return false end
    return WoW.gamepad
end }
C_Cursor = { GetCursorItem = function()
    local c = WoW.cursor
    if c and c.kind == nil and c.bag then return { bag = c.bag, slot = c.slot } end
    return nil
end }
C_Item.GetItemLinkByGUID = function(guid) return WoW.itemLinks[guid] end
local function readOnly(t, label)
    return setmetatable({}, { __index = t, __newindex = function(_, k) error(label .. ": wrote " .. tostring(k)) end })
end
function WoW.showDeleteDialog(which, guid)
    local state = { text = "", yes = false }
    local box = { GetText = function() return state.text end }
    function box:SetText(text)
        state.text = text
        state.yes = text == DELETE_ITEM_CONFIRM_STRING      -- Blizzard's confirmation handler
    end
    local d = { which = which, data = readOnly({ itemGUID = guid }, "dialog data") }
    function d:GetEditBox() return box end
    function d:GetButton1() return { IsEnabled = function() return state.yes end } end
    d.state = state
    WoW.dialogs[which] = readOnly(d, "dialog")
    return WoW.dialogs[which]
end
function StaticPopup_FindVisible(which)
    if WoW.popupThrows then error("popup read refused") end
    return WoW.dialogs[which]
end

--------------------------------------------------------------------------------
-- Quest loot sparkle (#44). In the 70532 dump: C_CVar.GetCVar(name) -> optional
-- string, C_CVar.SetCVar(name, value) -> success (nil on a failed precondition,
-- CVarDocumentation.lua), CVAR_UPDATE(eventName, value), GX_RESTARTED.
--   WoW.cvarValues[name] = "2" (nil: unknown to the client; a WoW.Secret)
--   WoW.cvarRefuse[name] = false | "nil" | "throw" | "throwRead"; WoW.cvarSets = { { name, value } };
--   WoW.cvarReads counts GetCVar calls
--   WoW.cvarEventsLater: CVAR_UPDATE queued in WoW.cvarQueue instead of fired inside SetCVar
--------------------------------------------------------------------------------

WoW.cvarValues, WoW.cvarRefuse, WoW.cvarSets, WoW.cvarQueue = {}, {}, {}, {}
C_CVar = C_CVar or {}
WoW.cvarReads = 0
C_CVar.GetCVar = function(name)
    WoW.cvarReads = WoW.cvarReads + 1
    if WoW.cvarRefuse[name] == "throwRead" then error("read refused") end
    return WoW.cvarValues[name]
end
C_CVar.SetCVar = function(name, value)
    local r = WoW.cvarRefuse[name]
    if r == "throw" then error("set refused") end
    if r == false then return false end
    if r == "nil" then return nil end
    WoW.cvarValues[name] = value
    table.insert(WoW.cvarSets, { name, value })
    if WoW.cvarEventsLater then
        table.insert(WoW.cvarQueue, { name, value })
    else
        WoW.fire("CVAR_UPDATE", name, value)
    end
    return true
end

--------------------------------------------------------------------------------
-- Trade summary (#45). In the 70532 dump: TRADE_SHOW / _UPDATE / _MONEY_CHANGED /
-- _PLAYER_ITEM_CHANGED / _TARGET_ITEM_CHANGED / _ACCEPT_UPDATE / _CLOSED,
-- UI_INFO_MESSAGE(errorType, message), PLAYER_MONEY; GetPlayerTradeMoney,
-- GetTargetTradeMoney, GetTradePlayerItemInfo / Link, GetTradeTargetItemInfo /
-- Link in its _G walk (TradeFrame.lua:100: name, texture, numItems, ...).
-- ERR_TRADE_COMPLETE is GlobalStrings'; its message index is ours (WoW.TRADE_COMPLETE).
--   WoW.trade = { mine = { money, items = { [slot] = { link, count } | "secret" } }, theirs = { ... } };
--   the partner is GetUnitName("NPC") (WoW.fullNames.NPC)
--------------------------------------------------------------------------------

ERR_TRADE_COMPLETE = "Trade complete."
WoW.TRADE_COMPLETE = 230
WoW.errorNames[WoW.TRADE_COMPLETE] = "ERR_TRADE_COMPLETE"
local function tradeSide(which) return WoW.trade and WoW.trade[which] or { items = {} } end
local function tradeItem(which, i)
    local it = tradeSide(which).items[i]
    if it == "secret" then return WoW.Secret("trade item"), nil, WoW.Secret("count") end
    if it then return "Item", 134400, it.count == "secret" and WoW.Secret("count") or it.count end
    return nil
end
local function tradeLink(which, i)
    local it = tradeSide(which).items[i]
    return type(it) == "table" and it.link or nil
end
function GetTradePlayerItemInfo(i) return tradeItem("mine", i) end
function GetTradeTargetItemInfo(i) return tradeItem("theirs", i) end
function GetTradePlayerItemLink(i) return tradeLink("mine", i) end
function GetTradeTargetItemLink(i) return tradeLink("theirs", i) end
function GetPlayerTradeMoney() return tradeSide("mine").money or 0 end
function GetTargetTradeMoney() return tradeSide("theirs").money or 0 end

function WoW.calledCount(name)
    local n = 0
    for _, c in ipairs(WoW.calls) do if c[1] == name then n = n + 1 end end
    return n
end

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
