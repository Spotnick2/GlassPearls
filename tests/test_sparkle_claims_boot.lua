-- The stars' CVars at a login with the whole quest loot sparkle pearl off (#90,
-- Codex round 2): its Start, called for every pearl, applies the off edge the
-- saved activation calls for and finishes the put-back once settled, through
-- the real bootstrap.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local IA, RANGE, ICON = "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetIconGameObject"
-- Ours left from the last session: the interact owned while on, the range waiting to be put back.
WoW.cvarValues[IA], WoW.cvarValues[RANGE], WoW.cvarValues[ICON] = "3", "60", "0"
local GP = loadAddon({ db = { sparkle = {
    softActive = true,
    soft = {
        [IA] = { old = "1", ours = "3", st = "owned" },
        [RANGE] = { old = "10", ours = "60", st = "release" },
    },
} } })
local ST, P = GP.SparkleStars, GP.Pearls

check(not P.IsOn("sparkle") and not GP.Sparkle.enabled, "the pearl is off")
check(ST.state.started, "its Start ran anyway")
local s = ST._test.store()
eq(s.softActive, nil, "the saved activation ended: the off edge")
eq(s.soft[IA] and s.soft[IA].st, "release", "  the owned one to put back")
eq(WoW.cvarValues[IA], "3", "inside the login window: nothing written")
check(ST._test.driver._scripts.OnUpdate ~= nil, "  the passes armed")
WoW.now = ST.SETTLE + 1
WoW.tick(ST.TICK + 0.01)
eq(WoW.cvarValues[IA] .. "," .. WoW.cvarValues[RANGE], "1,10", "settled: both put back")
check(next(s.soft) == nil, "  nothing left")
WoW.tick(ST.TICK + 0.01)
check(ST._test.driver._scripts.OnUpdate == nil, "  the passes stop")
eq(WoW.cvarValues[ICON], "0", "a name never claimed: untouched")

done("test_sparkle_claims_boot")
