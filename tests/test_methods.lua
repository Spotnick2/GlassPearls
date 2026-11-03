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
WoW.bags[0] = { size = 1, items = { [1] = { id = 1 } } }
WoW.openLoot({ { id = 10, qty = 1 } })
WoW.flushTimers(0)
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

-- WowTestKit: the animation subtypes' own methods aren't in its widget-method
-- lists, though the 70532 dump documents them (SimpleAnimAlphaAPI,
-- SimpleAnimScaleAPI); allowed here with that source.
-- The others are Blizzard's Lua mixins on its own frames, which the dump's
-- widget walk can't see (wow-ui-source, forever branch).
local ALPHA = "70532 dump, SimpleAnimAlphaAPI (documented)"
local SCALE = "70532 dump, SimpleAnimScaleAPI (documented)"
local MAP = "WorldMapFrame's MapCanvasMixin (Blizzard_MapCanvas.lua)"
local TIP = "GameTooltipDataMixin's accessor (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)"
local recorded = Kit.checkMethods({ allow = {
    ["Alpha:SetFromAlpha"] = ALPHA, ["Alpha:SetToAlpha"] = ALPHA,
    ["Scale:SetScaleFrom"] = SCALE, ["Scale:SetScaleTo"] = SCALE,
    ["Frame:GetMapID"] = MAP, ["Frame:GetNormalizedCursorPosition"] = MAP, ["Frame:IsCanvasMouseFocus"] = MAP,
    ["GameTooltip:SetBagItem"] = TIP, ["GameTooltip:SetLootItem"] = TIP,
} })
-- Loading alone records about 45: the floor keeps the exercise from quietly
-- shrinking back to that.
check(recorded >= 120,"the exercise reached the windows and panels (" .. recorded .. " methods recorded)")
done("test_methods" .. (glass and " (glass)" or ""))
