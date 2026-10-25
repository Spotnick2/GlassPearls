-- Data/Landmarks.lua (#10): the generated map landmarks are well formed and
-- match their sources (Tools/landmarks/*.csv): every entrance in the CSV is
-- in the data, shared doors are one icon, transports have a kind, a side and
-- destinations, zone levels are sane, and the data names its client build.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ pearls = false })
local D = GP.LandmarkData
check(type(D) == "table", "the data loads")
eq(D.build, "1.60.1.70532", "built from the measured client build's tables")

local function isNum(v) return type(v) == "number" and v == v end
local CONTINENTS = { [0] = true, [1] = true }

-- Entrances.
local seenLfg, doors = {}, {}
for _, e in ipairs(D.entrances) do
    check(type(e.key) == "string" and not doors[e.key], "a door key, once: " .. tostring(e.key))
    doors[e.key] = e
    check(e.kind == "dungeon" or e.kind == "raid", e.key .. ": kind")
    check(CONTINENTS[e.c] and isNum(e.x) and isNum(e.y), e.key .. ": world position on Azeroth")
    check(isNum(e.zone), e.key .. ": its zone map")
    check(e.confidence == "client" or e.confidence == "near" or e.confidence == "hand", e.key .. ": a confidence")
    check(#e.list >= 1, e.key .. ": at least one dungeon")
    local allRaid = true
    for _, d in ipairs(e.list) do
        check(isNum(d.lfg) and not seenLfg[d.lfg], e.key .. ": LFG ID once: " .. tostring(d.lfg))
        seenLfg[d.lfg] = true
        check(type(d.name) == "string" and d.name ~= "", e.key .. ": a name")
        check(d.min == nil or (isNum(d.min) and d.min >= 1 and d.min <= 60), d.name .. ": min level")
        check(d.max == nil or (isNum(d.max) and d.min and d.max >= d.min and d.max <= 63), d.name .. ": max level")
        if not d.raid then allRaid = false end
    end
    eq(e.kind, allRaid and "raid" or "dungeon", e.key .. ": raid only when every one is a raid")
end
-- Every row of the source is there, and shared doors are one icon.
local csv = 0
for line in io.lines("Tools/landmarks/entrances.csv") do
    local lfg = tonumber(line:match("^(%d+),"))
    if lfg then
        csv = csv + 1
        check(seenLfg[lfg], "entrances.csv's LFG " .. lfg .. " is in the data")
    end
end
local n = 0
for _ in pairs(seenLfg) do n = n + 1 end
eq(n, csv, "as many dungeons as the CSV has rows")
eq(#doors.brm.list, 5, "Blackrock Mountain: one door for its five")
eq(#doors.dm.list, 3, "Dire Maul: one door for its three wings")
eq(doors.lfg41.kind, "raid", "Zul'Gurub is a raid door")

-- Transports: kinds, sides, destinations, and Auberdine's three piers.
local KINDS, SIDES = { ship = true, zeppelin = true, tram = true }, { A = true, H = true, AH = true }
local names, auberdine = {}, 0
for _, t in ipairs(D.transports) do
    check(KINDS[t.kind], t.name .. ": kind")
    check(SIDES[t.sides], t.name .. ": side")
    check(isNum(t.c) and isNum(t.x) and isNum(t.y), t.name .. ": world position")
    check(#t.routes >= 1, t.name .. ": somewhere to go")
    names[t.name] = true
    if t.name == "Auberdine" then auberdine = auberdine + 1 end
end
for _, t in ipairs(D.transports) do
    for _, to in ipairs(t.routes) do check(names[to], t.name .. " -> " .. to .. ": a dock that exists") end
end
eq(auberdine, 3, "Auberdine's three piers stay three icons")
for _, z in ipairs({ "Orgrimmar", "Undercity", "Grom'gol Base Camp" }) do
    local found = false
    for _, t in ipairs(D.transports) do if t.name == z and t.kind == "zeppelin" and t.sides == "H" then found = true end end
    check(found, z .. ": a Horde zeppelin tower")
end

-- Zone levels and zone maps.
for uiMap, r in pairs(D.zones) do
    check(isNum(uiMap) and isNum(r[1]) and isNum(r[2]) and r[1] <= r[2] and r[2] <= 63, "zone " .. uiMap .. " levels")
end
eq(D.zones[1453], nil, "no level range for a city (Stormwind City)")
eq(D.zones[1411] and D.zones[1411][2], 10, "Durotar 1-10")
check(#D.zonemaps >= 40, "the zone maps for flight points (" .. #D.zonemaps .. ")")

done("test_landmarks_data")
