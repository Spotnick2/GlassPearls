-- Equipment set guard (#142): which sets hold one copy (by location, never by
-- item ID), the tooltip line, the destroy warning under Blizzard's popup, easy
-- delete never filling for a set item, the sale warning after a use at a
-- merchant, and the disenchant warning during the cast.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local SG, ES, P = GP.SetGuard, GP.EquipSets, GP.Pearls
local Item = Enum.TooltipDataType.Item
local RING, CLOAK, ROBE = 19140, 19430, 16923

local function frame() WoW.advance(0) end

-- Chat since the last setup (chatHas reads all of it).
local mark = 0
local function said(pattern)
    for i = mark + 1, #WoW.chat do
        if WoW.chat[i]:find(pattern) then return true end
    end
    return false
end
local function saidCount() return #WoW.chat - mark end

-- Bag 0: slot 1 a ring in "Shadow", slot 2 the same ring in no set, slot 3 a
-- cloak in "Shadow" and "Discipline"; worn: robe (5) in "Discipline", a ring (11) in none.
local function setup()
    WoW.resetBags()
    WoW.resetSets()
    WoW.bags[0] = { size = 16, items = {
        [1] = { id = RING, count = 1, guid = "Item-A" },
        [2] = { id = RING, count = 1, guid = "Item-B" },
        [3] = { id = CLOAK, count = 1, guid = "Item-C" },
        [4] = { id = 4306, count = 5, guid = "Item-S" },
    } }
    WoW.bags[1] = { size = 16, items = {} }
    WoW.equipped = { [5] = ROBE, [11] = RING }
    WoW.wornGUIDs = { [5] = "Item-R", [11] = "Item-W" }
    WoW.itemLinks = { ["Item-A"] = "[Ring A]", ["Item-B"] = "[Ring B]", ["Item-C"] = "[Cloak]",
                      ["Item-R"] = "[Robe]", ["Item-W"] = "[Worn ring]", ["Item-S"] = "[Silk]" }
    WoW.addSet(1, "Shadow", { [11] = WoW.packBag(0, 1), [15] = WoW.packBag(0, 3) })
    WoW.addSet(2, "Discipline", { [5] = WoW.packWorn(5), [15] = WoW.packBag(0, 3), [1] = 0, [2] = 1 })
    WoW.cursor = nil
    WoW.dialogs = {}
    SG.Forget()
    newChat()
    mark = #WoW.chat
end

--------------------------------------------------------------------------------
-- Membership

setup()
eq(ES.ForGUID("Item-A"), "Shadow", "a bag item in one set")
eq(ES.ForGUID("Item-B"), false, "  the same ring's other copy: in none")
eq(ES.ForGUID("Item-C"), "Shadow, Discipline", "a bag item in two sets")
eq(ES.ForGUID("Item-R"), "Discipline", "a worn item in a set")
eq(ES.ForGUID("Item-W"), false, "  a worn copy of the set ring: in none")
eq(ES.ForGUID("Item-X"), nil, "an unknown GUID: can't tell")
eq(ES.ForGUID(WoW.Secret("guid")), nil, "a secret GUID: can't tell")
eq(ES.Decode(WoW.packWorn(5)), 5, "decode: a worn slot")
eq(ES.Decode(WoW.packBag(0, 3)), false, "  a bag location: plainly not worn")
eq(ES.Decode(ITEM_INVENTORY_LOCATION_PLAYER + ITEM_INVENTORY_LOCATION_BANK + 40), false, "  nor a bank one")
eq(ES.Decode(0), false, "  the empty slot value")
eq(ES.Decode(1), false, "  the ignored slot value")
eq(ES.Decode(-1), false, "  the missing value")
eq(ES.Decode(WoW.Secret("v")), nil, "  a secret: can't tell")
eq(ES.Decode("5"), nil, "  not a number: can't tell")
eq(ES.Decode(1.5), nil, "  not whole: can't tell")
WoW.setInfoThrows = true
eq(ES.ForGUID("Item-A"), nil, "the bag answer throws: can't tell")
WoW.setInfoThrows = false
WoW.setListSecret = true
eq(ES.ForGUID("Item-A"), nil, "a secret list: can't tell")
WoW.setListSecret = false
WoW.locationThrows = true
eq(ES.ForGUID("Item-A"), nil, "the location throws: can't tell")
WoW.locationThrows = false
WoW.setInfo[2].locations[5] = WoW.Secret("loc")
eq(ES.ForGUID("Item-R"), nil, "a secret set location: can't tell")
eq(ES.ForGUID("Item-W"), nil, "  nor 'in none' for another worn item")
setup()
WoW.setInfo[1].locations[9] = "odd"
eq(ES.ForGUID("Item-W"), nil, "an odd set location: never 'in none'")
setup()
WoW.setInfo[2].name = "Sh|cffff0000ow"
eq(ES.ForGUID("Item-R"), "Sh||cffff0000ow", "a worn set's name: escaped")
WoW.setInfo[1].name = "A|B"
eq(ES.ForGUID("Item-A"), "A||B", "a bag set list: escaped")

