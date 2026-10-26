-- The restock pearl's "ask first" window and its panel (#14): the rows, the
-- total and limits, Buy from its click (the shown counts as the most), Not
-- now, gone with the merchant; the panel's switches, numbers (clamped) and
-- this class's reagents; the command. tests/test_restock_frame_glass.lua runs
-- it again under Glass UI.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
for id, name in pairs({ [1708] = "Sweet Nectar", [17031] = "Rune of Teleportation", [17020] = "Arcane Powder" }) do
    WoW.items[id] = { name = name, maxStack = 20, price = 1, quality = 1 }
end
WoW.goods = { { id = 1708, price = 1000, pack = 5 }, { id = 17031, price = 1000, pack = 1 } }
WoW.bags = { [0] = { size = 16, items = {} } }
WoW.class, WoW.playerLevel, WoW.money = "MAGE", 26, 100000
WoW.known[3561] = true
local GP = loadAddon()
local R, P, F = GP.Restock, GP.Pearls, GP.RestockFrame
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))
P.Set("junk", false)
P.SetSetting("restock", "mode", "ask")

local function soon()
    for _ = 1, 100 do
        local any = false
        for _, t in ipairs(WoW.timers) do if t.s <= 1 then any = true end end
        if not any then return end
        WoW.flushTimers(1)
    end
end
local function bought()
    local n = 0
    for _, c in ipairs(WoW.calls) do if c[1] == "BuyMerchantItem" then n = n + 1 end end
    return n
end
local function rows()
    local out = {}
    for _, row in ipairs(F.Get().rows) do if row:IsShown() then out[#out + 1] = row.text:GetText() end end
    return table.concat(out, ", ")
end

-- Ask first.
WoW.openMerchant()
soon()
check(F.IsShown(), "ask first: the window when the merchant opens")
eq(rows(), "10 Rune of Teleportation, 20 Sweet Nectar", "  a row per line, with the count")
eq(F.Get().total:GetText(), "Total: 14000c", "  the total")
check(F.Get().limits:GetText():find("50%", 1, true) and F.Get().limits:GetText():find("5g", 1, true), "  the limits")
eq(bought(), 0, "  nothing bought yet")
F.Get().buy:GetScript("OnClick")(F.Get().buy)
soon()
check(not F.IsShown(), "Buy: the window goes")
eq(bought(), 2, "  and it buys")
WoW.closeMerchant()
WoW.bags[0].items = {}
WoW.calls = {}
WoW.openMerchant()
soon()
F.Get().later:GetScript("OnClick")(F.Get().later)
check(not F.IsShown(), "Not now: gone")
eq(bought(), 0, "  nothing bought")
WoW.closeMerchant()
WoW.openMerchant()
soon()
WoW.closeMerchant()
check(not F.IsShown(), "the merchant closed: gone")
WoW.openMerchant()
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
soon()
check(not F.IsShown(), "in combat when it would ask: no window")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.closeMerchant()
-- The shown counts are the most: more needed after the window opened isn't bought.
WoW.bags[0].items = { [1] = { id = 17031, count = 5 }, [2] = { id = 1708, count = 20 } }
WoW.calls = {}
WoW.openMerchant()
soon()
eq(rows(), "5 Rune of Teleportation", "5 runes of 10 carried: the window offers 5")
WoW.bags[0].items = {}
F.Buy()
soon()
eq(WoW.calls[1] and WoW.calls[1][1] == "BuyMerchantItem" and WoW.calls[1][3], 5, "  they went meanwhile: Buy still keeps to the shown 5")
WoW.closeMerchant()
P.ResetSettings("restock")
P.SetSetting("restock", "mode", "ask")

-- The command.
WoW.bags[0].items = {}
newChat()
SlashCmdList.GLASSPEARLS("restock")
check(newChat()[1]:find("open a merchant", 1, true), "/gpearls restock away from a merchant: says to open one")
WoW.openMerchant()
soon()
newChat()
SlashCmdList.GLASSPEARLS("restock")
local said = table.concat(newChat(), "\n")
check(said:find("10 Rune of Teleportation (reagent; you have 0 of 10)", 1, true), "  at one: each line and why: " .. said)
WoW.closeMerchant()

-- The panel.
GP.Options.Open("cat:Loot & Bags")
local row
for _, pl in ipairs(GP.Options._test.pages["cat:Loot & Bags"].placed) do if pl.key == "restock" then row = pl.row end end
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:restock"].frame._children[1]
local checks, boxes = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
    if w._template == "InputBoxTemplate" then boxes[#boxes + 1] = w end
end
eq(#checks, 4, "four switches: food, water, ammo, reagents")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("restock", "food"), false, "  the first: food")
-- Numbers: three targets, two limits, then the mage's reagents.
eq(#boxes, 5 + 4, "five numbers and a mage's four reagents")
eq(boxes[1]:GetText(), "20", "  the food target shown")
boxes[1]:SetText("500")
boxes[1]:GetScript("OnEnterPressed")(boxes[1])
eq(P.Setting("restock", "foodTarget"), 200, "  clamped to its range")
eq(boxes[1]:GetText(), "200", "  and shown so")
boxes[4]:SetText("abc")
boxes[4]:GetScript("OnEditFocusLost")(boxes[4])
eq(P.Setting("restock", "budget"), 50, "  not a number: unchanged")
eq(boxes[4]:GetText(), "50", "  and shown back")
check(boxes[6].label:GetText():find("Arcane Powder", 1, true), "the reagents by name: " .. tostring(boxes[6].label:GetText()))
P.ResetSettings("restock")
GP.Options._test.win():Hide()

-- Off: nothing at a merchant.
SlashCmdList.GLASSPEARLS("restock off")
P.SetSetting("restock", "mode", "ask")
WoW.openMerchant()
soon()
check(not F.IsShown(), "off: no window")
WoW.closeMerchant()

done("test_restock_frame" .. (glass and " (glass)" or ""))
