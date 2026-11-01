-- SettingsSync's live layer (#4), through the real addon: what registers,
-- stamping on a real change only, the debounced send, applying a received
-- snapshot without re-stamping, the reply rule, sets, retries, the budget,
-- new peers, the login send, adopting a newer version's key, /gpearls sync.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ME = WoW.playerGUID   -- "Player-1-AAA"
local GP = loadAddon({
    -- A relayed key a newer version sent, newer than anything here: adopted at login.
    db = { sync = { foreign = { ["on.alpha"] = { v = "b1", t = 50, o = "Player-7-NEW", s = 2 } } } },
    before = function(GP)
        local R = GP.Pearls.Register
        R({ key = "alpha", name = "Alpha", Enable = function() end, Disable = function() end })
        R({ key = "beta", name = "Beta", Enable = function() end, Disable = function() end,
            defaults = { mode = "grey", size = 3, greys = true, label = "x" },
            choices = { mode = { "grey", "white" } }, ranges = { size = { 0, 10 } } })
        GP.SettingsSync.RegisterSet("beta.keep")
    end,
})
local SS, P, AS = GP.SettingsSync, GP.Pearls, GP.AccountSync
local store = GP.db.sync

-- What registers: each pearl's on/off, its settings by type, the look choice.
for _, id in ipairs({ "on.alpha", "on.beta", "beta.mode", "beta.size", "beta.greys", "core.glassui" }) do
    check(SS.reg.keys[id] ~= nil, "registered: " .. id)
end
eq(SS.reg.keys["beta.mode"].kind, "enum", "a string setting with choices is an enum")
eq(SS.reg.keys["beta.size"].max, 10, "an integer setting takes its range")
eq(SS.reg.keys["beta.label"], nil, "a string setting without choices doesn't sync")
check(GP.failures["settings sync beta.label"] ~= nil, "  and says so")
check(SS.reg.sets["beta.keep"] ~= nil, "the pearl's set")
-- The link asks for the wire ceiling the budget is sized to (the library's
-- default is 16 KB: a full snapshot would come back too-large).
eq(AS.inst.maxPayload, 32768, "the sync instance's payload ceiling is 32 KB")

-- Adopted at login: the relayed key, now known, newer than nothing here.
check(P.IsOn("alpha"), "a relayed key this version knows is adopted")
eq(store.stamps["on.alpha"] and store.stamps["on.alpha"].o, "Player-7-NEW", "  with its origin's stamp")
eq(store.foreign["on.alpha"], nil, "  and leaves the relayed keys")

