-- Every widget method the addon calls must exist on this client, on that
-- widget type: the stub answers any method (a no-op for one it doesn't
-- implement), so a call Forever lacks would otherwise pass silently. The
-- addon is exercised as widely as is cheap, then WowTestKit's
-- Kit.checkMethods checks each recorded "Type:Method" against the pinned
-- build's widget methods. In both looks: tests/test_methods_glass.lua runs it
-- again under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
local GP = loadAddon()
local O, P = GP.Options, GP.Pearls
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))

-- Every event, then a few seconds of frames and timers.
WoW.fireAllRegistered()
for _ = 1, 5 do WoW.tick(); WoW.advance(1) end

-- Every frame under f, depth first.
local function walk(f, fn)
    fn(f)
    for _, c in ipairs(f._children or {}) do walk(c, fn) end
end
-- Hover and click everything clickable on a page: tooltips, checkboxes, gears,
-- radios, the Reset / Help / Back buttons.
local function poke(frame)
    walk(frame, function(w)
        local s = w._scripts
        if s.OnEnter then s.OnEnter(w) end
        if s.OnLeave then s.OnLeave(w) end
        if s.OnClick and (w._type == "Button" or w._type == "CheckButton") and not w._protected then
            s.OnClick(w, "LeftButton", false)
        end
    end)
end

-- The window: every page, every pearl's Configuration Panel, the search.
SlashCmdList.GLASSPEARLS("")
check(O.IsOpen(), "the options window opens")
local pages = O._test.pages
O.ShowPage("home")
O.ShowPage("settings")
poke(pages.settings.frame)
for _, category in ipairs(P.Categories()) do
    O.ShowPage("cat:" .. category)
    poke(pages["cat:" .. category].frame)
end
local panels = 0
for _, def in ipairs(P.List()) do
    if def.configure and O.ShowConfig(def.key) then
        panels = panels + 1
        poke(pages["config:" .. def.key].frame)
        O.ShowConfig(def.key)   -- shown again: every refresher re-reads
    end
end
check(panels >= 20, "every pearl's Configuration Panel built (" .. panels .. ")")
O._test.search():SetText("loot")
O._test.search():SetText("")
O._test.panel:Show()   -- Esc > Options > AddOns
SlashCmdList.GLASSPEARLS("")

-- The client's windows the pearls work with: a loot window the bags can't
-- take, a merchant, a bag, the world map, the trainer.
WoW.items[1] = { name = "Grey Junk", price = 5, quality = 0, maxStack = 1 }
WoW.items[10] = { name = "Ring", price = 620, quality = 2, maxStack = 1, classID = 4 }
-- Bread: the bags-full helper's white alternative and its row (#101).
WoW.items[20] = { name = "Bread", price = 1, quality = 1, maxStack = 20, classID = 0, subclassID = 5, spell = true }
WoW.bags[0] = { size = 2, items = { [1] = { id = 1 }, [2] = { id = 20, count = 2 } } }
WoW.openLoot({ { id = 10, qty = 1 } })
WoW.flushTimers(0)
poke(GP.BagsFullFrame._test.frame())
GP.BagsFull.ToggleAlternative()
poke(GP.BagsFullFrame._test.frame())
WoW.closeLoot()
WoW.openMerchant()
for _ = 1, 3 do WoW.tick(); WoW.advance(1) end
WoW.closeMerchant()
WoW.showBag(WoW.containerFrames[1], { { 0, 1 } })
poke(WoW.containerFrames[1])
WorldMapFrame:Show()
WoW.tick()
WorldMapFrame:Hide()
WoW.loadTrainerUI()
WoW.tick()

-- Every command: the framework's, each pearl's report, and its test where it has one.
for _, cmd in ipairs({ "help", "list", "version", "failures", "sync" }) do SlashCmdList.GLASSPEARLS(cmd) end
for _, c in ipairs(P.Commands()) do
    SlashCmdList.GLASSPEARLS(c.name)
    if c.help:find("[test]", 1, true) then SlashCmdList.GLASSPEARLS(c.name .. " test") end
