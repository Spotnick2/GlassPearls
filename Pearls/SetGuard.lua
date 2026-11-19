-- Pearls/SetGuard.lua: equipment set guard (#142). Item tooltips name the
-- equipment sets an item is in (Forever's don't), and losing a set item is
-- warned about: destroying it (under Blizzard's own delete popup), selling it
-- (a tooltip line at a merchant before, a warning after), disenchanting it
-- (during the cast).
--
-- What the client allows (plan reviewed by Codex, #142): a right-click sale
-- can't be stopped without replacing Blizzard's bag button, and the cast can't
-- be stopped by addon code (SpellStopCasting is protected). So the sale and
-- disenchant warnings are warnings, not confirmations, and the help says so.
--
-- - Membership is per copy, by location (Core/EquipSets.lua): a second copy
--   outside the set is never named.
-- - Destroy: DELETE_ITEM_CONFIRM's GUID, a frame later (after Blizzard's
--   handler showed its popup); the cursor's location when it holds that GUID,
--   else the GUID's. Our own click-through warning under the popup whose data
--   names that GUID (read only, polled while shown), else the centre notice.
-- - The uses: one hooksecurefunc on C_Container.UseContainerItem, which
--   Blizzard's bag right-click calls (Mainline/ContainerFrame.lua:1611, loaded
--   by Forever), and so do spell targeting and other add-ons (our junk seller).
--   Every call is recorded (bag, slot, the GUID there right after the call,
--   its sets), set item or not, a few kept. The item read after the call is
--   taken as the one used (the sale or cast still pending): a day-one check.
-- - Disenchant: UNIT_SPELLCAST_START of 13262 (the only Disenchant, a 3 s
--   cast); PAIR seconds later every use within PAIR of the start belongs to
--   it, and a set item among them is warned with "may be": time is the only
--   link between a use and a cast. Other targeting paths (target-item, an
--   inventory slot) aren't seen.
-- - Sell: a single set item used at a merchant (bags 0-4), claimed by no cast,
--   whose GUID has no location, or none in bags or gear (the buyback slots),
--   between SALE_FROM and SALE_UNTIL, the visit still open; still in its slot:
--   pending; elsewhere: moved, dropped. Said as "left your bags", never "sold".
--   A visit already open when the pearl is switched on isn't seen.
-- Unmeasured until checked in game (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local SG = {}
GP.SetGuard = SG

SG.KEY = "setguard"
SG.DISENCHANT = 13262
SG.PAIR = 0.5            -- a use and a Disenchant start this close may belong together
SG.SALE_FROM = 1.1       -- past 2 x PAIR: any cast that could claim the use has settled
SG.SALE_UNTIL = 2.5      -- a sale seen by then, or dropped
SG.KEEP = 5              -- recent uses kept this long
SG.USES_MAX = 8
SG.POLL = 0.1
SG.WARNING_WIDTH = 340
SG.POPUPS = { "DELETE_ITEM", "DELETE_GOOD_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM",
              "DELETE_GOOD_ITEM_GAMEPAD", "DELETE_GOOD_QUEST_ITEM_GAMEPAD" }
SG.CAST_ENDS = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_FAILED = true,
                 UNIT_SPELLCAST_SUCCEEDED = true }
SG.EQUIP_LAST = 19       -- INVSLOT_LAST_EQUIPPED: gear, not the buyback or bank slots

local events = CreateFrame("Frame")
local state = { hooked = false, tipHooked = false, token = 0, gen = 0, uses = {}, cast = nil,
                last = "nothing yet" }
SG.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(SG.KEY, name) end
local function on(name) return GP.Pearls.IsOn(SG.KEY) and setting(name) == true end

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, table.maxn(r))
end

local function now() return plain((call(GetTime)), "number") or 0 end

-- A method's boolean answer: true, false, or nil (absent, threw, secret, other).
local function ask(obj, name, ...)
    local fn = obj[name]
    if API.IsSecret(fn) or type(fn) ~= "function" then return nil end
    return plain((call(fn, obj, ...)), "boolean")
end

local function linkOf(guid)
    local link = plain((call(C_Item.GetItemLinkByGUID, guid)), "string")
    if link and link ~= "" then return link end
    return "an item"
