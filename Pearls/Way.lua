-- Pearls/Way.lua: waypoint routes (#139). Paste `/way` lines, get a route of
-- steps; the shared compass (Core/Compass.lua, owner "way", above the books)
-- points at the current one, the step list (Pearls/WayFrame.lua) shows each
-- step's direction and distance, numbered pins mark them on the world map and
-- the minimap. Previous / Next at will; within NEAR yards of the current step
-- it is done and the next one is current, by itself.
--
-- Parsing (`W.Parse`, pure but for the client's map names): a line is an
-- optional leading `/word`, then `x y [desc]` (the player's zone, read once
-- per paste), `#mapID x y [desc]` (that map, never climbed) or `zone name x y
-- [desc]` (the client's own, localized names of the zone maps and the two
-- continents; exact, else one unique substring). `66 34`, `66.2 34.5`,
-- `66,2 34,5`, `66.2, 34.5`. A widely used waypoint add-on is the behaviour
-- reference for this syntax (All Rights Reserved: behaviour only).
--
-- The route (GlassPearlsCharDB.way = { steps = { { map, x, y, desc, done } },
-- current, closed }, never synced): `current` is 1..#steps, or #steps + 1
-- when complete. A paste replaces it (one with no valid step leaves it as it
-- was); one `/way` appends a step. A step chosen by hand (Previous, Next, a
-- row) is current, done or not, and **disarmed**: it can't be reached until a
-- plain reading puts the player more than NEAR from it. A step that can't be
-- placed on this build ("no position") is skipped by the route's own advance,
-- never marked done; chosen by hand it stays.
--
-- Progress belongs to the controller alone (a TICK ticker while there's a
-- current step and the pearl is on): eligibility first (not dead, not on a
-- taxi, not in an instance: each read plainly false), then the position; one
-- advance per tick at most. The ring never advances a route. Shown in combat
-- (position and facing read plain outdoors in combat, measured).
--
-- `/way`: claimed once a session, a frame after the registry's Start (or a
-- later switch-on), only while no add-on owns it (Blizzard's hash and every
-- SLASH_* global). Unmeasured until checked in game.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local W = {}
GP.Way = W

W.KEY = "way"
W.OWNER = "way"
W.MAX_STEPS = 100
W.NEAR = 10
W.MAX_BYTES = 20000
W.MAX_LINES = 200
W.DESC_MAX = 60
W.REPORT_MAX = 5
W.TICK = 0.5
W.CLIMB_MAX = 5
W.CONTINENTS = { 1414, 1415 }   -- Kalimdor, the Eastern Kingdoms
W.ZONE_TYPE = 3                 -- Enum.UIMapType.Zone

local state = {
    pos = {},          -- [i] = { c, north, west } | false: the steps' world positions
    armed = true,
    started = false,   -- the registry's Start ran
    claimed = false,   -- /way is ours this session
    ticker = nil,
}
W.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(W.KEY, name) end
local function Frame() return GP.WayFrame end

local function finite(v)
    if API.IsSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function lib(name)
    local stub = rawget(_G, "LibStub")
    return stub and stub(name, true)
end

--------------------------------------------------------------------------------
-- Maps

local function mapInfo(id)
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if not ok or API.IsSecret(info) or type(info) ~= "table" then return nil end
    return info
end

local function mapName(id)
    local info = mapInfo(id)
    local n = info and info.name
    if n ~= nil and not API.IsSecret(n) and type(n) == "string" and n ~= "" then return n end
end

function W.ZoneName(id) return mapName(id) or ("Map " .. tostring(id)) end

-- A map's coordinates (0-100) to the world: continent, north, west; nil when HereBeDragons can't.
function W.World(map, x, y)
    local HBD = lib("HereBeDragons-2.0")
    if not (HBD and HBD.GetWorldCoordinatesFromZone) then return nil end
    local ok, west, north, c = pcall(HBD.GetWorldCoordinatesFromZone, HBD, x / 100, y / 100, map)
    if not ok then return nil end
    west, north, c = finite(west), finite(north), finite(c)
    if not (west and north and c) then return nil end
    return c, north, west
end

local function zoneType()
    local E = rawget(_G, "Enum")
    local t = E and E.UIMapType
    return type(t) == "table" and finite(t.Zone) or W.ZONE_TYPE
end

-- The player's zone map for bare coordinates: HereBeDragons' map, climbed
-- from a dungeon, micro or orphan map to its zone; nil when it can't be told.
function W.Here()
    local HBD = lib("HereBeDragons-2.0")
    if not (HBD and HBD.GetPlayerZone) then return nil end
    local ok, id, kind = pcall(HBD.GetPlayerZone, HBD)
    if not ok then return nil end
    id, kind = finite(id), finite(kind)
    local Z, seen = zoneType(), {}
    for _ = 0, W.CLIMB_MAX do
        if not (id and kind) or seen[id] then return nil end
        if kind == Z then return id end
        if kind < Z then return nil end
        seen[id] = true
        local info = mapInfo(id)
        local parent = info and finite(info.parentMapID)
        local up = parent and parent > 0 and mapInfo(parent)
        if not up then return nil end
        id, kind = parent, finite(up.mapType)
    end
    return nil
end

local function squash(s) return (s:lower():gsub("%s", "")) end

-- The names a zone can be given by: every zone map and the continents, as the client names them.
function W.NameIndex()
    local list = {}
    local function add(id)
        local n = mapName(id)
        if n then list[#list + 1] = { id = id, name = n, key = squash(n) } end
    end
    local data = GP.LandmarkData
    for _, id in ipairs(data and data.zonemaps or {}) do add(id) end
    for _, id in ipairs(W.CONTINENTS) do add(id) end
    return list
end

function W.ZoneByName(name, index)
    local key = squash(name)
    if key == "" then return nil, "no zone given" end
    local partial = {}
    for _, z in ipairs(index) do
        if z.key == key then return z.id end
        if z.key:find(key, 1, true) then partial[#partial + 1] = z end
    end
    if #partial == 1 then return partial[1].id end
    if #partial == 0 then return nil, ('no zone named "%s"'):format(name) end
    local names = {}
    for _, z in ipairs(partial) do names[#names + 1] = z.name end
    table.sort(names)
    local more = #names > 5 and (" and %d more"):format(#names - 5) or ""
    for i = #names, 6, -1 do names[i] = nil end
    return nil, ('"%s" could be %s%s'):format(name, table.concat(names, ", "), more)
end

--------------------------------------------------------------------------------
-- Parsing

-- A description: no escapes or control characters, spaces collapsed, at most DESC_MAX bytes (whole characters).
function W.Clean(desc)
    if type(desc) ~= "string" then return "" end
    desc = desc:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if #desc > W.DESC_MAX then
        local cut = W.DESC_MAX
        while cut > 0 and desc:byte(cut + 1) and desc:byte(cut + 1) >= 0x80 and desc:byte(cut + 1) < 0xC0 do
            cut = cut - 1
        end
        desc = desc:sub(1, cut):gsub(" $", "")
    end
    return desc
end

local function coordinate(token)
    if not token then return nil end
    if not (token:match("^%d+%.?%d*$") or token:match("^%d*%.%d+$")) then return nil end
    local v = tonumber(token)
    if not v or v < 0 or v > 100 then return nil end
    return math.floor(v * 100 + 0.5) / 100
end

-- One line: a step { map, x, y, desc }, or nil and why (nil, nil for a blank line).
-- `here` is the player's zone (or nil); `names()` gives the name index on demand.
function W.ParseLine(line, here, names)
    line = line:gsub("^%s*/%S*", "")
    if not line:find("%S") then return nil, nil end
    line = line:gsub("(%d)[,.]%s+(%d)", "%1 %2"):gsub("(%d),(%d)", "%1.%2")
    local tokens = {}
    for t in line:gmatch("%S+") do tokens[#tokens + 1] = t end
    local map, first
    local id = tokens[1]:match("^#(%d+)$")
    if id then
        map, first = tonumber(id), 2
    elseif coordinate(tokens[1]) then
        if not here then return nil, "your zone can't be read here: name it (Zone name x y)" end
        map, first = here, 1
    else
        for i = 2, #tokens do
            if coordinate(tokens[i]) then first = i; break end
        end
        if not first then return nil, "no coordinates" end
        local why
        map, why = W.ZoneByName(table.concat(tokens, " ", 1, first - 1), names())
        if not map then return nil, why end
    end
    local x, y = coordinate(tokens[first]), coordinate(tokens[first + 1])
    if not (x and y) then return nil, "two coordinates from 0 to 100 are needed" end
    if not W.World(map, x, y) then return nil, ("map %d can't be placed"):format(map) end
    return { map = map, x = x, y = y, desc = W.Clean(table.concat(tokens, " ", first + 2)) }
end

-- Pasted text: its steps (at most MAX_STEPS) and what was wrong (lines).
function W.Parse(text, here)
    local steps, problems, over = {}, {}, 0
    if #text > W.MAX_BYTES then
        problems[#problems + 1] = ("only the first %d characters were read"):format(W.MAX_BYTES)
        text = text:sub(1, W.MAX_BYTES)
    end
    local index
    local function names()
        index = index or W.NameIndex()
        return index
    end
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if n > W.MAX_LINES then
            problems[#problems + 1] = ("only the first %d lines were read"):format(W.MAX_LINES)
            break
        end
        local step, why = W.ParseLine(line:gsub("\r", ""), here, names)
        if step then
            if #steps < W.MAX_STEPS then steps[#steps + 1] = step else over = over + 1 end
        elseif why then
            problems[#problems + 1] = ("line %d: %s"):format(n, why)
        end
    end
    if over > 0 then
        problems[#problems + 1] = ("%d more steps than the %d a route holds were left out"):format(over, W.MAX_STEPS)
    end
    return steps, problems
end

local function report(problems)
    for i, p in ipairs(problems) do
        if i > W.REPORT_MAX then
            return say(("  and %d more."):format(#problems - W.REPORT_MAX))
        end
        say("  " .. p)
    end
end

--------------------------------------------------------------------------------
-- The route

local function valid(s)
    if type(s) ~= "table" then return false end
    local map, x, y = finite(s.map), finite(s.x), finite(s.y)
    return map ~= nil and map > 0 and map == math.floor(map) and x ~= nil and x >= 0 and x <= 100
        and y ~= nil and y >= 0 and y <= 100
end

-- A saved route, checked: invalid steps dropped (each keeps its own `done`),
-- `current` carried through the compaction (a dropped one: the next kept
-- step), complete kept complete; nil when nothing is left.
function W.CleanRoute(r)
    if type(r) ~= "table" or type(r.steps) ~= "table" then return nil end
    local total = #r.steps
    local cur = finite(r.current)
    cur = (cur and cur == math.floor(cur)) and cur or 1
    if cur < 1 then cur = 1 end
    local out, newCur = {}, nil
    for i = 1, total do
        local s = r.steps[i]
        if valid(s) and #out < W.MAX_STEPS then
            out[#out + 1] = { map = s.map, x = s.x, y = s.y, desc = W.Clean(s.desc), done = s.done == true }
            if not newCur and i >= cur then newCur = #out end
        end
    end
    if #out == 0 then return nil end
    if not newCur then newCur = #out + 1 end   -- nothing kept from `current` on: complete
    return { steps = out, current = newCur, closed = r.closed == true }
end

function W.Route()
    local c = GP.charDB
    local r = type(c) == "table" and c.way
    if type(r) == "table" and type(r.steps) == "table" and #r.steps > 0 then return r end
    return nil
end

-- The current step: its index and step, or nil (no route, or complete).
function W.Current()
    local r = W.Route()
    if not r then return nil end
    local i = r.current
    if type(i) == "number" and r.steps[i] then return i, r.steps[i] end
    return nil
end

function W.IsComplete()
    local r = W.Route()
    return r ~= nil and r.current == #r.steps + 1
end

function W.Position(i) return state.pos[i] end

local function positions()
    state.pos = {}
    local r = W.Route()
    if not r then return end
    for i, s in ipairs(r.steps) do
        local c, north, west = W.World(s.map, s.x, s.y)
        state.pos[i] = c and { c = c, north = north, west = west } or false
    end
end

local function stopTicker()
    if state.ticker then state.ticker:Cancel() end
    state.ticker = nil
end

-- The route changed (content or current step): the ring, the controller, the list, the pins.
local function changed()
    positions()
    GP.Compass.Changed(W.OWNER)
    if W.enabled and W.Current() then
        if not state.ticker then state.ticker = C_Timer.NewTicker(W.TICK, function() W.Tick() end) end
        GP.Compass.Want(W.OWNER)
    else
        stopTicker()
        GP.Compass.Drop(W.OWNER)
    end
    if W.enabled and Frame() then
        Frame().Refresh()
        Frame().Pins()
    end
end
W.Changed = changed

local function setCurrent(i, byHand)
    local r = W.Route()
    if not r then return end
    r.current = i
    state.armed = not byHand
    changed()
end

-- Pasted text: replaces the route when it has a valid step.
function W.Load(text)
    local steps, problems = W.Parse(text or "", W.Here())
    if #steps == 0 then
        say("Waypoint route: nothing to load, the route is unchanged.")
        report(problems)
        return false
    end
    if type(GP.charDB) ~= "table" then return false end
    GP.charDB.way = { steps = steps, current = 1 }
    state.armed = true
    say(("Waypoint route: %d step%s loaded."):format(#steps, #steps == 1 and "" or "s"))
    report(problems)
    changed()
    if Frame() then Frame().ShowList() end
    return true
end

-- One line: added at the end (a new route when there's none; current when the route was complete).
function W.Append(line)
    local step, why = W.ParseLine(line or "", W.Here(), W.NameIndex)
    if not step then
        say("Waypoint route: " .. (why or "no coordinates") .. ".")
        return false
    end
    if type(GP.charDB) ~= "table" then return false end
    local r = W.Route()
    if r and #r.steps >= W.MAX_STEPS then
        say(("Waypoint route: a route holds %d steps; nothing added."):format(W.MAX_STEPS))
        return false
    end
    if not r then
        GP.charDB.way = { steps = { step }, current = 1 }
        state.armed = true
    else
        -- A complete route's current (#steps + 1) becomes this step: a fresh one, armed.
        if W.IsComplete() then state.armed = true end
        r.steps[#r.steps + 1] = step
    end
    say(("Waypoint route: step %d added (%s %.2f, %.2f)."):format(#W.Route().steps, W.ZoneName(step.map),
        step.x, step.y))
    changed()
    if Frame() then Frame().ShowList() end
    return true
end

function W.Previous()
    local r = W.Route()
    if not r then return end
    setCurrent(math.max(1, math.min(r.current - 1, #r.steps)), true)
end

function W.Next()
    local r = W.Route()
    if not r or r.current > #r.steps then return end
    setCurrent(r.current + 1, true)
end

function W.Select(i)
    local r = W.Route()
    if r and r.steps[i] then setCurrent(i, true) end
end

function W.Clear()
    if type(GP.charDB) == "table" then GP.charDB.way = nil end
    state.armed = true
    changed()
    say("Waypoint route cleared.")
end

--------------------------------------------------------------------------------
-- The controller

local function plainlyFalse(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and not API.IsSecret(v) and v == false
end

-- May the route make progress now? Each read plainly false: not dead, not on a taxi, not in an instance.
function W.Eligible()
    return plainlyFalse(UnitIsDeadOrGhost, "player") and plainlyFalse(UnitOnTaxi, "player")
        and plainlyFalse(IsInInstance)
end

-- The current step reached: done, the next one current (armed); past the last, complete.
local function arrive(i)
    local r = W.Route()
    r.steps[i].done = true
    r.current = i + 1
    state.armed = true
    if r.current > #r.steps then say("Waypoint route complete.") end
    changed()
end

-- One tick: eligibility, then the position; at most one advance.
function W.Tick()
    if not W.enabled then return stopTicker() end
    local i = W.Current()
    if not i then return stopTicker() end
    if not W.Eligible() then return end
    local p = state.pos[i]
    if not p then
        if state.armed then           -- no position: the route's own advance passes it, not done
            local r = W.Route()
            r.current = i + 1
            changed()
        end
        return
    end
    local c, north, west = GP.Compass.Position()
    if not c then return end
    if p.c == c then
        local d = math.sqrt((north - p.north) ^ 2 + (west - p.west) ^ 2)
        if not state.armed and d > W.NEAR then state.armed = true end
        if state.armed and d <= W.NEAR then return arrive(i) end
    end
    GP.Compass.Want(W.OWNER)
end

-- The ring's owner: above the books; no arrival in the ring (the controller advances).
GP.Compass.Register(W.OWNER, {
    priority = 2,
    Hidden = function() return not (W.enabled and W.Current() and W.Eligible()) end,
    Point = function(c)
        local i = W.Current()
        local p = i and state.pos[i]
        if p and p.c == c then return p.north, p.west end
        return nil
    end,
    Label = function()
        local i = W.Current()
        return i and tostring(i) or nil
    end,
    Tooltip = function(tooltip)
        local i, s = W.Current()
        if not i then return false end
        tooltip:SetText(("Step %d of %d"):format(i, #W.Route().steps))
        if s.desc ~= "" then tooltip:AddLine(s.desc, 1, 1, 1, true) end
        tooltip:AddLine(("%s %.1f, %.1f"):format(W.ZoneName(s.map), s.x, s.y), 0.8, 0.8, 0.8)
    end,
})

--------------------------------------------------------------------------------
-- /way

-- Does another add-on own /way? Blizzard's hash, then every SLASH_* global.
function W.WayTaken()
    local hash = rawget(_G, "hash_SlashCmdList")
    if type(hash) == "table" and rawget(hash, "/WAY") ~= nil then return true end
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^SLASH_") and not API.IsSecret(v) and type(v) == "string"
            and v:lower() == "/way" then
            return true
        end
    end
    return false
end

function W.Claim()
    if state.claimed or not W.enabled then return end
    if W.WayTaken() then return end
    _G.SLASH_GLASSPEARLSWAY1 = "/way"
    SlashCmdList.GLASSPEARLSWAY = function(msg) W.Command(msg, true) end
    state.claimed = true
end

local function claimSoon() C_Timer.After(0, W.Claim) end

--------------------------------------------------------------------------------
-- Commands

-- `/gpearls way ...` and `/way ...`: nothing opens the list (or the paste box);
-- paste, clear / reset, list; anything else is one step to add.
function W.Command(arg, fromWay)
    if not W.enabled then return say("Waypoint routes is off: /gpearls way on.") end
    arg = (arg or ""):match("^%s*(.-)%s*$")
    local verb = arg:match("^(%S+)") and arg:match("^(%S+)"):lower()
    if arg == "" then
        if W.Route() then return Frame().ToggleList() end
        return Frame().ShowPaste()
    elseif verb == "paste" then
        return Frame().ShowPaste()
    elseif verb == "clear" or verb == "reset" then
        return W.Clear()
    elseif verb == "list" and not fromWay then
        return Frame().ShowList()
    end
    W.Append(arg)
end

--------------------------------------------------------------------------------
-- The pearl

local function enable()
    W.enabled = true
    if type(GP.charDB) == "table" then GP.charDB.way = W.CleanRoute(GP.charDB.way) end
    state.armed = true
    changed()
    local r = W.Route()
    if r and not r.closed and W.Current() and Frame() then Frame().ShowList() end
    if state.started then claimSoon() end
end

local function disable()
    W.enabled = false
    stopTicker()
    GP.Compass.Drop(W.OWNER)
    if Frame() then Frame().HideAll() end
end

GP.Pearls.Register({
    key = W.KEY,
    name = "Waypoint routes",
    desc = "Paste /way lines and follow them step by step with a compass, a step list and map pins.",
    help = "Paste lines such as \"/way 66 34\" (also \"/way Zone name 66 34 note\" or \"/way #1429 66 34\") into the "
        .. "paste box (/gpearls way paste, or /way alone when no other add-on uses /way) and they become a route. "
        .. "The compass points at the current step; within 10 yards it is done and the next one is current. The "
        .. "step list shows each step's direction and distance: Previous, Next or a click on a row choose another. "
        .. "Numbered pins mark the steps on the world map and the minimap. The route is kept for this character "
        .. "until you clear it or paste another. Not while dead, on a flight or in an instance.",
    default = true,
    category = "Interface",
    section = "Maps",
    defaults = { worldmap = true, minimap = true },
    Enable = enable,
    Disable = disable,
    Start = function()
        state.started = true
        if W.enabled then claimSoon() end
    end,
    onSettingChanged = function() if W.enabled and Frame() then Frame().Pins() end end,
    configure = function(panel, refreshers) Frame().Configure(panel, refreshers) end,
    commands = { way = { help = "x y [note], Zone x y, paste, list or clear: your waypoint route", run = function(arg)
        W.Command(arg, false)
    end } },
})

W._test = { state = state, positions = positions }
