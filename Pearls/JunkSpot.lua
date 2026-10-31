-- Pearls/JunkSpot.lua: junk spotlight (#41). Shows in your bags what the
-- junk seller (#15) may sell at the next merchant: a coin on the bag button
-- and a tooltip line, by the seller's own rules (Junk.Judge on the slot, the
-- equipment-set snapshot read once per pass), never a rule of its own.
--
-- Eligibility, not a promise: Judge answers whether a stack passes the item
-- rules; a visit can still leave it (an unreadable GUID, the buyback room in
-- buyback-safe mode, Shift, combat, a refusal). Active only while the seller
-- sells (the junk pearl on and its autoSell setting), and only in the bags
-- it sells from (0-4).
--
-- The marks are Core/BagMarks.lua's kind "junkspot". Refreshed, bags open or
-- not, by Blizzard's UpdateItems (the hook), a change of the sell or keep
-- list (SettingsSync.OnSetChanged: commands, the options lists, sync), the
-- seller's settings and switch (Junk calls JunkSpot.Refresh), our own setting,
-- MERCHANT_CLOSED, EQUIPMENT_SETS_CHANGED and ITEM_LOCK_CHANGED (Judge refuses
-- a locked stack, and Blizzard's lock handler never runs UpdateItems).
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local JS = {}
GP.JunkSpot = JS

JS.KEY = "junkspot"
JS.SHOW = { "both", "bags", "tooltip" }
JS.MARK_ATLAS = "Coin-Gold"
JS.TIP_SALE = "Eligible for automatic sale"
JS.TIP_KEPT = "Kept: on your keep list"

local events = CreateFrame("Frame")
local tooltipHooked, listening = false, false
local Bags = GP.Bags

local function setting(name) return GP.Pearls.Setting(JS.KEY, name) end
local function J() return GP.Junk end

-- The seller sells: the junk pearl on, with its autoSell setting.
function JS.SellerSells()
    return GP.Pearls.IsOn("junk") and GP.Pearls.Setting("junk", "autoSell") == true
end

local function shows(where)
    local show = setting("show")
    return JS.enabled == true and JS.SellerSells() and (show == where or show == "both")
end

-- A plain whole bag of the seller's (0-4) and a plain whole slot.
local function inScope(bag, slot)
    if API.IsSecret(bag) or API.IsSecret(slot) then return false end
    return type(bag) == "number" and bag % 1 == 0 and bag >= Bags.FIRST and bag <= Bags.LAST
        and type(slot) == "number" and slot % 1 == 0 and slot >= 1
end

GP.BagMarks.Add(JS.KEY, {
    anchor = "BOTTOMLEFT", x = 2, y = 2, size = 12, atlas = JS.MARK_ATLAS, color = { 1, 0.82, 0, 0.9 },
    active = function() return shows("bags") end,
    prepare = function() return { sets = Bags.SetItems() } end,
    shows = function(bag, slot, ctx)
        if not inScope(bag, slot) then return false end
        return J().Judge(Bags.Slot(bag, slot), ctx.sets) ~= nil
    end,
})

function JS.Refresh() GP.BagMarks.Refresh(JS.KEY) end

-- The tooltip line, for one of Blizzard's bag buttons only.
local function onTooltip(tooltip, data)
    if not shows("tooltip") or API.InCombat() then return end
    if API.IsSecret(data) or type(data) ~= "table" then return end
    local id = data.id
    if API.IsSecret(id) or type(id) ~= "number" then return end
    if not (tooltip and tooltip.GetOwner and tooltip.AddLine) then return end
    local okO, owner = pcall(tooltip.GetOwner, tooltip)
    if not okO or API.IsSecret(owner) or type(owner) ~= "table" then return end
    local okB, bag = pcall(owner.GetBagID, owner)      -- not a bag button: no method, the pcall fails
    local okS, slot = pcall(owner.GetID, owner)
    if not (okB and okS) or not inScope(bag, slot) then return end
    local okI, here = pcall(C_Container.GetContainerItemID, bag, slot)
    if not okI or API.IsSecret(here) or here ~= id then return end
    local entry, why = J().Judge(Bags.Slot(bag, slot), Bags.SetItems())
    if entry then
        tooltip:AddLine(JS.TIP_SALE .. ": " .. GP.TrainingFrame.Money(entry.value), 1, 0.82, 0)
    elseif why == "kept" then
        tooltip:AddLine(JS.TIP_KEPT, 0.6, 0.8, 1)
    end
end

local function hookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true
    local TDP = rawget(_G, "TooltipDataProcessor")
    local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if not (TDP and TDP.AddTooltipPostCall and kind) then
        return API.Fail("pearl junkspot tooltip", "TooltipDataProcessor missing")
    end
    local ok, err = pcall(TDP.AddTooltipPostCall, kind, function(...)
        local ok2, err2 = pcall(onTooltip, ...)
        if not ok2 then API.Fail("pearl junkspot tooltip", err2) end
    end)
    if not ok then API.Fail("pearl junkspot tooltip", err) end
end

-- Hooks the setting needs, once each (they can't be removed: each checks).
local function start()
    if shows("tooltip") then hookTooltip() end
    if shows("bags") then GP.BagMarks.Hook() end
    if not listening then
        listening = true
        local SS = GP.SettingsSync
        SS.OnSetChanged(J().SELL, JS.Refresh)
        SS.OnSetChanged(J().KEEP, JS.Refresh)
    end
end

events:SetScript("OnEvent", function() JS.Refresh() end)   -- payloads unread

local function configure(panel, refreshers)
    local KEY, P = JS.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "Show what the junk seller may sell")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local last, _, refresh = GP.UI.Radios(panel, head,
        { { "both", "In the bags and the tooltip" }, { "bags", "A coin in the bags" }, { "tooltip", "A tooltip line" } },
        function() return P.Setting(KEY, "show") end, function(v) P.SetSetting(KEY, "show", v) end)
    refreshers[#refreshers + 1] = refresh
    local note = GP.UI.Label(panel,
        "It follows Sell junk & repair: with that off, or its selling off, nothing is shown. Eligible means it "
            .. "passes the seller's rules; a visit can still leave it (Shift held, combat, buyback room, a refusal).",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

local function enable()
    JS.enabled = true
    API.RegisterEvents(events, { "MERCHANT_CLOSED", "EQUIPMENT_SETS_CHANGED", "ITEM_LOCK_CHANGED" })
    start()
    JS.Refresh()
end

local function disable()
    JS.enabled = false
    events:UnregisterAllEvents()
    JS.Refresh()
end

GP.Pearls.Register({
    key = JS.KEY,
    name = "Junk spotlight",
    desc = "Shows in your bags what Sell junk & repair may sell: a coin and a tooltip line.",
    help = "A coin on the bag items Sell junk & repair may sell at the next merchant, and a tooltip line (\"Eligible "
        .. "for automatic sale\" with its value, or \"Kept: on your keep list\"). By the seller's own rules and "
        .. "lists, from your bags (not the bank). A visit can still leave an eligible item: Shift held, combat, the "
        .. "buyback room in buyback-safe mode, or the merchant refusing it. Unverified until the game is live.",
    default = false,
    category = "Loot & Bags",
    section = "Merchant",
    defaults = { show = "both" },
    choices = { show = JS.SHOW },
    Enable = enable,
    Disable = disable,
    configure = configure,
    onSettingChanged = function()
        if JS.enabled then start() end
        JS.Refresh()
    end,
})

JS._test = { events = events, onTooltip = onTooltip }
