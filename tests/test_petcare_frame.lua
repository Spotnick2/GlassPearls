-- Hunter pet care's window, Feed button, tooltip line, bag marks and panel
-- (#38), in both looks (an argument "glass" runs it under Glass UI's glass).
-- The Feed button: disarmed at rest; one action per click, on the release,
-- under every setting of the CVars Blizzard's dispatch reads; armed with the
-- slot, type last; every stale state refused; disarmed after.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local QUAIL, FISH, BREAD = 8952, 4593, 4540
local GP = loadAddon({ before = function()
    WoW.class = "HUNTER"
    WoW.known[883] = true
    WoW.pet = { happiness = 3, level = 60, guid = "Pet-1" }
    WoW.items[QUAIL] = { name = "Roasted Quail", price = 200, level = 55, quality = 1, icon = 133971 }
    WoW.items[FISH] = { name = "Bristle Whisker Catfish", price = 4, level = 52, quality = 1 }
    WoW.items[BREAD] = { name = "Tough Hunk of Bread", price = 1, level = 5, quality = 1 }
    WoW.edible[QUAIL], WoW.edible[FISH] = true, true
    WoW.bags[0] = { size = 16, items = { [1] = { id = QUAIL, count = 5 }, [2] = { id = BREAD, count = 20 } } }
end })
local PC, P, SS, FR = GP.PetCare, GP.Pearls, GP.SettingsSync, GP.PetCareFrame
local ATTRS = { "type", "spell", "target-bag", "target-slot" }

local function happy(h)
    WoW.pet.happiness = h
    WoW.fire("UNIT_HAPPINESS", "pet")
end
local function fight()
    WoW.fire("PLAYER_REGEN_DISABLED")
    WoW.combat = true
end
local function peace()
    WoW.combat = false
    WoW.fire("PLAYER_REGEN_ENABLED")
end
local function disarmed(b)
    for _, a in ipairs(ATTRS) do if b:GetAttribute(a) ~= nil then return false end end
    return true
end

--------------------------------------------------------------------------------
-- The window

check(FR._test.frame() == nil, "no window until one is needed")
happy(2)
local f = FR._test.frame()
local b = FR._test.button()
check(FR.IsShown(), "Content: the window")
eq(f.mood:GetText(), "Your pet is Content.", "  the happiness")
eq(f.food:GetText(), "Roasted Quail (5 in your bags)", "  the food")
check(f.icon:IsShown(), "  its icon")
check(b:IsEnabled() and f.never:IsEnabled(), "  Feed and Never feed this enabled")
check(b._protected and b._template:find("SecureActionButtonTemplate", 1, true), "Feed: a secure action button")
eq(b:GetParent(), f, "  a child of the window")
eq(table.concat(b._registeredClicks, ","), "AnyDown,AnyUp", "  both edges registered")
eq(b:GetAttribute("useOnKeyDown"), false, "  useOnKeyDown false")
check(disarmed(b), "  disarmed at rest")
local special = false
for _, name in ipairs(UISpecialFrames) do if name == FR.NAME then special = true end end
check(not special, "the window isn't in UISpecialFrames (protected in combat)")

--------------------------------------------------------------------------------
-- The Feed button

local function reset()
    WoW.fed, WoW.secureActions, WoW.spellTargeting, WoW.cursor = {}, {}, nil, nil
end

for _, keyDown in ipairs({ false, true }) do
    for _, held in ipairs({ false, true }) do
        for _, isKey in ipairs({ false, true }) do
            local label = ("ActionButtonUseKeyDown %s, KeyHeldSpell %s, %s: "):format(tostring(keyDown),
                tostring(held), isKey and "key press" or "mouse press")
            WoW.cvars.ActionButtonUseKeyDown, WoW.cvars.ActionButtonUseKeyHeldSpell = keyDown, held
            reset()
            WoW.click(b, "LeftButton", true, isKey)
            eq(#WoW.secureActions, 0, label .. "the down edge does nothing")
            check(disarmed(b), label .. "  still disarmed")
            WoW.click(b, "LeftButton", false, isKey)
            eq(#WoW.secureActions, 1, label .. "exactly one action")
            check(WoW.secureActions[1] and WoW.secureActions[1].kind == "spell" and WoW.secureActions[1].down == false,
                label .. "  Feed Pet, on the release")
            eq(#WoW.fed, 1, label .. "one item fed")
            check(WoW.fed[1] and WoW.fed[1].bag == 0 and WoW.fed[1].slot == 1 and WoW.fed[1].id == QUAIL,
                label .. "  the quail's slot")
            check(disarmed(b), label .. "disarmed after")
        end
    end
end
WoW.cvars = {}

-- Armed with the slot, type last.
reset()
local order = {}
local set = b.SetAttribute
b.SetAttribute = function(self, k, v)
    if v ~= nil then order[#order + 1] = k end
    return set(self, k, v)
end
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
eq(table.concat(order, ","), "target-bag,target-slot,spell,type", "armed: the slot and the spell, type last")
b.SetAttribute = nil
eq(WoW.calls[#WoW.calls - 1] and WoW.calls[#WoW.calls - 1][1], "CastSpellByID", "  Feed Pet cast by the secure action")
eq(WoW.forbidden[#WoW.forbidden], nil, "  nothing forbidden")

-- Refused: another spell already waits for an item. The button's targets are
-- cleared, so Blizzard's targeting block uses nothing.
local function refused(label, setup, undo)
    reset()
    check(FR.Choice() ~= nil, label .. ": food on offer before")
    setup()
    WoW.click(b, "LeftButton", true)
    WoW.click(b, "LeftButton", false)
    eq(#WoW.secureActions, 0, label .. ": no action")
    eq(#WoW.fed, 0, label .. ": nothing fed")
    check(disarmed(b), label .. ": disarmed")
    if undo then undo() end
end
refused("another spell targeting an item", function() WoW.spellTargeting = "item" end)
check(f.status:GetText():find("another spell is waiting", 1, true), "  the reason in the window")
refused("an item on the cursor", function() WoW.cursor = { bag = 0, slot = 2, id = BREAD } end)
refused("a spell on the cursor", function() WoW.cursor = { kind = "spell", id = 6991 } end)
refused("a locked slot", function() WoW.bags[0].items[1].locked = true end,
    function() WoW.bags[0].items[1].locked = nil; WoW.fire("BAG_UPDATE_DELAYED") end)
refused("Feed Pet unusable", function() WoW.spellUsable[6991] = false end, function() WoW.spellUsable[6991] = nil end)
refused("the pet gone", function() WoW.pet.dead = true end, function() WoW.pet.dead = nil; happy(2) end)
check(FR.IsShown(), "offered again once the pet is back")
refused("not a hunter pet now", function() WoW.pet.hunter = false end, function() WoW.pet.hunter = nil; happy(2) end)
refused("Happy since, no event yet", function() WoW.pet.happiness = 3 end, function() happy(2) end)
check(FR.IsShown(), "offered again once Content")
refused("the happiness unreadable", function() WoW.pet.happiness = WoW.Secret("happiness") end,
    function() happy(2) end)
refused("in combat (lockdown)", function() WoW.combat = true end, function() WoW.combat = false end)
reset()
WoW.click(b, "RightButton", true)
WoW.click(b, "RightButton", false)
eq(#WoW.secureActions, 0, "the right button: no action")
reset()
WoW.click(b, "LeftButton", false)
eq(#WoW.secureActions, 0, "a release with no press of ours: no action")

-- A stale slot: the food moved; the click re-chooses, the next one feeds it.
WoW.bags[0].items[1], WoW.bags[0].items[5] = nil, { id = QUAIL, count = 5 }
reset()
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
eq(#WoW.fed, 0, "the food moved: nothing fed")
eq(FR.Choice() and FR.Choice().slot, 5, "  chosen again: its new slot")
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
check(WoW.fed[1] and WoW.fed[1].slot == 5, "  the next click feeds it")

-- A never-list change between the choice and the click.
WoW.bags[0].items[3] = { id = FISH, count = 2 }
WoW.fire("BAG_UPDATE_DELAYED")
eq(FR.Choice() and FR.Choice().id, FISH, "the catfish on offer (cheaper, within 10 levels)")
SS.SetAdd(PC.NEVER, FISH)        -- synced from another account: no event here
reset()
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
eq(#WoW.fed, 0, "never-listed since: nothing fed")
eq(FR.Choice() and FR.Choice().id, QUAIL, "  chosen again: the quail")
SS.SetRemove(PC.NEVER, FISH)

-- Never feed this.
WoW.fire("BAG_UPDATE_DELAYED")
eq(FR.Choice() and FR.Choice().id, FISH, "the catfish on offer again")
f.never:GetScript("OnClick")(f.never)
check(SS.SetHas(PC.NEVER, FISH), "Never feed this: on the list")
eq(FR.Choice() and FR.Choice().id, QUAIL, "  the quail now")
SS.SetRemove(PC.NEVER, FISH)
WoW.bags[0].items[3] = nil

-- Hidden as a fight starts, before lockdown.
WoW.blocked = {}
fight()
check(not FR.IsShown(), "hidden inside PLAYER_REGEN_DISABLED")
eq(#WoW.blocked, 0, "  nothing refused")
check(disarmed(b), "  disarmed")
peace()
check(FR.IsShown(), "offered again after the fight")

-- Close: dismissed.
f.close:GetScript("OnClick")(f.close)
check(not FR.IsShown() and PC.state.dismissed, "Close: dismissed")
happy(3)

-- No food: the window says why, Feed and Never disabled.
WoW.bags[0] = { size = 16, items = { [1] = { id = BREAD, count = 20 } } }
happy(2)
eq(f.food:GetText(), "No food it eats in your bags.", "no food: says so")
check(not f.icon:IsShown(), "  no icon")
check(not b:IsEnabled() and not f.never:IsEnabled(), "  Feed and Never feed this disabled")
happy(3)
WoW.bags[0] = { size = 16, items = { [1] = { id = QUAIL, count = 5 }, [2] = { id = BREAD, count = 20 } } }

-- /gpearls petcare test, never in lockdown.
WoW.combat = true
P.Command("petcare").run("test")
check(not FR.IsShown(), "test in combat: not shown")
WoW.combat = false
P.Command("petcare").run("test")
check(FR.IsShown() and f.status:GetText():find("A test", 1, true), "test: the window")
check(FR.Choice() ~= nil and b:IsEnabled(), "  with food on offer, Feed enabled")
reset()
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
eq(#WoW.secureActions, 0, "  Feed on a Happy pet: no action")
eq(#WoW.fed, 0, "  nothing fed")
check(disarmed(b), "  disarmed")
check(not FR.IsShown(), "  closed: the pet is happy enough")
FR.Close()

--------------------------------------------------------------------------------
-- The tooltip line

local function tip(id, data)
    local added = {}
    local tt = { AddLine = function(_, text) added[#added + 1] = text end }
    for _, fn in ipairs(WoW.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
        fn(tt, data or { type = Enum.TooltipDataType.Item, id = id, lines = {} })
    end
    return table.concat(added, "\n")
end
eq(#(WoW.tooltipPostCalls[Enum.TooltipDataType.Item] or {}), 1, "one item tooltip hook")
eq(tip(QUAIL), FR.TIP, "tooltip (the default): edible")
eq(tip(BREAD), "", "  not edible: nothing")
eq(tip(nil, { id = WoW.Secret("id") }), "", "  a secret ID: nothing")
WoW.edible[777777] = true
WoW.MarkSecret(777777, "item id")
eq(tip(777777), "", "  a secret ID that is still a number: nothing")
eq(tip(nil, WoW.Secret("data")), "", "  secret data: nothing")
WoW.pet = nil
eq(tip(QUAIL), "", "  no pet out: nothing")
WoW.pet = { happiness = 3, level = 60, guid = "Pet-1" }
WoW.fire("PLAYER_REGEN_DISABLED")
eq(tip(QUAIL), "", "  in combat: nothing")
WoW.fire("PLAYER_REGEN_ENABLED")
for food, want in pairs({ bags = "", both = FR.TIP, off = "" }) do
    P.SetSetting("petcare", "food", food)
    eq(tip(QUAIL), want, "food = " .. food)
end
P.Set("petcare", false)
P.SetSetting("petcare", "food", "both")
eq(tip(QUAIL), "", "switched off: nothing")
P.Set("petcare", true)
eq(#WoW.tooltipPostCalls[Enum.TooltipDataType.Item], 1, "  still one hook after switching back on")

--------------------------------------------------------------------------------
-- The bag marks

local CF1, CF2, COMBINED = WoW.containerFrames[1], WoW.containerFrames[2], ContainerFrameCombinedBags
P.SetSetting("petcare", "food", "tooltip")
WoW.showBag(CF1, { { 0, 1 }, { 0, 2 } })
local marks = FR._test.marks
eq(next(marks), nil, "tooltip only: no marks")
P.SetSetting("petcare", "food", "bags")
for i, cf in ipairs(WoW.containerFrames) do
    check(WoW.hooked[cf] and WoW.hooked[cf].UpdateItems, "UpdateItems hooked: bag frame " .. i)
end
check(WoW.hooked[COMBINED] and WoW.hooked[COMBINED].UpdateItems, "  and the combined bags")
local b1, b2 = CF1.Items[1], CF1.Items[2]
check(marks[b1] and marks[b1]:IsShown(), "turned on with the bags open: the quail marked")
eq(marks[b2], nil, "  the bread not (no mark made)")
check(marks[b1]:GetParent() == b1, "  our own child frame on Blizzard's button")
local keys = {}
for k in pairs(b1) do if type(k) ~= "string" or k:sub(1, 1) ~= "_" then keys[#keys + 1] = tostring(k) end end
table.sort(keys)
eq(table.concat(keys, ","), "GetBagID", "  nothing written on Blizzard's button")
P.SetSetting("petcare", "food", "both")
P.SetSetting("petcare", "food", "bags")
eq(WoW.hooked[CF1].UpdateItems, 1, "hooked once")
eq(WoW.hooked[COMBINED].UpdateItems, 1, "  the combined bags too")

-- A pooled button reused for another slot.
WoW.showBag(CF1, { { 0, 2 }, { 0, 1 } })
check(not marks[b1]:IsShown(), "a pooled button now on the bread: hidden")
check(marks[b2] and marks[b2]:IsShown(), "  the other, now on the quail: shown")

-- A new pet (a new diet), and none.
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
check(not marks[b2]:IsShown(), "no pet: hidden on UNIT_PET")
WoW.pet = { happiness = 3, level = 60, guid = "Pet-1" }
WoW.fire("UNIT_PET", "player")
check(marks[b2]:IsShown(), "  back: shown")

-- The combined bags.
CF1:Hide()
WoW.showBag(COMBINED, { { 0, 1 }, { 0, 2 } })
check(marks[COMBINED.Items[1]] and marks[COMBINED.Items[1]]:IsShown(), "the combined bags: marked")

-- Off: hidden everywhere.
P.SetSetting("petcare", "food", "off")
check(not marks[COMBINED.Items[1]]:IsShown() and not marks[b2]:IsShown(), "off: every mark hidden")
WoW.showBag(COMBINED, { { 0, 1 } })
check(not marks[COMBINED.Items[1]]:IsShown(), "  Blizzard's update doesn't bring it back")
P.SetSetting("petcare", "food", "bags")
check(marks[COMBINED.Items[1]]:IsShown(), "on again: shown")
check(not marks[b2]:IsShown(), "  a closed bag's buttons left alone")

-- In combat: no mark created; existing ones only shown or hidden.
fight()
WoW.showBag(CF2, { { 0, 1 } })
local c1 = CF2.Items[1]
eq(marks[c1], nil, "a button first met in combat: no mark yet")
check(FR._test.pending[c1], "  noted")
peace()
check(marks[c1] and marks[c1]:IsShown(), "  marked after the fight")

-- Switched off: hidden.
P.Set("petcare", false)
check(not marks[c1]:IsShown(), "switched off: hidden")
WoW.showBag(CF2, { { 0, 1 } })
check(not marks[c1]:IsShown(), "  Blizzard's update while off: still hidden")
P.Set("petcare", true)
P.ResetSettings("petcare")

--------------------------------------------------------------------------------
-- The panel

GP.Options.Open("cat:Combat")
local page = GP.Options._test.pages["cat:Combat"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "petcare" then row = pl.row end end
check(row ~= nil, "on the Combat page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:petcare"].frame._children[1]
local checks, radios = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
    if w._template == "UIRadioButtonTemplate" then radios[#radios + 1] = w end
end
eq(#radios, 6, "six radios: four for the food, two for the threshold")
eq(#checks, 6, "six switches: feed, missing, passive and the three times")
radios[3]:GetScript("OnClick")(radios[3])
eq(P.Setting("petcare", "food"), "both", "  the food radio")
radios[6]:GetScript("OnClick")(radios[6])
eq(P.Setting("petcare", "feedAt"), "unhappy", "  the threshold radio")
checks[6]:SetChecked(true)
checks[6]:GetScript("OnClick")(checks[6])
eq(P.Setting("petcare", "away"), true, "  the away switch")
check(content.neverList ~= nil, "  the never-feed list")
P.ResetSettings("petcare")

done("test_petcare_frame" .. (glass and " (glass)" or ""))
