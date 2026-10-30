-- The centre text any pearl shows (Core/Notice.lua; instance gear #43, pet
-- care #38): click-through, held then faded, replaced by a new one.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local N = GP.Notice

check(not N.IsShown(), "nothing shown at login outdoors")
N.Show("Equip your Argent Dawn Commission")
local f = N._test.frame()
check(N.IsShown(), "shown")
eq(f.text:GetText(), "Equip your Argent Dawn Commission", "  the text")
eq(f._mouse, false, "  click-through")
local p = f._points[#f._points]
check(p[1] == "CENTER" and p[3] == "CENTER" and p[5] == N.Y, "  in the middle, below the fixate alert")
check(N.Y < 260, "  (+200 below +260)")
check(f.anim:IsPlaying(), "  held, then fading")
f.anim._scripts.OnFinished(f.anim)
check(not N.IsShown(), "  then gone")
N.Show("one")
f:SetAlpha(0.3)                                  -- mid-fade
N.Show("two")
eq(f.text:GetText(), "two", "a new one replaces the old")
eq(f:GetAlpha(), 1, "  at full alpha")
f.anim._scripts.OnFinished(f.anim)

done("test_notice")
