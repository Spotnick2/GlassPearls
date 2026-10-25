-- Buff alerts' frame and Configuration Panel (#21): the slots in a row, the
-- three sizes, the time text ("~" estimated, tenths, none), the pulse,
-- click-through outside a test, the drag saved per character, and the panel:
-- each buff with its sound switch, the alert, pulse, sizes and Test. In both
-- looks: tests/test_buffs_frame_glass.lua runs it again under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
WoW.spells[29166] = { name = "Innervate", icon = 136048 }
WoW.spells[10060] = { name = "Power Infusion", icon = 135939 }
local GP = loadAddon()
local BF, P, B = GP.BuffsFrame, GP.Pearls, GP.Buffs
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))

-- Time text.
eq(BF.TimeText({ expiration = 112.4 }, 100), "12", "whole seconds above 10")
eq(BF.TimeText({ expiration = 104.5 }, 100), "4.5", "tenths under 10")
eq(BF.TimeText({ expiration = 112, approximate = true }, 100), "~12", "'~' when estimated")
eq(BF.TimeText({ expiration = 0 }, 100), "", "none without a time")
eq(BF.TimeText({ expiration = 99 }, 100), "", "none once passed")

-- Slots in a row.
WoW.now = 100
BF.Show({ { key = "innervate", id = 29166, expiration = 120, from = "Elune" },
          { key = "powerinfusion", id = 10060, expiration = 115 } })
local f = BF._test.frame()
check(f:IsShown(), "shown")
eq(f.slots[1].name:GetText(), "Innervate", "slot 1: the client's name")
eq(f.slots[1].from:GetText(), "from Elune", "  from")
eq(f.slots[1].icon._file, 136048, "  its icon")
eq(f.slots[2].name:GetText(), "Power Infusion", "slot 2")
local p1, p2 = f.slots[1]._points[1], f.slots[2]._points[1]
check(p2[4] - p1[4] == BF.SLOT_W, "  side by side")
eq(f._width, 2 * BF.SLOT_W + 16, "the frame fits its slots")
check(f.slots[1].pulse:IsPlaying(), "the pulse plays")
eq(f._mouse, false, "click-through outside a test")
BF.Show({ { key = "innervate", id = 29166, expiration = 120 } })
check(not f.slots[2]:IsShown(), "fewer buffs: the extra slot hidden")
check(not f.slots[2].pulse:IsPlaying(), "  its pulse stopped")
-- Sizes and the pulse switch.
for size, px in pairs(BF.SIZES) do
    P.SetSetting("buffs", "size", size)
    BF.Show({ { key = "innervate", id = 29166, expiration = 120 } })
    eq(f.slots[1].icon._width, px, size .. " icons")
    eq(f._height, BF.Height(px), "  and the frame's height")
end
P.SetSetting("buffs", "pulse", false)
BF.Show({ { key = "innervate", id = 29166, expiration = 120 } })
check(not f.slots[1].pulse:IsPlaying(), "pulse off: still")
P.ResetSettings("buffs")
-- Placement: below the fixate alert by default; dragged during a test, remembered.
BF.Show({ { key = "innervate", id = 29166, expiration = 120 } })
local p = f._points[#f._points]
check(p[1] == "CENTER" and p[5] == BF.DEFAULT_Y, "below the fixate alert by default")
BF.Unlock()
eq(f._mouse, true, "a test unlocks it")
function f:GetCenter() return 700, 400 end
f:GetScript("OnDragStop")(f)
eq(GP.charDB.buffs and GP.charDB.buffs.x, 700, "the drag is saved per character")
BF.Hide()
eq(f._mouse, false, "hiding locks it again")

-- The Configuration Panel.
GP.Options.Open("cat:Combat")
local page = GP.Options._test.pages["cat:Combat"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "buffs" then row = pl.row end end
check(row ~= nil, "on the Combat page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:buffs"].frame._children[1]
eq(#content.entryChecks, #B.ENTRIES, "a switch per buff")
eq(#content.soundChecks, #B.ENTRIES, "  and its sound")
eq(content.entryChecks[2].label:GetText(), "Innervate", "  named by the client")
content.entryChecks[2]:SetChecked(false)
content.entryChecks[2]:GetScript("OnClick")(content.entryChecks[2])
eq(P.Setting("buffs", "innervate"), false, "the Innervate switch")
content.soundChecks[1]:SetChecked(true)
content.soundChecks[1]:GetScript("OnClick")(content.soundChecks[1])
eq(P.Setting("buffs", "clearcastingSound"), true, "Clearcasting's sound switch")
local radios = 0
for _, w in ipairs(content._children) do if w._template == "UIRadioButtonTemplate" then radios = radios + 1 end end
eq(radios, 3, "three sizes")
P.ResetSettings("buffs")
content.test:GetScript("OnClick")(content.test)
check(BF.IsShown() and B.state.test, "Test shows the alerts")
GP.Options._test.win():Hide()

done("test_buffs_frame" .. (glass and " (glass)" or ""))
