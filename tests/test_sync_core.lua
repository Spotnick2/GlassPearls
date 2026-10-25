-- SettingsSync's core (#4): stamp order, the GPS1 format and its strict
-- decoder, the per-key merge, set tombstones, unknown keys, caps, cleaning.
-- Pure functions over a registry and a store; no wire.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local SS = GP.SettingsSync
local C = SS.Core

local function stamp(t, o, s) return { t = t, o = o or "Player-1-AAA", s = s or 1 } end

-- A client: values in a plain table, a registry over them, an empty store.
local function client()
    local values = { flag = false, size = 3, mode = "grey" }
    local reg = { keys = {}, sets = { ["bf.keep"] = { min = 1, max = 2147483647 } } }
    local function spec(kind, name, extra)
        local s = { kind = kind, get = function() return values[name] end, set = function(v) values[name] = v end }
        for k, v in pairs(extra or {}) do s[k] = v end
        return s
    end
    reg.keys["on.flag"] = spec("bool", "flag")
    reg.keys["bf.size"] = spec("int", "size", { min = 0, max = 10 })
    reg.keys["bf.mode"] = spec("enum", "mode", { allowed = { grey = true, white = true } })
    return { values = values, reg = reg, store = C.Clean({}) }
end
local function apply(spec, v) spec.set(v) end

-- Order: time, then origin, then sequence; missing is the oldest.
eq(C.Compare(stamp(2), stamp(1)), 1, "a later time is newer")
eq(C.Compare(stamp(1), stamp(2)), -1, "  an earlier one older")
eq(C.Compare(stamp(5, "Player-1-BBB"), stamp(5, "Player-1-AAA")), 1, "same second: the higher origin wins")
eq(C.Compare(stamp(5, "P-1", 7), stamp(5, "P-1", 6)), 1, "same second and origin: the higher sequence wins")
eq(C.Compare(stamp(5, "P-1", 6), stamp(5, "P-1", 6)), 0, "the same stamp")
eq(C.Compare(stamp(0), nil), 1, "any stamp beats none")
eq(C.Compare(nil, nil), 0, "none ties none")

-- Encode -> Decode -> Merge round trip.
local a = client()
a.values.flag, a.values.size, a.values.mode = true, 7, "white"
a.store.stamps["on.flag"] = stamp(100)
a.store.stamps["bf.size"] = stamp(101)
a.store.stamps["bf.mode"] = stamp(102)
a.store.sets["bf.keep"] = { [2589] = { a = 1, t = 103, o = "Player-1-AAA", s = 4 },
                            [4306] = { a = 0, t = 104, o = "Player-1-AAA", s = 5 } }
