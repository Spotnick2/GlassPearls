-- The minimap button (#121) when following the minimap's size is refused:
-- recorded, the button made and placed all the same.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

Minimap.HookScript = function() error("hook refused") end
local GP = loadAddon()
local btn = GP.Minimap.Button()
check(GP.failures["minimap size"] ~= nil, "a refused HookScript is recorded")
check(btn ~= nil and btn:GetParent() == Minimap, "  the button made all the same")
check(btn._points and #btn._points > 0, "  and placed")
check(btn:IsShown(), "  and shown")

done("test_minimap_fail")
