-- Theme.lua following Glass UI's suite look live (#117): registered for
-- LookChanged before the one pull of Look(), every change repaints the shells
-- (tint, backing, wash), the accent titles and each OnLook consumer at once,
-- in combat too, then reports live = true with the effective look; a key the
-- suite can't answer falls back to ours, named and flagged own; a repaint
-- that throws is recorded and not reported; the payload is never kept.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local BODIES = {
    clear = { tint = { 0.13, 0.16, 0.22, 0.24 }, backing = { 0.04, 0.05, 0.07, 0.35 }, wash = 1 },
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, backing = { 0.04, 0.05, 0.07, 0.92 }, wash = 0.14 },
    class = { classShade = 0.6, backing = { 0.04, 0.05, 0.07, 0.35 }, wash = 1 },
}
local ACCENTS = { gold = { 1, 0.82, 0 }, ice = { 0.65, 0.835, 0.905 } }
local current = { tint = "clear", accent = "gold" }
local pulls, registeredAtPull = 0, nil
local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local function copyColor(c) return c and { unpack(c) } end
local opts = {
    look = function()
        pulls = pulls + 1
        local cbs = WoW.eventCallbacks["GlassUI.Suite.LookChanged"]
        registeredAtPull = cbs ~= nil and next(cbs) ~= nil
        return copy(current)
    end,
    body = function(name)
        local b = BODIES[name]
        if not b then return nil end
        return { tint = copyColor(b.tint), classShade = b.classShade, backing = copyColor(b.backing), wash = b.wash }
    end,
    accent = function(name) return copyColor(ACCENTS[name]) end,
}
WoW.installGlassUI(opts)
local GP = loadAddon()
local T = GP.Theme
local EVENT = T.EVENT
local function fire(look) EventRegistry:TriggerEvent(EVENT, look) end
local function lastReport() return WoW.suiteReports[#WoW.suiteReports].state end
local function same(a, b, eps)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for i = 1, #b do if math.abs((a[i] or -1) - b[i]) > (eps or 1e-6) then return false end end
    return true
end

-- The start: registered before the one pull; live.
eq(pulls, 1, "Look() pulled once at the start")
check(registeredAtPull, "  after registering for LookChanged (a change isn't replayed)")
check(T._test.live(), "live")
local r = lastReport()
eq(r.live, true, "reported live = true")
eq(r.look.tint, "clear", "  the suite's tint")
eq(r.look.accent, "gold", "  and accent")
eq(r.own, nil, "  nothing of our own")

-- A window and a title, built in the current look.
local f = CreateFrame("Frame", nil, UIParent)
T.Window(f, { header = 40 })
local g = f.glass
local preset = T._test.following().wash
check(same(g.tint._color, BODIES.clear.tint), "a shell in the clear body's tint")
check(same(g.backing._color, BODIES.clear.backing), "  and backing")
eq(g.wash.glassPeak, preset * 1, "  and wash")
local title = UIParent:CreateFontString()
title:SetTextColor(0.2, 0.3, 0.4, 1)              -- its font's own colour
T.Accent(title)
check(same(title._textColor, ACCENTS.gold), "a title in the gold accent")
local consumer, consumerCalls = nil, 0
T.OnLook(function() consumerCalls = consumerCalls + 1; consumer = { T.AccentRGB() } end)

-- A change: everything repainted at once, then reported.
local n = #WoW.suiteReports
local payload = { tint = "smoked", accent = "ice" }
fire(payload)
check(same(g.tint._color, BODIES.smoked.tint), "smoked: the shell's tint")
check(same(g.backing._color, BODIES.smoked.backing), "  its backing")
check(math.abs(g.wash.glassPeak - preset * 0.14) < 1e-9, "  its wash (the preset's x the body's)")
check(same(title._textColor, ACCENTS.ice), "ice: the title")
eq(consumerCalls, 1, "  the consumer called once")
check(same(consumer, ACCENTS.ice), "  and reads the new accent")
eq(#WoW.suiteReports, n + 1, "  one report after the repaint")
eq(lastReport().look.tint, "smoked", "  the effective tint")
eq(lastReport().look.accent, "ice", "  and accent")
eq(lastReport().live, true, "  live")
-- The payload is never kept: changing it afterwards changes nothing.
payload.tint, payload.accent = "clear", "gold"
eq(T._test.following().tint, "smoked", "the shared payload isn't kept")
-- A window built after a change wears the current look.
local f2 = CreateFrame("Frame", nil, UIParent)
T.Window(f2)
check(same(f2.glass.tint._color, BODIES.smoked.tint), "a later window in the current tint")

-- Unknown values: our recipe for the tint (tint, backing and no wash), the
-- title's first colour; named and flagged own in the report.
local SHELL = T._test.SHELL
fire({ tint = "neon", accent = "pink" })
check(same(g.tint._color, SHELL.tint), "an unknown tint: the recipe's tint")
check(same(g.backing._color, SHELL.backing), "  the recipe's backing")
eq(g.wash.glassPeak, 0, "  no wash")
check(same(title._textColor, { 0.2, 0.3, 0.4, 1 }), "an unknown accent: the title's first colour")
eq(T.AccentRGB(), nil, "  and no accent for the consumers")
r = lastReport()
eq(r.look.tint, "glasspearls", "  reported: our tint")
eq(r.look.accent, "font", "  and our accent")
check(r.own and r.own.tint and r.own.accent, "  both flagged own")
-- And back: the flags cleared.
fire({ tint = "clear", accent = "gold" })
r = lastReport()
eq(r.own, nil, "back to the suite's: nothing own")
check(same(g.tint._color, BODIES.clear.tint), "  the clear tint again")
check(same(title._textColor, ACCENTS.gold), "  the gold accent again")
-- A missing key in the payload is unknown too.
fire({})
eq(lastReport().look.tint, "glasspearls", "a payload without keys: ours")
fire("junk")
eq(lastReport().look.accent, "font", "a payload that isn't a table: ours")
fire({ tint = "clear", accent = "gold" })

-- Class: the colour unreadable at the change, painted at the next PEW; the
-- retry frame made on demand by the live repaint.
WoW.class = "NOBODY"
fire({ tint = "class", accent = "gold" })
check(same(g.tint._color, g.tint.glassColor), "class unreadable: the shell's built tint")
WoW.class = "MAGE"
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(same(g.tint._color, { 0.25 * 0.6, 0.78 * 0.6, 0.92 * 0.6 }), "  at PEW: the class colour x its shade")
fire({ tint = "clear", accent = "gold" })

-- In combat: repainted at once, nothing blocked.
WoW.combat = true
WoW.blocked = {}
fire({ tint = "smoked", accent = "ice" })
check(same(g.tint._color, BODIES.smoked.tint), "in combat: repainted at once")
check(same(title._textColor, ACCENTS.ice), "  the title too")
eq(#WoW.blocked, 0, "  nothing blocked")
WoW.combat = false

-- Failures. A throwing Body or Accent: recorded, that key ours, the rest painted.
GlassUI.Suite.Body = function() error("body boom") end
fire({ tint = "smoked", accent = "gold" })
check(GP.failures["theme Body"] ~= nil, "a throwing Body is recorded")
eq(lastReport().look.tint, "glasspearls", "  the tint ours")
eq(lastReport().look.accent, "gold", "  the accent still the suite's")
GlassUI.Suite.Body = opts.body
GlassUI.Suite.Accent = function() error("accent boom") end
fire({ tint = "smoked", accent = "gold" })
check(GP.failures["theme Accent"] ~= nil, "a throwing Accent is recorded")
eq(lastReport().look.accent, "font", "  the accent ours")
GlassUI.Suite.Accent = opts.accent
-- A throwing consumer: recorded, the others still run, the change reported.
T.OnLook(function() error("consumer boom") end)
local after = 0
T.OnLook(function() after = after + 1 end)
n = #WoW.suiteReports
fire({ tint = "clear", accent = "gold" })
check(GP.failures["theme onlook"] ~= nil, "a throwing consumer is recorded")
eq(after, 1, "  the next consumer still runs")
eq(#WoW.suiteReports, n + 1, "  and the change is reported")
-- A repaint that throws: recorded, and no report of a look half painted.
local setColor = g.backing.SetColorTexture
g.backing.SetColorTexture = function() error("paint boom") end
n = #WoW.suiteReports
fire({ tint = "smoked", accent = "ice" })
check(GP.failures["theme look"] ~= nil, "a repaint that throws is recorded")
eq(#WoW.suiteReports, n, "  and not reported")
g.backing.SetColorTexture = setColor

-- Not live: no Look, or no EventRegistry. Built once, reported live = false.
local function again(o, follow)
    T._test.reset()
    WoW.resetEventRegistry()
    WoW.suiteReports = {}
    rawset(_G, "GlassUI", nil)
    if o then WoW.installGlassUI(o) end
    return T.Init(follow ~= false, function() end)
end
again({ body = opts.body, accent = opts.accent })
eq(lastReport().live, false, "no Look(): live = false")
eq(WoW.eventCallbacks[EVENT], nil, "  not registered")
local registry = rawget(_G, "EventRegistry")
rawset(_G, "EventRegistry", nil)
again(opts)
eq(lastReport().live, false, "no EventRegistry: live = false")
eq(lastReport().look.tint, "clear", "  the look built once all the same")
rawset(_G, "EventRegistry", registry)

-- Declined or absent: never registered, a change does nothing.
again(opts, false)
eq(lastReport().declined, "WoW Forever", "declined")
eq(WoW.eventCallbacks[EVENT], nil, "  not registered")
n = #WoW.suiteReports
fire({ tint = "smoked", accent = "ice" })
eq(#WoW.suiteReports, n, "  a change reports nothing")
again(nil)
eq(WoW.eventCallbacks[EVENT], nil, "no Glass UI: not registered")

done("test_theme_live")
