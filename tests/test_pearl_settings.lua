-- A pearl's own settings (Pearls.Setting / SetSetting / ResetSettings /
-- CleanSettings): defaults fall through, only non-defaults are saved, Reset
-- clears and calls onReset, and junk saved by an older or newer copy is
-- cleaned at load.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local resets = 0
local GP = loadAddon({
    db = { settings = {
        demo = { mode = "white", greys = true, size = "big", stale = 1 },   -- greys = default, size = wrong type, stale = unknown
        other = { anything = "kept" },                                       -- no pearl claims it
        broken = "not a table",
    } },
    before = function(GP)
        GP.Pearls.Register({
            key = "demo", name = "Demo", Enable = function() end,
            defaults = { mode = "grey", greys = true, size = 3 },
            onReset = function() resets = resets + 1 end,
        })
    end,
})
local P = GP.Pearls

-- Cleaned at load.
local saved = GlassPearlsDB.settings
eq(saved.demo.mode, "white", "a real choice is kept")
eq(saved.demo.greys, nil, "a value equal to its default is dropped")
eq(saved.demo.size, nil, "a value of the wrong type is dropped")
eq(saved.demo.stale, nil, "a setting the pearl doesn't declare is dropped")
eq(saved.other and saved.other.anything, "kept", "an unknown pearl's settings stay")
eq(saved.broken, nil, "a pearl's settings that aren't a table are dropped")

-- Read: saved value, else default.
eq(P.Setting("demo", "mode"), "white", "Setting reads the saved value")
eq(P.Setting("demo", "size"), 3, "  else the default")
eq(P.Setting("demo", "nope"), nil, "an undeclared setting reads nil")
eq(P.Setting("ghost", "mode"), nil, "an unknown pearl reads nil")

-- Write: only non-defaults saved; the pearl's table goes when empty.
check(P.SetSetting("demo", "size", 5), "SetSetting")
eq(saved.demo.size, 5, "  saved")
P.SetSetting("demo", "size", 3)
eq(saved.demo.size, nil, "back to the default: not saved")
P.SetSetting("demo", "mode", "grey")
eq(saved.demo, nil, "nothing left: the pearl's table goes")
check(not P.SetSetting("demo", "nope", 1), "an undeclared setting is refused")
check(not P.SetSetting("ghost", "mode", 1), "an unknown pearl is refused")

-- Reset: everything back to defaults, then onReset.
P.SetSetting("demo", "mode", "white")
check(P.ResetSettings("demo"), "ResetSettings")
eq(saved.demo, nil, "  clears the saved settings")
eq(P.Setting("demo", "mode"), "grey", "  defaults again")
eq(resets, 1, "  and calls onReset once")
check(not P.ResetSettings("ghost"), "an unknown pearl can't be reset")

done("test_pearl_settings")
