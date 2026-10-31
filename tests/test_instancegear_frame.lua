-- Instance gear reminders' panel (#43), in both looks (an argument "glass" runs
-- it under Glass UI's glass): the panel's two switches; `test` shows the
-- centre text (Core/Notice.lua, test_notice.lua).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local GP = loadAddon()
local P, N = GP.Pearls, GP.Notice

-- `test`.
P.Command("instancegear").run("test")
check(N.IsShown() and N.Text() == "Equip your Argent Dawn trinket", "/gpearls instancegear test: shown")
N._test.frame().anim._scripts.OnFinished(N._test.frame().anim)

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
