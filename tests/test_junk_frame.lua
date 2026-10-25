-- "Sell junk & repair"'s Configuration Panel (#15): four switches wired to
-- their settings, the two repair choices, the guild note, and the two lists
-- (names, Remove, paging, Clear all), reached through the options window's
-- gear. tests/test_junk_frame_glass.lua runs it again under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
for id, name in pairs({ [201] = "Linen Cloth", [202] = "Wool Cloth", [203] = "Silk Cloth",
                        [204] = "Mageweave", [205] = "Runecloth", [206] = "Felcloth" }) do
    WoW.items[id] = { name = name, price = 10, quality = 1 }
end
local GP = loadAddon()
local P, SS, J = GP.Pearls, GP.SettingsSync, GP.Junk
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))

GP.Options.Open("cat:Loot & Bags")
local page = GP.Options._test.pages["cat:Loot & Bags"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "junk" then row = pl.row end end
check(row ~= nil, "on the Loot & Bags page")
eq(row.label:GetText(), "Sell junk & repair", "  switches live (no *)")
row.gear:GetScript("OnClick")(row.gear)
local cfg = GP.Options._test.pages["config:junk"]
local content = cfg.frame._children[1]
local checks, radios = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
    if w._template == "UIRadioButtonTemplate" then radios[#radios + 1] = w end
end
eq(#checks, 4, "four switches")
eq(#radios, 2, "two repair choices")
local names = { "autoSell", "sellGrey", "safe", "autoRepair" }
for i, name in ipairs(names) do
    local was = P.Setting("junk", name)
    checks[i]:SetChecked(not was)
    checks[i]:GetScript("OnClick")(checks[i])
    eq(P.Setting("junk", name), not was, "switch " .. i .. ": " .. name)
end
P.ResetSettings("junk")
check(radios[1]:GetChecked(), "guild funds first, by default")
radios[2]:GetScript("OnClick")(radios[2])
eq(P.Setting("junk", "repairFunds"), "mine", "'My money only'")
check(radios[2]:GetChecked() and not radios[1]:GetChecked(), "  the radios follow")
P.ResetSettings("junk")

-- The lists: names, Remove, paging, Clear all.
local sell, keep = content.sellList, content.keepList
for id = 201, 206 do J.List("sell", id) end
J.List("keep", 205)
sell.refresh()
keep.refresh()
eq(sell.count:GetText(), "5 item(s)", "the sell list counts its items (205 moved to keep)")
eq(sell.rows[1].label:GetText(), "Linen Cloth", "  by name")
eq(sell.pageText:GetText(), "1/2", "  in pages")
sell.next:GetScript("OnClick")(sell.next)
eq(sell.rows[1].label:GetText(), "Felcloth", "  page 2")
check(not sell.rows[2].label:IsShown(), "  one row on it")
sell.rows[1].remove:GetScript("OnClick")(sell.rows[1].remove)
check(not SS.SetHas(J.SELL, 206), "Remove takes it off")
eq(sell.pageText:GetText(), "", "  one page left")
eq(keep.rows[1].label:GetText(), "Runecloth", "the keep list shows its own")
keep.clear:GetScript("OnClick")(keep.clear)
check(not SS.SetHas(J.KEEP, 205), "Clear all empties the keep list")
check(not keep.clear:IsEnabled(), "  then disabled")
check(SS.SetHas(J.SELL, 201), "  the sell list untouched")
GP.Options._test.win():Hide()

done("test_junk_frame" .. (glass and " (glass)" or ""))
