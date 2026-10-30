-- Instance gear reminders' centre text and panel (#43): click-through, held
-- then faded, replaced by a new one, in both looks (an argument "glass" runs
-- it under Glass UI's glass); the panel's two switches; `test`.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local GP = loadAddon()
local FR, P = GP.InstanceGearFrame, GP.Pearls

check(not FR.IsShown(), "nothing shown at login outdoors")
FR.Show("Equip your Argent Dawn Commission")
local f = FR._test.frame()
check(FR.IsShown(), "shown")
eq(f.text:GetText(), "Equip your Argent Dawn Commission", "  the text")
eq(f._mouse, false, "  click-through")
local p = f._points[#f._points]
check(p[1] == "CENTER" and p[3] == "CENTER" and p[5] == FR.Y, "  in the middle, below the fixate alert")
check(FR.Y < 260, "  (+200 below +260)")
check(f.anim:IsPlaying(), "  held, then fading")
f.anim._scripts.OnFinished(f.anim)
check(not FR.IsShown(), "  then gone")
FR.Show("one")
f:SetAlpha(0.3)                                  -- mid-fade
FR.Show("two")
eq(f.text:GetText(), "two", "a new one replaces the old")
eq(f:GetAlpha(), 1, "  at full alpha")
f.anim._scripts.OnFinished(f.anim)

-- `test`.
P.Command("instancegear").run("test")
check(FR.IsShown() and f.text:GetText() == "Equip your Argent Dawn trinket", "/gpearls instancegear test: shown")
f.anim._scripts.OnFinished(f.anim)

-- The panel.
GP.Options.Open("cat:Combat")
local page = GP.Options._test.pages["cat:Combat"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "instancegear" then row = pl.row end end
check(row ~= nil, "on the Combat page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:instancegear"].frame._children[1]
local checks = {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
eq(#checks, 2, "two switches")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("instancegear", "argentdawn"), false, "  the Argent Dawn case")
checks[2]:SetChecked(true)
checks[2]:GetScript("OnClick")(checks[2])
eq(P.Setting("instancegear", "exalted"), true, "  also at Exalted")
P.ResetSettings("instancegear")

done("test_instancegear_frame" .. (glass and " (glass)" or ""))
