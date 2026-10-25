-- Data/SpellRanks.lua (#12): the generated rank groups are well formed and
-- hold the chains the pearl relies on: every group ranks upward with unique
-- IDs, no Season of Discovery rune copy, shared names split into their own
-- chains, the same spell at one rank kept as both IDs, the exclusions out,
-- and the client build named. Levels are shown only: ties and zeros allowed.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ pearls = false })
local D = GP.SpellRankData
check(type(D) == "table", "the data loads")
eq(D.build, "1.60.1.70532", "built from the measured client build's tables")

local function isNum(v) return type(v) == "number" and v == v end

-- Every group: two or more distinct ranks, never falling; every ID once, and
-- ranks[] agrees with groups[].
local seen, groups = {}, 0
for g, ids in ipairs(D.groups) do
    groups = groups + 1
    local last, distinct = 0, {}
    for _, id in ipairs(ids) do
        check(isNum(id) and not seen[id], "group " .. g .. ": ID " .. tostring(id) .. " once")
        seen[id] = true
        local e = D.ranks[id]
        check(e and e[1] == g, "group " .. g .. ": ranks[" .. id .. "] names its group")
        check(e and isNum(e[2]) and e[2] >= last, "group " .. g .. ": ranks never fall")
        check(e and isNum(e[3]) and e[3] >= 0 and e[3] <= 60, "group " .. g .. ": a level (0 allowed)")
        if e then last = e[2]; distinct[e[2]] = true end
    end
    local n = 0
    for _ in pairs(distinct) do n = n + 1 end
    check(n >= 2, "group " .. g .. ": at least two ranks")
end
local n = 0
for id in pairs(D.ranks) do
    n = n + 1
    check(seen[id], "ranks[" .. id .. "] is in a group")
end
eq(n, #(function() local t = {} for id in pairs(seen) do t[#t + 1] = id end return t end)(), "ranks and groups hold the same IDs")
check(groups >= 300, "the class rank groups (" .. groups .. ")")

-- No Season of Discovery rune copy (AcquireMethod 3: 408xxx, 425xxx).
for _, id in ipairs({ 408439, 408440, 425268, 425277 }) do
    eq(D.ranks[id], nil, "no rune copy: " .. id)
end

local function chain(first)
    local e = D.ranks[first]
    return e and D.groups[e[1]]
end
local function same(a, b)
    if not a or #a ~= #b then return false end
    for i = 1, #b do if a[i] ~= b[i] then return false end end
    return true
end
check(same(chain(8042), { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }), "Earth Shock: its seven ranks in order")
eq(D.ranks[8046][2], 4, "  rank 4 is 8046")
eq(D.ranks[8046][3], 24, "  learned at 24")
check(same(chain(403), { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 }), "Lightning Bolt: ten ranks, no rune copies")
-- Two spells sharing a name: one chain each.
check(same(chain(324), { 324, 325, 905, 945, 8134, 10431, 10432 }), "Lightning Shield's buff: its own chain")
check(D.ranks[26364] and D.ranks[26364][1] ~= D.ranks[324][1], "  its bolt is another chain")
check(D.ranks[15237] and D.ranks[23455] and D.ranks[15237][1] ~= D.ranks[23455][1], "Holy Nova: damage and heal apart")
check(D.ranks[13795] and D.ranks[13797] and D.ranks[13795][1] ~= D.ranks[13797][1], "Immolation Trap: the trap and its burn apart")
-- The same spell at one rank: both IDs, one chain.
check(D.ranks[20154] and D.ranks[21084] and D.ranks[20154][1] == D.ranks[21084][1], "Seal of Righteousness 1: both IDs in one chain")
eq(D.ranks[20154][2], 1, "  both rank 1")
-- A level tie is allowed (Fireball 11 and 12 at 60), and a zero (Dash).
eq(D.ranks[10151][3], D.ranks[25306][3], "Fireball 11 and 12 both at 60")
eq(D.ranks[1850] and D.ranks[1850][3], 0, "Dash: level 0 is kept")
-- Exclusions: different spells per rank, and pet skill lines.
for _, id in ipairs({ 132, 2970, 11743 }) do eq(D.ranks[id], nil, "Detect Invisibility excluded: " .. id) end
for _, id in ipairs({ 23100, 23111, 23112 }) do eq(D.ranks[id], nil, "a pet's Dash excluded: " .. id) end

-- The exclusion list the generator read is the one committed.
local found = false
for line in io.lines("Tools/ranks/exclude.csv") do
    if line:find("^354,Detect Invisibility,") then found = true end
end
check(found, "Tools/ranks/exclude.csv names Detect Invisibility")

done("test_spellranks_data")
