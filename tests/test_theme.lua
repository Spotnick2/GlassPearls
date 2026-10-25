-- Theme.lua: WoW Forever by default, Glass only from Glass UI's suite (#3).
-- The suite contract is GlassUI docs/SUITE.md; every answer it can give, or
-- fail to give, ends in a look and (when the suite is there) one report.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- At load, with Glass UI already here (OptionalDeps loads it first): GlassPearls
-- asks the suite at its ADDON_LOADED and follows it by default.
WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
    body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
    accent = { 0.9, 0.7, 0.2 } })
local GP = loadAddon()
local T = GP.Theme
eq(WoW.suiteAsked, "GlassPearls", "it asked the suite for its own name")
eq(T.Active(), "glass", "following Glass UI: glass")
check(T.Following(), "  and says so")
check(T.Glass() ~= nil, "  with a LibGlass instance")
eq(#WoW.suiteReports, 1, "one report")
local r = WoW.suiteReports[1].state
eq(WoW.suiteReports[1].addon, "GlassPearls", "  for GlassPearls")
eq(r.api, 1, "  api 1")
eq(r.built, "pearl", "  built: pearl")
eq(r.live, false, "  live = false: a suite change waits for a /reload")
eq(type(r.options), "function", "  with a link to our options")
eq(r.look and r.look.tint, "smoked", "  the suite tint it took")
eq(r.look and r.look.accent, "gold", "  and accent")
eq(r.declined, nil, "  not declined")
r.options()
check(GP.Options.IsOpen(), "Glass UI's link opens our window")
GP.Options._test.win():Hide()

-- A window in glass: the library's shell on the frame, our backing under it.
local f = CreateFrame("Frame", nil, UIParent)
eq(T.Window(f, { header = 40 }), "glass", "Window dresses in glass")
check(f.glass ~= nil and f.glass.backing ~= nil, "  shell and backing")
eq(f.border, nil, "  no Forever border")
local fs = UIParent:CreateFontString()
T.Accent(fs)
local c = fs._textColor
check(c and c[1] == 0.9 and c[2] == 0.7, "a title wears the suite's accent")
eq(T.Control(CreateFrame("Frame", nil, f)), "glass", "a control in glass")

-- From here, each suite answer on its own: reset the session's look and ask again.
local function again(opts, follow)
    T._test.reset()
    WoW.suiteReports = {}
    rawset(_G, "GlassUI", nil)
    if opts then WoW.installGlassUI(opts) end
    return T.Init(follow ~= false, function() end)
end

-- No Glass UI: Forever, nobody to report to.
eq(again(nil), "forever", "no Glass UI: Forever")
eq(#WoW.suiteReports, 0, "  no report")
eq(T.Glass(), nil, "  no LibGlass instance")
local g = CreateFrame("Frame", nil, UIParent)
eq(T.Window(g), "forever", "a Forever window")
check(g.border and g.border._template == "DialogBorderDarkTemplate", "  Blizzard's dark dialog border")
check(g.border.Bg ~= nil, "  with its background")
eq(g.glass, nil, "  no glass")
local fs2 = UIParent:CreateFontString()
T.Accent(fs2)
eq(fs2._textColor, nil, "no accent: titles keep Blizzard's colour")
local ctl = CreateFrame("Frame", nil, g)
eq(T.Control(ctl), "forever", "a Forever control")
check(ctl.surface and #ctl.surface.edges == 4, "  a fill and four edges")

-- The dialog template missing: a plain dark fill, never a bare frame.
WoW.missingTemplates.DialogBorderDarkTemplate = true
local bare = CreateFrame("Frame", nil, UIParent)
T.Window(bare)
check(bare.border and bare.border._regions and #bare.border._regions == 1, "missing template: a dark fill instead")
WoW.missingTemplates.DialogBorderDarkTemplate = nil

-- Declined: the player turned following off. Forever, reported as chosen.
eq(again({}, false), "forever", "declined: Forever")
eq(WoW.suiteAsked == "GlassPearls" and #WoW.suiteReports, 1, "  reported")
eq(WoW.suiteReports[1].state.declined, "WoW Forever", "  declined = WoW Forever")
eq(WoW.suiteReports[1].state.built, nil, "  nothing built")

-- A suite that doesn't speak API 1 counts as absent.
eq(again({ api = 2 }), "forever", "API 2: absent")
eq(#WoW.suiteReports, 0, "  no report to a suite we don't speak")

-- Theme throwing, junk, not-ready: Forever, and the report says nothing was built.
eq(again({ theme = function() error("boom") end }), "forever", "Theme throws: Forever")
eq(WoW.suiteReports[1].state.built, nil, "  reported, nothing built")
eq(again({ theme = "pearl" }), "forever", "Theme returns junk: Forever")
eq(again({ theme = function() return nil, "not-ready" end }), "forever", "not-ready: Forever")
eq(#WoW.suiteReports, 1, "  still reported")

-- The suite's material can't be built: the reason goes to the report.
eq(again({ theme = { name = "x", preset = "frosted" } }), "forever", "an unknown preset: Forever")
eq(WoW.suiteReports[1].state.reason, "library-too-old", "  reason library-too-old")

-- A Report that throws is recorded, never fatal.
GP.failures["theme report"] = nil
again({})
GlassUI.Suite.Report = function() error("report boom") end
T._test.reset()
T.Init(true, function() end)
check(GP.failures["theme report"] ~= nil, "a throwing Report is recorded")
eq(T.Active(), "glass", "  and the look still built")

-- Init is once a session.
local before = T.Active()
rawset(_G, "GlassUI", nil)
eq(T.Init(true), before, "a second Init keeps the session's look")

done("test_theme")
