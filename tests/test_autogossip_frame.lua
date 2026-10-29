-- Auto gossip's prompt and Configuration Panel (#47): the prompt's text and
-- buttons, one at a time, its position per character; the panel's lone
-- radios, the offer switch, the repeats number and the two lists. In both
-- looks: tests/test_autogossip_frame_glass.lua runs it under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local GP = loadAddon()
local G, FR, P, SS = GP.AutoGossip, GP.AutoGossipFrame, GP.Pearls, GP.SettingsSync
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))

-- The prompt.
FR.Offer(11, "Take me to the faire")
local f = FR._test.frame()
check(f:IsShown(), "the prompt shows")
eq(f.text:GetText(), 'Always choose "Take me to the faire"?', "  with the option's own text")
local p = f._points[#f._points]
check(p[1] == "TOP" and p[2] == UIParent, "  top centre by default")
FR.Offer(12, "Another")
eq(f.id, 11, "one prompt at a time")
FR.Withdraw(12)
check(f:IsShown(), "withdrawing another option leaves it")
FR.Withdraw(11)
check(not f:IsShown(), "withdrawing its own option hides it")
FR.Offer(13, nil)
eq(f.text:GetText(), "Always choose option 13?", "an option with no known text: by its ID")
eq(FR.Hold(), 13, "a fight: it gives its option back")
check(not f:IsShown(), "  and hides")
eq(FR.Hold(), nil, "  nothing to give when hidden")
-- Answers go to the logic (with the exclusions checked again).
G.state.meta[14] = { icon = 132053, lone = false }
FR.Offer(14, "Fourteen")
f.always:GetScript("OnClick")(f.always)
check(SS.SetHas(G.ALWAYS, 14), "Always: added")
G.state.meta[15] = { icon = 132052, lone = false }     -- a binder: never offerable
FR.Offer(15, "Bind")
f.always:GetScript("OnClick")(f.always)
check(not SS.SetHas(G.ALWAYS, 15), "Always on an option no longer offerable: refused")
-- Dragged: remembered per character.
FR.Offer(16, "Sixteen")
f._left, f._top = 300, 700
f:GetScript("OnDragStop")(f)
check(GP.charDB.autogossipPrompt and GP.charDB.autogossipPrompt.x == 300, "the drag is saved per character")
FR.Withdraw()
FR.Offer(17, "Seventeen")
p = f._points[#f._points]
check(p[1] == "TOPLEFT" and p[4] == 300 and p[5] == 700, "  and used next time")
FR.Withdraw()

-- The Configuration Panel.
GP.Options.Open("cat:Automation")
local page = GP.Options._test.pages["cat:Automation"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "autogossip" then row = pl.row end end
check(row ~= nil, "on the Automation page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:autogossip"].frame._children[1]
local radios, checks, boxes = {}, {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UIRadioButtonTemplate" then radios[#radios + 1] = w end
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
    if w._template == "InputBoxTemplate" then boxes[#boxes + 1] = w end
end
eq(#radios, 4, "four lone-option choices")
radios[2]:GetScript("OnClick")(radios[2])
eq(P.Setting("autogossip", "lone"), "services", "  the second: services only")
radios[4]:GetScript("OnClick")(radios[4])
eq(P.Setting("autogossip", "lone"), "off", "  the fourth: never")
eq(#checks, 1, "one switch")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("autogossip", "offer"), false, "  the offer")
eq(#boxes, 1, "one number")
boxes[1]:SetText("7")
boxes[1]:GetScript("OnEnterPressed")(boxes[1])
eq(P.Setting("autogossip", "repeats"), 7, "  the repeats")
boxes[1]:SetText("40")
boxes[1]:GetScript("OnEnterPressed")(boxes[1])
eq(P.Setting("autogossip", "repeats"), 10, "  clamped to 10")
P.ResetSettings("autogossip")
-- The lists, by the option's text when known.
G._test.db().names[14] = "Fourteen"
content.alwaysList.refresh()
eq(content.alwaysList.rows[1].label:GetText(), '"Fourteen"', "the always list names its options")
content.alwaysList.rows[1].remove:GetScript("OnClick")(content.alwaysList.rows[1].remove)
check(not SS.SetHas(G.ALWAYS, 14), "  Remove takes one off")
SS.SetAdd(G.NEVER, 18)
content.neverList.refresh()
eq(content.neverList.rows[1].label:GetText(), "option 18", "the never list: by ID when the text is unknown")

done("test_autogossip_frame" .. (glass and " (glass)" or ""))
