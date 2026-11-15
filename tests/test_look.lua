-- The own look when Glass UI isn't driving it (#119): WoW Forever or Pearl
-- from our LibGlass with our recipe; what Glass UI is told in each case
-- (Codex round 2's table): declined only when our switch is off, by what was
-- built; a failed suite build keeps its reason; anything else reports nothing
-- more; a local Pearl always reports built = nil.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- No Glass UI, Pearl chosen: glass from the pearl preset, our recipe.
local GP = loadAddon({ db = { look = "pearl" } })
local T = GP.Theme
eq(T.Active(), "glass", "no Glass UI, Pearl chosen: glass")
check(not T.Following(), "  not following anything")
check(T.Glass() ~= nil and T.Glass().STYLE ~= nil, "  a LibGlass instance")
check(not T._test.live(), "  not live")
eq(#WoW.suiteReports, 0, "  nobody to report to")
local f = CreateFrame("Frame", nil, UIParent)
T.Window(f)
local SHELL = T._test.SHELL
local function same(a, b)
    if type(a) ~= "table" then return false end
    for i = 1, #b do if math.abs((a[i] or -1) - b[i]) > 1e-6 then return false end end
    return true
end
check(same(f.glass.tint._color, SHELL.tint), "  a shell in our recipe's tint")
check(same(f.glass.backing._color, SHELL.backing), "  and backing")
local title = UIParent:CreateFontString()
T.Accent(title)
eq(title._textColor, nil, "  titles keep their font's colour")
eq(T.AccentRGB(), nil, "  no accent for the consumers")

-- Each case from here: a fresh session's look.
local function again(opts, follow, look)
    T._test.reset()
    WoW.resetEventRegistry()
    WoW.suiteReports = {}
    rawset(_G, "GlassUI", nil)
    if opts then WoW.installGlassUI(opts) end
    return T.Init(follow ~= false, function() end, look)
end
local function report() return WoW.suiteReports[#WoW.suiteReports] and WoW.suiteReports[#WoW.suiteReports].state end

eq(again(nil, true, nil), "forever", "no Glass UI, nothing chosen: WoW Forever")
eq(again(nil, true, "forever"), "forever", "no Glass UI, Forever chosen: WoW Forever")
eq(again(nil, true, "junk"), "forever", "an unknown choice: WoW Forever")

-- Pearl that can't be built: WoW Forever, recorded and said.
local newGlass = T.NewGlass
T.NewGlass = function() return nil, "the loaded LibGlass-1.0 is older than r9", "library-too-old" end
newChat()
GP.failures["theme pearl"] = nil
eq(again(nil, true, "pearl"), "forever", "Pearl that can't be built: WoW Forever")
check(GP.failures["theme pearl"] ~= nil, "  recorded")
check(chatHas("Pearl look couldn't be built"), "  and said")
T.NewGlass = newGlass

-- Glass UI driving the look: the own choice ignored.
eq(again({}, true, "forever"), "glass", "following Glass UI: its glass")
check(T.Following(), "  following")
eq(report().built, "pearl", "  reported built")
eq(report().declined, nil, "  not declined")

-- Our switch off: the own look, declined by what was built.
eq(again({}, false, "pearl"), "glass", "switch off, Pearl chosen: glass")
check(not T.Following(), "  not following")
eq(report().declined, "Pearl", "  declined = Pearl")
eq(report().built, nil, "  built = nil (Glass UI reads built as following)")
eq(again({}, false, nil), "forever", "switch off, nothing chosen: WoW Forever")
eq(report().declined, "WoW Forever", "  declined = WoW Forever")
T.NewGlass = function() return nil, "old", "library-too-old" end
eq(again({}, false, "pearl"), "forever", "switch off, Pearl that can't be built: WoW Forever")
eq(report().declined, "WoW Forever", "  declined by what was built")
T.NewGlass = newGlass

-- Glass UI's answer unusable: the own look, the report adds nothing.
eq(again({ theme = function() return nil, "not-following" end }, true, "pearl"), "glass",
    "Glass UI answers not-following: our Pearl")
local r = report()
check(r.built == nil and r.declined == nil and r.reason == nil, "  reported: nothing built, no reason, not declined")
eq(again({ theme = function() return nil, "not-ready" end }, true, "pearl"), "glass", "not-ready: our Pearl")
r = report()
check(r.built == nil and r.declined == nil and r.reason == nil, "  reported the same")
eq(again({ theme = function() error("boom") end }, true, nil), "forever", "Theme throws, nothing chosen: WoW Forever")

-- Glass UI's preset fails to build: its reason kept, our Pearl underneath.
eq(again({ theme = { name = "x", preset = "frosted" } }, true, "pearl"), "glass", "the suite's build fails: our Pearl")
r = report()
eq(r.reason, "library-too-old", "  the suite attempt's reason kept")
eq(r.built, nil, "  built = nil")
eq(r.declined, nil, "  not declined (it would hide the failure)")

done("test_look")
