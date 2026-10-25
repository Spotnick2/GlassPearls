-- The fixate alert's frame and Configuration Panel (#17): the three sizes, the
-- countdown text, click-through outside a test, the drag saved per
-- character, and the panel's switches, sizes and Test. In both looks:
-- tests/test_fixate_frame_glass.lua runs it again under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
WoW.spells[12021] = { name = "Fixate", icon = 136129 }
local GP = loadAddon()
local F, FR, P = GP.Fixate, GP.FixateFrame, GP.Pearls
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))

-- Countdown text.
eq(FR.CountdownText(9.94), "9.9", "under 10 s: tenths")
eq(FR.CountdownText(12.6), "13", "above: whole seconds, rounded")

-- Sizes.
WoW.now = 0
FR.Show({ id = 12021, expiration = 10, duration = 10 })
local f = FR._test.frame()
eq(f.icon._width, FR.SIZES.normal, "normal size by default")
eq(f._mouse, false, "click-through outside a test")
P.SetSetting("fixate", "size", "large")
FR.Show({ id = 12021, expiration = 10, duration = 10 })
eq(f.icon._width, FR.SIZES.large, "large")
P.SetSetting("fixate", "size", "small")
FR.Show({ id = 12021, expiration = 10, duration = 10 })
eq(f.icon._width, FR.SIZES.small, "small")
P.ResetSettings("fixate")
FR.Hide()
check(not f:IsShown(), "hidden")
-- Above the centre by default; dragged during a test, remembered per character.
FR.Show({ id = 12021, expiration = 10, duration = 10 })
local p = f._points[#f._points]
check(p[1] == "CENTER" and p[2] == UIParent and p[5] == 260, "above the centre by default")
FR.Unlock()
eq(f._mouse, true, "a test unlocks it")
function f:GetCenter() return 640, 500 end
f:GetScript("OnDragStop")(f)
eq(GP.charDB.fixate and GP.charDB.fixate.x, 640, "the drag is saved per character")
FR.Hide()
eq(f._mouse, false, "hiding locks it again")
FR.Show({ id = 12021, expiration = 10, duration = 10 })
p = f._points[#f._points]
check(p[1] == "CENTER" and p[3] == "BOTTOMLEFT" and p[4] == 640 and p[5] == 500, "  and used next time")
FR.Hide()

-- The Configuration Panel.
GP.Options.Open("cat:Combat")
local page = GP.Options._test.pages["cat:Combat"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "fixate" then row = pl.row end end
check(row ~= nil, "on the Combat page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:fixate"].frame._children[1]
local checks, radios = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
    if w._template == "UIRadioButtonTemplate" then radios[#radios + 1] = w end
end
eq(#checks, 2, "two switches")
eq(#radios, 3, "three sizes")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("fixate", "sound"), false, "the first: the sound")
checks[2]:SetChecked(false)
checks[2]:GetScript("OnClick")(checks[2])
eq(P.Setting("fixate", "alert"), false, "the second: the alert")
radios[3]:GetScript("OnClick")(radios[3])
eq(P.Setting("fixate", "size"), "large", "the third size: large")
P.ResetSettings("fixate")
content.test:GetScript("OnClick")(content.test)
check(FR.IsShown() and F.state.alert.test, "Test shows a test alert")
F.Clear()
GP.Options._test.win():Hide()

done("test_fixate_frame" .. (glass and " (glass)" or ""))
