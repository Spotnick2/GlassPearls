-- Core/Merchant.lua (#15): the session (open, closed, a counter per visit, a
-- repeated MERCHANT_CLOSED), listeners (registered lazily, a failing one
-- recorded and the others still told), and After (only in the same visit).
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

done("test_merchant")
