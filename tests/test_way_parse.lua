-- Waypoint routes (#139): reading /way lines. Every format, the refusals, the
-- bounds, zone names (the client's own), the player's zone climbed from a
-- micro map (cycles, secrets, refusals), and a saved route cleaned at login.
-- The route's life is test_way.lua; the windows and pins test_way_frame.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local W = GP.Way

local ELWYNN, DUROTAR, DUN, DUSK, MICRO = 1429, 1411, 1426, 1431, 9001
WoW.zoneRects[ELWYNN] = { 1000, 700, 0, 0, 0 }
WoW.zoneRects[DUROTAR] = { 800, 600, 5000, 5000, 1 }
WoW.zoneRects[DUN] = { 900, 600, 100, 100, 0 }
WoW.zoneRects[DUSK] = { 900, 600, 200, 200, 0 }
WoW.mapInfo[ELWYNN] = { name = "Elwynn Forest" }
WoW.mapInfo[DUROTAR] = { name = "Durotar" }
WoW.mapInfo[DUN] = { name = "Dun Morogh" }
WoW.mapInfo[DUSK] = { name = "Duskwood" }
local function names() return W.NameIndex() end
local function one(line, here)
    if here == nil then here = ELWYNN elseif here == false then here = nil end
    return W.ParseLine(line, here, names)
end
local function is(step, map, x, y, desc)
    return step ~= nil and step.map == map and step.x == x and step.y == y and step.desc == (desc or "")
end

-- Formats.
check(is(one("/way 66 34"), ELWYNN, 66, 34), "/way x y: the player's zone")
check(is(one("66 34"), ELWYNN, 66, 34), "  without the command")
check(is(one("  /tway   66   34  "), ELWYNN, 66, 34), "  another command word, extra spaces")
check(is(one("/way 66.2 34.5"), ELWYNN, 66.2, 34.5), "decimals")
check(is(one("/way 66,2 34,5"), ELWYNN, 66.2, 34.5), "a comma decimal")
check(is(one("/way 66.2, 34.5"), ELWYNN, 66.2, 34.5), "a comma between the two")
check(is(one("/way 66, 34"), ELWYNN, 66, 34), "  whole numbers too")
check(is(one("/way 66.256 34.004"), ELWYNN, 66.26, 34), "rounded to 0.01")
check(is(one("/way 0 100"), ELWYNN, 0, 100), "0 and 100 are in range")
check(is(one("/way 66 34 Kill the boar"), ELWYNN, 66, 34, "Kill the boar"), "a note after the numbers")
check(is(one("/way #1411 50 50 orc town"), DUROTAR, 50, 50, "orc town"), "#mapID x y note")
check(is(one("/way #1411 50 50", false), DUROTAR, 50, 50), "  without a readable zone")
check(is(one("/way Durotar 50 50 note", false), DUROTAR, 50, 50, "note"), "a zone name")
check(is(one("/way elwynn forest 1 2"), ELWYNN, 1, 2), "  any case")
check(is(one("/way ElwynnForest 1 2"), ELWYNN, 1, 2), "  spaces ignored")
check(is(one("/way elwyn 1 2"), ELWYNN, 1, 2), "  a unique part of it")
check(is(one("/way Dun Morogh 5 5"), DUN, 5, 5), "  an exact name over its substrings")

-- Notes: no escapes, at most DESC_MAX bytes, whole characters.
local s = one("/way 1 2 a|cffff0000red|r note")
check(s and not s.desc:find("|", 1, true), "a note loses its | (no escapes)")
s = one("/way 1 2 " .. string.rep("x", 80))
eq(#s.desc, W.DESC_MAX, "a long note: cut to the limit")
s = one("/way 1 2 " .. string.rep("x", W.DESC_MAX - 1) .. "\195\169")   -- an é across the limit
eq(s.desc, string.rep("x", W.DESC_MAX - 1), "  never inside a character")
eq(W.Clean(nil), "", "no note: empty")
eq(W.Clean("a\tb\nc"), "a b c", "control characters become spaces")

-- Refusals.
local function refused(line, here, pattern)
    local step, why = one(line, here)
    return step == nil and type(why) == "string" and (pattern == nil or why:find(pattern, 1, true) ~= nil)
end
check(refused("/way 66 34", false, "can't be read"), "bare coordinates with no zone: refused, said")
check(refused("/way 66", nil, "two coordinates"), "one number: refused")
check(refused("/way 66 101", nil, "two coordinates"), "over 100: refused")
check(refused("/way 66 -3", nil, "two coordinates"), "negative: refused")
check(refused("/way 0x10 5", nil), "hexadecimal: not a coordinate")
check(refused("/way 1e1 5", nil), "an exponent: not a coordinate")
check(refused("/way Narnia 1 2", nil, 'no zone named "Narnia"'), "an unknown zone")
local _, why = one("/way du 1 2")
check(why and why:find("could be Dun Morogh, Durotar, Duskwood", 1, true), "several zones: refused, listed")
check(refused("/way #9999 50 50", nil, "map 9999 can't be placed"), "a map that can't be placed")
WoW.zoneRects[4242] = "throw"
check(refused("/way #4242 1 2", nil, "can't be placed"), "  a conversion that throws")
WoW.zoneRects[4243] = { secret = WoW.Secret("w") }
check(refused("/way #4243 1 2", nil, "can't be placed"), "  a secret conversion")
check(refused("/way notes only", nil, "no coordinates"), "no numbers")
local blank, bwhy = one("   ")
check(blank == nil and bwhy == nil, "a blank line: skipped silently")
blank, bwhy = one("/way")
check(blank == nil and bwhy == nil, "  a bare command word too")

-- Names: the client's, skipped when unreadable.
WoW.mapInfo[DUSK] = { name = WoW.Secret("n") }
check(refused("/way duskwood 1 2", nil, "no zone named"), "a secret zone name: not offered")
WoW.mapInfo[DUSK] = "throw"
check(refused("/way duskwood 1 2", nil, "no zone named"), "  a throwing one either")
WoW.mapInfo[DUSK] = { name = "Duskwood" }

-- A paste.
local text = table.concat({ "/way 66 34", "", "/way nowhere", "/way 50 50 b", "garbage here 12" }, "\r\n")
local steps, problems = W.Parse(text, ELWYNN)
eq(#steps, 2, "a paste: the valid lines")
eq(problems[1], "line 3: no coordinates", "  each problem with its line number")
eq(problems[2], 'line 5: no zone named "garbage here"', "  and its reason")
eq(#problems, 2, "  blank lines aren't problems")
local many = {}
for i = 1, W.MAX_STEPS + 5 do many[i] = ("/way %d %d"):format(i % 100, 50) end
steps, problems = W.Parse(table.concat(many, "\n"), ELWYNN)
eq(#steps, W.MAX_STEPS, "at most MAX_STEPS steps")
check(problems[#problems]:find("5 more steps", 1, true), "  the rest said")
many = {}
for i = 1, W.MAX_LINES + 50 do many[i] = "" end
steps, problems = W.Parse(table.concat(many, "\n") .. "\n/way 1 1", ELWYNN)
eq(#steps, 0, "only MAX_LINES lines are read")
check(problems[1]:find("first 200 lines", 1, true), "  said")
steps, problems = W.Parse("/way 1 1\n" .. string.rep(" ", W.MAX_BYTES + 10), ELWYNN)
eq(#steps, 1, "a huge paste: the first MAX_BYTES read")
check(problems[1]:find("first 20000 characters", 1, true), "  said")

-- The player's zone.
local function here(zone) WoW.playerZone = zone; return W.Here() end
eq(here({ ELWYNN, 3 }), ELWYNN, "a zone map: itself")
WoW.mapInfo[MICRO] = { name = "Goldshire Inn", mapType = 5, parentMapID = ELWYNN }
eq(here({ MICRO, 5 }), ELWYNN, "a micro map: climbed to its zone")
WoW.mapInfo[MICRO + 1] = { name = "Cellar", mapType = 5, parentMapID = MICRO }
eq(here({ MICRO + 1, 5 }), ELWYNN, "  two levels")
WoW.mapInfo[MICRO + 2] = { name = "Loop", mapType = 5, parentMapID = MICRO + 3 }
WoW.mapInfo[MICRO + 3] = { name = "Loop", mapType = 5, parentMapID = MICRO + 2 }
eq(here({ MICRO + 2, 5 }), nil, "  a cycle: unreadable")
WoW.mapInfo[MICRO + 4] = { name = "Lost", mapType = 6, parentMapID = 0 }
eq(here({ MICRO + 4, 6 }), nil, "  no parent: unreadable")
WoW.mapInfo[MICRO + 5] = { name = "S", mapType = 5, parentMapID = WoW.Secret("p") }
eq(here({ MICRO + 5, 5 }), nil, "  a secret parent: unreadable")
WoW.mapInfo[MICRO + 6] = { name = "S", mapType = 5, parentMapID = MICRO + 7 }
WoW.mapInfo[MICRO + 7] = { name = "S", mapType = WoW.Secret("t"), parentMapID = ELWYNN }
eq(here({ MICRO + 6, 5 }), nil, "  a secret map type: unreadable")
local chain = MICRO + 10
for i = 0, W.CLIMB_MAX + 1 do WoW.mapInfo[chain + i] = { name = "C", mapType = 5, parentMapID = chain + i + 1 } end
WoW.mapInfo[chain + W.CLIMB_MAX + 2] = { name = "Z", mapType = 3 }
eq(here({ chain, 5 }), nil, "  deeper than CLIMB_MAX: unreadable")
eq(here({ 1414, 2 }), nil, "a continent map: not a zone")
eq(here({ WoW.Secret("z"), 3 }), nil, "a secret map: unreadable")
eq(here({ ELWYNN, WoW.Secret("t") }), nil, "a secret type: unreadable")
eq(here("throw"), nil, "a refusal: unreadable")
eq(here(nil), nil, "nothing: unreadable")

-- A saved route, cleaned.
local R = W.CleanRoute
eq(R(nil), nil, "no saved route")
eq(R({ steps = "x" }), nil, "  steps not a table")
eq(R({ steps = {} }), nil, "  no steps")
local r = R({ current = 3, steps = {
    { map = ELWYNN, x = 1, y = 1, done = true },
    { map = ELWYNN, x = 200, y = 1 },                   -- dropped
    { map = ELWYNN, x = 3, y = 3, desc = "a|cffb", done = "yes" },
    { map = 1.5, x = 4, y = 4 },                         -- dropped
    { map = ELWYNN, x = 5, y = 5, done = true },
} })
eq(#r.steps, 3, "invalid steps dropped")
check(r.steps[1].done == true and r.steps[2].done == false and r.steps[3].done == true, "  done stays with its step")
eq(r.current, 2, "  the current step followed through the compaction")
check(not r.steps[2].desc:find("|", 1, true), "  notes cleaned")
eq(R({ current = 2, steps = { { map = ELWYNN, x = 1, y = 1 }, { map = ELWYNN, x = 999, y = 1 },
    { map = ELWYNN, x = 2, y = 2 } } }).current, 2, "a dropped current: the next kept step")
eq(R({ current = 2, steps = { { map = ELWYNN, x = 1, y = 1 }, { map = ELWYNN, x = 999, y = 1 } } }).current, 2,
    "  none after it: complete")
eq(R({ current = 3, steps = { { map = ELWYNN, x = 1, y = 1 }, { map = ELWYNN, x = 2, y = 2 } } }).current, 3,
    "complete stays complete")
eq(R({ current = 9, steps = { { map = ELWYNN, x = 1, y = 1 } } }).current, 2, "  past the end: complete")
eq(R({ current = 0.5, steps = { { map = ELWYNN, x = 1, y = 1 } } }).current, 1, "a broken current: the first")
eq(R({ current = WoW.Secret("c"), steps = { { map = ELWYNN, x = 1, y = 1 } } }).current, 1, "  a secret one too")
local big = {}
for i = 1, W.MAX_STEPS + 3 do big[i] = { map = ELWYNN, x = 1, y = 1 } end
eq(#R({ steps = big }).steps, W.MAX_STEPS, "at most MAX_STEPS kept")

done("test_way_parse")