-- Capture what the link is asked to send.
-- Results given synchronously during Send (a pending handshake) come from
-- `syncResults`; a later result is given through the recorded callback.
local sends, nextResult, syncResults = {}, { 1 }, nil
AS.Send = function(kind, body, cb)
    sends[#sends + 1] = { kind = kind, body = body, cb = cb }
    for _, r in ipairs(syncResults or {}) do cb(r[1], r[2], r[3]) end
    return unpack(nextResult)
end

-- The login send (5 s after PLAYER_LOGIN).
WoW.flushTimers(SS.LOGIN_DELAY)
eq(#sends, 1, "a snapshot goes out at login")
eq(sends[1].kind, "ST", "  as kind ST")
check(sends[1].body:find("^GPS1"), "  in format GPS1")
sends = {}

-- A real change stamps its key with this character and sends after the debounce.
P.Set("beta", true)
local st = store.stamps["on.beta"]
check(st ~= nil and st.o == ME, "switching a pearl stamps it with this character's GUID")
eq(#sends, 0, "  nothing sent at once")
local s1 = st.s
P.SetSetting("beta", "size", 7)
check(store.stamps["beta.size"].s > s1, "a second change gets a higher sequence")
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 1, "two changes in the debounce: one send")
check(sends[1].body:find("V\ton.beta\t", 1, true) and sends[1].body:find("V\tbeta.size\t", 1, true), "  carrying both")
sends = {}

-- No change, no stamp.
local before = store.stamps["on.beta"].s
P.Set("beta", true)
P.SetSetting("beta", "size", 7)
eq(store.stamps["on.beta"].s, before, "setting the same value again doesn't stamp")
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 0, "  nor send")
check(not P.SetSetting("beta", "size", "7"), "a value of the wrong type is refused")

-- The look choice syncs too.
GP.Settings.SetUseGlassUI(false)
check(store.stamps["core.glassui"] ~= nil, "'Use Glass UI appearance' is stamped")
GP.Settings.SetUseGlassUI(true)
WoW.flushTimers(SS.DEBOUNCE)
sends = {}

-- Receiving: a peer's newer values applied through the same setters, keeping
-- the peer's stamps, without stamping or sending in turn.
local peer = { name = "Alt", guid = "Player-1-BBB" }
local function deliver(body) AS._test.dispatch("ST\n" .. body, peer, 1) end
local hi = store.stamps["on.beta"].t + 100
GP.Options.Open("cat:Miscellaneous")
local row
for _, p in ipairs(GP.Options._test.pages["cat:Miscellaneous"].placed) do if p.key == "alpha" then row = p.row end end
check(row.check:GetChecked(), "the window shows Alpha on")
local body = table.concat({ "GPS1",
    "V\tbeta.mode\t" .. hi .. "\tPlayer-1-BBB\t1\tewhite",
    "V\tbeta.size\t" .. hi .. "\tPlayer-1-BBB\t2\ti7",
    "V\ton.alpha\t" .. hi .. "\tPlayer-1-BBB\t3\tb0",
    "V\ton.beta\t" .. hi .. "\tPlayer-1-BBB\t4\tb1",
    "V\tcore.glassui\t" .. hi .. "\tPlayer-1-BBB\t5\tb1",
    "S\tbeta.keep", "M\t2589\t1\t" .. hi .. "\tPlayer-1-BBB\t6" }, "\n")
deliver(body)
eq(P.Setting("beta", "mode"), "white", "a received setting is applied")
check(not P.IsOn("alpha"), "a received switch is applied")
check(not row.check:GetChecked(), "  and the open window shows it")
eq(store.stamps["beta.mode"].o, "Player-1-BBB", "  the peer's stamp is kept, not re-stamped here")
check(SS.SetHas("beta.keep", 2589), "a received set member")
eq(SS.status.received.from, "Alt", "the status names the sender")
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 0, "nothing newer here: no reply")
GP.Options._test.win():Hide()

-- A key the peer doesn't have that we stamped: reply.
P.SetSetting("beta", "greys", false)
WoW.flushTimers(SS.DEBOUNCE)
sends = {}
deliver(body)
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 1, "holding something newer than the peer's snapshot: one reply")
sends = {}

-- A malformed snapshot changes nothing and is noted.
deliver("GPS1\nV\tbeta.size\tbad")
eq(P.Setting("beta", "size"), 7, "a malformed snapshot changes nothing")
check(SS.status.error and SS.status.error:find("ignored", 1, true), "  and the status says why")

-- Sets: add, has, members, remove (a tombstone stays), the cap.
check(SS.SetAdd("beta.keep", 4306), "SetAdd")
check(SS.SetHas("beta.keep", 4306), "  SetHas")
eq(table.concat(SS.SetMembers("beta.keep"), ","), "2589,4306", "  SetMembers, sorted")
SS.SetRemove("beta.keep", 4306)
check(not SS.SetHas("beta.keep", 4306), "SetRemove")
eq(store.sets["beta.keep"][4306].a, 0, "  leaves a tombstone")
check(not SS.SetAdd("beta.keep", -1), "an invalid member is refused")
check(not SS.SetAdd("nope.set", 1), "an unknown set is refused")
for i = 1, SS.SET_MAX do store.sets["beta.keep"][100000 + i] = { a = 0, t = 1, o = ME, s = i } end
local ok, why = SS.SetAdd("beta.keep", 999)
check(not ok and why == "full", "at the cap a new member is refused")
check(SS.SetAdd("beta.keep", 4306), "  a removed member's entry is reused")
for i = 1, SS.SET_MAX do store.sets["beta.keep"][100000 + i] = nil end
WoW.flushTimers(SS.DEBOUNCE)
sends = {}