end
for _ = 1, 5 do WoW.tick(); WoW.advance(1) end
-- The quest sparkle's stars on a soft-interact object's plate (#79): the art and its animations.
WoW.units.softinteract = { id = "rock" }
WoW.units.nameplate1 = { id = "rock", object = true, quest = true }
WoW.plates = { WoW.newPlate("nameplate1") }
P.Set("sparkle", true)
P.SetSetting("sparkle", "stars", "all")
WoW.tick(1)
check(GP.SparkleStars.state.bound ~= nil, "the stars bound for the exercise")
SlashCmdList.GLASSPEARLS("sparkle target")
-- A library book's pin: its tooltip (#72).
for icon, r in pairs(WoW.hbd.world) do
    if r.ref == GP.Books then
        icon._scripts.OnEnter(icon)
        icon._scripts.OnLeave(icon)
        break
    end
end
-- A waypoint route (#139): the paste box, the step list and its rows, the compass for it, a pin's tooltip.
WoW.zoneRects[1429] = { 1000, 700, 0, 0, 0 }
WoW.playerZone = { 1429, 3 }
WoW.playerWorld = { 0, 0, 0 }
WoW.facing = 0
SlashCmdList.GLASSPEARLS("way paste")
local wayPaste = GP.WayFrame._test.paste()
wayPaste.edit:SetText("/way 10 10 one\n/way 20 20 two")
wayPaste.load:GetScript("OnClick")(wayPaste.load)
check(GP.Way.Route() ~= nil, "a route loaded for the exercise")
WoW.tick(1)
local wayList = GP.WayFrame._test.list()
wayList:GetScript("OnMouseWheel")(wayList, -1)
wayList.rows[2]:GetScript("OnClick")(wayList.rows[2])
for icon, r in pairs(WoW.hbd.mini) do
    if r.ref == GP.WayFrame then
        icon._scripts.OnEnter(icon)
        icon._scripts.OnLeave(icon)
        break
    end
end
GP.Compass._test.disc():GetScript("OnEnter")(GP.Compass._test.disc())
-- The equipment set guard's destroy warning under a popup, and its report.
WoW.bags[0] = { size = 16, items = { [1] = { id = 19140, count = 1, guid = "Item-SG" } } }
WoW.addSet(1, "Shadow", { [11] = WoW.packBag(0, 1) })
WoW.cursor = { bag = 0, slot = 1, id = 19140 }
WoW.showDeleteDialog("DELETE_ITEM", "Item-SG")
WoW.fire("DELETE_ITEM_CONFIRM", "Ring", 2, 1, 0, "Item-SG")
WoW.advance(0)
check(GP.SetGuard._test.warning():IsShown(), "the set guard's warning shown for the exercise")
WoW.tick(0.2)
WoW.hideDialog("DELETE_ITEM")
WoW.tick(0.2)
WoW.cursor = nil
SlashCmdList.GLASSPEARLS("setguard")
-- Each pearl off and on again (its Disable and Enable).
for _, def in ipairs(P.List()) do
    SlashCmdList.GLASSPEARLS(def.key .. " off")
    SlashCmdList.GLASSPEARLS(def.key .. " on")
end
WoW.tick()

-- The exercise reached everything: nothing failed on the way.
local failed = {}
for k, v in pairs(GP.failures) do failed[#failed + 1] = k .. ": " .. tostring(v) end
table.sort(failed)
eq(#failed, 0, "nothing failed while exercising" .. (failed[1] and (": " .. table.concat(failed, "; ")) or ""))
-- FINDING: /gpearls help's gossip and petcare lines hold a bare "|"
-- (test_bagsfull_flow names them); only those two are let through until
-- they're fixed.
local strays = {}
for _, line in ipairs(WoW.strays) do
    if not line:find("/gpearls gossip - [list | trace", 1, true)
        and not line:find("/gpearls petcare - [never <item> | forget", 1, true) then
        strays[#strays + 1] = line
    end
end
eq(#WoW.strays - #strays, 2, "the two known stray lines (gossip, petcare help)")
WoW.strays = strays

-- Blizzard's Lua mixins on its own frames, which the dump's widget walk can't
-- see (wow-ui-source, forever branch). GameTooltip's setters are allowed in
-- the stub (Kit.allowMethods), which checkMethods accepts too.
local MAP = "WorldMapFrame's MapCanvasMixin (Blizzard_MapCanvas.lua)"
local recorded = Kit.checkMethods({ allow = {
    ["Frame:GetMapID"] = MAP, ["Frame:GetNormalizedCursorPosition"] = MAP, ["Frame:IsCanvasMouseFocus"] = MAP,
} })
-- Loading alone records about 45: the floor keeps the exercise from quietly
-- shrinking back to that.
check(recorded >= 120,"the exercise reached the windows and panels (" .. recorded .. " methods recorded)")
done("test_methods" .. (glass and " (glass)" or ""))