end

local function sets(names) return names:find(", ", 1, true) and "equipment sets" or "equipment set" end

local function notice(text)
    if GP.Notice then GP.Notice.Show(text) end
end

-- Where an item with this GUID is: "held" (a bag slot, any bag, or worn
-- gear), "gone" (no location, or another kind: the buyback slots), nil (can't tell).
local function whereabouts(guid)
    local r = { pcall(C_Item.GetItemLocation, guid) }
    if not r[1] then return nil end
    local loc = r[2]
    if API.IsSecret(loc) then return nil end
    if loc == nil then return "gone" end
    if type(loc) ~= "table" then return nil end
    local isBag = ask(loc, "IsBagAndSlot")
    if isBag == true then
        local bag, slot = call(loc.GetBagAndSlot, loc)
        bag, slot = plain(bag, "number"), plain(slot, "number")
        if not (bag and slot) then return nil end      -- unknown: never "moved"
        return "held", bag, slot
    end
    local isEquip = ask(loc, "IsEquipmentSlot")
    if isEquip == true then
        local slot = plain((call(loc.GetEquipmentSlot, loc)), "number")
        if not slot then return nil end
        return (slot >= 1 and slot <= SG.EQUIP_LAST) and "held" or "gone"
    end
    if isBag == false and isEquip == false then return "gone" end
    return nil
end
SG.Whereabouts = whereabouts

-- The location of the item with this GUID: the cursor's when it holds it
-- (the item being destroyed is on the cursor), else wherever the GUID is.
function SG.Locate(guid)
    local loc = call(C_Cursor.GetCursorItem)
    if plain(loc, "table") then
        local g = plain((call(C_Item.GetItemGUID, loc)), "string")
        if g == guid then return loc end
    end
    loc = call(C_Item.GetItemLocation, guid)
    return plain(loc, "table")
end

--------------------------------------------------------------------------------
-- Tooltip

local function onTooltip(tooltip, data)
    if not on("tooltip") or type(tooltip) ~= "table" or not plain(data, "table") then return end
    local guid = plain(data.guid, "string")
    if not guid or guid == "" then return end
    local loc = plain((call(C_Item.GetItemLocation, guid)), "table")
    local names = GP.EquipSets.ForLocation(loc)
    if type(names) ~= "string" or not tooltip.AddLine then return end
    tooltip:AddLine("Equipment sets: |cffffffff" .. names .. "|r", 1, 0.82, 0, true)
    if on("sell") and GP.Merchant.IsOpen() then
        local bag = ask(loc, "IsBagAndSlot") == true and plain((call(loc.GetBagAndSlot, loc)), "number")
        if bag and bag >= 0 and bag <= 4 then
            tooltip:AddLine("Careful when selling it to this merchant.", 1, 0.125, 0.125, true)
        end
    end
end
SG.OnTooltip = onTooltip

local function hookTooltip()
    if state.tipHooked then return end
    state.tipHooked = true
    local TDP = rawget(_G, "TooltipDataProcessor")
    local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if not (TDP and TDP.AddTooltipPostCall and kind) then
        return API.Fail("pearl setguard tooltip", "TooltipDataProcessor missing")
    end
    local ok, err = pcall(TDP.AddTooltipPostCall, kind, function(...)
        local ok2, err2 = pcall(onTooltip, ...)
        if not ok2 then API.Fail("pearl setguard tooltip", err2) end
    end)
    if not ok then API.Fail("pearl setguard tooltip", err) end
end

--------------------------------------------------------------------------------
-- Destroy

local warning      -- built on first use
local function buildWarning()
    warning = CreateFrame("Frame", "GlassPearlsSetGuardWarning", UIParent)
    warning:SetSize(SG.WARNING_WIDTH, 44)
    warning:SetFrameStrata("DIALOG")
    warning:EnableMouse(false)
    warning:Hide()
    local bg = warning:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    warning.text = warning:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warning.text:SetPoint("TOP", 0, -6)
    warning.text:SetWidth(SG.WARNING_WIDTH - 16)
    warning.text:SetTextColor(1, 0.125, 0.125)
    warning.text:SetWordWrap(true)
    warning.elapsed = 0
    warning:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < SG.POLL then return end
        self.elapsed = 0
        if not SG.PopupStill(self.dialog, self.guid) then SG.HideWarning() end
    end)
