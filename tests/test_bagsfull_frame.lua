-- The bags-full helper's window and Configuration Panel (#6): where it sits,
-- what each state shows, and the panel reached through the options window's
-- gear (quality scope, greys first, the never-suggest list).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local BF, SS, P = GP.BagsFull, GP.SettingsSync, GP.Pearls
local function tick() WoW.flushTimers(0) end
for id, it in pairs({
    [1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 },
    [2] = { name = "Old Boot", price = 30, quality = 0, maxStack = 1 },
    [10] = { name = "Ring", price = 620, quality = 2, maxStack = 1, classID = 4 },
    [13] = { name = "Tooth", price = 1, quality = 0, maxStack = 1 },
}) do WoW.items[id] = it end
WoW.bags[0] = { size = 2, items = { [1] = { id = 1 }, [2] = { id = 2 } } }

-- Beside the loot window.
WoW.openLoot({ { id = 10, qty = 1 } })
tick()
local f = GP.BagsFullFrame._test.frame()
check(f:IsShown(), "shown")
local p = f._points[#f._points]
check(p and p[1] == "TOPLEFT" and p[2] == LootFrame and p[3] == "TOPRIGHT", "anchored to the loot window's right")
eq(f.title:GetText(), "Bags full!", "titled Bags full!")
eq(f.sub:GetText(), "Destroy a low-value item to loot.", "  the line says what to do")
eq(f.out.name:GetText(), "Grey Junk", "the Destroy card: the item")
eq(f.out.value:GetText(), "5c", "  its value")
eq(f.counter:GetText(), "1/2", "  1 of 2")
eq(f.inc.name:GetText(), "Ring", "the You get card: the ring")
eq(f.inc.caption:GetText(), "You get:", "  one row: plain caption")
eq(f.net:GetText(), "You lose 5c, you get 620c.", "the net line")
eq(f.button:GetText(), "Destroy & loot", "the button")
check(f.button:IsShown() and not f.anyway:IsShown(), "  shown, 'Choose anyway' not")
check(f.never:IsShown(), "the X shows")
-- Tooltips use Blizzard's bag and loot tooltips.
f.out:GetScript("OnEnter")(f.out)
eq(GameTooltip._owner, f.out, "hovering the Destroy card shows its tooltip")
f.inc:GetScript("OnEnter")(f.inc)
eq(GameTooltip._owner, f.inc, "  and the You get card")

-- Dragged: where the player put it, from then on (per character).
f._left, f._top = 300, 700
function f:GetLeft() return self._left end
function f:GetTop() return self._top end
f:GetScript("OnDragStop")(f)
check(GP.charDB.bagsfull and GP.charDB.bagsfull.moved, "dragging saves its place for this character")
BF.Evaluate()
p = f._points[#f._points]
check(p[1] == "TOPLEFT" and p[2] == UIParent and p[4] == 300 and p[5] == 700, "  and it stays there, not beside the loot window")
GP.charDB.bagsfull = nil
WoW.closeLoot(); tick()

-- Not worth it: the message, and "Choose anyway" instead of the button.
WoW.bags[0].items = { [1] = { id = 2 }, [2] = { id = 2 } }
WoW.openLoot({ { id = 13, qty = 1 } })
tick()
eq(f.sub:GetText(), "This loot is worth less than anything in your bags.", "not worth it: said")
check(f.anyway:IsShown() and not f.button:IsShown(), "  'Choose anyway' instead of the button")
check(not f.never:IsShown() and not f.prev:IsShown(), "  no browsing")
eq(f.net:GetText(), "", "  no net line")
f.anyway:GetScript("OnClick")(f.anyway)
check(f.button:IsShown() and not f.anyway:IsShown(), "'Choose anyway': the button is back")
WoW.closeLoot(); tick()

-- Several rows: the caption counts them.
WoW.bags[0].items = { [1] = { id = 1 }, [2] = { id = 2 } }
WoW.openLoot({ { id = 10, qty = 1 }, { id = 13, qty = 1 } })
tick()
eq(f.inc.caption:GetText(), "You get (1/2):", "two rows: 'You get (1/2):'")
f.inc:GetScript("OnClick")(f.inc)
eq(f.inc.caption:GetText(), "You get (2/2):", "  a click: the next row")
WoW.closeLoot(); tick()

-- Make room: its own line and button text.
WoW.fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
tick()
eq(f.sub:GetText(), "Destroy a low-value item, then loot again.", "make room: its line")
eq(f.button:GetText(), "Destroy", "  the button just destroys")
check(f.inc.msg:IsShown(), "  the You get card says to loot again")
f.close:GetScript("OnClick")(f.close)
check(not f:IsShown(), "the close button hides it")

-- The Configuration Panel, through the options window's gear.
GP.Options.Open("cat:Loot & Bags")
local page = GP.Options._test.pages["cat:Loot & Bags"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "bagsfull" then row = pl.row end end
check(row ~= nil, "the helper is on the Loot & Bags page")
eq(row.label:GetText(), "Bags full helper", "  switches live (no *)")
check(row.gear:IsShown(), "  with a gear")
row.gear:GetScript("OnClick")(row.gear)
local cfg = GP.Options._test.pages["config:bagsfull"]
check(cfg and cfg.frame:IsShown(), "the gear opens its Configuration Panel")
-- Find the panel's controls (the content frame the configure callback built).
local content = cfg.frame._children[1]
local radios, checks = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UIRadioButtonTemplate" then radios[#radios + 1] = w end
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
end
eq(#radios, 2, "two scope choices")
check(radios[1]:GetChecked() and not radios[2]:GetChecked(), "  grey only by default")
radios[2]:GetScript("OnClick")(radios[2])
eq(P.Setting("bagsfull", "scope"), "white", "choosing grey and white saves it")
check(radios[2]:GetChecked() and not radios[1]:GetChecked(), "  and the radios follow")
eq(#checks, 1, "one check: greys first")
check(checks[1]:GetChecked(), "  on by default")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("bagsfull", "greysFirst"), false, "  unticking saves it")
-- Reset puts them back.
cfg.reset:GetScript("OnClick")(cfg.reset)
eq(P.Setting("bagsfull", "scope"), "grey", "Reset: grey only again")
check(radios[1]:GetChecked(), "  and the panel shows it")
-- The never-suggest list: names, remove, clear all, pages.
SS.SetAdd(BF.KEEP, 1)
SS.SetAdd(BF.KEEP, 2)
content.refreshList()
eq(content.rows[1].label:GetText(), "Grey Junk", "the list shows the kept items by name")
eq(content.rows[2].label:GetText(), "Old Boot", "  sorted by item ID")
check(not content.rows[3].label:IsShown(), "  and nothing more")
content.rows[1].remove:GetScript("OnClick")(content.rows[1].remove)
check(not SS.SetHas(BF.KEEP, 1), "Remove takes it off the list")
eq(content.rows[1].label:GetText(), "Old Boot", "  the list moves up")
SS.SetAdd(BF.KEEP, 777)
content.refreshList()
eq(content.rows[2].label:GetText(), "item 777", "an uncached item shows its ID")
check(WoW.calledCount("RequestLoadItemDataByID") >= 1, "  and asks the client to load it")
for i = 1, 10 do SS.SetAdd(BF.KEEP, 1000 + i) end
content.refreshList()
eq(content.pageText:GetText(), "1/2", "12 items: two pages")
content.nextPage:GetScript("OnClick")(content.nextPage)
eq(content.pageText:GetText(), "2/2", "  the next page")
content.clear:GetScript("OnClick")(content.clear)
eq(#SS.SetMembers(BF.KEEP), 0, "Clear all empties the list")
check(not content.clear:IsEnabled(), "  and disables itself")
GP.Options._test.win():Hide()

done("test_bagsfull_frame")
