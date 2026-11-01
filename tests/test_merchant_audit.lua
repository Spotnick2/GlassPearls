-- Core/Merchant.lua after the audit (#61): a MERCHANT_SHOW while a visit is
-- open tells the listeners MERCHANT_CLOSED for that visit first (a vendor
-- opened straight from another), a loading screen (PLAYER_ENTERING_WORLD)
-- closes an open visit, each told once, a step or a waiter of a visit so
-- closed never runs, and the next visit counts up as before. The pearls' side
-- of it is test_junk_audit.lua and test_restock_audit.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ pearls = false })
local M = GP.Merchant
M._test.reset()
local heard = {}
M.On("a", function(event, s) heard[#heard + 1] = event .. ":" .. s end)
local function told() return table.concat(heard, " ") end

-- Another vendor opened with no close between: the first visit ends first.
WoW.openMerchant()
WoW.openMerchant()
eq(told(), "MERCHANT_SHOW:1 MERCHANT_CLOSED:1 MERCHANT_SHOW:2", "a second show closes the first visit first, in that order")
check(M.IsOpen() and M.Current(2) and not M.Current(1), "  the second visit is the open one")
local ran = 0
M.After(0.2, 1, function() ran = ran + 1 end)
M.After(0.2, 2, function() ran = ran + 10 end)
WoW.flushTimers()
eq(ran, 10, "  a step of the replaced visit never runs; the new visit's does")

-- A loading screen: the visit ends, told once, and its steps never run.
M.After(0.2, 2, function() ran = ran + 100 end)
WoW.merchantGone()
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(told(), "MERCHANT_SHOW:1 MERCHANT_CLOSED:1 MERCHANT_SHOW:2 MERCHANT_CLOSED:2", "a loading screen closes the open visit")
check(not M.IsOpen() and not M.Current(2), "  nothing is open")
WoW.flushTimers()
eq(ran, 10, "  and its steps never run")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
WoW.fire("MERCHANT_CLOSED")   -- the client's own close, late
eq(#heard, 4, "  told once, however many closes follow")
WoW.openMerchant()
eq(heard[5], "MERCHANT_SHOW:3", "the next visit counts up as before")
WoW.closeMerchant()
eq(heard[6], "MERCHANT_CLOSED:3", "  and closes as before")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(#heard, 6, "a loading screen with no visit open tells nobody")

-- A waiter of a replaced visit is never told, not even by its timeout.
local got = {}
WoW.openMerchant()
M.Await("junk", M.Session(), 10, function(o) got[#got + 1] = "old:" .. o end)
WoW.openMerchant()
M.Report("junk", M.Session() - 1, "ready")
WoW.flushTimers(10)
eq(#got, 0, "a replaced visit's waiter is never told, not even by its timeout")
M.Await("junk", M.Session(), 10, function(o) got[#got + 1] = "new:" .. o end)
M.Report("junk", M.Session(), "ready")
eq(got[1], "new:ready", "  the new visit's is")
WoW.closeMerchant()

done("test_merchant_audit")
