-- Junk spotlight (#41): off by default; only while the junk seller sells
-- (on, with autoSell); the coin and the tooltip line by Junk.Judge, bags 0-4
-- only; "eligible", not a promise; each show setting; refreshed with the bags
-- open and no bag update by the list commands, the options lists, a synced
-- change, the seller's settings and switch, equipment sets and lock changes.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ITEMS = {
    [101] = { name = "Broken Fang", price = 5, quality = 0, classID = 15 },
    [103] = { name = "Linen Cloth", price = 10, quality = 1, classID = 7 },
    [107] = { name = "Quest Bone", price = 3, quality = 0, classID = 15 },
    [108] = { name = "Cracked Pot", price = 2, quality = 0, classID = 15 },
    [109] = { name = "Old Coin", price = 7, quality = 0, classID = 15 },
}
for id, it in pairs(ITEMS) do WoW.items[id] = it end
WoW.bags = { [0] = { size = 16, items = {
    [1] = { id = 101, count = 3 },          -- grey: eligible
    [2] = { id = 103, count = 5 },          -- white: only if listed
    [3] = { id = 107 },                     -- a quest item
    [4] = { id = 108, refundable = true },  -- refundable: never
} }, [5] = { size = 4, items = { [1] = { id = 109 } } } }       -- not one of the seller's bags
WoW.quest = { ["0:3"] = { isQuestItem = true } }

local GP = loadAddon()
local JS, P, SS, J = GP.JunkSpot, GP.Pearls, GP.SettingsSync, GP.Junk
local CF1 = WoW.containerFrames[1]
local marks = GP.BagMarks.Marks("junkspot")
local function shown(i) return marks[CF1.Items[i]] ~= nil and marks[CF1.Items[i]]:IsShown() end
local function open() WoW.showBag(CF1, { { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 5, 1 } }) end
-- The tooltip for the button at index i, or another owner.
local function tip(i, id, owner)
    GameTooltip._lines = {}
    GameTooltip:SetOwner(owner or CF1.Items[i], "ANCHOR_RIGHT")
    for _, fn in ipairs(WoW.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
        fn(GameTooltip, { type = Enum.TooltipDataType.Item, id = id, lines = {} })
    end
    return table.concat(GameTooltip._lines, "|")
end

open()
check(not P.IsOn("junkspot"), "off by default")
eq(next(marks), nil, "  no marks")
P.Set("junkspot", true)
eq(P.Setting("junkspot", "show"), "both", "both by default")
check(shown(1), "a grey: marked")
check(not shown(2), "a white, not listed: not")
check(not shown(3), "a quest item: not")
check(not shown(4), "refundable: not")
check(not shown(5), "bag 5 (not the seller's): not")
check(tip(1, 101):find("Eligible for automatic sale: " .. GP.TrainingFrame.Money(15), 1, true),
    "the tooltip: eligible, with the stack's value")
eq(tip(2, 103), "", "  a white: no line")
eq(tip(5, 109), "", "  bag 5, its data.id matching: no line")
eq(tip(1, 999), "", "  data.id not the slot's: no line")
eq(tip(1, 101, UIParent), "", "  an owner that isn't a bag button: no line")

-- Refreshed with the bags open, no bag update.
J.List("sell", 103)
check(shown(2), "/gpearls sell: marked at once")
J.Forget(103)
check(not shown(2), "/gpearls forget: unmarked at once")
J.List("keep", 101)
check(not shown(1), "/gpearls keep: unmarked at once")
check(tip(1, 101):find("Kept: on your keep list", 1, true), "  the tooltip: kept")
SS.SetRemove(J.KEEP, 101)                               -- the options list's Remove
check(shown(1), "the options list's Remove: marked again")
SS.SetAdd(J.SELL, 103)
SS.SetClear(J.SELL)                                     -- the options list's Clear all
check(not shown(2), "Clear all: unmarked")
P.SetSetting("junk", "sellGrey", false)
check(not shown(1), "the seller's sellGrey off: unmarked")
P.ResetSettings("junk")
check(shown(1), "  a reset: marked again")
P.SetSetting("junk", "autoSell", false)
check(not shown(1), "the seller kept for repairs only: nothing")
eq(tip(1, 101), "", "  no line either")
P.SetSetting("junk", "autoSell", true)
P.Set("junk", false)
check(not shown(1), "the seller off: nothing")
P.Set("junk", true)
check(shown(1), "  on again: marked")
WoW.bags[0].items[1].locked = true
WoW.fire("ITEM_LOCK_CHANGED", 0, 1)
check(not shown(1), "locked (ITEM_LOCK_CHANGED alone): hidden")
WoW.bags[0].items[1].locked = nil
WoW.fire("ITEM_LOCK_CHANGED", 0, 1)
check(shown(1), "  unlocked: back")
WoW.sets = { [1] = { 101 } }
WoW.fire("EQUIPMENT_SETS_CHANGED")
check(not shown(1), "now in an equipment set (EQUIPMENT_SETS_CHANGED): hidden")
WoW.sets = {}
WoW.fire("EQUIPMENT_SETS_CHANGED")
check(shown(1), "  out of it: back")

-- A synced list change.
local hi = GetServerTime() + 1000
GP.AccountSync._test.dispatch("ST\nGPS1\nS\t" .. J.SELL .. "\nM\t103\t1\t" .. hi .. "\tPlayer-1-BBB\t1",
    { name = "Alt" }, 1)
check(shown(2), "a synced sell-list change: marked at once")
SS.SetRemove(J.SELL, 103)

-- Eligibility, not a promise: buyback-safe and a GUID unreadable still show it.
P.SetSetting("junk", "safe", true)
check(shown(1), "buyback-safe on: still eligible")
P.ResetSettings("junk")

-- Each show setting.
P.SetSetting("junkspot", "show", "tooltip")
check(not shown(1), "tooltip only: no coin")
check(tip(1, 101) ~= "", "  the line")
P.SetSetting("junkspot", "show", "bags")
check(shown(1), "bags only: the coin")
eq(tip(1, 101), "", "  no line")
P.SetSetting("junkspot", "show", "both")

-- Combat: no line.
WoW.fire("PLAYER_REGEN_DISABLED")
eq(tip(1, 101), "", "in combat: no line")
WoW.fire("PLAYER_REGEN_ENABLED")

-- Off: hidden, and nothing on a later update.
P.Set("junkspot", false)
check(not shown(1), "off: hidden")
J.List("sell", 103)
check(not shown(2), "  a list change while off: nothing")
eq(tip(1, 101), "", "  no line")

done("test_junkspot")