--------------------------------------------------------------------------------
-- The tooltip

local function tip(guid)
    local added = {}
    local tt = { AddLine = function(_, text, r, g, b) added[#added + 1] = { text = text, r = r } end }
    for _, fn in ipairs(WoW.tooltipPostCalls[Item] or {}) do
        fn(tt, { type = Item, id = RING, guid = guid, lines = {} })
    end
    local out = {}
    for _, l in ipairs(added) do out[#out + 1] = l.text end
    return table.concat(out, "\n"), added
end

setup()
check(P.IsOn("setguard"), "on by default")
check(SG.state.tipHooked, "the tooltip post-call installed")
eq(tip("Item-A"), "Equipment sets: |cffffffffShadow|r", "a set ring's tooltip names its set")
eq(tip("Item-B"), "", "  its other copy: nothing")
eq(tip("Item-C"), "Equipment sets: |cffffffffShadow, Discipline|r", "two sets named")
eq(tip("Item-R"), "Equipment sets: |cffffffffDiscipline|r", "worn: named")
eq(tip(nil), "", "no GUID (a vendor's, a link): nothing")
eq(tip(WoW.Secret("g")), "", "a secret GUID: nothing")
WoW.openMerchant()
local text, lines = tip("Item-A")
eq(text, "Equipment sets: |cffffffffShadow|r\nCareful when selling it to this merchant.", "at a merchant: the warning")
eq(lines[2] and lines[2].r, 1, "  in red")
eq(tip("Item-R"), "Equipment sets: |cffffffffDiscipline|r", "  not for worn gear")
P.SetSetting("setguard", "sell", false)
eq(tip("Item-A"), "Equipment sets: |cffffffffShadow|r", "  the sale warning off: no line")
P.SetSetting("setguard", "sell", true)
WoW.closeMerchant()
P.SetSetting("setguard", "tooltip", false)
eq(tip("Item-A"), "", "the tooltip switch off: nothing")
P.SetSetting("setguard", "tooltip", true)
P.Set("setguard", false)
eq(tip("Item-A"), "", "the pearl off: nothing")
P.Set("setguard", true)
eq(WoW.hooked[C_Container].UseContainerItem, 1, "one use hook, kept across off and on")

--------------------------------------------------------------------------------
-- Destroy

local function destroy(bag, slot, guid, which)
    WoW.cursor = { bag = bag, slot = slot, id = WoW.bags[bag].items[slot].id }
    local dialog = WoW.showDeleteDialog(which or "DELETE_ITEM", guid)
    WoW.fire("DELETE_ITEM_CONFIRM", "Ring", which == "DELETE_GOOD_ITEM" and 4 or 2, 1, 0, guid)
    frame()
    return dialog
end
local function warning() return SG._test.warning() end

setup()
local dialog = destroy(0, 1, "Item-A")
check(said("Careful: %[Ring A%] is in your equipment set Shadow%."), "a set item: said with its link")
check(warning() and warning():IsShown(), "  the warning shown")
eq(warning().text:GetText(), "In your equipment set: Shadow", "  its text")
local pt = warning()._points and warning()._points[1]
check(pt == nil or pt[2] == dialog, "  anchored to the popup")
WoW.tick(0.2)
check(warning():IsShown(), "  kept while the popup is up")
WoW.hideDialog("DELETE_ITEM")
WoW.tick(0.2)
check(not warning():IsShown(), "  gone with the popup")

setup()
dialog = destroy(0, 1, "Item-A")
dialog.state.shown = WoW.Secret("shown")
WoW.tick(0.2)
check(not warning():IsShown(), "the popup's visibility unreadable: hidden")

setup()
destroy(0, 2, "Item-B")
eq(saidCount(), 0, "the copy in no set: nothing said")
check(not (warning() and warning():IsShown()), "  no warning")

setup()
destroy(0, 3, "Item-C", "DELETE_GOOD_ITEM")
check(said("in your equipment sets Shadow, Discipline%."), "two sets, the good-item popup")
check(warning():IsShown(), "  shown")
WoW.fire("DELETE_ITEM_CONFIRM", "Ring", 2, 1, 0, "Item-B")
check(not warning():IsShown(), "  a new popup hides the last warning at once")

setup()
destroy(0, 1, "Item-A")
P.SetSetting("setguard", "destroy", false)
check(not warning():IsShown(), "the switch turned off: hidden")
mark = #WoW.chat
destroy(0, 1, "Item-A")
eq(saidCount(), 0, "  off: nothing said")
P.SetSetting("setguard", "destroy", true)

setup()
destroy(0, 1, "Item-A")
P.Set("setguard", false)
check(not warning():IsShown(), "the pearl off: hidden")
P.Set("setguard", true)

-- No popup found (the gamepad's, or none): the centre notice instead.
setup()
WoW.cursor = { bag = 0, slot = 1, id = RING }
WoW.fire("DELETE_ITEM_CONFIRM", "Ring", 2, 1, 0, "Item-A")
frame()
check(GP.Notice.IsShown() and GP.Notice.Text() == "In your equipment set: Shadow", "no popup: the notice")

-- A popup naming another GUID isn't the one.
setup()
WoW.cursor = { bag = 0, slot = 1, id = RING }
WoW.showDeleteDialog("DELETE_ITEM", "Item-B")
WoW.fire("DELETE_ITEM_CONFIRM", "Ring", 2, 1, 0, "Item-A")
frame()
check(not (warning() and warning():IsShown()), "a popup for another item: not anchored to")

-- The cursor holds another item: the GUID's own location decides.
setup()
WoW.cursor = { bag = 0, slot = 2, id = RING }
WoW.showDeleteDialog("DELETE_ITEM", "Item-A")
WoW.fire("DELETE_ITEM_CONFIRM", "Ring", 2, 1, 0, "Item-A")
frame()
check(warning():IsShown(), "the cursor on another copy: the GUID's own location")

-- Unreadable sets: nothing (never a guess).
setup()
WoW.setInfoThrows = true
destroy(0, 1, "Item-A")
eq(saidCount(), 0, "sets unreadable: nothing said")

--------------------------------------------------------------------------------
-- Easy delete never fills in DELETE for a set item

setup()
P.Set("easydelete", true)
local d = destroy(0, 1, "Item-A", "DELETE_GOOD_ITEM")
eq(d.state.text, "", "easy delete: a set item isn't filled in")
eq(GP.EasyDelete.state.last, "in an equipment set", "  why")
d = destroy(0, 2, "Item-B", "DELETE_GOOD_ITEM")
eq(d.state.text, "DELETE", "  its copy in no set is")
WoW.setInfoThrows = true
d = destroy(0, 2, "Item-B", "DELETE_GOOD_ITEM")
eq(d.state.text, "", "  sets unreadable: not filled in")
eq(GP.EasyDelete.state.last, "equipment sets unreadable", "  why")
WoW.setInfoThrows = false
P.Set("setguard", false)
d = destroy(0, 1, "Item-A", "DELETE_GOOD_ITEM")
eq(d.state.text, "", "  whatever the guard's switch says")
P.Set("setguard", true)
P.Set("easydelete", false)

--------------------------------------------------------------------------------
-- Sell, after the fact

local function sold() return said("left your bags at this merchant") end

setup()
WoW.salesAsync = true
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.advance(0.5)
check(not sold(), "a set ring right-clicked: nothing before SALE_FROM")
WoW.advance(0.6)
check(not sold(), "  still in its slot: pending")
WoW.applySales()
check(said("%[Ring A%], in your equipment set Shadow, left your bags at this merchant: if you sold it, buy it back "
    .. "from the Buyback tab%."), "  gone: said, never as a certain sale")
check(GP.Notice.Text() == "A set item left your bags (Shadow)", "  the notice")
mark = #WoW.chat
WoW.advance(2)
WoW.fire("BAG_UPDATE_DELAYED")
eq(saidCount(), 0, "  once")
WoW.closeMerchant()

setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 2)
WoW.applySales()
WoW.advance(3)
check(not sold(), "the copy in no set sold: nothing")
WoW.closeMerchant()

-- Pending past the window: dropped.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.advance(1)
WoW.advance(1.6)
WoW.applySales()
WoW.advance(1)
check(not sold(), "gone after SALE_UNTIL: dropped")
WoW.closeMerchant()

-- Closed before it went: nothing.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.closeMerchant()
WoW.applySales()
WoW.advance(3)
check(not sold(), "the visit closed: nothing")

-- Moved to another slot (bank, a bag): not a sale.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.pendingSales = {}
WoW.bags[0].items[1].pendingSale = nil
WoW.bags[1].items[2] = WoW.bags[0].items[1]
WoW.bags[0].items[1] = nil
WoW.advance(1.2)
WoW.fire("BAG_UPDATE_DELAYED")
WoW.bags[1].items[2] = nil
WoW.advance(1)
WoW.fire("BAG_UPDATE_DELAYED")
check(not sold(), "moved elsewhere first: dropped, never a sale")
WoW.closeMerchant()

-- A stack, the sale warning off, the pearl off.
setup()
WoW.openMerchant()
WoW.addSet(3, "Tailor", { [16] = WoW.packBag(0, 4) })
C_Container.UseContainerItem(0, 4)
WoW.applySales()
WoW.advance(1.5)
check(not sold(), "a stack: never")
P.SetSetting("setguard", "sell", false)
C_Container.UseContainerItem(0, 1)
WoW.applySales()
WoW.advance(1.5)
check(not sold(), "the sale warning off: nothing")
P.SetSetting("setguard", "sell", true)
WoW.closeMerchant()

setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
P.SetSetting("setguard", "sell", false)
P.SetSetting("setguard", "sell", true)
WoW.applySales()
WoW.advance(1.5)
check(not sold(), "switched off while pending: dropped")
WoW.closeMerchant()

-- A sale the client completes inside the call: the slot reads empty after it,
-- so nothing is known about the item (a day-one check).
setup()
WoW.salesAsync = false
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.advance(1.5)
check(not sold(), "a sale done inside the call: not seen")
WoW.closeMerchant()
WoW.salesAsync = true

--------------------------------------------------------------------------------
-- Disenchant, during the cast

local castN = 0
local function start(id)
    castN = castN + 1
    WoW.fire("UNIT_SPELLCAST_START", "player", "Cast-" .. castN, id or SG.DISENCHANT)
    return "Cast-" .. castN
end
local function warned() return said("Your Disenchant may be on") end

setup()
C_Container.UseContainerItem(0, 1)
WoW.advance(0.1)
start()
WoW.advance(0.3)
check(not warned(), "nothing before the cast settles")
WoW.advance(0.3)
check(said("Your Disenchant may be on %[Ring A%], in your equipment set Shadow: move or press Esc to stop%."),
    "a set ring used, then a Disenchant: warned")
eq(GP.Notice.Text(), "Disenchanting a set item? (Shadow)", "  the notice")
eq(WoW.soundsPlayed[#WoW.soundsPlayed][1], SOUNDKIT.RAID_WARNING, "  the sound")

setup()
start()
WoW.advance(0.2)
C_Container.UseContainerItem(0, 3)
WoW.advance(0.5)
check(said("may be on %[Cloak%], in your equipment sets Shadow, Discipline"), "the start first, then the use")

setup()
C_Container.UseContainerItem(0, 2)
WoW.advance(0.1)
start()
WoW.advance(0.6)
check(not warned(), "the copy in no set: nothing")

setup()
C_Container.UseContainerItem(0, 1)
WoW.advance(0.6)
start()
WoW.advance(0.6)
check(not warned(), "a use longer ago than PAIR: not this cast's")

setup()
C_Container.UseContainerItem(0, 1)
start(7620)
WoW.advance(0.6)
check(not warned(), "another spell: nothing")

setup()
C_Container.UseContainerItem(0, 1)
local g = start()
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", g, SG.DISENCHANT)
WoW.advance(0.6)
check(not warned(), "the cast over before it settled: nothing")

setup()
C_Container.UseContainerItem(0, 1)
WoW.fire("UNIT_SPELLCAST_START", "player", WoW.Secret("cast"), SG.DISENCHANT)
WoW.advance(0.6)
check(not warned(), "a secret cast GUID: nothing")

setup()
P.SetSetting("setguard", "disenchant", false)
C_Container.UseContainerItem(0, 1)
start()
WoW.advance(0.6)
check(not warned(), "the warning off: nothing")
P.SetSetting("setguard", "disenchant", true)

-- A use a Disenchant claims is never a sale, warning on or off.
for _, onOff in ipairs({ true, false }) do
    setup()
    P.SetSetting("setguard", "disenchant", onOff)
    WoW.openMerchant()
    C_Container.UseContainerItem(0, 1)
    start()
    WoW.applySales()
    WoW.advance(1.5)
    check(not sold(), "a Disenchant at a merchant (warning " .. tostring(onOff) .. "): never a sale")
    WoW.closeMerchant()
end
P.SetSetting("setguard", "disenchant", true)

setup()
C_Container.UseContainerItem(0, 1)
start()
WoW.fire("PLAYER_LEAVING_WORLD")
WoW.advance(0.6)
check(not warned(), "a loading screen forgets the cast")

-- A cast over before it settled still claims its uses: a later cast never
-- takes them (Codex round 3).
setup()
C_Container.UseContainerItem(0, 1)
local first = start()
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", first, SG.DISENCHANT)
WoW.advance(0.1)
C_Container.UseContainerItem(0, 2)
start()
WoW.advance(0.6)
check(not warned(), "a cancelled cast's set item isn't the next cast's")
eq(SG.state.uses[1].cast, first, "  claimed by the cancelled cast")

-- Switched off and on with a sale pending: its timers do nothing.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
start()
P.Set("setguard", false)
P.Set("setguard", true)
WoW.applySales()
WoW.advance(1.5)
WoW.fire("BAG_UPDATE_DELAYED")
check(not sold(), "the pearl off and on while pending: the old use never becomes a sale")
WoW.closeMerchant()

-- Used while the sale warning was off, switched on before its timers: nothing.
setup()
WoW.openMerchant()
P.SetSetting("setguard", "sell", false)
C_Container.UseContainerItem(0, 1)
P.SetSetting("setguard", "sell", true)
WoW.applySales()
WoW.advance(1.5)
check(not sold(), "used while the warning was off: never a sale")
WoW.closeMerchant()

-- Bag coordinates unreadable at a check: still pending, never "moved".
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
local getBagAndSlot = WoW.LocationMixin.GetBagAndSlot
WoW.LocationMixin.GetBagAndSlot = function() return WoW.Secret("bag"), WoW.Secret("slot") end
WoW.advance(1.1)
WoW.fire("BAG_UPDATE_DELAYED")
WoW.LocationMixin.GetBagAndSlot = getBagAndSlot
WoW.applySales()
check(sold(), "unreadable coordinates kept it pending: said once it went")
WoW.closeMerchant()

-- Gone at once, the Disenchant start a moment later: still not a sale.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.applySales()
WoW.advance(0.3)
start()
WoW.advance(1.5)
WoW.fire("BAG_UPDATE_DELAYED")
check(not sold(), "a Disenchant start after the bags changed: never a sale")
WoW.closeMerchant()

-- The latest start that can claim the use (PAIR after it) settles before the
-- first sale check.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.applySales()
WoW.advance(SG.PAIR)
start()
WoW.advance(2)
check(not sold(), "a Disenchant started PAIR after the use: settled first, never a sale")
WoW.closeMerchant()

-- A pending use pushed out by later uses, then the switch off and on: its
-- timers do nothing (Codex round 4).
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
for _ = 1, SG.USES_MAX do C_Container.UseContainerItem(1, 9) end
P.SetSetting("setguard", "sell", false)
P.SetSetting("setguard", "sell", true)
WoW.applySales()
WoW.advance(1.5)
WoW.fire("BAG_UPDATE_DELAYED")
check(not sold(), "an evicted use never becomes a sale")
WoW.closeMerchant()

-- Two set items sold one after the other: both said.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.advance(0.2)
C_Container.UseContainerItem(0, 3)
WoW.applySales()
WoW.advance(1.5)
check(said("%[Ring A%], in your equipment set Shadow, left"), "two pending sales: the first said")
check(said("%[Cloak%], in your equipment sets Shadow, Discipline, left"), "  and the second")
WoW.closeMerchant()

-- A loading screen drops a pending sale.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.fire("PLAYER_LEAVING_WORLD")
WoW.applySales()
WoW.advance(1.5)
check(not sold(), "a loading screen drops a pending sale")
WoW.closeMerchant()

-- Unreadable location answers and constants: never "in none".
setup()
local isBagAndSlot = WoW.LocationMixin.IsBagAndSlot
WoW.LocationMixin.IsBagAndSlot = function() return WoW.Secret("isBag") end
eq(ES.ForGUID("Item-A"), nil, "IsBagAndSlot secret: can't tell")
WoW.LocationMixin.IsBagAndSlot = isBagAndSlot
local constant = ITEM_INVENTORY_LOCATION_BAGS
ITEM_INVENTORY_LOCATION_BAGS = nil
eq(ES.ForGUID("Item-W"), nil, "a location constant missing: can't tell")
ITEM_INVENTORY_LOCATION_BAGS = constant
eq(ES.ForGUID("Item-W"), false, "  back: in none")

-- A use exactly PAIR after the start, recorded as the window closes: still
-- that cast's (Codex round 5).
setup()
WoW.openMerchant()
start()
WoW.advance(SG.PAIR)
C_Container.UseContainerItem(0, 1)
WoW.applySales()
WoW.advance(1.5)
WoW.fire("BAG_UPDATE_DELAYED")
check(not sold(), "a use at the edge of a cast's window is never a sale")
eq(SG.state.uses[1].cast, "Cast-" .. castN, "  claimed by that cast")
WoW.closeMerchant()

-- The settle timer late: a sale check meanwhile waits for it.
setup()
WoW.openMerchant()
C_Container.UseContainerItem(0, 1)
WoW.applySales()
WoW.advance(0.4)
start()
WoW.now = WoW.now + 1.0        -- time passes, the timers don't run
WoW.fire("BAG_UPDATE_DELAYED")
check(not sold(), "an unsettled cast near the use: the sale check waits")
WoW.advance(0)
WoW.fire("BAG_UPDATE_DELAYED")
check(not sold(), "  then the cast claims it")
WoW.closeMerchant()

-- A cast before a loading screen, a new one after: the old settle timer
-- leaves the new one's open record alone (Codex round 6, optional).
setup()
start()
WoW.fire("PLAYER_LEAVING_WORLD")
start()
WoW.advance(SG.SETTLE)
eq(#SG.state.open, 0, "the new cast settled, the old timer did nothing")
setup()
start()
WoW.fire("PLAYER_LEAVING_WORLD")
WoW.advance(0.3)
start()
WoW.advance(0.3)
eq(#SG.state.open, 1, "  the old timer fired first: the new cast still open")
WoW.advance(0.3)
eq(#SG.state.open, 0, "  then settled by its own")

-- Where an item is: unknown stays unknown.
setup()
eq(SG.Whereabouts("Item-A"), "held", "whereabouts: in a bag")
eq(SG.Whereabouts("Item-R"), "held", "  worn")
eq(SG.Whereabouts("Item-X"), "gone", "  no location: gone")
WoW.locationThrows = true
eq(SG.Whereabouts("Item-A"), nil, "  a throw: can't tell")
WoW.locationThrows = false

--------------------------------------------------------------------------------
-- The report

setup()
newChat()
SG.Report()
local out = table.concat(newChat(), "\n")
check(out:find("bag 0 slot 1: .-: Shadow"), "the report: a bag item")
check(out:find("bag 0 slot 3: .-: Shadow, Discipline"), "  two sets")
check(not out:find("bag 0 slot 2"), "  not the copy in no set")
check(out:find("worn slot 5: Discipline"), "  worn")

done("test_setguard")
