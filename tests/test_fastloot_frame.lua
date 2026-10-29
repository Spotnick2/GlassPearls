-- Faster loot's coin text and panel (#36): a coins-only pass shows the money
-- observed while loot money came in, at the cursor, once the window closed,
-- before 2 s; every way it doesn't. In both looks:
-- tests/test_fastloot_frame_glass.lua runs it under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local GP = loadAddon()
local L, FR, P = GP.FastLoot, GP.FastLootFrame, GP.Pearls
local T = Enum.LootSlotType
local AUTO = { autoloot = true }

local function shown() return FR.IsShown() end
local function hide() local f = FR._test.frame(); if f then f:Hide() end end
local function earn(n)
    WoW.money = WoW.money + n
    WoW.fire("PLAYER_MONEY")
end
-- A coins-only corpse: the pass, then the events in a chosen order.
local function coins(steps, rows, opts)
    hide()
    WoW.resetBags()
    WoW.bags[0] = { size = 4, items = {} }
    WoW.money = 1000
    WoW.mouse = { x = 640, y = 360 }
    WoW.openLoot(rows or { { kind = T.Money } }, opts or AUTO)
    for _, step in ipairs(steps) do
        if step == "money" then earn(250)
        elseif step == "message" then WoW.fire("CHAT_MSG_MONEY", "You loot 2 Silver 50 Copper")
        elseif step == "close" then WoW.closeLoot()
        elseif type(step) == "number" then WoW.advance(step) end
    end
end

-- Shown: the money, at the cursor, then it fades and hides.
WoW.now = 0
coins({ "money", "message", "close" })
check(shown(), "coins only: the money floats up")
local f = FR._test.frame()
eq(f.amount, 250, "  the money observed")
check(f.text:GetText():find("250", 1, true), "  with the coin text")
local p = f._points[#f._points]
check(p[3] == "BOTTOMLEFT" and p[4] == 640 and p[5] == 360, "  at the cursor")
eq(f._mouse, false, "  click-through")
check(f.anim:IsPlaying(), "  rising and fading")
f.anim._scripts.OnFinished(f.anim)
check(not shown(), "  then gone")
-- Orders, and two changes added up.
coins({ "message", "money", "close" })
check(shown() and f.amount == 250, "the message before the money: shown")
coins({ "close", "money", "message" })
check(shown(), "the window closed first: shown when the rest comes")
coins({ "money", "money", "message", "close" })
eq(shown() and f.amount, 500, "two money changes added up")
-- The window closing during the pass itself (the game took the coins at once).
local realLoot = LootSlot
LootSlot = function(i) realLoot(i); WoW.closeLoot() end
coins({ "money", "message" }, nil, { autoloot = true, noOpened = true })
check(shown(), "the window closed during the pass: still shown when the money comes")
LootSlot = realLoot
-- Not shown.
coins({ "money", "close", 3, "message" })
check(not shown(), "no loot-money message within 2 s: nothing")
coins({ "message", "close", 3, "money" })
check(not shown(), "no money change within 2 s: nothing")
coins({ "message", "close" })
check(not shown(), "the money didn't change: nothing")
coins({ "money", "message", 3, "close" })
check(not shown(), "the window still open at the deadline: nothing")
check(not shown(), "  and the late close doesn't bring it back")
coins({ "money", "message", "close" }, { { kind = T.Money }, { kind = T.Currency } })
check(not shown(), "money and currency: no coin text")
WoW.items[10] = { name = "Linen", maxStack = 20 }
coins({ "money", "message", "close" }, { { kind = T.Money }, { id = 10 } })
check(not shown(), "money and an item: no coin text")
-- A new corpse cancels a pending one; so does switching off; so does the setting.
coins({ "money" })
WoW.closeLoot()
WoW.openLoot({ { id = 10 } }, AUTO)
WoW.fire("CHAT_MSG_MONEY", "x")
WoW.closeLoot()
check(not shown(), "a new corpse cancels the pending coin text")
coins({ "money", "message" })
P.Set("fastloot", false)
WoW.closeLoot()
check(not shown(), "switched off with a coin text pending: cancelled")
P.Set("fastloot", true)
P.SetSetting("fastloot", "coins", false)
coins({ "money", "message", "close" })
check(not shown(), "the setting off: nothing")
P.ResetSettings("fastloot")
-- Unreadable money.
local realMoney = GetMoney
GetMoney = function() return WoW.Secret("money") end
coins({ "money", "message", "close" })
check(not shown(), "money that can't be read: nothing")
local first = true
GetMoney = function()                      -- secret at the pass, plain afterwards
    if first then first = false; return WoW.Secret("money") end
    return realMoney()
end
coins({ "money", "message", "close" })
check(not shown(), "a baseline that can't be read: nothing (never measured from 0)")
GetMoney = realMoney
-- A second one replaces the first.
coins({ "money", "message", "close" })
WoW.mouse = { x = 100, y = 100 }
FR.Show(999, 100, 100)
eq(f.amount, 999, "a second one replaces the first")

-- The panel.
GP.Options.Open("cat:Loot & Bags")
local page = GP.Options._test.pages["cat:Loot & Bags"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "fastloot" then row = pl.row end end
check(row ~= nil, "on the Loot & Bags page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:fastloot"].frame._children[1]
local checks = {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
eq(#checks, 1, "one switch")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("fastloot", "coins"), false, "  the coin text")
P.ResetSettings("fastloot")

done("test_fastloot_frame" .. (glass and " (glass)" or ""))
