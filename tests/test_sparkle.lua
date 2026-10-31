-- Quest loot sparkle (#44): off by default; on, the five CVars set and the
-- player's own values remembered once; re-applied 1 s after a graphics change
-- (one pass for a burst, our own CVAR_UPDATE settles); never in combat;
-- Disable restores only what still reads ours, deferred past combat,
-- cancelled by switching back on; what can't be restored stays remembered and
-- `/gpearls sparkle restore` finishes it while off.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local SP, P = GP.Sparkle, GP.Pearls
local NAMES = SP.ORDER

local function preset()
    WoW.cvarValues.outlineModeShowLootEffectWhenDisabled = "0"
    for i = 2, #NAMES do WoW.cvarValues[NAMES[i]] = "2" end
end
local function wanted()
    for _, n in ipairs(NAMES) do if WoW.cvarValues[n] ~= SP.WANTED[n] then return false end end
    return true
end
local function before() return GP.db.sparkle and GP.db.sparkle.before or {} end
local function sets() local n = #WoW.cvarSets; WoW.cvarSets = {}; return n end
local function fight() WoW.fire("PLAYER_REGEN_DISABLED"); WoW.combat = true end
local function peace() WoW.combat = false; WoW.fire("PLAYER_REGEN_ENABLED") end

preset()
check(not P.IsOn("sparkle"), "off by default")
eq(sets(), 0, "  nothing set")
check(P.Get("sparkle").desc:find("outline", 1, true) and P.Get("sparkle").desc:find("restart", 1, true),
    "the trade-off and the restart in its description (the checkbox tooltip)")

P.Set("sparkle", true)
check(wanted(), "on: the five set")
eq(before().graphicsOutlineMode, "2", "  the player's own remembered")
eq(before().outlineModeShowLootEffectWhenDisabled, "0", "  the loot effect's too")
sets()
WoW.advance(2)
eq(sets(), 0, "  our own CVAR_UPDATEs settle: nothing set again")

-- A preset, as a burst of updates.
preset()
WoW.cvarReads = 0
WoW.fire("CVAR_UPDATE", "graphicsOutlineMode", "2")
WoW.fire("CVAR_UPDATE", "raidGraphicsOutlineMode", "2")
WoW.advance(0.5)
check(not wanted(), "a preset: not at once")
WoW.advance(0.6)
check(wanted(), "  re-applied 1 s after the last update")
eq(sets(), #NAMES, "  one pass for the burst")
eq(WoW.cvarReads, #NAMES, "  one read pass, not one per update")
eq(before().graphicsOutlineMode, "2", "  the baseline kept (remembered once)")
WoW.advance(2)
eq(sets(), 0, "  and it settles")
-- The update arriving later than the set (async).
WoW.cvarEventsLater = true
preset()
WoW.fire("GX_RESTARTED")
WoW.advance(1)
check(wanted(), "GX_RESTARTED: re-applied")
for _, q in ipairs(WoW.cvarQueue) do WoW.fire("CVAR_UPDATE", q[1], q[2]) end
WoW.cvarQueue, WoW.cvarEventsLater = {}, nil
sets()
WoW.advance(2)
eq(sets(), 0, "  late updates settle too")
-- The player's own value is remembered once: a later change while on isn't.
WoW.cvarValues.graphicsOutlineMode = "1"
WoW.fire("GX_RESTARTED")
WoW.advance(1)
eq(before().graphicsOutlineMode, "2", "remembered once: a later value while on isn't")
-- A loading screen.
preset()
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(wanted(), "a loading screen: applied")

-- Combat holds it.
preset()
sets()
fight()
WoW.fire("CVAR_UPDATE", "graphicsOutlineMode", "2")
WoW.advance(1)
check(not wanted(), "in combat: held")
eq(sets(), 0, "  nothing set")
peace()
check(wanted(), "  applied at the fight's end")

-- Refusals, throws, unreadable and unknown CVars.
sets()
preset()
WoW.cvarRefuse.OutlineEngineMode = false
WoW.cvarRefuse.RAIDOutlineEngineMode = "throw"
WoW.cvarValues.raidGraphicsOutlineMode = WoW.Secret("cvar")
WoW.fire("GX_RESTARTED")
WoW.advance(1)
eq(WoW.cvarValues.graphicsOutlineMode, "0", "a refused and a throwing set: the others applied")
eq(WoW.cvarValues.OutlineEngineMode, "2", "  the refused one unchanged")
check(GP.failures["pearl sparkle OutlineEngineMode"] and GP.failures["pearl sparkle RAIDOutlineEngineMode"],
    "  both recorded as failures")
WoW.cvarRefuse = {}
WoW.cvarValues.raidGraphicsOutlineMode = "2"
WoW.cvarValues.RAIDOutlineEngineMode = nil
WoW.fire("GX_RESTARTED")
WoW.advance(1)
eq(WoW.cvarValues.RAIDOutlineEngineMode, nil, "a CVar the client doesn't know: skipped")
WoW.cvarValues.RAIDOutlineEngineMode = "0"

--------------------------------------------------------------------------------
-- Disable restores

P.Set("sparkle", false)
eq(WoW.cvarValues.graphicsOutlineMode, "2", "off: the player's outline back")
eq(WoW.cvarValues.outlineModeShowLootEffectWhenDisabled, "0", "  the loot effect's too")
check(next(before()) == nil, "  nothing remembered any more")
sets()
preset()
WoW.fire("GX_RESTARTED")
WoW.advance(2)
eq(sets(), 0, "  off: nothing set")
eq(WoW.cvarValues.graphicsOutlineMode, "2", "  no more enforcing")

-- A value the player changed since stays theirs.
P.Set("sparkle", true)
WoW.cvarValues.graphicsOutlineMode = "1"
P.Set("sparkle", false)
eq(WoW.cvarValues.graphicsOutlineMode, "1", "changed since: the player's stays")
eq(WoW.cvarValues.OutlineEngineMode, "2", "  the others restored")
check(next(before()) == nil, "  nothing left remembered")

-- Disable before a pending apply: it never runs.
preset()
P.Set("sparkle", true)
preset()
WoW.fire("CVAR_UPDATE", "graphicsOutlineMode", "2")
P.Set("sparkle", false)
sets()
WoW.advance(2)
eq(sets(), 0, "off before the pending apply: it never runs")

-- Disable in combat: restored at the fight's end, also while off.
preset()
P.Set("sparkle", true)
fight()
P.Set("sparkle", false)
check(wanted(), "off in combat: not restored yet")
check(SP.state.restorePending, "  pending")
peace()
eq(WoW.cvarValues.graphicsOutlineMode, "2", "  restored at the fight's end")
-- Off in combat, then on again before it ends: no restore, the baseline kept.
P.Set("sparkle", true)
fight()
P.Set("sparkle", false)
P.Set("sparkle", true)
peace()
check(wanted(), "off then on in combat: no restore")
newChat()
P.Command("sparkle").run()
check(chatHas("Quest loot sparkle: on%.$"), "  nothing said pending")
eq(before().graphicsOutlineMode, "2", "  the baseline kept")

-- A restore refused, throwing or unreadable: kept, the others restored.
WoW.cvarRefuse.graphicsOutlineMode = "nil"
WoW.cvarRefuse.OutlineEngineMode = "throw"
WoW.cvarRefuse.RAIDOutlineEngineMode = "throwRead"
newChat()
P.Set("sparkle", false)
eq(WoW.cvarValues.raidGraphicsOutlineMode, "2", "a refused restore: the others restored")
eq(before().graphicsOutlineMode, "2", "  a nil answer: kept")
eq(before().OutlineEngineMode, "2", "  a throw: kept")
eq(before().RAIDOutlineEngineMode, "2", "  an unreadable read: kept")
eq(before().raidGraphicsOutlineMode, nil, "  a restored one: forgotten")
check(chatHas("3 outline setting%(s%) couldn't be put back"), "  said")
WoW.cvarRefuse = {}
P.Command("sparkle").run("restore")
check(next(before()) == nil, "/gpearls sparkle restore, while off: finished")
eq(WoW.cvarValues.graphicsOutlineMode, "2", "  the outline back")
check(chatHas("your outline settings are back"), "  said")
-- The command while on, and in combat.
P.Set("sparkle", true)
newChat()
P.Command("sparkle").run("restore")
check(chatHas("is on: switch it off"), "restore while on: switch it off first")
WoW.cvarRefuse.graphicsOutlineMode = false
P.Set("sparkle", false)
WoW.cvarRefuse = {}
fight()
P.Command("sparkle").run("restore")
check(chatHas("comes back after the fight"), "restore in combat: after the fight")
peace()
check(next(before()) == nil, "  done at its end")

-- The report.
newChat()
P.Command("sparkle").run()
check(chatHas("Quest loot sparkle: off%.") and chatHas("graphicsOutlineMode: 2 now, 0 wanted"), "the report")

done("test_sparkle")