end

function SG.HideWarning()
    if warning then
        warning:Hide()
        warning:ClearAllPoints()
        warning.dialog, warning.guid = nil, nil
    end
end

-- Is this popup still shown and naming this GUID? Any unreadable read: no.
function SG.PopupStill(dialog, guid)
    if not plain(dialog, "table") then return false end
    if ask(dialog, "IsShown") ~= true then return false end
    local data = plain(dialog.data, "table")
    return data ~= nil and plain(data.itemGUID, "string") == guid
end

local function findPopup(guid)
    for _, which in ipairs(SG.POPUPS) do
        local dialog = call(StaticPopup_FindVisible, which)
        if SG.PopupStill(dialog, guid) then return dialog end
    end
end

local function checkDelete(token, guid)
    if token ~= state.token or not on("destroy") then return end
    local names = GP.EquipSets.ForLocation(SG.Locate(guid))
    if type(names) ~= "string" then return end
    local link = linkOf(guid)
    state.last = "destroy warning for " .. link
    say(("Careful: %s is in your %s %s."):format(link, sets(names), names))
    local text = ("In your %s: %s"):format(sets(names), names)
    local dialog = findPopup(guid)
    if not dialog then return notice(text) end
    if not warning then buildWarning() end
    warning.text:SetText(text)
    warning:SetHeight(math.max(30, (plain((call(warning.text.GetStringHeight, warning.text)), "number") or 18) + 12))
    warning:ClearAllPoints()
    warning:SetPoint("TOP", dialog, "BOTTOM", 0, -4)
    warning.dialog, warning.guid, warning.elapsed = dialog, guid, 0
    warning:Show()
end

--------------------------------------------------------------------------------
-- The click record, the sale, the cast

local function warnDisenchant(u)
    state.last = "disenchant warning for " .. u.link
    say(("Your Disenchant may be on %s, in your %s %s: move or press Esc to stop."):format(
        u.link, sets(u.names), u.names))
    notice(("Disenchanting a set item? (%s)"):format(u.names))
    if SOUNDKIT and plain(SOUNDKIT.RAID_WARNING, "number") then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
end

