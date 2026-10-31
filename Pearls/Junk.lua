-- Pearls/Junk.lua: sell junk and repair at a merchant (#15). When a merchant
-- opens: sell the junk in your bags, then repair, guild funds first when the
-- guild allows it. Its gear's panel is Pearls/JunkFrame.lua; the session is
-- Core/Merchant.lua; bag facts are Core/Bags.lua.
--
-- Junk, judged per stack on known data only (anything unknown, secret or
-- locked is not junk; bags 0-4): grey items with a sell price, and anything on
-- the sell list up to rare. Never: the keep list, quest items, tools,
-- equipment-set items, the Hearthstone, refundable purchases
-- (C_Item.CanBeRefunded, even when listed), no value. The grey rule also skips
-- unbound grey gear (it may be worth more elsewhere) and greys with a use;
-- listing one sells it anyway.
--
-- Selling, at MERCHANT_SHOW (+0.2 s), out of combat, with an empty cursor;
-- Shift held skips the visit. Cheapest first, so the last sales (the ones the
-- buyback page keeps) are the most valuable. One sale in flight: the slot is
-- read again just before (same GUID, ID, count, link; not locked; still junk),
-- then C_Container.UseContainerItem, then the next only once the slot reads
-- empty or the buyback page grew (BAG_UPDATE_DELAYED; 1 s without, it stops).
-- A refusal stops it (UI_ERROR_MESSAGE by GetGameMessageInfo name, or the
-- localized text as a fallback), only while one of our sales is in flight.
-- Buyback-safe: at most the room left on the buyback page at the start; the
-- promise holds provided the player sells nothing meanwhile, and a best-effort
-- check of the page's links stops the run if one of ours seems gone.
--
-- Money is reported as observed while selling and while repairing: the sale
-- phase settles (no PLAYER_MONEY for 0.5 s, 2 s at most) before repair reads
-- its own baseline. Nothing claims an exact sale price or guild share.
--
-- Repair, after selling: guild funds first (RepairAllItems(true), as
-- Blizzard's guild repair button; it may take the player's money for what the
-- allowance doesn't cover), then once that settled (the cost read again has
-- changed, on UPDATE_INVENTORY_DURABILITY, within 2 s) the rest from the
-- player's money if it covers it; or the player's money only. A guild whose
-- info text says [noautorepair] is never charged. An unsettled repair stops:
-- never a second payment on stale data. Unmeasured until 2026-11-04.
--
-- The visit's outcome, for the restock pearl (#14), through Merchant.Report:
-- "ready" once selling and repairing ended with nothing that may still land;
-- "skip" when a sale or repair may (a run ended unconfirmed, by the buyback
-- check, refused or by combat; an unconfirmed repair; combat; switched off).

local ADDON = ...
GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Bags = GP.Bags
local Merchant = GP.Merchant
local J = {}
GP.Junk = J

J.KEY = "junk"
J.SELL = "junk.sell"            -- sold whatever the grey rule says, a sync set
J.KEEP = "junk.keep"            -- never sold, a sync set
J.OPEN_DELAY = 0.2
J.CONFIRM_SECONDS = 1
J.SETTLE_QUIET, J.SETTLE_MAX = 0.5, 2
J.REPAIR_SECONDS = 2
J.BUYBACK_SLOTS = 12            -- Blizzard's buyback page (MerchantFrame.lua:2)
J.MAX_LISTED_QUALITY = 3        -- rare: the sell list never sells epic or better
J.HEARTHSTONE = 6948
-- Items that report a price but can't be sold: filled on day one.
J.UNSELLABLE = {}
J.GEAR_CLASSES = { [2] = true, [4] = true }   -- weapon, armour (ItemConstantsDocumentation.lua:269)
-- UI error names (GetGameMessageInfo) that mean "this merchant won't take it".
J.REFUSALS = { ERR_VENDOR_DOESNT_BUY = true, ERR_TOO_MUCH_GOLD = true }
-- A run that ended this way may still have a sale landing: the visit is "skip".
J.UNSAFE = { unconfirmed = true, buyback = true, refused = true, combat = true }

local events = CreateFrame("Frame")
local state = {
    run = nil,        -- the selling run of this visit
    repair = nil,     -- the repair in progress
    lastMoney = 0,    -- PLAYER_MONEY's generation, for the settle wait
}
J.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(J.KEY, name) end
local function money(v) return C_CurrencyInfo.GetCoinTextureString(v) end
local function SS() return GP.SettingsSync end

local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function getMoney()
    local ok, m = pcall(GetMoney)
    return ok and plainNumber(m) or nil
end

local function signed(delta)
    if not delta then return "unknown" end
    if delta >= 0 then return "+" .. money(delta) end
    return "-" .. money(-delta)
end

local function cursorEmpty()
    local ok, kind = pcall(GetCursorInfo)
    return ok and not API.IsSecret(kind) and kind == nil
end

local function location(bag, slot)
    local IL = rawget(_G, "ItemLocation")
    if not (IL and IL.CreateFromBagAndSlot) then return nil end
    local ok, loc = pcall(IL.CreateFromBagAndSlot, IL, bag, slot)
    return ok and loc or nil
end

-- A C_Item answer about the stack in this slot: true / false / nil.
local function askItem(fnName, bag, slot)
    local fn = C_Item and C_Item[fnName]
    local loc = location(bag, slot)
    if not (fn and loc) then return nil end
    local ok, v = pcall(fn, loc)
    if not ok or API.IsSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end

local function guidOf(bag, slot)
    local loc = location(bag, slot)
    if not loc then return nil end
    local ok, g = pcall(C_Item.GetItemGUID, loc)
    if not ok or API.IsSecret(g) or type(g) ~= "string" or g == "" then return nil end
    return g
end

--------------------------------------------------------------------------------
-- What is junk

-- A stack (Bags.Slot) as junk: { ..., price, value, why }, or nil and why not.
function J.Judge(s, setItems)
    if not s then return nil, "empty" end
    if s.locked then return nil, "locked" end
    if s.noValue then return nil, "no value" end
    if type(s.quality) ~= "number" then return nil, "unknown quality" end
    if SS().SetHas(J.KEEP, s.id) then return nil, "kept" end
    if s.id == J.HEARTHSTONE or J.UNSELLABLE[s.id] then return nil, "never sold" end
    if GP.ToolItems and GP.ToolItems[s.id] then return nil, "a tool" end
    if setItems == nil then return nil, "equipment sets unreadable" end
    if setItems[s.id] then return nil, "in an equipment set" end
    local quest = Bags.IsQuestItem(s.bag, s.slot)
    if quest == nil then return nil, "unknown quest info" end
    if quest then return nil, "a quest item" end
    local f = Bags.ItemFacts(s.id)
    if not f then return nil, "not cached" end
    if f.price <= 0 then return nil, "no value" end
    if f.quality ~= s.quality then return nil, "quality changed" end
    local refundable = askItem("CanBeRefunded", s.bag, s.slot)
    if refundable == nil then return nil, "unknown refund" end
    if refundable then return nil, "refundable" end
    local why
    if SS().SetHas(J.SELL, s.id) then
        if s.quality > J.MAX_LISTED_QUALITY then return nil, "epic or better" end
        why = "listed"
    elseif setting("sellGrey") and s.quality == 0 then
        if J.GEAR_CLASSES[f.classID] then
            local bound = askItem("IsBound", s.bag, s.slot)
            if bound == nil then return nil, "unknown binding" end
            if not bound then return nil, "unbound grey gear" end
        end
        local use = Bags.HasUse(s.id)
        if use == nil then return nil, "unknown use" end
        if use then return nil, "it has a use" end
        why = "grey"
    else
        return nil, "not junk"
    end
    return {
        bag = s.bag, slot = s.slot, id = s.id, link = s.link, count = s.count, quality = s.quality,
        price = f.price, value = f.price * s.count, why = why,
    }
end

local function numSlots(bag)
    local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
    return ok and plainNumber(n) or 0
end

-- Every junk stack, cheapest first (value, then item ID, bag, slot).
function J.Candidates()
    local list, setItems = {}, Bags.SetItems()
    for bag = Bags.FIRST, Bags.LAST do
        for slot = 1, numSlots(bag) do
            local s = Bags.Slot(bag, slot)
            local e = s and J.Judge(s, setItems)
            if e then list[#list + 1] = e end
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        if a.id ~= b.id then return a.id < b.id end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return list
end

--------------------------------------------------------------------------------
-- The buyback page

local function buybackCount()
    local ok, n = pcall(GetNumBuybackItems)
    return ok and plainNumber(n) or nil
end

-- The page's entries: { { link, count } }, or nil when unreadable.
local function buybackPage()
    local n = buybackCount()
    if not n then return nil end
    local page = {}
    for i = 1, n do
        local okL, link = pcall(GetBuybackItemLink, i)
        local okI, _, _, _, qty = pcall(GetBuybackItemInfo, i)
        if not okL or not okI or API.IsSecret(link) or API.IsSecret(qty) then return nil end
        page[#page + 1] = { link = link, count = qty }
    end
    return page
end

-- Best effort: is every sale of this run still on the page? A match is not
-- proof (two identical links can't be told apart); a miss stops the run.
local function salesOnPage(sold)
    if #sold == 0 then return true end
    local page = buybackPage()
    if not page then return false end
    local free = {}
    for i, e in ipairs(page) do free[i] = e end
    for _, s in ipairs(sold) do
        local found
        for i, e in pairs(free) do
            if e.link == s.link and e.count == s.count then found = i; break end
        end
        if not found then return false end
        free[found] = nil
    end
    return true
end

--------------------------------------------------------------------------------
-- Repair

local function noAutoRepair()
    local ok, text = pcall(GetGuildInfoText)
    -- Can't tell (an error, a secret, nil or anything not a string): never charge the guild.
    if not ok or API.IsSecret(text) or type(text) ~= "string" then return true end
    return text:lower():find("[noautorepair]", 1, true) ~= nil
end

local function repairCost()
    local ok, cost, can = pcall(GetRepairAllCost)
    if not ok then return nil end
    cost = plainNumber(cost)
    if API.IsSecret(can) then return nil end
    return cost, can == true
end

local function guildCanPay()
    if setting("repairFunds") ~= "guild" then return false end
    local okG, inGuild = pcall(IsInGuild)
    if not (okG and inGuild == true) then return false end
    local okR, may = pcall(CanGuildBankRepair)
    if not (okR and may == true) then return false end
    return not noAutoRepair()
end

-- This visit's outcome (Core/Merchant.lua): "ready" or "skip".
local function outcome(s, result, unsafe)
    Merchant.Report(J.KEY, s, unsafe and "skip" or result)
end

local function finishRepair(r, text, result)
    state.repair = nil
    if text then say(text) end
    outcome(r.session, result or "ready", r.unsafe)
end

-- One RepairAllItems(guild) call, then wait for it to settle: the cost read
-- again differs from `cost` after UPDATE_INVENTORY_DURABILITY, within 2 s.
local function repairStep(r, guild, cost, after)
    r.step = { guild = guild, cost = cost, after = after }
    pcall(RepairAllItems, guild)
    local step = r.step
    Merchant.After(J.REPAIR_SECONDS, r.session, function()
        if state.repair == r and r.step == step then
            finishRepair(r, "The repair couldn't be confirmed: stopped (check your gear at the merchant).", "skip")
        end
    end)
end

local function onDurability()
    local r = state.repair
    local step = r and r.step
    if not step then return end
    local cost = repairCost()
    if cost == nil or cost == step.cost then return end   -- not settled yet
    r.step = nil
    step.after(cost)
end

-- What the repair did, as observed: the player's money change since the
-- repair began (its baseline is read after selling settled).
local function repaired(r, rest)
    local now = getMoney()
    local delta = now and r.before and (now - r.before) or nil
    local text
    if r.guild and delta == 0 then
        text = "Repaired with guild funds."
    else
        text = (r.guild and "Repaired, guild funds first" or "Repaired") .. ": your money " .. signed(delta) .. "."
    end
    if rest and rest > 0 then text = text .. " Still " .. money(rest) .. " to repair." end
    return text
end

-- unsafe: the selling run before it ended in a way that may still land a sale.
function J.Repair(s, unsafe)
    if not Merchant.Current(s) then return end
    if API.InCombat() then return outcome(s, "skip") end
    if not setting("autoRepair") then return outcome(s, "ready", unsafe) end
    local okM, can = pcall(CanMerchantRepair)
    if not (okM and can == true) then return outcome(s, "ready", unsafe) end
    local cost, canRepair = repairCost()
    if not cost or cost <= 0 or not canRepair then return outcome(s, "ready", unsafe) end
    local r = { session = s, before = getMoney(), guild = guildCanPay(), unsafe = unsafe }
    state.repair = r
    -- The player's money: only when it covers what's left.
    local function personal(left)
        local m = getMoney()
        if not m or m < left then
            return finishRepair(r, (r.guild and "Guild funds covered part; not enough money for the rest ("
                or "Not enough money to repair (") .. money(left) .. ").")
        end
        repairStep(r, false, left, function(rest) finishRepair(r, repaired(r, rest)) end)
    end
    if r.guild then
        repairStep(r, true, cost, function(left)
            if left > 0 then personal(left) else finishRepair(r, repaired(r)) end
        end)
    else
        personal(cost)
    end
end

--------------------------------------------------------------------------------
-- Selling

local REASONS = {
    refused = "This merchant won't take more: stopped.",
    cursor = "Something is on your cursor: stopped selling.",
    combat = "Combat: stopped selling.",
    unconfirmed = "A sale wasn't confirmed: stopped selling.",
    buyback = "Some of this visit's sales may no longer be on the buyback page: stopped selling.",
}

-- Wait for money to settle (no PLAYER_MONEY for SETTLE_QUIET, SETTLE_MAX at
-- most), then fn().
local function settle(s, fn)
    local done = false
    local function finish() if not done then done = true; fn() end end
    local function quiet()
        local gen = state.lastMoney
        Merchant.After(J.SETTLE_QUIET, s, function()
            if done then return end
            if state.lastMoney == gen then finish() else quiet() end
        end)
    end
    quiet()
    Merchant.After(J.SETTLE_MAX, s, finish)
end

local function endRun(r, reason)
    if r.ended then return end
    r.ended, r.reason, r.inFlight = true, reason, nil
    settle(r.session, function()
        if r.stacks > 0 then
            local now = getMoney()
            say("Sold " .. r.items .. (r.items == 1 and " item" or " items") .. " (" .. r.stacks
                .. (r.stacks == 1 and " stack" or " stacks") .. "): your money "
                .. signed(now and r.before and now - r.before or nil) .. ".")
        end
        if r.capped then
            say("Buyback-safe: sold " .. r.stacks .. " of " .. r.total .. " stacks; the rest next visit.")
        end
        if reason and REASONS[reason] then say(REASONS[reason]) end
        if state.run == r then state.run = nil end
        J.Repair(r.session, J.UNSAFE[reason or ""] == true)
    end)
end

local nextSale

local function confirm(r)
    local e = r.inFlight
    if not e then return end
    local s, why = Bags.Slot(e.bag, e.slot)
    -- Sold: the slot reads empty, or holds another stack (a GUID read and
    -- different). An unreadable GUID proves nothing: keep waiting (the
    -- timeout stops the run).
    local gone = s == nil and why == "empty"
    if s and not gone then
        local now = guidOf(e.bag, e.slot)
        gone = now ~= nil and now ~= e.guid
    end
    local n = buybackCount()
    local grew = n and e.buybackBefore and n > e.buybackBefore
    if not (gone or grew) then return end
    r.inFlight = nil
    r.sold[#r.sold + 1] = { link = e.link, count = e.count }
    r.stacks, r.items = r.stacks + 1, r.items + e.count
    r.i = r.i + 1
    C_Timer.After(0, function() nextSale(r) end)
end

nextSale = function(r)
    if r.ended or state.run ~= r then return end
    if API.InCombat() then return endRun(r, "combat") end
    local e = r.queue[r.i]
    if not e then
        -- Once more at the end: is every sale of this run still on the page?
        if setting("safe") and not salesOnPage(r.sold) then return endRun(r, "buyback") end
        return endRun(r, nil)
    end
    if not cursorEmpty() then return endRun(r, "cursor") end
    if setting("safe") and not salesOnPage(r.sold) then return endRun(r, "buyback") end
    -- The slot again, just before: the same stack, still junk.
    local s = Bags.Slot(e.bag, e.slot)
    local now = s and J.Judge(s, Bags.SetItems())
    if not (now and s.id == e.id and s.count == e.count and s.link == e.link and guidOf(e.bag, e.slot) == e.guid) then
        r.i = r.i + 1
        return nextSale(r)
    end
    e.buybackBefore = buybackCount()
    r.inFlight = e
    pcall(C_Container.UseContainerItem, e.bag, e.slot)
    Merchant.After(J.CONFIRM_SECONDS, r.session, function()
        if r.inFlight == e then endRun(r, "unconfirmed") end
    end)
    confirm(r)   -- a client that answers at once
end

function J.Sell(s)
    local queue = {}
    for _, e in ipairs(J.Candidates()) do
        e.guid = guidOf(e.bag, e.slot)
        if e.guid then queue[#queue + 1] = e end
    end
    local r = { session = s, queue = queue, i = 1, sold = {}, stacks = 0, items = 0, before = getMoney(),
                total = #queue }
    if setting("safe") then
        local used = buybackCount()
        local room = used and math.max(0, J.BUYBACK_SLOTS - used) or 0
        if #queue > room then
            for i = #queue, room + 1, -1 do queue[i] = nil end
            r.capped = true
        end
    end
    state.run = r
    nextSale(r)
    return r
end

local function onOpen(s)
    if IsShiftKeyDown() then return end   -- Shift: this visit, nothing
    Merchant.After(J.OPEN_DELAY, s, function()
        if API.InCombat() or not J.enabled then return outcome(s, "skip") end
        if setting("autoSell") then J.Sell(s) else J.Repair(s) end
    end)
end

local function onError(errorType, message)
    local r = state.run
    if not (r and r.inFlight) then return end
    local name
    local ok, n = pcall(GetGameMessageInfo, errorType)
    if ok and not API.IsSecret(n) then name = n end
    local refused = name and J.REFUSALS[name]
    if not refused and not API.IsSecret(message) and type(message) == "string" then
        for key in pairs(J.REFUSALS) do
            if rawget(_G, key) == message then refused = true end
        end
    end
    if refused then endRun(r, "refused") end
end

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if event == "BAG_UPDATE_DELAYED" then
        if state.run then confirm(state.run) end
    elseif event == "PLAYER_MONEY" then
        state.lastMoney = state.lastMoney + 1
    elseif event == "UI_ERROR_MESSAGE" then
        onError(...)
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        onDurability()
    end
end)

--------------------------------------------------------------------------------
-- The lists and commands

local function itemIDOf(arg)
    if type(arg) ~= "string" then return nil end
    return tonumber(arg:match("item:(%d+)")) or tonumber(arg:match("^%s*(%d+)%s*$"))
end
J.ItemIDOf = itemIDOf

local function nameOf(id)
    local ok, n = pcall(C_Item.GetItemNameByID, id)
    if ok and not API.IsSecret(n) and type(n) == "string" then return n end
    pcall(C_Item.RequestLoadItemDataByID, id)
    return "item " .. id
end

-- Put an item on one list (taking it off the other). false, "full" at the cap.
function J.List(which, id)
    local add, other = which == "sell" and J.SELL or J.KEEP, which == "sell" and J.KEEP or J.SELL
    local ok, why = SS().SetAdd(add, id)
    if not ok then return false, why end
    if SS().SetHas(other, id) then SS().SetRemove(other, id) end
    return true
end

function J.Forget(id)
    if SS().SetHas(J.SELL, id) then SS().SetRemove(J.SELL, id) end
    if SS().SetHas(J.KEEP, id) then SS().SetRemove(J.KEEP, id) end
end

local function listCommand(which)
    return function(arg)
        local id = itemIDOf(arg)
        if not id then return say("Shift-click an item into chat after /gpearls " .. which .. ".") end
        local ok, why = J.List(which, id)
        if not ok then
            return say(why == "full" and "The lists are full: remove some first (the gear on Glass Pearls' Loot & Bags page)."
                or "Couldn't list that item.")
        end
        say(nameOf(id) .. (which == "sell" and " will be sold at merchants." or " will never be sold."))
    end
end

local function sellCommand(arg)
    if arg and arg ~= "" then return listCommand("sell")(arg) end
    local list = J.Candidates()
    if #list == 0 then return say("Nothing in your bags would be sold.") end
    local total = 0
    for _, e in ipairs(list) do total = total + e.value end
    say(#list .. (#list == 1 and " stack" or " stacks") .. " would be sold, worth " .. money(total) .. ":")
    for i = 1, math.min(#list, 10) do say("  " .. list[i].link .. (list[i].count > 1 and (" x" .. list[i].count) or "")) end
    if #list > 10 then say("  and " .. (#list - 10) .. " more") end
end

local function forgetCommand(arg)
    local id = itemIDOf(arg)
    if not id then return say("Shift-click an item into chat after /gpearls forget.") end
    J.Forget(id)
    say(nameOf(id) .. ": off both lists (grey items sell again by the grey rule).")
end

--------------------------------------------------------------------------------
-- The pearl

local function enable()
    J.enabled = true
    API.RegisterEvents(events, { "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "UI_ERROR_MESSAGE",
        "UPDATE_INVENTORY_DURABILITY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    Merchant.On(J.KEY, function(event, s)
        if event == "MERCHANT_SHOW" then
            onOpen(s)
        elseif event == "MERCHANT_CLOSED" then
            if state.run then endRun(state.run, "closed") end
            state.repair = nil
        end
    end)
end

-- The junk spotlight (#41) shows what this sells: tell it when that changes.
local function spotlight()
    if GP.JunkSpot then GP.JunkSpot.Refresh() end
end

local function disable()
    J.enabled = false
    events:UnregisterAllEvents()
    Merchant.On(J.KEY, nil)
    if state.run then state.run.ended = true end
    state.run, state.repair = nil, nil
    outcome(Merchant.Session(), "skip")   -- switched off mid-visit: whatever was in flight may land
    spotlight()
end

GP.SettingsSync.RegisterSet(J.SELL)
GP.SettingsSync.RegisterSet(J.KEEP)

GP.Pearls.Register({
    key = J.KEY,
    name = "Sell junk & repair",
    desc = "At a merchant, sells your grey items and the ones you list, then repairs, guild funds first.",
    help = "When a merchant opens, Glass Pearls sells your junk, cheapest first: grey items with a price, and "
        .. "anything on your sell list (/gpearls sell, shift-click the item). Never your keep list (/gpearls keep), "
        .. "quest items, tools, equipment-set items or refundable purchases; not unbound grey gear or greys with a "
        .. "use unless listed. Then it repairs: guild funds first when your guild allows it (that can take your money "
        .. "for what the guild doesn't cover), then your money. Hold Shift when you open the merchant to skip both.",
    default = true,
    category = "Loot & Bags",
    section = "Merchant",
    defaults = { autoSell = true, sellGrey = true, safe = false, autoRepair = true, repairFunds = "guild" },
    choices = { repairFunds = { "guild", "mine" } },
    Enable = function() enable(); spotlight() end,
    Disable = disable,
    onSettingChanged = spotlight,
    configure = function(panel, refreshers) GP.JunkFrame.Configure(panel, refreshers) end,
    commands = {
        sell = { help = "[item] - list what would be sold at a merchant, or put an item on the sell list", run = sellCommand },
        keep = { help = "<item> - never sell this item", run = listCommand("keep") },
        forget = { help = "<item> - take an item off the sell and keep lists", run = forgetCommand },
    },
})

J._test = { events = events, salesOnPage = salesOnPage, noAutoRepair = noAutoRepair }
