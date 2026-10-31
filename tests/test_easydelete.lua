-- Easy delete (#40): off by default; DELETE filled in a frame after the event,
-- only up to the chosen quality (read again in the callback), only when the
-- popup, its data and the cursor name the same item, the box is empty and the
-- link reads. The dialog and its data are read-only in the stubs: a write
-- fails the test. The fill never deletes.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local ED, P = GP.EasyDelete, GP.Pearls
local function frame() WoW.advance(0) end
local LINK = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"

-- An item in bag 0 slot 1 on the cursor, its delete popup shown.
local dialog, guid
local function pick(opts)
    opts = opts or {}
    WoW.bags[0] = { size = 16, items = { [1] = { id = 19019, count = 1 } } }
    WoW.cursor = { bag = 0, slot = 1, id = 19019 }
    guid = C_Item.GetItemGUID({ bag = 0, slot = 1 })
    WoW.itemLinks[guid] = opts.link == nil and LINK or opts.link
    WoW.dialogs = {}
    if opts.popup ~= false then
        dialog = WoW.showDeleteDialog(opts.quest and "DELETE_GOOD_QUEST_ITEM" or "DELETE_GOOD_ITEM",
            opts.dataGUID or guid)
    end
    newChat()
end
local function confirm(quality, opts)
    opts = opts or {}
    pick(opts)
    local payloadGUID = guid
    if opts.payloadGUID ~= nil then payloadGUID = opts.payloadGUID end
    WoW.fire("DELETE_ITEM_CONFIRM", "Thunderfury", quality, 1, opts.quest and 1 or 0, payloadGUID)
    if opts.between then opts.between() end
    frame()
end
local function filled() return dialog and dialog.state.text == "DELETE" end

check(not P.IsOn("easydelete"), "off by default")
confirm(4)
check(not filled(), "  off: nothing filled")
P.Set("easydelete", true)
eq(P.Setting("easydelete", "upTo"), "epic", "up to epic by default")

confirm(4)
check(filled(), "an epic: DELETE filled in")
check(dialog.state.yes, "  Yes enabled by Blizzard's handler")
check(chatHas("Easy delete: DELETE filled in for " .. LINK:gsub("%p", "%%%0") .. ": Yes destroys it%."), "  the link said")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  never deleted by us")
confirm(3)
check(filled(), "a rare: filled in")
confirm(5)
check(not filled(), "a legendary at epic: left to you")
confirm(7)
check(not filled(), "an heirloom: never")
confirm(2)
check(not filled(), "below rare: not ours")
confirm(3.5)
check(not filled(), "an odd quality: no")
confirm(WoW.Secret("q"))
check(not filled(), "a secret quality: no")
P.SetSetting("easydelete", "upTo", "rare")
confirm(4)
check(not filled(), "upTo rare: an epic left")
P.SetSetting("easydelete", "upTo", "legendary")
confirm(5)
check(filled(), "upTo legendary: a legendary filled in")
P.SetSetting("easydelete", "upTo", "epic")

-- The setting lowered between the event and the callback.
confirm(4, { between = function() P.SetSetting("easydelete", "upTo", "rare") end })
check(not filled(), "the setting lowered before the callback: not filled")
P.SetSetting("easydelete", "upTo", "epic")

-- The quest variant.
confirm(4, { quest = true })
check(filled(), "the quest popup: filled in")
pick({ quest = true })
WoW.fire("DELETE_ITEM_CONFIRM", "Thunderfury", 4, 1, 0, guid)
frame()
check(not filled(), "  the quest popup for a non-quest event: not found, not filled")
confirm(4, { between = function() end, quest = false })
pick()
WoW.fire("DELETE_ITEM_CONFIRM", "Thunderfury", 4, 1, WoW.Secret("quest"), guid)
frame()
check(not filled(), "a secret quest flag: no")

-- The gamepad popup has no edit box.
WoW.gamepad = true
confirm(4)
check(not filled(), "the gamepad UI: left")
WoW.gamepad = WoW.Secret("pad")
confirm(4)
check(not filled(), "the gamepad flag unreadable: left")
WoW.gamepad = nil

-- Identity.
confirm(4, { popup = false })
check(not WoW.dialogs.DELETE_GOOD_ITEM, "no popup: nothing to fill")
confirm(4, { dataGUID = "Item-0-999" })
check(not filled(), "the popup's data names another item: no")
confirm(4, { payloadGUID = WoW.Secret("guid") })
check(not filled(), "a secret GUID: no")
confirm(4, { payloadGUID = false })
check(not filled(), "no GUID: no")
confirm(4, { between = function() WoW.cursor = nil end })
check(not filled(), "the cursor emptied: no")
confirm(4, { between = function()
    WoW.bags[0].items[2] = { id = 1, count = 1 }
    WoW.cursor = { bag = 0, slot = 2, id = 1 }
end })
check(not filled(), "the cursor holds another item: no")
confirm(4, { between = function() dialog:GetEditBox():SetText("DEL") end })
eq(dialog.state.text, "DEL", "you started typing: left as typed")
confirm(4, { link = false })
check(not filled(), "no link: no fill")
confirm(4, { between = function() WoW.popupThrows = true end })
WoW.popupThrows = nil
check(not filled(), "the popup read throws: no")

-- Tokens.
confirm(4, { between = function() WoW.fire("DELETE_ITEM_CONFIRM", "Other", 2, 1, 0, "Item-0-1") end })
check(not filled(), "a second, ineligible event first: the first is stale")
confirm(4, { between = function() P.Set("easydelete", false); P.Set("easydelete", true) end })
check(not filled(), "off and on before the callback: stale")
confirm(4, { between = function() P.Set("easydelete", false) end })
check(not filled(), "off before the callback: nothing")
P.Set("easydelete", true)

-- A localized confirmation word.
DELETE_ITEM_CONFIRM_STRING = "LÖSCHEN"
confirm(4)
eq(dialog.state.text, "LÖSCHEN", "the client's own word")
DELETE_ITEM_CONFIRM_STRING = "DELETE"

-- The report and the panel.
newChat()
P.Command("easydelete").run()
check(chatHas("Easy delete: on, up to epic%. Last: filled in for"), "the report")
GP.Options.Open("cat:Loot & Bags")
local page = GP.Options._test.pages["cat:Loot & Bags"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "easydelete" then row = pl.row end end
check(row ~= nil, "on the Loot & Bags page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:easydelete"].frame._children[1]
local radios = {}
for _, w in ipairs(content._children) do
    if w._template and w._template:find("Radio", 1, true) then radios[#radios + 1] = w end
end
eq(#radios, 3, "three choices")
radios[1]:GetScript("OnClick")(radios[1])
eq(P.Setting("easydelete", "upTo"), "rare", "  Rare chosen")
P.ResetSettings("easydelete")

done("test_easydelete")
