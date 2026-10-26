-- Core/Merchant.lua (#15): the session (open, closed, a counter per visit, a
-- repeated MERCHANT_CLOSED), listeners (registered lazily, a failing one
-- recorded and the others still told), After (only in the same visit), and
-- Report / Await (one pearl's outcome for a visit, another waiting for it, #14).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ pearls = false })
local M = GP.Merchant
M._test.reset()
local ev = M._test.events
check(not ev:IsEventRegistered("MERCHANT_SHOW"), "no events until a pearl listens")

local heard = {}
M.On("a", function(event, s) heard[#heard + 1] = event .. ":" .. s end)
check(ev:IsEventRegistered("MERCHANT_SHOW") and ev:IsEventRegistered("MERCHANT_CLOSED"), "the first listener registers them")
M.On("boom", function() error("x") end)

WoW.openMerchant()
check(M.IsOpen(), "open")
eq(M.Session(), 1, "the first visit")
check(M.Current(1), "  is the current one")
eq(heard[1], "MERCHANT_SHOW:1", "the listener hears it, with the visit")
check(GP.failures["merchant boom"] ~= nil, "a failing listener is recorded")
local ran = 0
M.After(0.2, 1, function() ran = ran + 1 end)
WoW.flushTimers()
eq(ran, 1, "After runs in the same visit")
M.After(0.2, 1, function() ran = ran + 1 end)
WoW.closeMerchant()
WoW.flushTimers()
eq(ran, 1, "  not once it closed")
check(not M.IsOpen() and not M.Current(1), "closed")
eq(heard[2], "MERCHANT_CLOSED:1", "the listener hears the close")
WoW.fire("MERCHANT_CLOSED")
eq(#heard, 2, "a repeated MERCHANT_CLOSED is told once")
WoW.openMerchant()
eq(M.Session(), 2, "the next visit counts up")
M.After(0.2, 1, function() ran = ran + 1 end)
WoW.flushTimers()
eq(ran, 1, "a step of the last visit never runs in this one")
M.On("a", nil)
WoW.closeMerchant()
eq(#heard, 3, "a listener taken off hears nothing more")

-- Report / Await: one pearl's outcome for a visit, another waiting for it (#14).
local got = {}
local function waiter(tag) return function(outcome) got[#got + 1] = tag .. ":" .. outcome end end
WoW.openMerchant()
local s = M.Session()
M.Await("junk", s, 10, waiter("early"))
eq(#got, 0, "Await waits for the report")
M.Report("junk", s, "ready")
eq(got[1], "early:ready", "  and is told it")
M.Report("junk", s, "skip")
M.Await("junk", s, 10, waiter("late"))
eq(got[2], "late:ready", "the first report counts; a late Await is told at once")
WoW.flushTimers(10)
eq(#got, 2, "  and the timeout never fires after a report")
M.Report("other", s - 1, "ready")
M.Await("other", s, 10, waiter("timeout"))
eq(#got, 2, "another visit's report is ignored")
WoW.flushTimers(10)
eq(got[3], "timeout:skip", "no report in time: skip")
M.Report("other", s, "ready")
eq(#got, 3, "  once only")
M.Await("closing", s, 10, waiter("closed"))
WoW.closeMerchant()
M.Report("closing", s, "ready")
WoW.flushTimers(10)
eq(#got, 3, "a closed visit tells nobody")
M.Await("closing", s, 10, waiter("after"))
eq(#got, 3, "  nor an Await after the close")
WoW.openMerchant()
M.Await("junk", M.Session(), 10, waiter("next"))
eq(#got, 3, "a new visit starts without the last one's reports")
M.Report("junk", M.Session(), "skip")
eq(got[4], "next:skip", "  and hears its own")
M.Await("boom", M.Session(), 10, function() error("x") end)
M.Report("boom", M.Session(), "ready")
check(GP.failures["merchant await boom"] ~= nil, "a failing waiter is recorded")
WoW.closeMerchant()

done("test_merchant")
