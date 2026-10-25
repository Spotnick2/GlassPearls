-- AccountSync.lua: one LibAccountSync-1.0 instance on the GlassPearls tag,
-- its store, the kind dispatch and the on/off switch.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

GlassPearlsSyncDB = nil
local GP = loadAddon()
local AS = GP.AccountSync

check(AS.inst ~= nil, "an instance was made")
eq(AS.inst.addon, "GlassPearls", "on the GlassPearls tag")
check(next(GP.failures) == nil, "nothing failed")
eq(type(GlassPearlsSyncDB), "table", "the store exists after load")

-- Handlers: the kind picks one; the body arrives without it.
local got
AS.On("PING", function(body, sender, sid) got = { body = body, sender = sender, sid = sid } end)
check(not pcall(AS.On, "bad kind", function() end), "a kind is letters or digits")
check(not pcall(AS.On, "X"), "a handler is a function")

-- Dispatch, as the library calls it on a delivered payload.
AS._test.dispatch("PING\nhello there", { name = "Alt" }, 7)
eq(got and got.body, "hello there", "the PING handler gets the body")
eq(got and got.sid, 7, "  and the sid")
got = nil
AS._test.dispatch("PONG\nx", {}, 8)
AS._test.dispatch("no kind here", {}, 9)
check(got == nil, "an unknown kind, or no kind, reaches no handler")
AS.On("BAD", function() error("bad body") end)
AS._test.dispatch("BAD\n", {}, 10)
check(GP.failures["account sync BAD"] ~= nil, "a handler that throws is recorded")
GP.failures["account sync BAD"] = nil

-- Send: the kind travels with the body; with no peers the library says why.
local n, why = AS.Send("PING", "hello")
check(n == 0 or n == nil, "no peers: nothing sent")
check(type(why) == "string", "  and a reason: " .. tostring(why))

-- The switch goes through the library, into the store.
check(AS.IsEnabled(), "enabled by default")
check(AS.SetEnabled(false), "switched off")
check(not AS.IsEnabled(), "  off")
eq(GlassPearlsSyncDB.enabled, false, "  remembered in the store")
newChat()
SlashCmdList.GLASSPEARLS("sync on")
check(AS.IsEnabled(), "/gpearls sync on")
check(newChat()[1]:find("account sync on", 1, true), "  confirmed")

-- The readout names the library and this host.
local lines = AS.Lines()
check(lines[1]:find("LibAccountSync-1.0", 1, true) and lines[1]:find("GlassPearls", 1, true),
    "the readout's first line names the library and the tag")

-- Without the library, the addon still loads and says so.
AS.inst = nil
eq(select(2, AS.Send("PING", "x")), "no-instance", "Send without an instance")
eq(AS.Lines()[1], "LibAccountSync-1.0 is not loaded", "Lines without an instance")
check(not AS.SetEnabled(true), "SetEnabled without an instance")

done("test_sync")