local body = C.Encode(a.reg, a.store)
check(body:find("^GPS1\n"), "the format line first")
check(body:find("\nS\tbf.keep\n", 1, true), "a set header")
local rec, why = C.Decode(body)
check(rec ~= nil, "it decodes: " .. tostring(why))
eq(#rec.values, 3, "three values")
eq(#rec.members, 2, "two set entries")
local b = client()
local res = C.Merge(b.reg, b.store, rec, apply)
eq(res.applied, 5, "all five applied on an empty client")
check(b.values.flag == true and b.values.size == 7 and b.values.mode == "white", "the values arrived")
eq(b.store.stamps["bf.size"].t, 101, "the origin's stamp kept")
eq(b.store.sets["bf.keep"][2589].a, 1, "a member")
eq(b.store.sets["bf.keep"][4306].a, 0, "a tombstone")
check(not res.newerHere, "nothing newer here: no reply")
eq(C.Encode(b.reg, b.store), body, "equal states encode equally")

-- Older or equal stamps change nothing; a newer one does.
b.values.size = 9
b.store.stamps["bf.size"] = stamp(200)
res = C.Merge(b.reg, b.store, rec, apply)
eq(b.values.size, 9, "an older value doesn't overwrite a newer one")
check(res.newerHere, "  and this side should reply")
res = C.Merge(b.reg, b.store, assert(C.Decode(C.Encode(b.reg, b.store))), apply)
eq(res.applied, 0, "its own snapshot changes nothing")

-- A key the sender never set is older than any here: reply.
local fresh = client()
res = C.Merge(b.reg, b.store, assert(C.Decode(C.Encode(fresh.reg, fresh.store))), apply)
check(res.newerHere, "an empty snapshot from a new peer: reply with ours")

-- A value this copy can't take (out of range, not allowed): skipped, the rest applied.
local bad = "GPS1\nV\tbf.size\t300\tPlayer-1-AAA\t1\ti99\nV\tbf.mode\t300\tPlayer-1-AAA\t2\tepurple\nV\ton.flag\t300\tPlayer-1-AAA\t3\tb0"
res = C.Merge(b.reg, b.store, assert(C.Decode(bad)), apply)
eq(#res.skipped, 2, "two values this copy can't take, skipped")
eq(b.values.flag, false, "  the valid one applied")
eq(b.values.size, 9, "  the out-of-range one didn't")

-- The decoder: all or nothing.
local function rejects(text, label)
    local r, w = C.Decode(text)
    check(r == nil and type(w) == "string", "rejected: " .. label .. (r and "" or (" (" .. tostring(w) .. ")")))
end
rejects("", "empty")
rejects("GPS2\n", "another format")
rejects("GPS1\nX\tfoo", "an unknown record")
rejects("GPS1\nV\tbf.size\t1\tP-1\t1", "a short value line")
rejects("GPS1\nV\tbf.size\t1\tP-1\t1\ti3\textra", "a long value line")
rejects("GPS1\nV\tnodot\t1\tP-1\t1\ti3", "an id without a section")
rejects("GPS1\nV\t" .. string.rep("a", 30) .. ".bc\t1\tP-1\t1\ti3", "an id over 32 bytes")
rejects("GPS1\nV\tbf.size\t1x\tP-1\t1\ti3", "a time that isn't digits")
rejects("GPS1\nV\tbf.size\t1\tP 1\t1\ti3", "an origin with a space")
rejects("GPS1\nV\tbf.size\t1\t" .. string.rep("P", 33) .. "\t1\ti3", "an origin over 32 bytes")
rejects("GPS1\nV\tbf.size\t1\tP-1\t1\tq3", "an unknown value tag")
rejects("GPS1\nV\tbf.mode\t1\tP-1\t1\tea|cffff", "a value with |")
rejects("GPS1\nV\tbf.mode\t1\tP-1\t1\te" .. string.rep("x", 65), "a value over 64 bytes")
rejects("GPS1\nV\tbf.size\t1\tP-1\t1\ti3\nV\tbf.size\t2\tP-1\t2\ti4", "a duplicate key")
rejects("GPS1\nM\t5\t1\t1\tP-1\t1", "a member before its set")
rejects("GPS1\nS\tbf.keep\nM\t5\t2\t1\tP-1\t1", "a member flag other than 0/1")
rejects("GPS1\nS\tbf.keep\nM\t5\t1\t1\tP-1\t1\nM\t5\t0\t2\tP-1\t2", "a duplicate member")
rejects("GPS1\nS\tbf.keep\nS\tbf.keep", "a duplicate set")
local lines = { "GPS1" }
for i = 1, SS.SETS_MAX + 1 do lines[#lines + 1] = "S\ts.set" .. i end
rejects(table.concat(lines, "\n"), "more sets than the cap")
lines = { "GPS1", "S\tbf.keep" }
for i = 1, SS.SET_MAX + 1 do lines[#lines + 1] = "M\t" .. i .. "\t1\t1\tP-1\t" .. i end
rejects(table.concat(lines, "\n"), "more set entries than the cap")
lines = { "GPS1" }
for i = 1, SS.KNOWN_MAX + SS.FOREIGN_MAX + 1 do lines[#lines + 1] = "V\tk.k" .. i .. "\t1\tP-1\t1\tb1" end
rejects(table.concat(lines, "\n"), "more values than the caps")
rejects(string.rep("x", SS.WIRE_MAX + 1), "over the wire ceiling")
rejects(WoW.Secret("payload"), "a secret")

-- Unknown keys (a newer version's): kept verbatim, relayed, never applied.
local c = client()
local newer = "GPS1\nV\tnew.thing\t50\tPlayer-9-ZZZ\t3\tewhatever"
res = C.Merge(c.reg, c.store, assert(C.Decode(newer)), apply)
eq(c.store.foreign["new.thing"] and c.store.foreign["new.thing"].v, "ewhatever", "an unknown key is kept")
check(C.Encode(c.reg, c.store):find("V\tnew.thing\t50\tPlayer-9-ZZZ\t3\tewhatever", 1, true), "  and relayed with its origin's stamp")
res = C.Merge(c.reg, c.store, assert(C.Decode("GPS1\nV\tnew.thing\t40\tPlayer-9-ZZZ\t9\teolder")), apply)
eq(c.store.foreign["new.thing"].v, "ewhatever", "  an older copy of it doesn't replace it")
-- The cap: past 32 unknown keys, new ones aren't stored.
lines = { "GPS1" }
for i = 1, SS.FOREIGN_MAX + 5 do lines[#lines + 1] = "V\tnew.k" .. i .. "\t1\tP-1\t1\tb1" end
res = C.Merge(c.reg, c.store, assert(C.Decode(table.concat(lines, "\n"))), apply)
eq(C.Count(c.store.foreign), SS.FOREIGN_MAX, "unknown keys stop at the cap")
check(#res.skipped >= 5, "  the rest reported as skipped")

-- A relayed entry for a key this copy also knows is never encoded beside the
-- known one: a duplicate key would make the peer reject the whole snapshot.
local k = client()
k.store.stamps["on.flag"] = stamp(70)
k.store.foreign["on.flag"] = { v = "b1", t = 60, o = "Player-1-AAA", s = 1 }
local kb = C.Encode(k.reg, k.store)
local _, nflag = kb:gsub("V\ton%.flag\t", "")
eq(nflag, 1, "a known key is encoded once, never also as a relayed one")
check(C.Decode(kb) ~= nil, "  so the snapshot decodes")

-- Sets: the newer entry wins, a tombstone included; a new member past the cap is refused.
local d = client()
d.store.sets["bf.keep"] = { [2589] = { a = 1, t = 300, o = "P-1", s = 1 } }
res = C.Merge(d.reg, d.store, assert(C.Decode("GPS1\nS\tbf.keep\nM\t2589\t0\t301\tP-2\t1")), apply)
eq(d.store.sets["bf.keep"][2589].a, 0, "a newer tombstone removes the member")
res = C.Merge(d.reg, d.store, assert(C.Decode("GPS1\nS\tbf.keep\nM\t2589\t1\t250\tP-3\t1")), apply)
eq(d.store.sets["bf.keep"][2589].a, 0, "an older add can't resurrect it")
check(res.newerHere, "  and this side replies with the tombstone")
res = C.Merge(d.reg, d.store, assert(C.Decode("GPS1\nS\tother.set\nM\t1\t1\t1\tP-1\t1")), apply)
eq(d.store.sets["other.set"], nil, "a set this copy doesn't know isn't stored")
d.store.sets["bf.keep"] = {}
for i = 1, SS.SET_MAX do d.store.sets["bf.keep"][i] = { a = 1, t = 1, o = "P-1", s = i } end
res = C.Merge(d.reg, d.store, assert(C.Decode("GPS1\nS\tbf.keep\nM\t999999\t1\t5\tP-1\t1")), apply)
eq(d.store.sets["bf.keep"][999999], nil, "a new member past the cap is refused")
res = C.Merge(d.reg, d.store, assert(C.Decode("GPS1\nS\tbf.keep\nM\t7\t0\t5\tP-1\t1")), apply)
eq(d.store.sets["bf.keep"][7].a, 0, "  an existing entry still updates at the cap")

-- A setter that throws: skipped and reported, the stamp not taken.
local e = client()
e.reg.keys["on.flag"].set = function() error("setter boom") end
res = C.Merge(e.reg, e.store, assert(C.Decode("GPS1\nV\ton.flag\t9\tP-1\t1\tb1")), apply)
eq(#res.skipped, 1, "a throwing setter is skipped")
eq(e.store.stamps["on.flag"], nil, "  and its stamp isn't taken")

-- Local stamps: the counter climbs and survives as saved data.
local f = client()
local s1, s2 = C.Stamp(f.store, 10, "P-1"), C.Stamp(f.store, 10, "P-1")
eq(C.Compare(s2, s1), 1, "two changes in one second are ordered by the counter")
eq(f.store.seq, 2, "  saved in the store")

-- Clean: junk from an older or damaged save goes, the rest stays.
local junk = C.Clean({
    stamps = { ["on.flag"] = stamp(1), ["bad id"] = stamp(1), ["on.x"] = { t = "x" } },
    sets = { ["bf.keep"] = { [5] = { a = 1, t = 1, o = "P-1", s = 1 }, [6] = { a = 2, t = 1, o = "P-1", s = 1 } },
             ["bad set"] = {} },
    foreign = { ["n.k"] = { v = "b1", t = 1, o = "P-1", s = 1 }, ["n.j"] = { v = "zz", t = 1, o = "P-1", s = 1 } },
    seq = -4,
})
check(junk.stamps["on.flag"] and not junk.stamps["bad id"] and not junk.stamps["on.x"], "Clean: stamps")
check(junk.sets["bf.keep"][5] and not junk.sets["bf.keep"][6] and not junk.sets["bad set"], "Clean: sets")
check(junk.foreign["n.k"] and not junk.foreign["n.j"], "Clean: unknown keys")
eq(junk.seq, 0, "Clean: the counter")

done("test_sync_core")
