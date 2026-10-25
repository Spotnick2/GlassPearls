-- SettingsSync between several clients (#4): crossing edits converge, the
-- same second resolves the same way everywhere, a removal can't be
-- resurrected by a peer that was away, a late peer catches up, a newer
-- version's key is relayed by an older one, and replies never loop.
-- Each client runs the live layer's rules over the core: a local change
-- stamps and broadcasts; a receipt merges and replies only when it holds
-- something newer (SettingsSync.Receive). The test owns delivery order.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local C = GP.SettingsSync.Core

local net = { clients = {}, queue = {}, sent = 0, online = {} }

local function newClient(guid, opts)
    opts = opts or {}
    local cl = { guid = guid, values = { flag = false, size = 3, mode = "grey" } }
    cl.reg = { keys = {}, sets = { ["bf.keep"] = {} } }
    local function spec(kind, name, extra)
        local s = { kind = kind, get = function() return cl.values[name] end, set = function(v) cl.values[name] = v end }
        for k, v in pairs(extra or {}) do s[k] = v end
        return s
    end
    cl.reg.keys["on.flag"] = spec("bool", "flag")
    cl.reg.keys["bf.size"] = spec("int", "size", { min = 0, max = 100 })
    cl.reg.keys["bf.mode"] = spec("enum", "mode", { allowed = { grey = true, white = true } })
    if opts.newer then   -- a newer version knows one more key
        cl.values.thing = "a"
        cl.reg.keys["new.thing"] = spec("enum", "thing", { allowed = { a = true, b = true } })
    end
    cl.store = C.Clean({})
    net.clients[#net.clients + 1] = cl
    net.online[cl] = true
    return cl
end

local function broadcast(from)
    if not net.online[from] then return end
    local body = C.Encode(from.reg, from.store)
    for _, to in ipairs(net.clients) do
        if to ~= from and net.online[to] then
            net.queue[#net.queue + 1] = { to = to, body = body }
        end
    end
    net.sent = net.sent + 1
end

-- A local edit at time t: set, stamp, send.
local function edit(cl, key, name, value, t)
    cl.values[name] = value
    cl.store.stamps[key] = C.Stamp(cl.store, t, cl.guid)
    broadcast(cl)
end
local function setEdit(cl, member, present, t)
    local st = C.Stamp(cl.store, t, cl.guid)
    cl.store.sets["bf.keep"] = cl.store.sets["bf.keep"] or {}
    cl.store.sets["bf.keep"][member] = { a = present and 1 or 0, t = st.t, o = st.o, s = st.s }
    broadcast(cl)
end

-- A receipt merges and, when this client holds something newer, marks a
-- reply pending: the live layer's reply is a debounced schedule that a newer
-- one replaces (SettingsSync.Receive -> schedule), so several receipts in
-- the debounce give ONE send. Replying per message instead multiplies
-- crossing replies across a mesh (found by scenario 7).
local function receive(msg)
    local cl = msg.to
    if not net.online[cl] then return end
    local rec = assert(C.Decode(msg.body))
    local res = C.Merge(cl.reg, cl.store, rec, function(spec, v) spec.set(v) end)
    if res.newerHere then cl.pending = true end
end

-- The debounce fires: each pending client sends once.
local function flush()
    local any = false
    for _, cl in ipairs(net.clients) do
        if cl.pending then
            cl.pending = false
            broadcast(cl)
            any = true
        end
    end
    return any
end

-- Deliver everything queued, in order (or reversed), let the debounces fire,
-- and repeat until quiet. Returns the number delivered; errors if it never
-- goes quiet.
local function drain(reverse)
    local n = 0
    repeat
        while #net.queue > 0 do
            local msg = reverse and table.remove(net.queue) or table.remove(net.queue, 1)
            receive(msg)
            n = n + 1
            assert(n < 2000, "the network never went quiet")
        end
    until not flush() and #net.queue == 0
    return n
end

local function same(a, b, keys)
    for _, k in ipairs(keys) do
        if a.values[k] ~= b.values[k] then return false end
    end
    return C.Encode(a.reg, a.store) == C.Encode(b.reg, b.store)
end

local A = newClient("Player-1-AAA")
local B = newClient("Player-1-BBB")
local KEYS = { "flag", "size", "mode" }

-- 1. One edit: it arrives, and nobody replies.
edit(A, "on.flag", "flag", true, 10)
eq(drain(), 1, "one edit: one delivery")
eq(B.values.flag, true, "  it arrived")
eq(net.sent, 1, "  no reply")

-- 2. Crossing edits of different keys: both survive, and it goes quiet.
net.sent = 0
edit(A, "bf.size", "size", 7, 20)
edit(B, "bf.mode", "mode", "white", 20)
local delivered = drain()
check(A.values.mode == "white" and A.values.size == 7, "A has both edits")
check(B.values.mode == "white" and B.values.size == 7, "B has both edits")
check(same(A, B, KEYS), "  identical states")
check(delivered <= 4, "  at most one reply each (" .. delivered .. " deliveries)")

-- 3. The same key in the same second: the same winner everywhere (higher origin).
edit(A, "bf.size", "size", 5, 30)
edit(B, "bf.size", "size", 6, 30)
drain(true)
eq(A.values.size, 6, "same second: B's value (the higher origin) on A")
eq(B.values.size, 6, "  and on B")
check(same(A, B, KEYS), "  identical states")

-- 4. A removal while a peer is away can't be resurrected by it.
setEdit(A, 2589, true, 40)
drain()
eq(B.store.sets["bf.keep"][2589].a, 1, "the item reached B")
net.online[B] = false
setEdit(A, 2589, false, 50)
drain()
eq(B.store.sets["bf.keep"][2589].a, 1, "B was away: it still has the item")
net.online[B] = true
broadcast(B)   -- B's login send, with its stale add
drain()
eq(A.store.sets["bf.keep"][2589].a, 0, "B's stale add doesn't bring the item back on A")
eq(B.store.sets["bf.keep"][2589].a, 0, "  and A's reply removes it on B")
check(same(A, B, KEYS), "  identical states")

-- 5. A late peer with nothing catches up from one reply.
local Cl = newClient("Player-1-CCC")
net.sent = 0
broadcast(Cl)   -- its login send (empty)
drain()
check(same(A, Cl, KEYS) and same(B, Cl, KEYS), "the late peer has everything")
check(net.sent <= 3, "  from a reply each, no more (" .. net.sent .. " sends)")

-- 6. A newer version's key passes through an older client untouched.
local N = newClient("Player-2-NNN", { newer = true })
local N2 = newClient("Player-2-OOO", { newer = true })
net.online[N2] = false
edit(N, "new.thing", "thing", "b", 60)
drain()
eq(A.values.thing, nil, "the older client never applies it")
check(A.store.foreign["new.thing"] ~= nil, "  but keeps it")
net.online[N] = false
net.online[N2] = true
broadcast(N2)   -- N2 logs in later; only the older clients are around
drain()
eq(N2.values.thing, "b", "a newer client gets it from the older ones")
eq(N2.store.stamps["new.thing"].o, "Player-2-NNN", "  with its origin's stamp")
net.online[N] = true

-- 7. Many random edits in random order: everyone converges, and it goes quiet.
math.randomseed(42)
local live = { A, B, Cl }
for i = 1, 60 do
    local cl = live[math.random(#live)]
    local r = math.random(4)
    local t = 100 + math.floor(i / 3)   -- several edits share a second
    if r == 1 then edit(cl, "on.flag", "flag", math.random(2) == 1, t)
    elseif r == 2 then edit(cl, "bf.size", "size", math.random(0, 100), t)
    elseif r == 3 then edit(cl, "bf.mode", "mode", math.random(2) == 1 and "grey" or "white", t)
    else setEdit(cl, math.random(1, 20), math.random(2) == 1, t) end
    if math.random(3) == 1 and #net.queue > 0 then
        -- deliver a random subset now, the rest later (messages overtake
        -- each other); sometimes a debounce fires in between
        for _ = 1, math.random(#net.queue) do
            if #net.queue == 0 then break end
            receive(table.remove(net.queue, math.random(#net.queue)))
        end
        if math.random(2) == 1 then flush() end
    end
end
local before = net.sent
local n = drain()
check(same(A, B, KEYS) and same(B, Cl, KEYS), "60 random edits: all three converge")
check(same(N, A, KEYS) and same(N2, A, KEYS), "  and the two newer clients too")
check(n < 2000, "  and it went quiet (" .. n .. " deliveries, " .. (net.sent - before) .. " sends after the edits)")

done("test_sync_two")
