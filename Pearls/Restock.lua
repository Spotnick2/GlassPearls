-- Pearls/Restock.lua: restock at a merchant (#14). Food, water (mana users),
-- ammunition (hunters) and class reagents, topped up to a target with the best
-- the merchant sells that the character can use. Its window and panel are
-- Pearls/RestockFrame.lua; what may be bought is Data/Restock.lua (generated);
-- the session is Core/Merchant.lua; bag facts are Core/Bags.lua.
--
-- When: at MERCHANT_SHOW, after the junk seller (#15) reports this visit
-- "ready" (Merchant.Await, 10 s), or 0.3 s after the show when it isn't on.
-- "skip", or no report in time, means no restock this visit: never buy while
-- a sale or repair may still land. Shift held at the show skips the visit.
--
-- What (R.Plan, over the merchant, the bags and the settings):
--   an offer is a merchant item in our data with a plain price below
--   Blizzard's high-price line, no extended cost or currency, purchasable,
--   usable, in stock; never bind-on-pickup food or water.
--   Food and water: the usable offer (required level) that restores the most;
--   owned = what the bags hold of that kind restoring at least as much
--   (conjured included). Ammo: the ranged weapon's kind (bow, crossbow:
--   arrows; gun: bullets), the highest level usable; owned = that kind at
--   least that level. Reagents: those of this class whose spell, at its
--   highest known rank, consumes them; never while Buffy restocks them.
--   Wanted = target - owned, in whole packs rounded up (a target is a floor).
--   A count is complete or nothing: one unreadable slot skips the line.
--
-- Buying (R.Run): one purchase in flight; each step reads everything again
-- (the offer at its index, the settings, the recount, room, money). A chunk is whole packs,
-- at most the merchant's max stack per call, within both limits for the visit
-- (budget % of the money at the start and maxSpend gold; spent = the larger of
-- the confirmed prices and the money observed gone). Confirmed when the count
-- reaches before + chunk (BAG_UPDATE_DELAYED) within 2 s; anything else (a
-- smaller increase, a refusal while ours is in flight, close, combat) stops
-- the run. Unmeasured until 2026-11-04: BuyMerchantItem's units, the events,
-- the refusal names.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Bags = GP.Bags
local Merchant = GP.Merchant
local R = {}
GP.Restock = R

R.KEY = "restock"
R.OPEN_DELAY = 0.3
R.JUNK_WAIT = 10
R.CONFIRM_SECONDS = 2
R.HIGH_PRICE = 1500000            -- MERCHANT_HIGH_PRICE_COST (MerchantFrame.lua), when the client lacks it
R.RANGED_SLOT = 18
R.WEAPON = 2                      -- item class
R.AMMO_FOR = { [2] = 2, [18] = 2, [3] = 3 }   -- bow, crossbow: arrows; gun: bullets
R.MANA = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true, SHAMAN = true, WARLOCK = true }
R.ORDER = { "reagent", "drink", "food", "ammo" }
-- Buffy's reagents (Classes/{Druid,Mage,Priest}.lua), when Buffy can't be read.
R.BUFFY = { [17020] = true, [17021] = true, [17026] = true, [17028] = true, [17029] = true }
-- UI error names (GetGameMessageInfo) that refuse a purchase: guesses until day one.
R.REFUSALS = { ERR_NOT_ENOUGH_MONEY = true, ERR_INV_FULL = true, ERR_ITEM_MAX_COUNT = true,
               ERR_VENDOR_SOLD_OUT = true }

local events = CreateFrame("Frame")
local state = {
    run = nil,      -- the buying run of this visit
    last = nil,     -- the last visit's lines, for /gpearls restock
}
R.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(R.KEY, name) end
local function data() return GP.RestockData end
local function Frame() return GP.RestockFrame end

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

