-- Restock's food below the level cap (#84): by default a visit whose plan has
-- food opens the Ask window (every line) instead of buying on its own; "off"
-- leaves food out (the plan and the report say why); "buy" as before. At the
-- cap, food follows the mode. A level or a cap that can't be read counts as
-- below it. Water is never affected (the owner: food only).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

for id, name in pairs({ [1708] = "Sweet Nectar", [4544] = "Mulgore Spice Bread", [17031] = "Rune of Teleportation",
                        [17056] = "Light Feather" }) do
    WoW.items[id] = { name = name, maxStack = 20, price = 1, quality = 1 }
end
local GOODS = {
    { id = 1708, price = 1000, pack = 5 },
    { id = 4544, price = 1000, pack = 5 },
    { id = 17031, price = 1000, pack = 1 },
    { id = 17056, price = 30, pack = 1, maxStack = 5 },
}
local function goods(list)
    WoW.goods = {}
    for i, g in ipairs(list or GOODS) do
        local c = {}
        for k, v in pairs(g) do c[k] = v end
        WoW.goods[i] = c
    end
end
goods()
WoW.bags = { [0] = { size = 16, items = {} } }
WoW.class, WoW.playerLevel, WoW.money = "MAGE", 26, 100000
WoW.known[130], WoW.known[3561] = true, true
local GP = loadAddon()
local R, P, F = GP.Restock, GP.Pearls, GP.RestockFrame
P.Set("junk", false)   -- restock starts 0.3 s after the show

local function drain()
    for _ = 1, 60 do
        if #WoW.timers == 0 then return end
        WoW.flushTimers()
    end
end
local function bought()
    local t = {}
    for _, c in ipairs(WoW.calls) do if c[1] == "BuyMerchantItem" then t[#t + 1] = c[2] end end
    return t
end
local function visit(setup)
    goods()
    WoW.bags = { [0] = { size = 16, items = {} } }
    WoW.calls, WoW.money = {}, 100000
    if WoW.merchant then WoW.closeMerchant() end
    drain()
    if setup then setup() end
    newChat()
    WoW.openMerchant()
    drain()
end
local function foodIndex() for i, g in ipairs(GOODS) do if g.id == 4544 then return i end end end
local function boughtFood()
    for _, i in ipairs(bought()) do if i == foodIndex() then return true end end
    return false
end

eq(P.Setting("restock", "foodUnderCap"), "ask", "below the cap, food asks first by default")
eq(P.Setting("restock", "mode"), "auto", "  the mode itself stays 'buy when the merchant opens'")

-- Below the cap (26 of 60), the default: the visit asks, nothing bought on its own.
visit()
check(F.IsShown(), "below the cap, food in the plan: the Ask window opens")
eq(#bought(), 0, "  nothing bought on its own")
local rows = {}
for _, row in ipairs(F.Get() and F.Get().rows or {}) do if row:IsShown() then rows[#rows + 1] = row.text:GetText() end end
check(table.concat(rows, "\n"):find("Mulgore Spice Bread", 1, true), "  food is in it")
check(table.concat(rows, "\n"):find("Sweet Nectar", 1, true), "  and the other lines too")
F.Hide()

-- Below the cap with no food to buy: the mode as usual (water bought on its own).
visit(function() P.SetSetting("restock", "food", false) end)
check(not F.IsShown(), "no food line: no Ask window")
check(#bought() > 0 and not boughtFood(), "  the rest bought as usual (water never asks)")
P.SetSetting("restock", "food", true)

-- "off": food left out, the rest bought; the plan says why.
visit(function() P.SetSetting("restock", "foodUnderCap", "off") end)
check(not F.IsShown(), "'off': no Ask window")
check(#bought() > 0 and not boughtFood(), "  the rest bought, never food")
local _, notes = R.Plan()
check(table.concat(notes, "\n"):find("food below the level cap (your setting)", 1, true), "  the plan says why")
newChat()
R.Report()
check(chatHas("not bought: food below the level cap"), "  /gpearls restock too")

-- "buy": as before.
visit(function() P.SetSetting("restock", "foodUnderCap", "buy") end)
check(not F.IsShown() and boughtFood(), "'buy': food bought on its own")

-- At the cap: food follows the mode, whatever the rule says.
for _, rule in ipairs({ "ask", "off" }) do
    visit(function()
        P.SetSetting("restock", "foodUnderCap", rule)
        WoW.maxLevel = 26
    end)
    check(not F.IsShown() and boughtFood(), "at the cap, rule '" .. rule .. "': food bought on its own")
end

-- A cap or a level that can't be read counts as below it: asks.
for _, case in ipairs({ { "the cap throwing", function() WoW.maxLevel = "throw" end },
                        { "the cap secret", function() WoW.maxLevel = WoW.Secret("cap") end },
                        { "the level unreadable", function() WoW.maxLevel = 60; WoW.playerLevel = nil end } }) do
    visit(function()
        P.SetSetting("restock", "foodUnderCap", "ask")
        case[2]()
    end)
    check(not boughtFood(), case[1] .. ": counts as below the cap, food not bought on its own")
    F.Hide()
    WoW.maxLevel, WoW.playerLevel = nil, 26
end

-- "Ask first" mode is unchanged: it asks either way.
visit(function()
    P.ResetSettings("restock")
    P.SetSetting("restock", "mode", "ask")
    WoW.maxLevel = 26
end)
check(F.IsShown(), "mode 'ask first' at the cap: the Ask window as before")
F.Hide()
WoW.maxLevel = nil
P.ResetSettings("restock")

-- The panel: three choices under "Food below the level cap".
GP.Options.Open("cat:Loot & Bags")
local row
for _, pl in ipairs(GP.Options._test.pages["cat:Loot & Bags"].placed) do if pl.key == "restock" then row = pl.row end end
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:restock"].frame._children[1]
local radios = {}   -- the mode's own "ask" comes first; the food group's three are the last ones
for _, w in ipairs(content._children) do
    if w.value == "ask" or w.value == "off" or w.value == "buy" then radios[w.value] = w end
end
check(radios.ask and radios.off and radios.buy, "the panel has the three choices")
check(radios.ask:GetChecked(), "  'Ask first' checked by default")
radios.off:GetScript("OnClick")(radios.off)
eq(P.Setting("restock", "foodUnderCap"), "off", "  'Don't buy food' sets it")
P.ResetSettings("restock")
GP.Options._test.win():Hide()

done("test_restock_foodcap")
