-- SettingsSync.lua: your GlassPearls settings on your other WoW accounts,
-- automatically (#4). Through AccountSync.lua's LibAccountSync-1.0 link
-- (the reason it's embedded: the owner wants settings in sync), payload kind
-- "ST". The plan (docs/PLAN.md, M1) was reviewed adversarially to consensus.
--
-- What travels: a registry of keys (`Register`): every pearl's on/off, each
-- pearl's own settings, "Use Glass UI appearance"; and sets (`RegisterSet`),
-- such as a pearl's keep list. Never per-character data, never the sync
-- store itself (GlassPearlsSyncDB holds the household key).
--
-- Per-key last-writer-wins, not whole snapshots. A local change stamps its
-- key { t = GetServerTime(), o = this character's GUID, s = a saved counter }.
-- The order is t, then o, then s: a total order every client computes the
-- same way, so all converge on the same winner. A key never changed has no
-- stamp and loses to any. A relayed value keeps its origin's stamp. A set
-- stamps each member; a removal is a tombstone kept forever (no expiry, so a
-- returning peer can't resurrect it), and growth is refused at the cap
-- instead. A key from a newer version is kept verbatim (within its limits),
-- merged by the same order and relayed, never applied, until a version that
-- knows it adopts it.
--
-- Sends are full, freshly encoded snapshots (LibAccountSync replaces a
-- sender's older snapshot with a newer one): after a local change (2 s
-- debounce), at login (+5 s), when a new peer appears (checked every 60 s),
-- and on a refused send a retry with backoff. Receiving applies through the
-- same setters the options use, with stamping and sending suppressed; it
-- replies only when this client holds something strictly newer, so a reply
-- never causes another (after a merge both hold the same per-key maxima).
--
-- Budget (each part capped where data is accepted, so the sum fits the
-- 32 KB wire ceiling; test_sync_budget fills every part with the longest
-- values): known keys <= 4 KB (asserted on the real registry); set entries
-- <= 300 in all sets together, each line <= 69 B (~20.7 KB); unknown keys
-- <= 32, each line <= 155 B (~5 KB); up to 8 set headers and the format line < 0.4 KB.
--
-- Format "GPS1", one record per line, tab-separated, data never run:
--   GPS1
--   V <id> <t> <origin> <seq> <value>        b0|b1, i<int>, e<text>
--   S <set>                                   the set the M lines below belong to
--   M <member> <0|1> <t> <origin> <seq>

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local SS = {}
GP.SettingsSync = SS

SS.KIND = "ST"
SS.FORMAT = "GPS1"
SS.WIRE_MAX = 32768          -- LibAccountSync's ceiling (AccountSync.lua asks for it)
SS.BUDGET = 31 * 1024        -- what an encoded snapshot may use
SS.ID_MAX, SS.ORIGIN_MAX, SS.VALUE_MAX = 32, 32, 64
SS.SET_MAX = 300             -- entries in all sets together, members and tombstones
SS.SETS_MAX = 8                -- sets; the 300 entries are shared, so more sets cost only their headers (raised before v0.1.0, #15)
SS.FOREIGN_MAX = 32
SS.KNOWN_MAX = 128           -- V lines for known keys
SS.DEBOUNCE, SS.LOGIN_DELAY, SS.PEER_CHECK = 2, 5, 60
SS.BACKOFF = { 30, 60, 120, 240 }

local function finiteInt(n, lo, hi)
    return type(n) == "number" and n == n and n == math.floor(n) and n >= lo and n <= hi
end

-- An integer as text, exactly. Not "%d": Lua 5.1 formats it through a C int,
-- which is 32 bits on Windows, so 9999999999 came out as -2147483648
-- (found by test_sync_budget). "%.0f" is exact up to 2^53.
local function intText(n) return string.format("%.0f", n) end
--------------------------------------------------------------------------------
-- The core: pure functions over a registry and a store, so two clients can
-- be tested against each other in one Lua state.
--   reg   = { keys = { [id] = spec }, sets = { [id] = setSpec } }
--   store = { stamps = { [id] = stamp }, sets = { [id] = { [member] = entry } },
--             foreign = { [id] = { v = valueText, t, o, s } }, seq = n }
--   stamp = { t = int, o = guid, s = int }; entry = { a = 0|1, t, o, s }
--------------------------------------------------------------------------------

local Core = {}
SS.Core = Core

-- 1 when a is newer than b, -1 when older, 0 when the same stamp. A missing
-- stamp is the oldest of all.
function Core.Compare(a, b)
    if a == nil then return b == nil and 0 or -1 end
    if b == nil then return 1 end
    if a.t ~= b.t then return a.t > b.t and 1 or -1 end
    if a.o ~= b.o then return a.o > b.o and 1 or -1 end
    if a.s ~= b.s then return a.s > b.s and 1 or -1 end
    return 0
end

local function validId(id)
    return type(id) == "string" and #id <= SS.ID_MAX and id:match("^[%w_]+%.[%w_.]+$") ~= nil
end
Core.ValidId = validId

local function validOrigin(o)
    return type(o) == "string" and #o >= 1 and #o <= SS.ORIGIN_MAX and o:match("^[%w%-]+$") ~= nil
end

local function validStamp(st)
    return type(st) == "table" and finiteInt(st.t, 0, 9999999999) and validOrigin(st.o)
        and finiteInt(st.s, 0, 999999999)
end
Core.ValidStamp = validStamp

-- A plain value text: no control characters, no "|" (chat escapes), no tab.
local function plainText(v)
    return type(v) == "string" and #v <= SS.VALUE_MAX and not v:find("[%c|]")
end

-- A spec's value to its text, or nil when the value isn't valid for it.
function Core.EncodeValue(spec, v)
    if spec.kind == "bool" then
        if type(v) ~= "boolean" then return nil end
        return v and "b1" or "b0"
    elseif spec.kind == "int" then
        if not finiteInt(v, spec.min or -999999999, spec.max or 999999999) then return nil end
        return "i" .. intText(v)
    elseif spec.kind == "enum" then
        if type(v) ~= "string" or not spec.allowed[v] or not plainText(v) then return nil end
        return "e" .. v
    end
end

-- A value text to the spec's value, or nil when it isn't valid for it.
function Core.DecodeValue(spec, text)
    if type(text) ~= "string" then return nil end
    local tag, rest = text:sub(1, 1), text:sub(2)
    if spec.kind == "bool" and tag == "b" and (rest == "0" or rest == "1") then
        return rest == "1"
    elseif spec.kind == "int" and tag == "i" and rest:match("^%-?%d+$") and #rest <= 10 then
        local n = tonumber(rest)
        if finiteInt(n, spec.min or -999999999, spec.max or 999999999) then return n end
    elseif spec.kind == "enum" and tag == "e" and spec.allowed[rest] then
        return rest
    end
end

-- A value text of any kind, as a key this copy doesn't know may carry.
local function validValueText(text)
    if type(text) ~= "string" or #text < 2 or #text > SS.VALUE_MAX + 1 then return false end
    local tag, rest = text:sub(1, 1), text:sub(2)
    if tag == "b" then return rest == "0" or rest == "1" end
    if tag == "i" then return rest:match("^%-?%d+$") ~= nil and #rest <= 10 end
    if tag == "e" then return plainText(rest) end
    return false
end

local function stampText(st) return intText(st.t) .. "\t" .. st.o .. "\t" .. intText(st.s) end

-- The snapshot: every stamped known key with its current value, every set
-- entry, every kept foreign key. Sorted, so equal states encode equally.
function Core.Encode(reg, store)
    local lines = { SS.FORMAT }
    -- Known and relayed keys in one sorted list: a key reads the same whether
    -- this copy knows it or only relays it.
    local vals = {}
    for id, st in pairs(store.stamps) do
        local spec = reg.keys[id]
        if spec and validStamp(st) then
            local ok, v = pcall(spec.get)
            local text = ok and Core.EncodeValue(spec, v)
            if text then vals[#vals + 1] = { id = id, line = "V\t" .. id .. "\t" .. stampText(st) .. "\t" .. text } end
        end
    end
    for id, f in pairs(store.foreign) do
        if not reg.keys[id] and validStamp(f) and validValueText(f.v) then
            vals[#vals + 1] = { id = id, line = "V\t" .. id .. "\t" .. stampText(f) .. "\t" .. f.v }
        end
    end
    table.sort(vals, function(x, y) return x.id < y.id end)
    for _, v in ipairs(vals) do lines[#lines + 1] = v.line end
    local sids = {}
    for id in pairs(store.sets) do if reg.sets[id] then sids[#sids + 1] = id end end
    table.sort(sids)
    for _, id in ipairs(sids) do
        local members = {}
        for m, e in pairs(store.sets[id]) do
            if validStamp(e) then members[#members + 1] = m end
        end
        table.sort(members)
        if #members > 0 then lines[#lines + 1] = "S\t" .. id end
        for _, m in ipairs(members) do
            local e = store.sets[id][m]
            lines[#lines + 1] = "M\t" .. intText(m) .. "\t" .. (e.a == 1 and "1" or "0") .. "\t" .. stampText(e)
        end
    end
    return table.concat(lines, "\n")
end

-- Entries in all sets of a store.
local function setEntries(store)
    local n = 0
    for _, set in pairs(store.sets) do
        for _ in pairs(set) do n = n + 1 end
    end
    return n
end
Core.SetEntries = setEntries

-- The payload's records, all or nothing: nil and why for any malformed
-- line, a duplicate, or a cap passed.
function Core.Decode(body)
    if type(body) ~= "string" or API.IsSecret(body) then return nil, "not a string" end
    if #body > SS.WIRE_MAX then return nil, "too large" end
    local values, members = {}, {}
    local seenV, seenM, seenS = {}, {}, {}
    local nV, nM, nS, first, current = 0, 0, 0, true, nil
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if first then
            if line ~= SS.FORMAT then return nil, "not " .. SS.FORMAT end
            first = false
        else
            local f = {}
            for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
            if f[1] == "V" and #f == 6 then
                local st = { t = tonumber(f[3]), o = f[4], s = tonumber(f[5]) }
                if not validId(f[2]) or not f[3]:match("^%d+$") or not f[5]:match("^%d+$")
                    or not validStamp(st) or not validValueText(f[6]) then
                    return nil, "bad value line"
                end
                if seenV[f[2]] then return nil, "duplicate " .. f[2] end
                seenV[f[2]] = true
                nV = nV + 1
                if nV > SS.KNOWN_MAX + SS.FOREIGN_MAX then return nil, "too many values" end
                values[#values + 1] = { id = f[2], stamp = st, text = f[6] }
            elseif f[1] == "S" and #f == 2 then
                if not validId(f[2]) then return nil, "bad set line" end
                if seenS[f[2]] then return nil, "duplicate set " .. f[2] end
                seenS[f[2]] = true
                nS = nS + 1
                if nS > SS.SETS_MAX then return nil, "too many sets" end
                current = f[2]
            elseif f[1] == "M" and #f == 6 then
                if not current then return nil, "a member before its set" end
                local st = { t = tonumber(f[4]), o = f[5], s = tonumber(f[6]) }
                local m = tonumber(f[2])
                if not f[2]:match("^%d+$") or #f[2] > 10 or not (f[3] == "0" or f[3] == "1")
                    or not f[4]:match("^%d+$") or not f[6]:match("^%d+$") or not validStamp(st) then
                    return nil, "bad member line"
                end
                local key = current .. "#" .. f[2]
                if seenM[key] then return nil, "duplicate " .. key end
                seenM[key] = true
                nM = nM + 1
                if nM > SS.SET_MAX then return nil, "sets too large" end
                members[#members + 1] = { set = current, member = m, a = tonumber(f[3]), stamp = st }
            else
                return nil, "bad line"
            end
        end
    end
    if first then return nil, "empty" end
    return { values = values, members = members }
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
Core.Count = countKeys

-- Merge decoded records into the store. `apply(spec, value, id)` sets a known
-- key's value (the caller suppresses stamping). Returns a result:
--   applied (n), skipped ({ why... }), newerHere (this store holds an entry
--   strictly newer than the sender's, so it should reply).
function Core.Merge(reg, store, rec, apply)
    local res = { applied = 0, skipped = {}, newerHere = false }
    local theirs, theirMembers = {}, {}
    for _, v in ipairs(rec.values) do
        theirs[v.id] = v.stamp
        local spec = reg.keys[v.id]
        if spec then
            local value = Core.DecodeValue(spec, v.text)
            if value == nil then
                res.skipped[#res.skipped + 1] = v.id .. ": a value this copy can't take"
            elseif Core.Compare(v.stamp, store.stamps[v.id]) > 0 then
                local ok, err = pcall(apply, spec, value, v.id)
                if ok then
                    store.stamps[v.id] = { t = v.stamp.t, o = v.stamp.o, s = v.stamp.s }
                    res.applied = res.applied + 1
                else
                    res.skipped[#res.skipped + 1] = v.id .. ": " .. tostring(err)
                end
            end
        else
            local mine = store.foreign[v.id]
            if not mine and countKeys(store.foreign) >= SS.FOREIGN_MAX then
                res.skipped[#res.skipped + 1] = v.id .. ": unknown keys full"
            elseif Core.Compare(v.stamp, mine) > 0 then
                store.foreign[v.id] = { v = v.text, t = v.stamp.t, o = v.stamp.o, s = v.stamp.s }
            end
        end
    end
    for _, m in ipairs(rec.members) do
        local key = m.set .. "#" .. m.member
        theirMembers[key] = m.stamp
        local spec = reg.sets[m.set]
        if not spec then
            res.skipped[#res.skipped + 1] = m.set .. ": a set this copy doesn't know"
        elseif not finiteInt(m.member, spec.min or 1, spec.max or 2147483647) then
            res.skipped[#res.skipped + 1] = key .. ": a member this copy can't take"
        else
            local set = store.sets[m.set] or {}
            local mine = set[m.member]
            if not mine and setEntries(store) >= SS.SET_MAX then
                res.skipped[#res.skipped + 1] = m.set .. ": full"
            elseif Core.Compare(m.stamp, mine) > 0 then
                set[m.member] = { a = m.a, t = m.stamp.t, o = m.stamp.o, s = m.stamp.s }
                store.sets[m.set] = set
                res.applied = res.applied + 1
            end
        end
    end
    -- Anything here newer than what they sent (theirs missing = the oldest)?
    for id, st in pairs(store.stamps) do
        if reg.keys[id] and Core.Compare(st, theirs[id]) > 0 then res.newerHere = true end
    end
    for id, f in pairs(store.foreign) do
        if Core.Compare(f, theirs[id]) > 0 then res.newerHere = true end
    end
    for sid, set in pairs(store.sets) do
        if reg.sets[sid] then
            for m, e in pairs(set) do
                if Core.Compare(e, theirMembers[sid .. "#" .. m]) > 0 then res.newerHere = true end
            end
        end
    end
    return res
end

-- The time a seed stamp carries: before any real edit could have been made.
SS.SEED_TIME = 1

-- Seed what was chosen before this key synced (an upgrade, or a key a later
-- version starts syncing): every registered key without a stamp whose value
-- isn't its default gets a stamp at SEED_TIME. So the choice travels to an
-- account that never set it, while any real edit since (always later) wins
-- over it (Codex review of #8). Returns how many were seeded.
function Core.Seed(reg, store, origin)
    local n = 0
    local ids = {}
    for id in pairs(reg.keys) do ids[#ids + 1] = id end
    table.sort(ids)   -- a stable order for the sequence numbers
    for _, id in ipairs(ids) do
        local spec = reg.keys[id]
        if not store.stamps[id] and spec.default ~= nil then
            local ok, v = pcall(spec.get)
            if ok and v ~= spec.default and Core.EncodeValue(spec, v) then
                store.stamps[id] = Core.Stamp(store, SS.SEED_TIME, origin)
                n = n + 1
            end
        end
    end
    return n
end

-- A new stamp for a local change.
function Core.Stamp(store, now, origin)
    store.seq = (finiteInt(store.seq, 0, 999999998) and store.seq or 0) + 1
    return { t = now, o = origin, s = store.seq }
end

-- Drop what isn't valid (an older or damaged save); keep the rest.
function Core.Clean(store)
    if type(store.stamps) ~= "table" then store.stamps = {} end
    if type(store.sets) ~= "table" then store.sets = {} end
    if type(store.foreign) ~= "table" then store.foreign = {} end
    if not finiteInt(store.seq, 0, 999999999) then store.seq = 0 end
    for id, st in pairs(store.stamps) do
        if not validId(id) or not validStamp(st) then store.stamps[id] = nil end
    end
    for id, f in pairs(store.foreign) do
        if not validId(id) or not validStamp(f) or not validValueText(f.v) then store.foreign[id] = nil end
    end
    for sid, set in pairs(store.sets) do
        if not validId(sid) or type(set) ~= "table" then
            store.sets[sid] = nil
        else
            for m, e in pairs(set) do
                if not finiteInt(m, 0, 9999999999) or not validStamp(e) or (e.a ~= 0 and e.a ~= 1) then set[m] = nil end
            end
        end
    end
    return store
end

--------------------------------------------------------------------------------
-- The live layer: GlassPearls' registry and store, the link, the timers.
--------------------------------------------------------------------------------

local reg = { keys = {}, sets = {} }
SS.reg = reg
local applying = false
local status = { sent = nil, received = nil, error = nil }
SS.status = status
local generation, retryStep = 0, 0
local knownPeers = {}

local function say(msg) API.Print(msg) end

local function store()
    local db = GP.db
    return db and type(db.sync) == "table" and db.sync or nil
end

local function origin()
    local ok, guid = pcall(UnitGUID, "player")
    if ok and not API.IsSecret(guid) and validOrigin(guid) then return guid end
    return "unknown"
end

local function now()
    local ok, t = pcall(GetServerTime)
    if ok and finiteInt(t, 0, 9999999999) then return t end
    return 0
end

-- spec: { kind = "bool" | "int" | "enum", get = fn, set = fn(value),
--         min, max (int), values = { ... } (enum) }
function SS.Register(id, spec)
    if not validId(id) then return false end
    if type(spec) ~= "table" or type(spec.get) ~= "function" or type(spec.set) ~= "function" then return false end
    if spec.kind == "enum" then
        if type(spec.values) ~= "table" then return false end
        spec.allowed = {}
        for _, v in ipairs(spec.values) do spec.allowed[v] = true end
    elseif spec.kind ~= "bool" and spec.kind ~= "int" then
        return false
    end
    if countKeys(reg.keys) >= SS.KNOWN_MAX and not reg.keys[id] then return false end
    reg.keys[id] = spec
    return true
end

-- A set of item IDs (or other positive integers) that syncs member by member.
function SS.RegisterSet(id, spec)
    spec = spec or {}
    if not validId(id) then return false end
    if countKeys(reg.sets) >= SS.SETS_MAX and not reg.sets[id] then return false end
    reg.sets[id] = { min = spec.min or 1, max = spec.max or 2147483647 }
    return true
end

function SS.PearlOnId(key) return "on." .. key end
function SS.SettingId(key, name) return key .. "." .. name end

local schedule

-- A local change to a registered key: stamp it and send soon. Ignored while
-- applying a received value (it keeps the origin's stamp).
function SS.Touch(id)
    local st = store()
    if applying or not st or not reg.keys[id] then return end
    st.stamps[id] = Core.Stamp(st, now(), origin())
    schedule(SS.DEBOUNCE)
end

-- The sets, for the pearls that own them.
function SS.SetHas(id, member)
    local st = store()
    local e = st and st.sets[id] and st.sets[id][member]
    return e ~= nil and e.a == 1
end

function SS.SetMembers(id)
    local list, st = {}, store()
    for m, e in pairs(st and st.sets[id] or {}) do
        if e.a == 1 then list[#list + 1] = m end
    end
    table.sort(list)
    return list
end

local function setWrite(id, member, present)
    local st = store()
    local spec = reg.sets[id]
    if not st or not spec or not finiteInt(member, spec.min, spec.max) then return false, "invalid" end
    local set = st.sets[id] or {}
    local e = set[member]
    if (e and e.a == 1) == present then return true end   -- no change
    if not e and Core.SetEntries(st) >= SS.SET_MAX then return false, "full" end
    local stamp = Core.Stamp(st, now(), origin())
    set[member] = { a = present and 1 or 0, t = stamp.t, o = stamp.o, s = stamp.s }
    st.sets[id] = set
    schedule(SS.DEBOUNCE)
    return true
end

-- Add a member; false, "full" at the cap (a removed member's entry is reused).
function SS.SetAdd(id, member) return setWrite(id, member, true) end
function SS.SetRemove(id, member) return setWrite(id, member, false) end
function SS.SetClear(id)
    for _, m in ipairs(SS.SetMembers(id)) do setWrite(id, m, false) end
end

-- Apply a received value through the key's own setter, without stamping.
local function apply(spec, value)
    applying = true
    local ok, err = pcall(spec.set, value)
    applying = false
    if not ok then error(err, 0) end
end

local function report(text)
    status.error = text
    if GP.IsDev and GP.IsDev() then say("settings sync: " .. text) end
end

function SS.Encode() return Core.Encode(reg, store()) end

local function transient(why)
    -- "disabled" while the switch is on means Battle.net isn't usable yet.
    return why == "not-ready" or why == "no-peers" or why == "offline" or why == "no-route"
        or (why == "disabled" and GP.AccountSync.IsEnabled())
end

-- One retry per send attempt, however many of its destinations failed: the
-- next send carries the full snapshot to every peer anyway.
local function retry(attempt, why)
    if attempt.retried or not transient(why) then return end
    attempt.retried = true
    retryStep = retryStep + 1
    local delay = SS.BACKOFF[retryStep]
    if delay then schedule(delay, true) end   -- after the last, only the peer check sends
end

-- A destination's result, which LibAccountSync gives per peer: at once for a
-- peer whose handshake is still pending ("failed", "not-ready", and Send
-- returns 0), later for one the frames were handed to ("sent", or "failed"
-- with "offline" / "no-route"). Only "sent" ends the backoff; a peer that
-- failed is forgotten by the peer check, so its next appearance sends again
-- (Codex review of #8: a positive count isn't delivery).
local function onResult(attempt, sender, result, reason)
    local g = type(sender) == "table" and sender.guid
    if result == "sent" then
        attempt.sent = attempt.sent + 1
        if not attempt.retried then retryStep = 0 end
    elseif result == "failed" then
        attempt.failed = attempt.failed + 1
        if type(g) == "string" and not API.IsSecret(g) then knownPeers[g] = nil end
        retry(attempt, reason or "not-ready")
    end
end

function SS.SendNow()
    local st = store()
    if not st then return nil, "not-ready" end
    local body = Core.Encode(reg, st)
    if #body + #SS.KIND + 1 > SS.WIRE_MAX or #body > SS.BUDGET then
        report("snapshot too large (" .. #body .. " bytes), not sent")
        API.Fail("settings sync", "too large")
        status.sent = { t = now(), why = "too-large" }
        return nil, "too-large"
    end
    local attempt = { sent = 0, failed = 0 }
    status.attempt = attempt
    local n, why = GP.AccountSync.Send(SS.KIND, body, function(sender, result, reason)
        onResult(attempt, sender, result, reason)
    end)
    status.sent = { t = now(), n = n, why = why }
    if why then
        retry(attempt, why)
    elseif n == 0 then
        retry(attempt, "not-ready")   -- every peer's handshake still pending
    end
    return n, why
end

-- A send `delay` seconds from now; a newer schedule replaces it. A retry
-- keeps the backoff step, any other schedule restarts it.
schedule = function(delay, isRetry)
    if not isRetry then retryStep = 0 end
    generation = generation + 1
    local mine = generation
    C_Timer.After(delay, function()
        if mine == generation then SS.SendNow() end
    end)
end
SS.Schedule = schedule

function SS.Receive(body, sender)
    local st = store()
    if not st then return end
    local rec, why = Core.Decode(body)
    local name = type(sender) == "table" and not API.IsSecret(sender.name) and type(sender.name) == "string"
        and sender.name or "?"
    if not rec then
        report("ignored a snapshot from " .. name .. ": " .. why)
        return
    end
    local res = Core.Merge(reg, st, rec, apply)
    status.received = { t = now(), from = name, applied = res.applied, skipped = #res.skipped }
    if #res.skipped > 0 then report(#res.skipped .. " entries from " .. name .. " skipped: " .. res.skipped[1]) end
    if res.applied > 0 and GP.Options then GP.Options.Refresh() end
    if res.newerHere then schedule(SS.DEBOUNCE) end
    return res
end

-- Keys a newer version sent that this one knows now: adopt them.
local function adopt(st)
    for id, f in pairs(st.foreign) do
        local spec = reg.keys[id]
        if spec then
            local value = Core.DecodeValue(spec, f.v)
            if value ~= nil and Core.Compare(f, st.stamps[id]) > 0 then
                local ok = pcall(apply, spec, value)
                if ok then st.stamps[id] = { t = f.t, o = f.o, s = f.s } end
            end
            st.foreign[id] = nil
        end
    end
end

-- Register what the core and every pearl own. A pearl's setting syncs by its
-- default's type: boolean, integer, or a string with `choices[name]`.
local function registerAll()
    local P = GP.Pearls
    for _, def in ipairs(P.List()) do
        local key = def.key
        SS.Register(SS.PearlOnId(key), { kind = "bool", default = def.default,
            get = function() return P.IsOn(key) end, set = function(v) P.Set(key, v) end })
        for name, d in pairs(def.defaults) do
            local id = SS.SettingId(key, name)
            local spec = { default = d,
                get = function() return P.Setting(key, name) end,
                set = function(v) P.SetSetting(key, name, v) end,
            }
            if type(d) == "boolean" then
                spec.kind = "bool"
            elseif type(d) == "number" and d == math.floor(d) then
                spec.kind = "int"
                local range = def.ranges and def.ranges[name]
                if range then spec.min, spec.max = range[1], range[2] end
            elseif type(d) == "string" and def.choices and type(def.choices[name]) == "table" then
                spec.kind, spec.values = "enum", def.choices[name]
            end
            if not (spec.kind and SS.Register(id, spec)) then API.Fail("settings sync " .. id, "not synced") end
        end
    end
    SS.Register("core.glassui", { kind = "bool", default = true,
        get = function() return GP.db.useGlassUI ~= false end,
        set = function(v) GP.Settings.SetUseGlassUI(v) end })
end

local function checkPeers()
    local inst = GP.AccountSync.inst
    if not inst or type(inst.Peers) ~= "function" then return end
    local ok, peers = pcall(inst.Peers)
    if not ok or type(peers) ~= "table" then return end
    -- The peers seen now replace those seen before: one that left and comes
    -- back is new again (Codex review of #8).
    local seen, fresh = {}, false
    for _, p in ipairs(peers) do
        local g = type(p) == "table" and p.guid
        if type(g) == "string" and not API.IsSecret(g) then
            seen[g] = true
            if not knownPeers[g] then fresh = true end
        end
    end
    for g in pairs(knownPeers) do knownPeers[g] = nil end
    for g in pairs(seen) do knownPeers[g] = true end
    if fresh then schedule(1) end
end

-- Sharing turned back on (AccountSync.SetEnabled): every peer counts as new
-- again, and the current snapshot goes out after the debounce, carrying what
-- changed while sharing was off.
function SS.SharingResumed()
    for g in pairs(knownPeers) do knownPeers[g] = nil end
    if store() then schedule(SS.DEBOUNCE) end
end

-- At PLAYER_LOGIN, from GlassPearls.lua: every pearl is registered by now.
function SS.Start()
    local st = store()
    if not st then return end
    registerAll()
    adopt(st)
    Core.Seed(reg, st, origin())
    GP.AccountSync.On(SS.KIND, function(body, sender) SS.Receive(body, sender) end)
    schedule(SS.LOGIN_DELAY)
    if C_Timer.NewTicker then C_Timer.NewTicker(SS.PEER_CHECK, checkPeers) end
end

local function ago(t)
    local d = now() - (t or 0)
    if d < 60 then return d .. " s ago" end
    if d < 3600 then return math.floor(d / 60) .. " min ago" end
    return math.floor(d / 3600) .. " h ago"
end

function SS.Lines()
    local lines = {}
    local s, r = status.sent, status.received
    lines[#lines + 1] = "settings: last sent " .. (s and (ago(s.t) .. (s.n and s.n > 0 and (" to " .. s.n .. " account(s)")
        or (" (" .. tostring(s.why) .. ")"))) or "never")
    lines[#lines + 1] = "settings: last received " .. (r and (ago(r.t) .. " from " .. r.from .. ", " .. r.applied
        .. " applied" .. (r.skipped > 0 and (", " .. r.skipped .. " skipped") or "")) or "never")
    if status.error then lines[#lines + 1] = "settings: " .. status.error end
    return lines
end

SS._test = {
    reset = function()
        for k in pairs(reg.keys) do reg.keys[k] = nil end
        for k in pairs(reg.sets) do reg.sets[k] = nil end
        generation, retryStep, applying = 0, 0, false
        for k in pairs(knownPeers) do knownPeers[k] = nil end
        status.sent, status.received, status.error = nil, nil, nil
    end,
    retryStep = function() return retryStep end,
    checkPeers = checkPeers,
}
