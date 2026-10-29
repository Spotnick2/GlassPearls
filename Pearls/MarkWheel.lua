-- Pearls/MarkWheel.lua: the raid mark wheel (#34). A wheel of the eight raid
-- marks at the cursor, for the unit under it (a key binding) or the unit of a
-- right-click menu (an entry added to Blizzard's unit menus). Out of combat
-- only. Its art, animations and panel are Pearls/MarkWheelFrame.lua.
--
-- Pings are not here: the client's own ping system (Blizzard_PingUI, its Ping
-- key and wheel) is the only thing that can ping a world spot correctly.
--
-- The mark itself is set by Blizzard's secure "raidtarget" action
-- (SecureTemplates.lua:582), never by our code (SetRaidTarget is protected).
-- One SecureActionButtonTemplate button covers the disc and is disarmed
-- (type nil) whenever no click is in progress. It acts on the release only
-- (useOnKeyDown false; both edges registered, porting guide "Register secure
-- buttons for BOTH mouse edges"): the down edge does nothing; the up edge's
-- insecure PreClick checks everything again and arms it, type last; the
-- template's OnClick acts; PostClick closes, which disarms. No snippets, state
-- drivers or override bindings.
--
-- Which unit: a session { token, guid, epoch } captured when the wheel is
-- asked for. The key resolves the mouseover at once to a token that survives
-- the cursor moving (UnitIsUnit over target, player, focus, group, pets,
-- nameplates); a menu gives its own token when the menu is built. A session
-- holds while one epoch is unchanged (bumped by every event that can move a
-- unit into another token, and by switching the pearl on or off) and, when
-- the GUID was plain at capture, while it still reads the same.
-- Unmeasured until 2026-11-04: all of it (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local M = {}
GP.MarkWheel = M

M.KEY = "markwheel"
M.NAME = "Raid mark wheel"
M.BINDING = "GLASSPEARLS_MARKWHEEL"
M.BUTTON = "GlassPearlsMarkWheelButton"
-- The mark on each of the art's eight segments. Blizzard's segment g sits at
-- (g-1)*45 degrees, counterclockwise from east (GamepadRadial.lua:1113):
-- skull at the top, then clockwise star, circle, diamond, triangle, moon,
-- square, cross.
M.MARKERS = { 2, 1, 8, 7, 6, 5, 4, 3 }
M.R_CLEAR = 44       -- the centre ring: Clear
M.R_OUTER = 160      -- the disc; beyond it is "outside"
-- The unit menus that carry Blizzard's own Raid Target Icon entry on this
-- client (Blizzard_UnitPopupShared/UnitPopupSharedMenus.lua with the Camelot
-- overrides, Blizzard_UnitPopup/Camelot/UnitPopupMenus.lua). Not
-- ENEMY_PLAYER (Camelot's lacks it); not VEHICLE or BOSS, whose tokens no
-- session can validate.
M.MENUS = { "SELF", "PET", "OTHERPET", "PARTY", "PLAYER", "RAID_PLAYER", "TARGET", "FOCUS" }

-- Tokens a session may hold: each has an event that tells when another unit
-- can take it.
local FAMILIES = { "^target$", "^player$", "^focus$", "^pet$", "^party[1-4]$", "^partypet[1-4]$",
    "^raid%d+$", "^raidpet%d+$", "^nameplate%d+$" }
-- The mouseover is matched against these, in this order.
M.TOKENS = { "target", "player", "focus" }
for i = 1, 4 do M.TOKENS[#M.TOKENS + 1] = "party" .. i end
for i = 1, 40 do M.TOKENS[#M.TOKENS + 1] = "raid" .. i end
M.TOKENS[#M.TOKENS + 1] = "pet"
for i = 1, 4 do M.TOKENS[#M.TOKENS + 1] = "partypet" .. i end
for i = 1, 40 do M.TOKENS[#M.TOKENS + 1] = "raidpet" .. i end
for i = 1, 40 do M.TOKENS[#M.TOKENS + 1] = "nameplate" .. i end

-- Events after which a token may hold another unit: each bumps the epoch.
M.STALE_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET", "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD" }

BINDING_NAME_GLASSPEARLS_MARKWHEEL = M.NAME

local state = {
    session = nil,      -- the open wheel's
    epoch = 0,
    down = false,       -- the down edge of a click on our button was seen while open
    armed = nil,        -- 0 (Clear) or a marker, between PreClick and PostClick
    pendingCleanup = false,
    last = "nothing yet",
}
M.state = state

local events = CreateFrame("Frame")
local button, guard    -- built on first open
local registering, menusRegistered = false, false

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(M.KEY, name) end
local function Frame() return GP.MarkWheelFrame end

-- One client read: its value, or nil when it threw or is secret.
local function ask(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

function M.Supported(token)
    if type(token) ~= "string" then return false end
    for _, pattern in ipairs(FAMILIES) do
        if token:match(pattern) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Sessions

-- The token that is the mouseover now, or nil (nothing there, or no token
-- the client says is it).
function M.Resolve(unit)
    unit = unit or "mouseover"
    if ask(UnitExists, unit) ~= true then return nil end
    for _, token in ipairs(M.TOKENS) do
        if ask(UnitExists, token) == true and ask(UnitIsUnit, unit, token) == true then return token end
    end
end

-- A session on `token`, or nil and why not.
function M.Capture(token)
    if API.IsSecret(token) or not M.Supported(token) then return nil, "unsupported" end
    if ask(UnitExists, token) ~= true then return nil, "gone" end
    local guid
    local ok, g = pcall(UnitGUID, token)
    if ok and not API.IsSecret(g) and type(g) == "string" then guid = g end
    return { token = token, guid = guid, epoch = state.epoch }
end

-- Is it still the unit it was captured on?
function M.Valid(s)
    if type(s) ~= "table" or s.epoch ~= state.epoch then return false end
    if ask(UnitExists, s.token) ~= true then return false end
    if s.guid then
        -- Plain at capture: it must read the same, plainly, now.
        local ok, g = pcall(UnitGUID, s.token)
        if not ok or API.IsSecret(g) or g ~= s.guid then return false end
    end
    return true
end

local function bump()
    state.epoch = state.epoch + 1
    if state.session then M.Close("stale") end
end

--------------------------------------------------------------------------------
-- Geometry (pure)

-- An offset from the wheel's centre, in UI units: 0 (Clear), the art's
-- segment 1..8, or "outside". Blizzard's segment math, GamepadRadial.lua:1017.
function M.Segment(dx, dy)
    local r2 = dx * dx + dy * dy
    if r2 <= M.R_CLEAR * M.R_CLEAR then return 0 end
    if r2 > M.R_OUTER * M.R_OUTER then return "outside" end
    local degrees = math.deg(math.atan2(dy, dx))
    if degrees < -22.5 then degrees = degrees + 360 end
    return math.floor((degrees + 45) / 45 + 0.5)
end

-- The same offset as a choice: 0 (Clear), a marker 1..8, or "outside".
function M.Choice(dx, dy)
    local g = M.Segment(dx, dy)
    if g == 0 or g == "outside" then return g end
    return M.MARKERS[g]
end

-- The cursor in UI units, or nil.
local function cursor(scale)
    local ok, x, y = pcall(GetCursorPosition)
    if not ok or API.IsSecret(x) or API.IsSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
    scale = scale or UIParent:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return x / scale, y / scale
end

-- The cursor's offset from the open wheel's actual centre, or nil.
function M.Offset()
    if not (button and state.center) then return nil end
    local cx, cy = button:GetCenter()
    if type(cx) ~= "number" or type(cy) ~= "number" then cx, cy = state.center[1], state.center[2] end
    local x, y = cursor(button:GetEffectiveScale())
    if not x then return nil end
    return x - cx, y - cy
end

--------------------------------------------------------------------------------
-- The secure button

-- Both edges reach PreClick and PostClick; only the release acts.
local function preClick(self, mouseButton, down)
    state.armed = nil
    if down then
        if state.session then state.down = true end
        return
    end
    -- An up with no down of ours (the click that opened us from a menu): nothing.
    if not state.down or InCombatLockdown() then return end
    local s = state.session
    if mouseButton ~= "LeftButton" or not (M.enabled and s and M.Valid(s)) then return end
    local dx, dy = M.Offset()
    local choice = dx and M.Choice(dx, dy)
    if choice == nil or choice == "outside" then return end
    self:SetAttribute("unit", s.token)
    if choice == 0 then
        self:SetAttribute("action", "clear")
        self:SetAttribute("marker", nil)
    else
        self:SetAttribute("action", "toggle")
        self:SetAttribute("marker", choice)
    end
    self:SetAttribute("type", "raidtarget")    -- last: armed only now
    state.armed = choice
end

local function postClick(self, mouseButton, down)
    if down or not state.down then return end
    local choice = state.armed
    state.armed = nil
    if choice == 0 then state.last = "cleared the mark"
    elseif choice then state.last = "chose mark " .. choice end
    M.Close(choice and "chosen" or "cancel")   -- disarms (or, locked, leaves it for later)
end

local function build()
    button = CreateFrame("Button", M.BUTTON, UIParent, "SecureActionButtonTemplate")
    button:SetSize(M.R_OUTER * 2, M.R_OUTER * 2)
    button:SetFrameStrata("FULLSCREEN_DIALOG")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", preClick)
    button:SetScript("PostClick", postClick)
    button:Hide()
    -- A cleanup lockdown refused is done when combat ends, on or off.
    guard = CreateFrame("Frame")
    API.RegisterEvents(guard, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    guard:SetScript("OnEvent", function(_, event)
        API.NoteCombat(event)
        if event == "PLAYER_REGEN_ENABLED" and state.pendingCleanup and not InCombatLockdown() then
            state.pendingCleanup = false
            button:SetAttribute("type", nil)
            if not state.session then button:Hide() end
        end
    end)
end

--------------------------------------------------------------------------------
-- Opening and closing

-- May a wheel open on session `s`? true, or false and why.
function M.Gate(s)
    if API.InCombat() then return false, "Not in combat: marks from the wheel wait until combat ends." end
    if not M.enabled then return false, "The raid mark wheel is off: /gpearls markwheel on." end
    if not M.Valid(s) then return false, "That unit is gone or changed." end
    if ask(IsInRaid) == true and ask(UnitIsGroupLeader, "player") ~= true
        and ask(UnitIsGroupAssistant, "player") ~= true then
        return false, "In a raid, only the leader or an assistant can set marks."
    end
    if ask(CanBeRaidTarget, s.token) == false then return false, "That unit can't be marked." end
    return true
end

function M.IsOpen() return state.session ~= nil end

-- Open the wheel on session `s` at the cursor. Every route comes here.
function M.Open(s)
    local ok, why = M.Gate(s)
    if not ok then
        state.last = why
        say(why)
        return false
    end
    if not button then build() end
    local x, y = cursor()
    if not x then
        state.last = "the cursor can't be read"
        return false
    end
    -- Whole on screen, when the screen's size is known.
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local r = M.R_OUTER
    if type(w) == "number" and w > 2 * r then x = math.min(math.max(x, r), w - r) end
    if type(h) == "number" and h > 2 * r then y = math.min(math.max(y, r), h - r) end
    state.session, state.down, state.armed = s, false, nil
    state.center = { x, y }
    button:SetAttribute("type", nil)
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    button:Show()
    API.RegisterEvents(events, { "GLOBAL_MOUSE_DOWN" })
    Frame().Open(x, y, s)
    state.last = "opened on " .. s.token
    return true
end

-- Close the wheel, whatever closed it. Idempotent.
function M.Close(reason)
    if not state.session then return end
    state.session, state.down, state.armed = nil, false, nil
    events:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    if button then
        if InCombatLockdown() then
            state.pendingCleanup = true
        else
            button:SetAttribute("type", nil)
            button:Hide()
        end
    end
    if reason ~= "chosen" and reason ~= "cancel" then state.last = "closed (" .. tostring(reason) .. ")" end
    Frame().Close()
end

-- The art was hidden (Esc): the wheel ends with it.
function M.OnArtHidden()
    if state.session then M.Close("esc") end
end

-- The key binding (Bindings.xml).
function M.OnKey()
    if state.session then return M.Close("key") end
    if not M.enabled then return say("The raid mark wheel is off: /gpearls markwheel on.") end
    if API.InCombat() then return say("Not in combat: marks from the wheel wait until combat ends.") end
    local token = M.Resolve("mouseover")
    if not token then
        if ask(UnitExists, "mouseover") == true then
            state.last = "no token for the mouseover"
            return say("That unit can't be followed: target it, or show its nameplate.")
        end
        state.last = "nothing under the cursor"
        return say("Point at a unit, then press the key.")
    end
    M.Open(M.Capture(token))
end

function M.Test() return M.Open(M.Capture("player")) end

--------------------------------------------------------------------------------
-- Blizzard's unit menus

-- A menu being built (or, at our registration, one built before: ignored).
local function onMenu(_, root, contextData)
    if registering or not (M.enabled and setting("menu")) or API.InCombat() then return end
    local unit = type(contextData) == "table" and contextData.unit
    if API.IsSecret(unit) or type(unit) ~= "string" or unit:match("^nameplate") then return end
    local s = M.Capture(unit)
    if not s then return end
    root:CreateDivider()
    root:CreateButton(M.NAME, function()
        if not setting("menu") then state.last = "the menu entry is off"; return end
        M.Open(s)
    end)
end
M.OnMenu = onMenu

-- Once, the first time the pearl is on; kept (the callback checks).
local function registerMenus()
    if menusRegistered then return end
    menusRegistered = true
    if not (Menu and Menu.ModifyMenu) then return API.Fail("pearl markwheel menu", "Menu.ModifyMenu missing") end
    registering = true
    for _, which in ipairs(M.MENUS) do
        local ok, err = pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, onMenu)
        if not ok then API.Fail("pearl markwheel menu " .. which, err) end
    end
    registering = false
end

--------------------------------------------------------------------------------
-- Commands

function M.BindingText()
    local ok, key = pcall(GetBindingKey, M.BINDING)
    if ok and not API.IsSecret(key) and type(key) == "string" and key ~= "" then return key end
end

function M.Report()
    local key = M.BindingText()
    say(M.NAME .. ": " .. (M.enabled and "on" or "off") .. "; key " .. (key or "not bound (Key Bindings > Glass Pearls)")
        .. "; unit menu entry " .. (setting("menu") and "on" or "off") .. ".")
    if ask(IsInRaid) == true then
        local lead = ask(UnitIsGroupLeader, "player") == true or ask(UnitIsGroupAssistant, "player") == true
        say("  In a raid: " .. (lead and "you may set marks." or "only the leader or an assistant may set marks."))
    end
    say("  Last: " .. state.last .. ".")
end

local function command(arg)
    if arg == "test" then return M.Test() end
    M.Report()
end

--------------------------------------------------------------------------------
-- The pearl

events:SetScript("OnEvent", function(_, event, arg1)
    API.NoteCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Lockdown hasn't started inside this event: the button can still be hidden.
        M.Close("combat")
    elseif event == "GLOBAL_MOUSE_DOWN" then
        local dx, dy = M.Offset()
        if dx and M.Segment(dx, dy) == "outside" then M.Close("outside") end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- Only the open wheel's plate matters (a menu never holds a plate's token).
        local s = state.session
        if s and (API.IsSecret(arg1) or type(arg1) ~= "string" or arg1 == s.token) then bump() end
    elseif event ~= "PLAYER_REGEN_ENABLED" then
        bump()
    end
end)

local function enable()
    M.enabled = true
    API.RegisterEvents(events, M.STALE_EVENTS)
    API.RegisterEvents(events, { "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    registerMenus()
end

local function disable()
    M.enabled = false
    -- Nothing is watched while off: a responder kept until it's back on is dead.
    state.epoch = state.epoch + 1
    M.Close("off")
    events:UnregisterAllEvents()
end

GP.Pearls.Register({
    key = M.KEY,
    name = M.NAME,
    desc = "A wheel of the eight raid marks at your cursor, from a key or a unit's right-click menu.",
    help = "Bind a key in Esc > Options > Key Bindings > Glass Pearls, point at a unit (in the world, on its "
        .. "nameplate or on a group frame) and press it: a wheel of the eight raid marks opens at your cursor. "
        .. "Click a mark to set it (the same mark again removes it), the centre to clear it, outside the wheel or "
        .. "Esc to close it. The unit's right-click menu has a Raid mark wheel entry too. Out of combat only; in a "
        .. "raid, only the leader or an assistant can set marks. Pings are the game's own: its Ping key in "
        .. "Key Bindings. Unverified until the game is live.",
    default = true,
    category = "Social",
    section = "Group",
    defaults = { menu = true },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.MarkWheelFrame.Configure(panel, refreshers) end,
    commands = { markwheel = { help = "[test] - the raid mark wheel's key and state, or open it on yourself",
        run = command } },
})

M._test = {
    events = events,
    button = function() return button end,
    guard = function() return guard end,
    preClick = preClick,
    postClick = postClick,
}