local function call(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

local function money()
    return plain(call(GetMoney), "number")
end

local function coins(v) return C_CurrencyInfo.GetCoinTextureString(v) end

function R.Class()
    local _, file = call(UnitClass, "player")
    return plain(file, "string")
end

function R.Level()
    return plain(call(UnitLevel, "player"), "number")
end

-- A plain "yes, this character knows it".
local function known(id)
    return plain(call(C_SpellBook.IsSpellKnown, id), "boolean") == true
        or plain(call(IsPlayerSpell, id), "boolean") == true
end

--------------------------------------------------------------------------------
-- Counting: complete or nothing

local function numSlots(bag)
    local n = plain(call(C_Container.GetContainerNumSlots, bag), "number")
    return n
end

-- How many of `ids` ({ [itemID] = true }) bags 0-4 hold, locked stacks
-- included; nil when any slot can't be read.
function R.Count(ids)
    local n = 0
    for bag = Bags.FIRST, Bags.LAST do
        local slots = numSlots(bag)
        if not slots then return nil end
        for slot = 1, slots do
            local s, why = Bags.Slot(bag, slot)
            if not s and why ~= "empty" then return nil end
            if s and ids[s.id] then n = n + s.count end
        end
    end
    return n
end

--------------------------------------------------------------------------------
-- The merchant's offers

local function highPrice()
    return plain(rawget(_G, "MERCHANT_HIGH_PRICE_COST"), "number") or R.HIGH_PRICE
end

-- One merchant item as an offer, or nil. Every field plain, or nothing.
function R.Offer(index)
    local id = plain(call(GetMerchantItemID, index), "number")
    if not id then return nil end
    local info = call(C_MerchantFrame.GetItemInfo, index)
    if API.IsSecret(info) or type(info) ~= "table" then return nil end
    local price, pack, stock = plain(info.price, "number"), plain(info.stackCount, "number"),
        plain(info.numAvailable, "number")
    local maxStack = plain(call(GetMerchantItemMaxStack, index), "number")
    if not (price and pack and stock and maxStack) then return nil end
    if API.IsSecret(info.currencyID) or info.currencyID ~= nil then return nil end
    if plain(info.hasExtendedCost, "boolean") ~= false then return nil end
    if plain(info.isPurchasable, "boolean") ~= true or plain(info.isUsable, "boolean") ~= true then return nil end
    if price <= 0 or price >= highPrice() or pack < 1 or maxStack < 1 then return nil end
    if stock ~= -1 and stock < pack then return nil end
    return { index = index, id = id, price = price, pack = pack, stock = stock, maxStack = maxStack }
end

function R.Offers()
    local out = {}
    local n = plain(call(GetMerchantNumItems), "number") or 0
    for i = 1, n do
        local o = R.Offer(i)
        if o then out[#out + 1] = o end
    end
    return out
end

-- The best of `offers` by score(o) (nil: not a candidate), ties cheaper per item.
local function best(offers, score)
    local top, topScore
    for _, o in ipairs(offers) do
        local sc = score(o)
        if sc and (not top or sc > topScore or (sc == topScore and o.price / o.pack < top.price / top.pack)) then
            top, topScore = o, sc
        end
    end
    return top, topScore
end

--------------------------------------------------------------------------------
-- What each kind wants

-- The ammo kind of the equipped ranged weapon (2 arrows, 3 bullets), or nil.
function R.AmmoKind()
    local id = plain(call(GetInventoryItemID, "player", R.RANGED_SLOT), "number")
    if not id then return nil end
    local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, id)
    if not ok or plain(classID, "number") ~= R.WEAPON then return nil end
    return R.AMMO_FOR[plain(subclassID, "number") or -1]
end

-- Is Buffy restocking this reagent now? Unreadable: its fixed list.
function R.BuffyHas(id)
    local okL, loaded = pcall(C_AddOns.IsAddOnLoaded, "Buffy")
    if not okL or loaded ~= true then return false end
    local ok, has = pcall(function()
        local B = rawget(_G, "Buffy")
        local r = B.class.restock
        if B.Get(r.enabledKey) ~= true then return false end
        for _, item in ipairs(r.items()) do
            if item == id then return true end
        end
        return false
    end)
    if ok and type(has) == "boolean" then return has end
    return R.BUFFY[id] == true
end

-- Does a spell at the highest rank this character knows consume it?
local function highestKnown(sid)
    if not known(sid) then return false end
    local higher = data().higher[sid]   -- a poison recipe (not in SpellRankData)
    if higher then
        for _, h in ipairs(higher) do
            if known(h) then return false end
        end
        return true
    end
    local ranks = GP.SpellRankData
    local r = ranks and ranks.ranks[sid]
    if not r then return true end
    local group = ranks.groups[r[1]]
    for j = r[2] + 1, #group do
        if known(group[j]) then return false end
    end
    return true
end

-- A kind's target now, or nil while it is switched off (a target of 0 wants nothing).
local SWITCH = { reagent = "reagents", drink = "water", food = "food", ammo = "ammo" }
local TARGET = { drink = "waterTarget", food = "foodTarget", ammo = "ammoTarget" }
function R.Target(kind, id)
    if not setting(SWITCH[kind]) then return nil end
    return setting(TARGET[kind] or ("r" .. id)) or 0
end

function R.ReagentNeeded(spells)
    for _, sid in ipairs(spells) do
        if highestKnown(sid) then return true end
    end
    return false
end

-- One line, or nil and why not.
local function line(kind, o, target, ids, label)
    local owned = R.Count(ids)
    if not owned then return nil, label .. ": your bags can't be read" end
    local wanted = target - owned
    if wanted <= 0 then return nil end
    return { kind = kind, id = o.id, index = o.index, price = o.price, pack = o.pack,
             packs = math.ceil(wanted / o.pack), owned = owned, target = target, ids = ids }
end

-- The lines for this merchant, in R.ORDER, and notes on what was skipped.
function R.Plan()
    local d, lines, notes = data(), {}, {}
    local class, level = R.Class(), R.Level()
    if not (d and class and level) then return lines, { "your class or level can't be read" } end
    local offers = R.Offers()
    local function add(l, why)
        if l then lines[#lines + 1] = l elseif why then notes[#notes + 1] = why end
    end
    -- Reagents.
    local mine = d.reagents[class]
    if mine then
        for item, spells in pairs(mine) do
            local target = R.Target("reagent", item)
            if target and R.ReagentNeeded(spells) then
                local o = best(offers, function(x) return x.id == item and 1 or nil end)
                if o then
                    if R.BuffyHas(item) then
                        notes[#notes + 1] = "a reagent Buffy restocks"
                    else
                        add(line("reagent", o, target, { [item] = true }, "reagents"))
                    end
                end
            end
        end
        table.sort(lines, function(a, b) return a.id < b.id end)
    end
    -- Water and food.
    for _, kind in ipairs({ "drink", "food" }) do
        local target = R.Target(kind)
        if target and (kind == "food" or R.MANA[class]) then
            local tbl = d[kind]
            local o, value = best(offers, function(x)
                local e = tbl[x.id]
                return e and not e.bop and e.level <= level and e.value or nil
            end)
            if o then
                local ids = {}
                for id, e in pairs(tbl) do if e.value >= value then ids[id] = true end end
                add(line(kind, o, target, ids, kind == "drink" and "water" or "food"))
            end
        end
    end
    -- Ammo.
    local ammoTarget = R.Target("ammo")
    if ammoTarget and class == "HUNTER" then
        local kind = R.AmmoKind()
        if kind then
            local o, lvl = best(offers, function(x)
                local e = d.ammo[x.id]
                return e and e.kind == kind and e.level <= level and e.level or nil
            end)
            if o then
                local ids = {}
                for id, e in pairs(d.ammo) do if e.kind == kind and e.level >= lvl then ids[id] = true end end
                add(line("ammo", o, ammoTarget, ids, "ammunition"))
            end
        end
    end
    return lines, notes
end

-- The first pass cost of the lines.
function R.Cost(lines)
    local c = 0
    for _, l in ipairs(lines) do c = c + l.packs * l.price end
    return c
end

-- The client's name for an item; uncached, it's asked for and "item <id>" meanwhile.
function R.Name(id)
    local name = plain(call(C_Item.GetItemNameByID, id), "string")
    if name then return name end
    pcall(C_Item.RequestLoadItemDataByID, id)
    return "item " .. id
end

--------------------------------------------------------------------------------
-- Buying

local REASONS = {
    combat = "Combat: stopped buying.",
    cursor = "Something is on your cursor: stopped buying.",
    unconfirmed = "A purchase wasn't confirmed: stopped buying.",
    refused = "The merchant refused: stopped buying.",
}

local function finish(r, reason)
    if r.ended then return end
    r.ended, r.inFlight = true, nil
    if state.run == r then state.run = nil end
    local parts = {}
    for _, b in ipairs(r.bought) do parts[#parts + 1] = b.count .. " " .. R.Name(b.id) end
    if #parts > 0 then
        local now = money()
        local delta = now and r.start and (r.start - now) or r.spent
        say("Bought " .. table.concat(parts, ", ") .. ": your money -" .. coins(math.max(delta, 0)) .. ".")
    end
    if reason and REASONS[reason] then say(REASONS[reason]) end
    for _, n in ipairs(r.notes) do say(n) end
end

-- What both limits still allow, in copper.
local function allowance(r)
    local now = money()
    if not now then return nil end
    local spent = math.max(r.spent, r.start - now)
    local cap = math.min(math.floor(r.start * setting("budget") / 100), setting("maxSpend") * 10000)
    return math.max(0, math.min(cap - spent, now))
end

local step

local function confirm(r)
    local e = r.inFlight
    if not e then return end
    local now = R.Count({ [e.id] = true })
    if not now or now < e.before + e.count then return end
    r.inFlight = nil
    r.spent = r.spent + e.cost
    e.line.done = e.line.done + e.count / e.line.pack
    local b = r.boughtBy[e.id]
    if not b then
        b = { id = e.id, count = 0 }
        r.boughtBy[e.id] = b
        r.bought[#r.bought + 1] = b
    end
    b.count = b.count + e.count
    C_Timer.After(0, function() step(r) end)
end

local function note(r, text)
    for _, n in ipairs(r.notes) do if n == text then return end end
    r.notes[#r.notes + 1] = text
end

step = function(r)
    if r.ended or state.run ~= r then return end   -- closed or switched off: finished there
    if API.InCombat() then return finish(r, "combat") end
    if call(GetCursorInfo) ~= nil then return finish(r, "cursor") end
    local l = r.lines[r.i]
    if not l then return finish(r, nil) end
    local function nextLine(why)
        if why then note(r, why) end
        r.i = r.i + 1
        return step(r)
    end
    -- The offer again, at its index.
    local o = R.Offer(l.index)
    if not (o and o.id == l.id and o.price == l.price and o.pack == l.pack) then
        return nextLine(R.Name(l.id) .. " changed at the merchant: skipped.")
    end
    -- The settings again (changed by hand or by sync since the plan): a kind
    -- switched off ends its line, a lower target counts; the plan stays the most.
    local target = R.Target(l.kind, l.id)
    if not target then return nextLine() end
    -- The recount.
    local owned = R.Count(l.ids)
    if not owned then return nextLine("Your bags can't be read: " .. R.Name(l.id) .. " skipped.") end
    local packs = math.min(math.ceil(math.max(target - owned, 0) / l.pack), l.packs - l.done)
    if packs <= 0 then return nextLine() end
    packs = math.min(packs, math.max(1, math.floor(o.maxStack / o.pack)))
    if o.stock ~= -1 then packs = math.min(packs, math.floor(o.stock / o.pack)) end
    local left = allowance(r)
    if not left then return nextLine("Your money can't be read: " .. R.Name(l.id) .. " skipped.") end
    packs = math.min(packs, math.floor(left / o.price))
    if packs <= 0 then return nextLine("The spending limit for this visit is reached.") end
    local snap = Bags.Snapshot()
    while packs > 0 do
        local fits = Bags.Fits(l.id, packs * o.pack, snap)
        if fits == nil then return nextLine("Can't tell whether " .. R.Name(l.id) .. " fits: skipped.") end
        if fits then break end
        packs = packs - 1
    end
    if packs <= 0 then return nextLine("No room for " .. R.Name(l.id) .. ".") end
    local before = R.Count({ [l.id] = true })
    if not before then return nextLine("Your bags can't be read: " .. R.Name(l.id) .. " skipped.") end
    local e = { id = l.id, count = packs * o.pack, cost = packs * o.price, before = before, line = l }
    r.inFlight = e
    pcall(BuyMerchantItem, o.index, e.count)
    Merchant.After(R.CONFIRM_SECONDS, r.session, function()
        if r.inFlight == e then finish(r, "unconfirmed") end
    end)
    confirm(r)   -- a client that answers at once
end

-- Buy `lines` (R.Plan's, or the ask window's) during visit `s`.
function R.Run(s, lines)
    if state.run or not Merchant.Current(s) then return nil end
    local start = money()
    if not start then return nil end
    for _, l in ipairs(lines) do l.done = 0 end
    local r = { session = s, lines = lines, i = 1, start = start, spent = 0, bought = {}, boughtBy = {}, notes = {} }
    state.run = r
    step(r)
    return r
end

--------------------------------------------------------------------------------
-- The visit

local function begin(s)
    if not (R.enabled and Merchant.Current(s)) or API.InCombat() then return end
    local lines, notes = R.Plan()
    state.last = { lines = lines, notes = notes }
    if #lines == 0 then return end
    if setting("mode") == "ask" then
        Frame().Ask(s, lines)
    else
        R.Run(s, lines)
    end
end

local function onShow(s)
    if IsShiftKeyDown() then return end   -- Shift: this visit, nothing
    if GP.Pearls.IsLive("junk") then
        Merchant.Await("junk", s, R.JUNK_WAIT, function(outcome)
            if outcome == "ready" then begin(s) end
        end)
    else
        Merchant.After(R.OPEN_DELAY, s, function() begin(s) end)
    end
end

local function onError(errorType, message)
    local r = state.run
    if not (r and r.inFlight) then return end
    local ok, name = pcall(GetGameMessageInfo, errorType)
    if ok and type(name) == "string" and not API.IsSecret(name) then
        if R.REFUSALS[name] then finish(r, "refused") end
        return
    end
    if API.IsSecret(message) or type(message) ~= "string" then return end
    for refusal in pairs(R.REFUSALS) do
        local text = rawget(_G, refusal)
        if type(text) == "string" and message == text then return finish(r, "refused") end
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if event == "BAG_UPDATE_DELAYED" then
        if state.run then confirm(state.run) end
    elseif event == "UI_ERROR_MESSAGE" then
        onError(...)
    end
end)

--------------------------------------------------------------------------------
-- The command

local KINDS = { reagent = "reagent", drink = "water", food = "food", ammo = "ammunition" }

function R.Report()
    if not Merchant.IsOpen() then
        return say("Restock: open a merchant to see what it would buy there.")
    end
    local lines, notes = R.Plan()
    if #lines == 0 then say("Restock: nothing to buy here.") end
    for _, l in ipairs(lines) do
        say(("Restock: %d %s (%s; you have %d of %d) for %s."):format(l.packs * l.pack, R.Name(l.id),
            KINDS[l.kind], l.owned, l.target, coins(l.packs * l.price)))
    end
    for _, n in ipairs(notes) do say("Restock: not bought: " .. n .. ".") end
end

--------------------------------------------------------------------------------
-- The pearl

local function enable()
    R.enabled = true
    API.RegisterEvents(events, { "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED" })
    Merchant.On(R.KEY, function(event, s)
        if event == "MERCHANT_SHOW" then
            onShow(s)
        elseif event == "MERCHANT_CLOSED" then
            if state.run then finish(state.run, "closed") end
            Frame().Hide()
        end
    end)
end

local function disable()
    R.enabled = false
    events:UnregisterAllEvents()
    Merchant.On(R.KEY, nil)
    if state.run then finish(state.run, "off") end
    Frame().Hide()
end

-- Every allowlisted reagent's target, a synced setting each.
local defaults = { mode = "auto", food = true, water = true, ammo = true, reagents = true,
                   foodTarget = 20, waterTarget = 20, ammoTarget = 1000, budget = 50, maxSpend = 5 }
local ranges = { foodTarget = { 0, 200 }, waterTarget = { 0, 200 }, ammoTarget = { 0, 5000 },
                 budget = { 10, 100 }, maxSpend = { 1, 100 } }
for item, target in pairs(GP.RestockData and GP.RestockData.targets or {}) do
    defaults["r" .. item] = target
    ranges["r" .. item] = { 0, 200 }
end

GP.Pearls.Register({
    key = R.KEY,
    name = "Restock",
    desc = "At a merchant, tops up your food, water, ammunition and class reagents with the best you can use.",
    help = "When a merchant opens (after selling junk and repairing), Glass Pearls buys what you're short of: "
        .. "the best food and water your level can use (water only if you use mana), arrows or bullets for a "
        .. "hunter's ranged weapon, and the reagents of the class spells you know. Only what's at least as good as "
        .. "the merchant's best counts toward a target, so you move up as you level. Each visit spends at most the "
        .. "share of your money and the gold you set. Hold Shift when you open the merchant to skip it; choose "
        .. "\"Ask first\" to confirm each time. /gpearls restock shows what it would buy here.",
    default = true,
    category = "Loot & Bags",
    section = "Merchant",
    defaults = defaults,
    choices = { mode = { "auto", "ask" } },
    ranges = ranges,
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) Frame().Configure(panel, refreshers) end,
    commands = {
        restock = { help = "- what it would buy at this merchant, and why not", run = function() R.Report() end },
    },
})

R._test = { events = events, step = function(r) return step(r) end, allowance = allowance }
