-- Camp timers' bars, digits and Configuration Panel (#149): the time text, the
-- label, the fill, a bar per view, click-through outside a test, the drag saved
-- per character, the digits, and the panel's four switches and Test. In both
-- looks: tests/test_camp_frame_glass.lua runs it again under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
WoW.spells[429959] = { name = "Well-Rested", icon = 132802 }
WoW.spells[1229739] = { name = "Welcoming Campfire", icon = 135805 }
local GP = loadAddon()
local CF, P, C = GP.CampFrame, GP.Pearls, GP.Camp
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))

-- Text and fill.
eq(CF.TimeText({ endsAt = 165 }, 100), "1:05", "minutes and seconds")
eq(CF.TimeText({ endsAt = 109.2 }, 100), "0:10", "  rounded up")
eq(CF.TimeText({ endsAt = 160.0000001 }, 100), "1:00", "  a float a hair over is that second")
eq(CF.TimeText({ endsAt = 90 }, 100), "0:00", "  never negative")
eq(CF.TimeText({}, 100), "...", "waiting: no time")
eq(CF.Label({ id = 429959, count = 2, max = 3 }), "Well-Rested 2/3", "the label with the stacks")
eq(CF.Label({ id = 429959 }), "Well-Rested", "  no count: no stacks")
eq(CF.Fill({ endsAt = 130, span = 60 }, 100), 0.5, "the fill: half way")
eq(CF.Fill({ span = 60 }, 100), 0, "  waiting: empty")
eq(CF.Fill({ endsAt = 90, span = 60 }, 100), 1, "  past: full")

-- A bar per view.
WoW.now = 100
CF.Show({ { kind = "bag", id = 429959, count = 1, max = 3, span = 60, endsAt = 130 },
          { kind = "camp", id = 1229739, span = 60, endsAt = 150 } }, 100)
local f = CF._test.frame()
check(f:IsShown(), "shown")
eq(f.rows[1].label:GetText(), "Well-Rested 1/3", "row 1: the bag")
eq(f.rows[1].time:GetText(), "0:30", "  its time")
eq(f.rows[1].icon._file, 132802, "  its icon")
eq(f.rows[2].label:GetText(), "Welcoming Campfire", "row 2: the campfire")
check(math.abs(f.rows[2].bar:GetValue() - 1 / 6) < 1e-9, "  its fill")
check(f.rows[2]._points[1][5] < f.rows[1]._points[1][5], "  under the bag's")
local h2 = f._height
CF.Show({ { kind = "camp", id = 1229739, span = 60, endsAt = 150 } }, 100)
check(not f.rows[2]:IsShown(), "one view: the extra row hidden")
check(f._height < h2, "  the frame shorter")
eq(f._mouse, false, "click-through outside a test")
local p = f._points[#f._points]
check(p[1] == "CENTER" and p[5] == CF.DEFAULT_Y, "placed under the middle by default")
CF.Unlock()
eq(f._mouse, true, "a test unlocks it")
function f:GetCenter() return 700, 400 end
f:GetScript("OnDragStop")(f)
eq(GP.charDB.camp and GP.charDB.camp.x, 700, "the drag is saved per character")
CF.Lock()
eq(f._mouse, false, "locked again")
CF.Hide()
check(not f:IsShown(), "hidden")
CF.Show({ { kind = "camp", id = 1229739, span = 60, endsAt = 150 } }, 100)
p = f._points[#f._points]
check(p[2] == UIParent and p[3] == "BOTTOMLEFT" and p[4] == 700, "shown again where it was dragged")
CF.Hide()

-- The digits.
CF.Digit(7)
eq(CF.DigitText(), "7", "a digit")
local d = CF._test.digit()
eq(d._mouse, false, "  click-through")
eq(d._points[1][5], CF.DIGIT_Y, "  above the centre text")
CF.Digit(nil)
eq(CF.DigitText(), nil, "nil hides it")

-- The Configuration Panel.
GP.Options.Open("cat:Interface")
local page = GP.Options._test.pages["cat:Interface"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "camp" then row = pl.row end end
check(row ~= nil, "on the Interface page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:camp"].content
for _, name in ipairs({ "bag", "campfire", "countdown", "sound" }) do
    local cb = content.checks[name]
    check(cb ~= nil and cb:GetChecked(), "the " .. name .. " switch, on")
    cb:SetChecked(false)
    cb:GetScript("OnClick")(cb)
    eq(P.Setting("camp", name), false, "  switches it off")
end
P.ResetSettings("camp")
content.test:GetScript("OnClick")(content.test)
check(CF.IsShown() and C.state.test ~= nil, "Test shows the bars")
GP.Options._test.win():Hide()

done("test_camp_frame" .. (glass and " (glass)" or ""))
