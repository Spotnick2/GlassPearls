-- SettingsSync's byte budget (#4): every part filled to its cap with the
-- longest values the format allows must encode within the budget, under the
-- 32 KB wire ceiling (with the "ST\n" prefix). If a new pearl's settings
-- push the known keys past their share, this fails and the budget needs a
-- second look before the pearl ships.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local SS = GP.SettingsSync
local C = SS.Core
local store = GP.db.sync

local T_MAX, S_MAX = 9999999999, 999999999
local O_MAX = "Player-" .. string.rep("9", SS.ORIGIN_MAX - 7)   -- 32 bytes
eq(#O_MAX, SS.ORIGIN_MAX, "the longest origin is " .. SS.ORIGIN_MAX .. " bytes")
local function maxStamp() return { t = T_MAX, o = O_MAX, s = S_MAX } end

-- Known keys: the real registry (every pearl's switch and settings, and the
-- look choice), each with the longest stamp. Their share is 4 KB.
local known = 0
for id in pairs(SS.reg.keys) do
    store.stamps[id] = maxStamp()
    known = known + 1
end
local knownBytes = #C.Encode(SS.reg, store)
check(known >= 1, "the registry has keys (" .. known .. ")")
check(knownBytes <= 4096, "the known keys fit their 4 KB share (" .. knownBytes .. " B)")

-- Unknown keys: 32 of them, the longest id and value, the longest stamp.
for i = 1, SS.FOREIGN_MAX do
    local id = string.format("z.%0" .. (SS.ID_MAX - 2) .. "d", i)
    store.foreign[id] = { v = "e" .. string.rep("x", SS.VALUE_MAX), t = T_MAX, o = O_MAX, s = S_MAX }
end
local withForeign = #C.Encode(SS.reg, store)
local foreignBytes = withForeign - knownBytes
check(foreignBytes <= 5 * 1024, "32 unknown keys fit their 5 KB share (" .. foreignBytes .. " B)")
for line in C.Encode(SS.reg, store):gmatch("[^\n]+") do
    if line:find("^V\tz%.") then check(#line + 1 <= 155, "an unknown key's line is at most 155 B") break end
end

-- Sets: 300 entries across the cap of sets (the shipped pearls' own, then
-- the longest set ids up to SETS_MAX), the longest members and stamps. Only
-- registered sets encode: entries go to those, never to a refused one.
for s = 1, SS.SETS_MAX do SS.RegisterSet(string.format("s.%0" .. (SS.ID_MAX - 2) .. "d", s)) end
local sids = {}
for sid in pairs(SS.reg.sets) do
    sids[#sids + 1] = sid
    store.sets[sid] = {}
end
table.sort(sids)
eq(#sids, SS.SETS_MAX, "the cap of " .. SS.SETS_MAX .. " sets is registered")
local i = 0
while i < SS.SET_MAX do
    for _, sid in ipairs(sids) do
        if i >= SS.SET_MAX then break end
        i = i + 1
        store.sets[sid][2147483647 - i] = { a = 1, t = T_MAX, o = O_MAX, s = S_MAX }
    end
end
eq(C.SetEntries(store), SS.SET_MAX, "the sets hold the cap of " .. SS.SET_MAX .. " entries")
local body = C.Encode(SS.reg, store)
local setBytes = #body - withForeign
check(setBytes <= 21 * 1024, "300 set entries fit their ~21 KB share (" .. setBytes .. " B)")
for line in body:gmatch("[^\n]+") do
    if line:find("^M\t") then check(#line + 1 <= 69, "a set entry's line is at most 69 B (" .. (#line + 1) .. ")") break end
end

-- The whole: within the budget, under the wire ceiling, and decodable.
check(#body <= SS.BUDGET, "every part full: " .. #body .. " B within the " .. SS.BUDGET .. " B budget")
check(#body + #SS.KIND + 1 <= SS.WIRE_MAX, "  under the 32 KB wire ceiling with the kind prefix")
local rec, why = C.Decode(body)
check(rec ~= nil, "  and a peer can decode it: " .. tostring(why))

-- At these caps, the live layer sends it.
local sent
GP.AccountSync.Send = function(kind, b) sent = b; return 1 end
local n = SS.SendNow()
eq(n, 1, "SendNow sends the full snapshot")
eq(sent, body, "  exactly what was encoded")

done("test_sync_budget")