-- Set listeners: told after a local change that changed the set, and after a
-- received one; not for a no-op.
local told = 0
SS.OnSetChanged("beta.keep", function() told = told + 1 end)
SS.SetAdd("beta.keep", 7001)
eq(told, 1, "OnSetChanged: a local add")
SS.SetAdd("beta.keep", 7001)
eq(told, 1, "  adding it again: no change, not told")
SS.SetRemove("beta.keep", 7001)
eq(told, 2, "  a local remove")
deliver("GPS1\nS\tbeta.keep\nM\t7002\t1\t" .. (hi + 50) .. "\tPlayer-1-BBB\t9")
eq(told, 3, "  a received member")
check(SS.SetHas("beta.keep", 7002), "  (applied)")
deliver("GPS1\nS\tbeta.keep\nM\t7002\t1\t" .. (hi + 50) .. "\tPlayer-1-BBB\t9")
eq(told, 3, "  the same snapshot again: not told")
SS.SetRemove("beta.keep", 7002)
WoW.flushTimers(SS.DEBOUNCE)
sends = {}

-- Retries: a refused send backs off (30 s, 1, 2, 4 min), then waits for the peer check.
nextResult = { nil, "no-peers" }
P.SetSetting("beta", "size", 2)
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 1, "the send was tried")
for i, delay in ipairs(SS.BACKOFF) do
    WoW.flushTimers(delay - 1)
    eq(#sends, i, "  no retry before " .. delay .. " s")
    WoW.flushTimers(delay)
    eq(#sends, i + 1, "  retry " .. i .. " after " .. delay .. " s")
end
WoW.flushTimers()
eq(#sends, #SS.BACKOFF + 1, "after the last retry, nothing more until a peer appears")
-- Still failing: a new local change starts the backoff over from 30 s.
P.SetSetting("beta", "size", 4)
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, #SS.BACKOFF + 2, "a new change is tried")
WoW.flushTimers(SS.BACKOFF[1])
eq(#sends, #SS.BACKOFF + 3, "  and retried after " .. SS.BACKOFF[1] .. " s again (the backoff restarted)")
nextResult = { 1 }
WoW.flushTimers()
sends = {}
-- A send refused because sharing is off isn't retried.
nextResult = { nil, "disabled" }
AS.SetEnabled(false)
P.SetSetting("beta", "size", 3)
WoW.flushTimers(SS.DEBOUNCE)
WoW.flushTimers()
eq(#sends, 1, "sharing off: tried once, never retried")
nextResult = { 1 }
sends = {}

-- Sharing back on sends what changed while it was off, even to a peer the
-- peer check already knew (Codex review of #8).
AS.SetEnabled(true)
WoW.flushTimers()
sends = {}
AS.inst.Peers = function() return { { guid = "Player-1-CCC", name = "Third" } } end
SS._test.checkPeers()
WoW.flushTimers()
sends = {}
SS._test.checkPeers()
WoW.flushTimers()
eq(#sends, 0, "a known peer: nothing (the setup)")
AS.SetEnabled(false)
P.SetSetting("beta", "size", 2)
WoW.flushTimers()
sends = {}
AS.SetEnabled(true)
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 1, "sharing back on: a snapshot, without waiting for a peer to leave and return")
check(sends[1] and sends[1].body:find("V\tbeta.size\t[^\n]*\ti2"), "  carrying the change made while it was off")
AS.SetEnabled(true)
WoW.flushTimers()
eq(#sends, 1, "  switching on when already on sends nothing more")
AS.inst.Peers = function() return {} end
SS._test.checkPeers()
sends = {}

-- A new peer gets our snapshot (the 60 s check).
AS.inst.Peers = function() return { { guid = "Player-1-CCC", name = "Third" } } end
SS._test.checkPeers()
WoW.flushTimers(1)
eq(#sends, 1, "a new peer: a snapshot")
SS._test.checkPeers()
WoW.flushTimers()
eq(#sends, 1, "  a known peer: nothing")
-- A peer that leaves and comes back is new again (Codex review of #8).
AS.inst.Peers = function() return {} end
SS._test.checkPeers()
WoW.flushTimers()
eq(#sends, 1, "a peer leaving: nothing")
AS.inst.Peers = function() return { { guid = "Player-1-CCC", name = "Third" } } end
SS._test.checkPeers()
WoW.flushTimers(1)
eq(#sends, 2, "  coming back: a snapshot again")
sends = {}

-- Delivery is per peer, and a positive count isn't delivery (Codex review of #8).
local third = { guid = "Player-1-CCC", name = "Third" }
-- Every peer's handshake pending: Send gives "failed"/"not-ready" at once and returns 0.
syncResults, nextResult = { { third, "failed", "not-ready" } }, { 0 }
P.SetSetting("beta", "size", 5)
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 1, "the send was tried")
eq(SS._test.retryStep(), 1, "  a pending handshake schedules one retry, not two")
WoW.flushTimers(SS.BACKOFF[1])
eq(#sends, 2, "  retried after " .. SS.BACKOFF[1] .. " s")
syncResults, nextResult = nil, { 1 }
WoW.flushTimers()
sends = {}
-- Handed to the wire (Send returns 1), then the frames fail: retry, and the
-- peer is forgotten so its next appearance sends again.
P.SetSetting("beta", "size", 6)
WoW.flushTimers(SS.DEBOUNCE)
eq(#sends, 1, "handed to the wire")
eq(SS._test.retryStep(), 0, "  a positive count alone doesn't count as delivered (no retry yet, no reset either)")
sends[1].cb(third, "failed", "offline")
eq(SS._test.retryStep(), 1, "  a later 'failed offline' schedules a retry")
sends[1].cb(third, "failed", "offline")
eq(SS._test.retryStep(), 1, "  once per attempt")
-- The retry is handed to the wire too (a positive count): still not delivery.
WoW.flushTimers(SS.BACKOFF[1])
eq(#sends, 2, "  the retry goes out")
eq(SS._test.retryStep(), 1, "  handed to the wire again: the backoff isn't reset yet")
-- A "sent" result ends the backoff.
sends[2].cb(third, "sent")
eq(SS._test.retryStep(), 0, "'sent' resets the backoff")
WoW.flushTimers()
sends = {}
-- A peer whose frames failed is forgotten: seen again by the peer check, it
-- gets a fresh snapshot (a fresh trigger, so the backoff starts over).
P.SetSetting("beta", "size", 8)
WoW.flushTimers(SS.DEBOUNCE)
sends[1].cb(third, "failed", "no-route")
SS._test.checkPeers()
WoW.flushTimers(1)
eq(#sends, 2, "the failed peer seen again: a snapshot")
WoW.flushTimers()
sends = {}

-- Over the budget: not sent, reported, not retried.
local budget = SS.BUDGET
SS.BUDGET = 10
GP.failures["settings sync"] = nil
local n, w = SS.SendNow()
eq(w, "too-large", "over the budget: too-large")
eq(#sends, 0, "  nothing sent")
check(GP.failures["settings sync"] ~= nil, "  recorded")
WoW.flushTimers()
eq(#sends, 0, "  never retried")
SS.BUDGET = budget

-- /gpearls sync: the link, then the settings' last send and receipt.
newChat()
SlashCmdList.GLASSPEARLS("sync")
local lines = table.concat(newChat(), "\n")
check(lines:find("settings: last sent", 1, true), "/gpearls sync: last sent")
check(lines:find("from Alt", 1, true), "  last received, from whom")

-- The snapshot never carries the sync store (the household key).
GlassPearlsSyncDB.secretKey = "do-not-send"
local enc = SS.Encode()
check(not enc:find("do-not-send", 1, true), "the household store never travels")
for line in enc:gmatch("[^\n]+") do
    check(line == "GPS1" or line:match("^[VSM]\t"), "only GPS1 records: " .. line:sub(1, 20))
end

done("test_settings_sync")
