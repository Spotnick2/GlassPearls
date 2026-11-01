-- Junk spotlight (#41) turned on while the junk seller doesn't sell: its hooks
-- (the tooltip post-call, the bag frames' UpdateItems) come once the seller
-- does, by its switch (this file) or its autoSell (arg "autosell"), each once.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
local path = arg and arg[1] == "autosell" and "autosell" or "switch"

WoW.items[101] = { name = "Broken Fang", price = 5, quality = 0, classID = 15 }
WoW.bags = { [0] = { size = 16, items = { [1] = { id = 101, count = 3 } } } }

local GP = loadAddon()
local P = GP.Pearls
local CF1 = WoW.containerFrames[1]
local marks = GP.BagMarks.Marks("junkspot")
local function shown() return marks[CF1.Items[1]] ~= nil and marks[CF1.Items[1]]:IsShown() end
local function postCalls() return #(WoW.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) end
local function hooks() return (WoW.hooked[CF1] or {}).UpdateItems or 0 end
local function tip()
    GameTooltip._lines = {}
    GameTooltip:SetOwner(CF1.Items[1], "ANCHOR_RIGHT")
    for _, fn in ipairs(WoW.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
        fn(GameTooltip, { type = Enum.TooltipDataType.Item, id = 101, lines = {} })
    end
    return table.concat(GameTooltip._lines, "|")
end

local function sells(on)
    if path == "autosell" then P.SetSetting("junk", "autoSell", on) else P.Set("junk", on) end
end

sells(false)
WoW.showBag(CF1, { { 0, 1 } })
local calls0, hooks0 = postCalls(), hooks()
P.Set("junkspot", true)
eq(postCalls(), calls0, path .. ": spotlight on, the seller not selling: no tooltip hook yet")
eq(hooks(), hooks0, "  no bag hook yet")
check(not shown(), "  no coin")

sells(true)
eq(postCalls(), calls0 + 1, "the seller now sells: the tooltip hook, once")
eq(hooks(), hooks0 + 1, "  the bag hook, once")
check(shown(), "  the coin at once, the bags open")
check(tip():find("Eligible for automatic sale", 1, true), "  the tooltip line")
CF1:UpdateItems()
check(shown(), "  and on Blizzard's next bag update")

sells(false)
sells(true)
P.SetSetting("junkspot", "show", "bags")
P.SetSetting("junkspot", "show", "both")
eq(postCalls(), calls0 + 1, "off and on again, a setting change: still one tooltip hook")
eq(hooks(), hooks0 + 1, "  still one bag hook")

done("test_junkspot_late" .. (path == "autosell" and " (autosell)" or ""))
