-- Easy fishing's panel (#64), in both looks (an argument "glass" runs it under
-- Glass UI's glass): three switches, the volume, the key's text.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
WoW.bindings.GLASSPEARLS_FISH = "F"
local GP = loadAddon()
local P = GP.Pearls

GP.Options.Open("cat:Professions")
local page = GP.Options._test.pages["cat:Professions"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "fishing" then row = pl.row end end
check(row ~= nil, "on the Professions page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:fishing"].frame._children[1]
local checks, texts = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
for _, r in ipairs(content._regions or {}) do
    if r._text then texts[#texts + 1] = r._text end
end
eq(#checks, 3, "three switches")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("fishing", "interact"), false, "  the Interact key")
checks[2]:SetChecked(true)
checks[2]:GetScript("OnClick")(checks[2])
eq(P.Setting("fishing", "sounds"), true, "  the sounds")
checks[3]:SetChecked(true)
checks[3]:GetScript("OnClick")(checks[3])
eq(P.Setting("fishing", "names"), true, "  the names")
local keyLine = false
for _, t in ipairs(texts) do if t:find("Fishing key: F", 1, true) then keyLine = true end end
check(keyLine, "the key bound is shown")
P.ResetSettings("fishing")
eq(P.Setting("fishing", "interact"), true, "Reset: the defaults back")

done("test_fishing_frame" .. (glass and " (glass)" or ""))