-- Recent uses, oldest first: after each new one, at most USES_MAX, none older
-- than KEEP. One let go is done: its timers, which still hold it, do nothing.
local function prune()
    local t, keep = now(), {}
    for _, u in ipairs(state.uses) do
        if t - u.at <= SG.KEEP then keep[#keep + 1] = u else u.done = true end
    end
    while #keep > SG.USES_MAX do table.remove(keep, 1).done = true end
    state.uses = keep
end

-- PAIR seconds after a Disenchant started, its candidates are settled: every
-- unclaimed use within PAIR of the start, either side, belongs to that cast
-- (never a sale, never another cast's), whether or not the warning is on and
-- even when the cast is already over; casts settle in the order they started,
-- so an overlap goes to the earlier one. A set item among them is warned only
-- while that cast is still the one under way.
local function settle(cast, gen)
    if gen ~= state.gen or cast.settled then return end
    cast.settled = true
    local live, warned = state.cast == cast, false
    for _, u in ipairs(state.uses) do
        if not u.cast and math.abs(u.at - cast.at) <= SG.PAIR then
            u.cast = cast.guid
            if live and not warned and type(u.names) == "string" and on("disenchant") then
                warned = true
                warnDisenchant(u)
            end
        end
    end
end

-- Could this use be a sale? Only once every Disenchant that could claim it
-- has settled (a start within PAIR of the use settles PAIR after it).
local function checkSale(u)
    if u.gen ~= state.gen or u.cast or u.done or not u.sale then return end
    if not on("sell") or not GP.Merchant.Current(u.session) then u.done = true; return end
    local age = now() - u.at
    if age > SG.SALE_UNTIL then u.done = true; return end
    if age < SG.SALE_FROM then return end
    local where, bag, slot = whereabouts(u.guid)
    if where == "held" then
        if bag ~= u.bag or slot ~= u.slot then u.done = true end   -- moved, not sold
        return
    end
    if where ~= "gone" then return end
    u.done = true
    state.last = "sale warning for " .. u.link
    say(("%s, in your %s %s, left your bags at this merchant: if you sold it, buy it back from the Buyback "
        .. "tab."):format(u.link, sets(u.names), u.names))
    notice(("A set item left your bags (%s)"):format(u.names))
end
function SG.CheckSales()
    for _, u in ipairs(state.uses) do checkSale(u) end
end

-- Every use is recorded, set item or not, so a cast is paired with what was
-- really used; only a single set item at a merchant can become a sale.
local function onUse(bag, slot)
    if not GP.Pearls.IsOn(SG.KEY) then return end
    bag, slot = plain(bag, "number"), plain(slot, "number")
    if not (bag and slot) then return end
    local u = { bag = bag, slot = slot, at = now(), link = "an item", gen = state.gen }
    state.uses[#state.uses + 1] = u
    prune()
    local loc = call(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    u.guid = plain((call(C_Item.GetItemGUID, loc)), "string")
    if not u.guid or u.guid == "" then u.guid = nil; return end
    u.link = linkOf(u.guid)
    u.names = GP.EquipSets.ForLocation(loc)
    local info = plain((call(C_Container.GetContainerItemInfo, bag, slot)), "table")
    local single = info and plain(info.stackCount, "number") == 1
    if type(u.names) == "string" and single and bag >= 0 and bag <= 4 and on("sell") and GP.Merchant.IsOpen() then
        u.sale, u.session = true, GP.Merchant.Session()
        C_Timer.After(SG.SALE_FROM, function() checkSale(u) end)
        C_Timer.After(SG.SALE_UNTIL, function() checkSale(u) end)
    end
end
SG.OnUse = onUse

local function hookUse()
    if state.hooked then return end
    state.hooked = true
    if not (C_Container and type(C_Container.UseContainerItem) == "function") then
        return API.Fail("pearl setguard hook", "C_Container.UseContainerItem missing")
    end
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        local ok, err = pcall(onUse, bag, slot)
        if not ok then API.Fail("pearl setguard use", err) end
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "DELETE_ITEM_CONFIRM" then
        state.token = state.token + 1          -- a new popup stales the last
        SG.HideWarning()
        local token, guid = state.token, plain(select(5, ...), "string")
        if not guid or guid == "" or not on("destroy") then return end
        C_Timer.After(0, function() checkDelete(token, guid) end)
    elseif event == "UNIT_SPELLCAST_START" then
        local unit, castGUID, spellID = ...
        if plain(unit, "string") ~= "player" or plain(spellID, "number") ~= SG.DISENCHANT then return end
        castGUID = plain(castGUID, "string")
        if not castGUID then return end
        local cast = { guid = castGUID, at = now() }
        state.cast = cast
        local gen = state.gen
        C_Timer.After(SG.PAIR, function() settle(cast, gen) end)
    elseif SG.CAST_ENDS[event] then
        local unit, castGUID = ...
        if state.cast and plain(unit, "string") == "player" and plain(castGUID, "string") == state.cast.guid then
            state.cast = nil
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        SG.CheckSales()
    elseif event == "PLAYER_LEAVING_WORLD" then
        SG.Forget()
    end
end)

--------------------------------------------------------------------------------
-- Report, panel, registration

function SG.Report()
    say(("Equipment set guard: %s. Last: %s."):format(GP.Pearls.IsOn(SG.KEY) and "on" or "off", state.last))
    local n = 0
    for bag = 0, 4 do
        local size = plain((call(C_Container.GetContainerNumSlots, bag)), "number") or 0
        for slot = 1, size do
            local loc = call(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
            local names = GP.EquipSets.ForLocation(loc)
            if names ~= false and plain((call(C_Item.GetItemGUID, loc)), "string") then
                n = n + 1
                local link = plain((call(C_Container.GetContainerItemLink, bag, slot)), "string") or "?"
                say(("  bag %d slot %d: %s: %s"):format(bag, slot, link,
                    type(names) == "string" and names or "can't tell"))
            end
        end
    end
    for slot = 1, SG.EQUIP_LAST do
        local names = GP.EquipSets.ForWornSlot(slot)
        if names ~= false then
            n = n + 1
            say(("  worn slot %d: %s"):format(slot, type(names) == "string" and names or "can't tell"))
        end
    end
    if n == 0 then say("  No item in your bags or gear is in an equipment set.") end
end

local function configure(panel, refreshers)
    local KEY, P = SG.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "Equipment set guard")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local rows = {
        { "tooltip", "Name the sets in item tooltips" },
        { "destroy", "Warn when destroying a set item" },
        { "sell", "Warn when selling a set item" },
        { "disenchant", "Warn when disenchanting a set item" },
    }
    local last = head
    for i, row in ipairs(rows) do
        local cb, refresh = GP.UI.Check(panel, row[2],
            function() return P.Setting(KEY, row[1]) end, function(v) P.SetSetting(KEY, row[1], v) end)
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", i == 1 and -4 or 0, i == 1 and -6 or -4)
        refreshers[#refreshers + 1] = refresh
        last = cb
    end
    local note = GP.UI.Label(panel,
        "Destroying keeps Blizzard's own confirmation, with the sets named under it. A sale can't be stopped: "
            .. "at a merchant the tooltip says to take care, and when a set item you right-clicked leaves your "
            .. "bags you're told to check the Buyback tab. A disenchant can't be stopped by an add-on: during the "
            .. "cast you're told which set item it may be on, to move or press Esc. Unverified until checked in "
            .. "game.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

local function enable()
    SG.enabled = true
    hookTooltip()
    hookUse()
    -- Listening makes the merchant session tracked even with the other merchant
    -- pearls off; a visit already open when this is switched on isn't seen.
    GP.Merchant.On(SG.KEY, function(event)
        if event == "MERCHANT_CLOSED" then
            for _, u in ipairs(state.uses) do u.done = true end
        end
    end)
    API.RegisterEvents(events, { "DELETE_ITEM_CONFIRM", "BAG_UPDATE_DELAYED", "PLAYER_LEAVING_WORLD" })
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
                         "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED" }) do
        local ok, registered = pcall(events.RegisterUnitEvent, events, e, "player")
        if not ok or registered == false then API.Fail("pearl setguard " .. e, ok and "refused" or registered) end
    end
end

-- Everything pending is dropped; a timer of an older generation does nothing.
function SG.Forget()
    state.gen = state.gen + 1
    state.uses, state.cast = {}, nil
end

local function disable()
    SG.enabled = false
    state.token = state.token + 1
    SG.Forget()
    GP.Merchant.On(SG.KEY, nil)
    SG.HideWarning()
    events:UnregisterAllEvents()
end

GP.Pearls.Register({
    key = SG.KEY,
    name = "Equipment set guard",
    desc = "Item tooltips name the equipment sets an item is in, and you're warned before destroying, and "
        .. "when selling or disenchanting, a set item.",
    help = "Tooltips of your own items (bags, bank, worn) name the equipment sets that copy is in. Destroying a "
        .. "set item keeps Blizzard's own confirmation, with the sets named under it. A sale can't be stopped by "
        .. "an add-on: at a merchant the tooltip says to take care, and when a set item you right-clicked there "
        .. "leaves your bags you're told to check the merchant's Buyback tab (dragging an item onto the merchant "
        .. "isn't noticed). A disenchant can't be stopped either: during its cast you're told which set item it "
        .. "may be on, so you can move or press Esc. Easy delete never fills in DELETE for a set item. /gpearls "
        .. "setguard lists your set items as the client reports them. Unverified until checked in game.",
    default = true,
    category = "Loot & Bags",
    section = "Bags",
    defaults = { tooltip = true, destroy = true, sell = true, disenchant = true },
    Enable = enable,
    Disable = disable,
    configure = configure,
    onSettingChanged = function()
        if not on("destroy") then state.token = state.token + 1; SG.HideWarning() end
        if not on("sell") then for _, u in ipairs(state.uses) do u.done = true end end
    end,
    commands = { setguard = { help = "- your items in equipment sets, as the client reports them",
        run = function() SG.Report() end } },
})

SG._test = { events = events, warning = function() return warning end }
