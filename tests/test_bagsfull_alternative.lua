-- The bags-full helper's white alternative (#101): beside the usual
-- suggestion, the cheapest white stack, food and items with a use included,
-- only when it's cheaper than the usual first or there is none. What may be
-- offered (Bags.Eligible's opts.uses), when it shows, picking it and going
-- back, the click acting only on what's shown in the role it's shown, the arm
-- bound to the whole stack and its role, the resets, not worth it, the window's
-- row and layout, and /gpearls cheapest.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local BF, Bags, Frame, SS, P = GP.BagsFull, GP.Bags, GP.BagsFullFrame, GP.SettingsSync, GP.Pearls
local function tick() WoW.flushTimers(0) end

local ITEMS = {
    [1] = { name = "Grey Junk", price = 50, quality = 0, maxStack = 1 },
    [2] = { name = "Cheap Grey", price = 6, quality = 0, maxStack = 1 },
    [10] = { name = "Ring", price = 620, quality = 2, maxStack = 1, classID = 4 },
    [13] = { name = "Tooth", price = 1, quality = 0, maxStack = 1 },
    [20] = { name = "Fresh Gustberry Bread", price = 2, quality = 1, maxStack = 20, classID = 0, subclassID = 5, spell = true },
    [21] = { name = "Tough Jerky", price = 1, quality = 1, maxStack = 20, classID = 0, subclassID = 5, spell = true },
    [24] = { name = "Linen Cloth", price = 13, quality = 1, maxStack = 20, classID = 7, subclassID = 5 },
    [30] = { name = "Green Filler", price = 500, quality = 2, maxStack = 1, classID = 4 },
    [40] = { name = "Light Hide", price = 10, quality = 1, maxStack = 1, classID = 7 },
    [41] = { name = "Ruined Pelt", price = 4, quality = 1, maxStack = 1, classID = 7 },
}

-- Full bags (one slot per entry: an id, or { id, count }), a loot row that
-- doesn't fit (the ring unless told), the settings at their defaults.
local function setup(slots, loot, lootOpts)
    BF._test.reset()
    WoW.resetBags()
    for id, it in pairs(ITEMS) do
        local c = {}
        for k, v in pairs(it) do c[k] = v end
        WoW.items[id] = c
    end
    local items = {}
    for i, s in ipairs(slots) do items[i] = type(s) == "table" and s or { id = s } end
    WoW.bags[0] = { size = #slots, items = items }
    P.ResetSettings("bagsfull")
    SS.SetClear(BF.KEEP)
    BF._test.reset()
    WoW.openLoot({ { id = loot or 10, qty = 1, isQuest = lootOpts and lootOpts.isQuest } })
    tick()
    return BF.view
end
local function f() return Frame._test.frame() end
local function lastPoint(w) return w._points[#w._points] end

--------------------------------------------------------------------------------
-- What may be offered: Bags.Eligible with opts.uses.

local function elig(id, it, uses, before, extra)
    WoW.resetBags()
    WoW.items[id] = it
    WoW.bags[0] = { size = 1, items = { [1] = { id = id } } }
    if before then before(WoW.bags[0].items[1]) end
    local opts = { scope = "white", uses = uses, setItems = {}, tools = GP.ToolItems,
                   keep = function(x) return SS.SetHas(BF.KEEP, x) end }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return Bags.Eligible(Bags.Slot(0, 1), opts)
end
local function bread() return { name = "Bread", price = 2, quality = 1, classID = 0, subclassID = 5, spell = true } end

check(elig(99, bread(), true) ~= nil, "uses: a white consumable may be offered")
eq(select(2, elig(99, bread(), nil)), "a consumable", "  without uses: refused, as before")
local potion = { name = "Trinket Thing", price = 9, quality = 1, classID = 7, subclassID = 5, spell = true }
check(elig(99, potion, true) ~= nil, "uses: a white item with a use may be offered")
eq(select(2, elig(99, potion, nil)), "it has a use", "  without uses: refused, as before")
eq(select(2, elig(99, { name = "Egg", price = 2, quality = 1, classID = 15, subclassID = 2, spell = true }, true)),
    "a companion", "uses: never a companion")
eq(select(2, elig(99, { name = "Reins", price = 2, quality = 1, classID = 15, subclassID = 5, spell = true }, true)),
    "a mount", "uses: never a mount")
for _, class in ipairs({ 15, 2, 7 }) do
    eq(select(2, elig(99, { name = "X", price = 2, quality = 1, classID = class, subclassID = WoW.Secret("subclass"), spell = true }, true)),
        "unknown subclass", "uses: a secret subclass refuses (class " .. class .. ")")
end
check(elig(99, { name = "X", price = 2, quality = 1, classID = 7, subclassID = WoW.Secret("subclass") }, nil) ~= nil,
    "  without uses: a secret subclass changes nothing")
eq(select(2, elig(99, { name = "Pole", price = 2, quality = 1, classID = 2, subclassID = 20, spell = true }, true)),
    "a fishing pole", "uses: never a fishing pole")
for class, why in pairs(Bags.NEVER_CLASSES) do
    eq(select(2, elig(99, { name = "X", price = 2, quality = 1, classID = class, subclassID = 0, spell = true }, true)),
        why, "uses: never " .. why)
end
eq(select(2, elig(2901, { name = "Mining Pick", price = 20, quality = 1, classID = 2, subclassID = 0, spell = true }, true)),
    "a tool", "uses: never a tool")
eq(select(2, elig(99, bread(), true, function() WoW.quest["0:1"] = { isQuestItem = true } end)),
    "a quest item", "uses: never a quest item")
eq(select(2, elig(99, { name = "Letter", price = 2, quality = 1, classID = 15, subclassID = 0, spell = true }, true,
    function() WoW.quest["0:1"] = { questID = 77 } end)), "a quest item", "  nor a quest starter outside class 12")
eq(select(2, elig(99, bread(), true, function() WoW.questUnreadable = true end)), "unknown quest info",
    "  an unreadable quest read refuses")
eq(select(2, elig(99, bread(), true, nil, { setItems = { [99] = true } })), "in an equipment set", "uses: never a set item")
check(elig(99, bread(), true) ~= nil, "  (the same stack, no set: offered)")
eq(select(2, Bags.Eligible(Bags.Slot(0, 1), { scope = "white", uses = true, tools = {}, keep = function() end })),
    "equipment sets unreadable", "  unreadable equipment sets refuse")
SS.SetAdd(BF.KEEP, 99)
eq(select(2, elig(99, bread(), true)), "kept", "uses: never the never-suggest list")
SS.SetClear(BF.KEEP)
local free = bread(); free.price = 0
eq(select(2, elig(99, free, true)), "no value", "uses: never without a sell price")
eq(select(2, elig(99, bread(), true, function(s) s.locked = true end)), "locked", "uses: never a locked stack")
eq(select(2, elig(99, bread(), true, function(s) s.quality = 1; WoW.items[99] = nil end)), "not cached",
    "uses: never an uncached item")

--------------------------------------------------------------------------------
-- When it shows.

local v = setup({ 1, { id = 20, count = 2 }, 30 })
eq(v.candidate.id, 1, "the usual suggestion stays the grey (50c)")
check(not v.usingAlt, "  in the usual role")
eq(v.alternative and v.alternative.id, 20, "the bread (2 x 2c) is the alternative")
eq(v.alternative.value, 4, "  valued as the whole stack")
check(f().alt:IsShown(), "  its row shows")
eq(f().alt.caption:GetText(), "|cffffd27fCheaper (white):|r", "  captioned")
eq(f().alt.name:GetText(), "2x Fresh Gustberry Bread", "  with the count and name")
eq(f().alt.value:GetText(), "4c", "  and the stack's value")
eq(f().counter:GetText(), "1/1", "the card's counter is the usual list's")

v = setup({ 1, { id = 20, count = 25 }, 30 })
eq(v.alternative, nil, "dearer (50c of bread against 50c of grey): no alternative")
check(not f().alt:IsShown(), "  no row")
v = setup({ 1, { id = 20, count = 30 }, 30 })
eq(v.alternative, nil, "dearer (60c): no alternative")

setup({ 1, { id = 20, count = 2 }, 30 })
P.SetSetting("bagsfull", "whiteAlt", false)
eq(BF.view.alternative, nil, "whiteAlt off: no alternative")
check(not f().alt:IsShown(), "  no row")
P.SetSetting("bagsfull", "whiteAlt", true)
eq(BF.view.alternative and BF.view.alternative.id, 20, "  on again: back")

-- No usual suggestion: the alternative is the one shown.
v = setup({ 30, { id = 20, count = 2 }, 24 })
eq(#v.candidates, 0, "nothing grey: no usual suggestion")
check(v.usingAlt and v.candidate.id == 20, "  the bread is shown, as the alternative")
check(not f().alt:IsShown(), "  no row (nothing to go back to)")
check(not f().prev:IsShown() and not f().next:IsShown(), "  no arrows")
eq(f().counter:GetText(), "white", "  the counter says white")
check(f().never:IsShown(), "  the X shows")
eq(f().out.name:GetText(), "Fresh Gustberry Bread", "  the card shows it")
eq(BF.Destroy(), "armed", "  the first click arms (white)")
eq(f().button:GetText(), "Click again to destroy", "  the button says so")
eq(BF.Destroy(), "destroyed", "  the second destroys")
eq(WoW.bags[0].items[2], nil, "  the bread's slot")
eq(WoW.bags[0].items[3].id, 24, "  the linen (13c, dearer) is still there")

--------------------------------------------------------------------------------
-- Picking it and going back.

setup({ 1, { id = 20, count = 2 }, 2, 30 })
eq(BF.view.candidate.id, 2, "two greys: the cheap grey (6c) first")
BF.NextCandidate(1)
eq(BF.view.candidate.id, 1, "  > : the grey junk (index 2)")
f().alt:GetScript("OnClick")(f().alt)
check(BF.view.usingAlt and BF.view.candidate.id == 20, "a click on the row picks the bread")
eq(f().out.name:GetText(), "Fresh Gustberry Bread", "  the card shows it")
eq(f().counter:GetText(), "white", "  the counter says white")
check(not f().prev:IsShown() and not f().next:IsShown(), "  the arrows are hidden")
eq(f().alt.caption:GetText(), "Back to:", "  the row goes back")
eq(f().alt.name:GetText(), "Grey Junk", "  to the usual one it came from (index 2)")
eq(f().net:GetText(), "You lose 4c, you get 620c.", "  the net line is the bread's")
f().alt:GetScript("OnClick")(f().alt)
check(not BF.view.usingAlt and BF.view.candidate.id == 1, "back: the grey junk again")

-- The alternative destroyed through the row: two clicks.
f().alt:GetScript("OnClick")(f().alt)
eq(BF.Destroy(), "armed", "the picked bread: the first click arms")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")
eq(BF.Destroy(), "destroyed", "  the second destroys")
eq(WoW.bags[0].items[2], nil, "  the bread")
check(WoW.bags[0].items[1] and WoW.bags[0].items[3], "  both greys stay")
check(BF.state.choice.alt == false, "  the pick is reset after a destroy")

--------------------------------------------------------------------------------
-- The click acts on what's shown, in its role.

-- The picked alternative A becomes B (a cheaper white) before a refresh.
setup({ 1, { id = 20, count = 2 }, 30 })
BF.ToggleAlternative()
WoW.bags[0].items[3] = { id = 21 }   -- Tough Jerky, 1c: the fresh alternative
eq(BF.Destroy(), "changed", "picked bread, a cheaper jerky appeared: refused")
eq(WoW.calledCount("PickupContainerItem"), 0, "  nothing picked up")
check(BF.view.usingAlt and BF.view.candidate.id == 21, "  the window now shows the jerky, picked")
eq(BF.Destroy(), "armed", "  a click on it arms, never destroys at once")
-- The same item in another stack: still another stack.
setup({ 1, { id = 20, count = 2 }, 30 })
BF.ToggleAlternative()
eq(BF.Destroy(), "armed", "picked bread (2): armed")
WoW.bags[0].items[3] = { id = 20, count = 1 }   -- one bread, 2c: the fresh alternative
eq(BF.Destroy(), "changed", "  a cheaper stack of bread appeared unseen: refused")
eq(WoW.calledCount("PickupContainerItem"), 0, "  nothing picked up")
eq(BF.view.candidate.slot, 3, "  the window now shows the new stack")

-- An unshown alternative appears, changes or disappears: only the shown usual one can go.
setup({ 1, 30, 30 })
eq(BF.view.alternative, nil, "no white: no alternative")
WoW.bags[0].items[2] = { id = 20, count = 2 }
eq(BF.Destroy(), "destroyed", "bread appeared unseen: the click destroys the shown grey")
eq(WoW.bags[0].items[1], nil, "  the grey")
eq(WoW.bags[0].items[2].id, 20, "  the bread stays")
setup({ 1, { id = 20, count = 2 }, 30 })
WoW.bags[0].items[2] = { id = 21 }
eq(BF.Destroy(), "destroyed", "the alternative changed unseen: the shown grey goes")
eq(WoW.bags[0].items[2].id, 21, "  the jerky stays")
setup({ 1, { id = 20, count = 2 }, 30 })
WoW.bags[0].items[2] = { id = 30 }
eq(BF.Destroy(), "destroyed", "the alternative gone unseen: the shown grey goes")

-- The alternative alone, then a usual entry appears.
setup({ 30, { id = 20, count = 2 }, 30 })
check(BF.view.usingAlt, "the bread alone, shown as the alternative")
WoW.bags[0].items[1] = { id = 2 }
eq(BF.Destroy(), "changed", "a grey appeared before a refresh: the role flipped, refused")
eq(WoW.calledCount("PickupContainerItem"), 0, "  nothing picked up")
setup({ 30, { id = 20, count = 2 }, 30 })
eq(BF.Destroy(), "armed", "the bread alone: armed")
WoW.bags[0].items[1] = { id = 2 }
BF.Evaluate()
check(not BF.view.usingAlt and BF.view.candidate.id == 2, "a grey appeared and the window redrew: it shows the grey")
eq(f().button:GetText(), "Destroy & loot", "  the bread's arm isn't shown")
eq(BF.Destroy(), "destroyed", "  a click acts on the grey by its own rule (one click)")
eq(WoW.bags[0].items[1], nil, "  the grey")
eq(WoW.bags[0].items[2].id, 20, "  never the bread")

-- One stack in both roles: the arm is bound to the role.
setup({ 1, { id = 24, count = 1 }, 30 })
P.SetSetting("bagsfull", "scope", "white")
eq(BF.view.candidates[2] and BF.view.candidates[2].id, 24, "white scope, greys first: the linen second in the list")
eq(BF.view.alternative and BF.view.alternative.id, 24, "  and the alternative (13c under 50c)")
BF.NextCandidate(1)
eq(BF.Destroy(), "armed", "the linen in the list: armed")
BF.state.choice.alt = true   -- the same stack, the other role, the arm kept
BF.Evaluate()
check(BF.view.usingAlt and BF.view.candidate.id == 24, "  shown as the alternative now")
check(not BF.ArmedFor(BF.view), "  the list's arm doesn't count for the alternative")
eq(f().button:GetText(), "Destroy & loot", "  the button doesn't say click again")
eq(BF.Destroy(), "armed", "  a click arms again, never destroys")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")

-- An armed stack whose value or link changes (an existing gap, Codex round 1).
setup({ 1, { id = 24, count = 1 }, 30 })
P.SetSetting("bagsfull", "scope", "white")
P.SetSetting("bagsfull", "greysFirst", false)
P.SetSetting("bagsfull", "whiteAlt", false)
eq(BF.view.candidate.id, 24, "white scope, by value: the linen first")
eq(BF.Destroy(), "armed", "  armed")
WoW.items[24].price = 14
BF.Evaluate()
eq(BF.view.candidate.value, 14, "its value changed and the window redrew")
check(not BF.ArmedFor(BF.view), "  the old arm doesn't count")
eq(BF.Destroy(), "armed", "  a click arms again, never destroys")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")
WoW.items[24].price = 15
eq(BF.Destroy(), "changed", "its value changed before a redraw: refused")
eq(WoW.calledCount("PickupContainerItem"), 0, "  nothing picked up")
eq(BF.Destroy(), "armed", "  then a click arms")
WoW.items[24].name = "Linen Cloth of Renown"
BF.Evaluate()
eq(BF.Destroy(), "armed", "its link changed and the window redrew: a click arms again")
eq(WoW.calledCount("DeleteCursorItem"), 0, "  nothing deleted")

--------------------------------------------------------------------------------
-- The resets.

setup({ 1, { id = 20, count = 2 }, 30 })
BF.ToggleAlternative()
WoW.closeLoot(); tick()
WoW.openLoot({ { id = 10, qty = 1 } }); tick()
check(not BF.view.usingAlt, "a new loot window: back to the usual suggestion")

setup({ 1, { id = 20, count = 2 }, 2, 30 })
BF.ToggleAlternative()
BF.NextCandidate(1)
check(not BF.view.usingAlt, "an arrow: back to the usual list")

setup({ 1, { id = 20, count = 2 }, 30 })
BF.ToggleAlternative()
check(BF.Never(BF.view.candidate), "the X on the picked bread")
check(SS.SetHas(BF.KEEP, 20), "  puts it on the never-suggest list")
check(not BF.view.usingAlt and BF.view.alternative == nil, "  and it's offered no more")

setup({ 1, { id = 20, count = 2 }, 30 })
BF.ToggleAlternative()
WoW.bags[0].items[2] = { id = 30 }
WoW.fire("BAG_UPDATE_DELAYED"); tick()
check(not BF.view.usingAlt and BF.state.choice.alt == false, "the picked alternative gone: the pick is dropped")
WoW.bags[0].items[2] = { id = 21 }
BF.Evaluate()
check(BF.view.alternative and not BF.view.usingAlt, "  a later alternative is offered, not picked")

setup({ 1, { id = 20, count = 2 }, 30 })
BF.ToggleAlternative()
eq(BF.Destroy(), "armed", "picked and armed")
P.SetSetting("bagsfull", "whiteAlt", false)
check(BF.state.choice.alt == false and BF.state.armed == nil, "whiteAlt off: the pick and the arm are dropped")
P.SetSetting("bagsfull", "whiteAlt", true)
check(not BF.view.usingAlt, "  on again: the usual suggestion")
-- Through settings sync, with no evaluation in between.
setup({ 1, { id = 20, count = 2 }, 30 })
BF.ToggleAlternative()
eq(BF.Destroy(), "armed", "picked and armed again")
local AS, hi = GP.AccountSync, GetServerTime() + 1000
local function deliver(value, s)
    AS._test.dispatch("ST\n" .. table.concat({ "GPS1",
        "V\tbagsfull.whiteAlt\t" .. hi .. "\tPlayer-1-BBB\t" .. s .. "\tb" .. value }, "\n"),
        { name = "Alt", guid = "Player-1-BBB" }, 1)
end
deliver(0, 1)
eq(P.Setting("bagsfull", "whiteAlt"), false, "a received whiteAlt off is applied")
check(BF.state.choice.alt == false and BF.state.armed == nil, "  the pick and the arm are dropped")
hi = hi + 1
deliver(1, 2)
check(P.Setting("bagsfull", "whiteAlt") and not BF.view.usingAlt, "  received on again: the usual suggestion")

-- The index clamp keeps an explicit pick; Back names what it returns to.
setup({ 1, { id = 20, count = 2 }, 2, 30 })
BF.NextCandidate(1)
BF.ToggleAlternative()
eq(BF.view.back.id, 1, "picked from index 2: Back names the grey junk")
WoW.bags[0].items[1] = { id = 30 }
BF.Evaluate()
check(BF.view.usingAlt, "the list shrank (the index clamps): still picked")
eq(BF.view.back.id, 2, "  Back names the first now")
eq(f().alt.name:GetText(), "Cheap Grey", "  and the row says so")

-- One usual entry: the arrows can't move, the row still toggles.
setup({ 1, { id = 20, count = 2 }, 30 })
check(not f().prev:IsEnabled() and not f().next:IsEnabled(), "one usual entry: the arrows are disabled")
f().alt:GetScript("OnClick")(f().alt)
check(BF.view.usingAlt, "  the row picks the bread")
f().alt:GetScript("OnClick")(f().alt)
check(not BF.view.usingAlt, "  and goes back")

--------------------------------------------------------------------------------
-- Not worth it: against the cheaper of the two.

v = setup({ 1, { id = 20, count = 2 }, 30 }, 13)
check(v.notWorth, "loot (1c) below both: not worth it")
check(not f().alt:IsShown(), "  no row")
v = setup({ 1, { id = 20, count = 2 }, 30 }, 40)
check(not v.notWorth, "loot (10c) between the bread (4c) and the grey (50c): worth it")
eq(v.candidate.id, 1, "  the usual suggestion still shown")
v = setup({ 1, { id = 20, count = 2 }, 30 }, 41)
check(not v.notWorth, "loot equal to the bread (4c): worth it (strictly less only)")
v = setup({ 1, { id = 20, count = 2 }, 30 }, 13, { isQuest = true })
check(not v.notWorth, "quest loot below both: always worth it")
setup({ 1, { id = 20, count = 2 }, 30 }, 13)
BF.ChooseAnyway()
check(not BF.view.notWorth and not BF.view.usingAlt, "Choose anyway: the usual suggestion, nothing picked")
f().alt:GetScript("OnClick")(f().alt)
check(BF.view.usingAlt and not BF.view.notWorth, "  then the row picks the bread")
eq(BF.Destroy(), "armed", "  still two clicks")

--------------------------------------------------------------------------------
-- The window: the layout, by hand.

local L = Frame.LAYOUT
check(L[false].net >= 56 + 86, "without the row: the net line under the cards")
check(L[true].net >= 146 + 20, "with it: the net line under the row")
for _, row in ipairs({ false, true }) do
    check(L[row].button >= L[row].net + 14, "  the button under the net line (row " .. tostring(row) .. ")")
    eq(L[row].height, L[row].button + 22 + 12, "  the height holds the button and its margin")
end
setup({ 1, { id = 20, count = 2 }, 30 })
eq(f():GetHeight(), L[true].height, "with the row: the taller window")
eq(lastPoint(f().net)[5], -L[true].net, "  the net line under the row")
eq(lastPoint(f().button)[5], -L[true].button, "  the button under it")
setup({ 1, 30, 30 })
eq(f():GetHeight(), L[false].height, "without: the shorter one")
eq(lastPoint(f().button)[5], -L[false].button, "  the button moves up")
setup({ 1, { id = 20, count = 2 }, 30 })
BF.Evaluate(); BF.Evaluate()
eq(f():GetHeight(), L[true].height, "shown again and again: the height is set, never added to")
f().alt:GetScript("OnEnter")(f().alt)
eq(GameTooltip._owner, f().alt, "hovering the row shows the item's tooltip")

setup({ 1, { id = 20, count = 2 }, 30 })
WoW.deleteForbidden = true
eq(BF.Destroy(), "refused", "the delete refused: by hand")
check(BF.view.byHand and not f().button:IsShown(), "  no button")
check(f().alt:IsShown(), "  the row still shows (it picks the stack to drag)")
f().alt:GetScript("OnClick")(f().alt)
check(BF.view.usingAlt and f().out.name:GetText() == "Fresh Gustberry Bread", "  and picks it")

--------------------------------------------------------------------------------
-- /gpearls cheapest.

setup({ 1, { id = 20, count = 2 }, 30 })
newChat()
SlashCmdList.GLASSPEARLS("cheapest")
local lines = table.concat(newChat(), "\n")
check(lines:find("Cheapest: ", 1, true) and lines:find("Grey Junk", 1, true), "/gpearls cheapest: the usual first")
check(lines:find("Cheaper white: 2x ", 1, true) and lines:find("Fresh Gustberry Bread", 1, true), "  and the bread")
setup({ 30, { id = 20, count = 2 }, 30 })
newChat()
SlashCmdList.GLASSPEARLS("cheapest")
lines = table.concat(newChat(), "\n")
check(lines:find("Cheapest white: 2x ", 1, true), "only the alternative: named")
check(not lines:find("Nothing", 1, true), "  never 'nothing'")

done("test_bagsfull_alternative")
