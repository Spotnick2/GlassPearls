-- Pearls/FastLoot.lua: faster loot (#36). With auto loot on, takes every
-- loot slot it safely can the moment the loot window opens, instead of at the
-- client's own pace. Its coin text and panel are Pearls/FastLootFrame.lua.
--
-- One pass per loot session (LOOT_READY / LOOT_OPENED to LOOT_CLOSED), only
-- when the event says auto loot is on (its payload; the client's CVar and
-- the AUTOLOOTTOGGLE modifier only when the payload is nil), consumed before
-- its first LootSlot (a LOOT_READY with no slots yet leaves it to
-- LOOT_OPENED), never repeated, never retried, and never while the bags-full
-- helper waits to loot a row itself. Slot 1 up, each read in one pcall. A
-- slot is left to the client when it is locked, cleared, of an unknown type,
-- an item a group's loot method may send to a roll or a list (group, need
-- before greed, master: at or above the threshold), unreadable, or an item
-- that may not fit (Bags.Take on a strict snapshot, which reserves the room
-- it finds). Money and currency are taken. Bind-on-pickup keeps Blizzard's
-- prompt: ConfirmLootSlot is never called; LootFrame and the errors are never
-- touched.
--
-- The client's own auto loot is expected to keep running beside it, so a
-- skipped slot should still be looted at the usual pace: that is a day-one
-- check, not a promise.
--
-- The session events stay registered after the first Enable, also while off
-- (they then only follow sessions): a window closed while off must not leave
-- the next corpse with a consumed pass.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local L = {}
GP.FastLoot = L

L.KEY = "fastloot"
L.COIN_SECONDS = 2

local state = {
    session = nil,       -- { token, consumed }
    token = 0,
    coin = nil,          -- a coins-only pass's money, waiting to show
    coinGen = 0,
    last = nil,          -- the last pass, for the report
    why = "no loot window yet",
}
L.state = state

local events = CreateFrame("Frame")     -- the session's boundaries, kept
local money = CreateFrame("Frame")      -- the coin text's, while on
local installed = false

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(L.KEY, name) end
local function Frame() return GP.FastLootFrame end

local function plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

-- One client call's first value, plain; nil when it threw or is secret.
local function ask(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return plain(v)
end

local function wholeNumber(v)
    return type(v) == "number" and v >= 0 and v % 1 == 0
end

--------------------------------------------------------------------------------
-- Is auto loot on for this event?

function L.AutoLoot(payload)
    if API.IsSecret(payload) then return false end
    if type(payload) == "boolean" then return payload end
    if payload ~= nil then return false end
    -- No payload: the client's rule, as an approximation.
    local cvar, mod = ask(GetCVarBool, "autoLootDefault"), ask(IsModifiedClick, "AUTOLOOTTOGGLE")
    if type(cvar) ~= "boolean" or type(mod) ~= "boolean" then return false end
    return cvar ~= mod
end

--------------------------------------------------------------------------------
-- One slot

-- May the group's loot method send this item to a roll or a list?
local function lootMethodHolds(quality)
    local grouped = ask(IsInGroup)
    if grouped == false then return false end
    if grouped ~= true then return true end
    local M = Enum and Enum.LootMethod
    local method = M and ask(C_PartyInfo.GetLootMethod)
    if type(method) ~= "number" then return true end
    if method == M.Freeforall or method == M.Roundrobin or method == M.Personal then return false end
    if method == M.Group or method == M.Needbeforegreed or method == M.Masterlooter then
        local threshold = ask(GetLootThreshold)
        if type(threshold) ~= "number" or type(quality) ~= "number" then return true end
        return quality >= threshold
    end
    return true
end

-- What to do with slot i: "money", "currency", "item" (take it), or why not.
function L.Verdict(i, snap)
    if ask(LootSlotHasItem, i) ~= true then return "cleared" end
    local T = Enum.LootSlotType
    local kind = ask(GetLootSlotType, i)
    local _, _, qty, _, quality, locked = GetLootSlotInfo(i)
    if API.IsSecret(locked) or type(locked) ~= "boolean" then return "unreadable" end
    if locked then return "locked" end
    if kind == T.Money then return "money" end
    if kind == T.Currency then return "currency" end
    if kind ~= T.Item then return "type" end
    if lootMethodHolds(plain(quality)) then return "loot method" end
    local link = ask(GetLootSlotLink, i)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    qty = plain(qty)
    if not id or not (wholeNumber(qty) and qty > 0) then return "unreadable" end
    if GP.Bags.Take(id, qty, snap) ~= true then return "no room" end
    return "item"
end

--------------------------------------------------------------------------------
-- The coin text: a coins-only pass's money, attributed and observed

local function cursor()
    local ok, x, y = pcall(GetCursorPosition)
    local scale = UIParent:GetEffectiveScale()
    if not ok or type(plain(x)) ~= "number" or type(plain(y)) ~= "number" then return nil end
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return x / scale, y / scale
end

local function coinCancel()
    state.coinGen = state.coinGen + 1
    state.coin = nil
end

-- A coin text belongs to the current session: a new one cancels it.
local function coinStart()
    coinCancel()
    local base = ask(GetMoney)
    if type(base) ~= "number" then return end
    local gen = state.coinGen
    local x, y = cursor()
    state.coin = { gen = gen, last = base, sum = 0, message = false, closed = false, x = x, y = y }
    C_Timer.After(L.COIN_SECONDS, function()
        if state.coin and state.coin.gen == gen then state.coin = nil end    -- expired, silently
    end)
end

local function coinCheck()
    local c = state.coin
    if not (c and not c.provisional and c.closed and c.message and c.sum > 0) then return end
    state.coin = nil
    Frame().Show(c.sum, c.x, c.y)
end

--------------------------------------------------------------------------------
-- The pass

local function pass(kind, payload)
    local s = state.session
    if not (L.enabled and s) or s.consumed then return end
    if not L.AutoLoot(payload) then state.why = "auto loot off"; return end
    local BF = GP.BagsFull
    if BF and BF.state and BF.state.pending then state.why = "the bags-full helper's loot is pending"; return end
    local n = ask(GetNumLootItems)
    if not wholeNumber(n) then state.why = "the slot count can't be read"; return end
    if n == 0 and kind == "ready" then return end      -- the slots come at LOOT_OPENED
    s.consumed = true
    -- The coin record starts before the first LootSlot: the game may credit
    -- the money (and close the window) before the call returns. It stays
    -- provisional until the pass knows the window held only money.
    if setting("coins") then
        coinStart()
        if state.coin then state.coin.provisional = true end
    end
    local snap = GP.Bags.Snapshot(true)
    local result = { calls = 0, skipped = {}, slots = n }
    local onlyMoney, read = n > 0, 0
    for i = 1, n do
        local ok, verdict = pcall(L.Verdict, i, snap)
        if not ok then verdict = "unreadable" end
        read = read + 1
        if verdict ~= "money" then onlyMoney = false end
        if verdict == "money" or verdict == "currency" or verdict == "item" then
            local okLoot, err = pcall(LootSlot, i)
            if okLoot then result.calls = result.calls + 1 else API.Fail("pearl fastloot LootSlot", err) end
        else
            result.skipped[verdict] = (result.skipped[verdict] or 0) + 1
        end
        if state.session ~= s then break end              -- the window closed under us
    end
    state.last = result
    state.why = "a pass ran"
    -- Not coins only: the provisional record never shows, and expires.
    local c = state.coin
    if c and onlyMoney and read == n then
        c.provisional = false
        coinCheck()                                       -- everything may have come during the pass
    end
end

events:SetScript("OnEvent", function(_, event, a1)
    if event == "LOOT_CLOSED" then
        state.session = nil
        local c = state.coin
        if c then
            c.closed = true
            coinCheck()
        end
        return
    end
    if not state.session then
        state.token = state.token + 1
        state.session = { token = state.token, consumed = false }
        if state.coin then coinCancel() end               -- a new corpse: the old coin text is gone
    end
    pass(event == "LOOT_READY" and "ready" or "opened", a1)
end)

money:SetScript("OnEvent", function(_, event)
    local c = state.coin
    if not c then return end
    if event == "PLAYER_MONEY" then
        local now = ask(GetMoney)
        if type(now) ~= "number" then return end
        if now > c.last then c.sum = c.sum + (now - c.last) end
        c.last = now
    else
        c.message = true                                  -- CHAT_MSG_MONEY: its text is never read
    end
    coinCheck()
end)

--------------------------------------------------------------------------------
-- The report

local REASONS = { "locked", "loot method", "no room", "unreadable", "type", "cleared" }

function L.Report()
    say(("Faster loot: %s; coin text %s."):format(L.enabled and "on" or "off", setting("coins") and "on" or "off"))
    local r = state.last
    if not r then
        say("  No pass yet (" .. state.why .. ").")
        return
    end
    local parts = {}
    for _, reason in ipairs(REASONS) do
        if r.skipped[reason] then parts[#parts + 1] = reason .. " " .. r.skipped[reason] end
    end
    say(("  Last pass: %d slot(s), %d loot call(s) made; left to the game: %s."):format(r.slots, r.calls,
        #parts > 0 and table.concat(parts, ", ") or "none"))
    if state.why ~= "a pass ran" then say("  Since then: " .. state.why .. ".") end
end

--------------------------------------------------------------------------------
-- The pearl

local function enable()
    L.enabled = true
    if not installed then
        installed = true
        API.RegisterEvents(events, { "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED" })
    end
    API.RegisterEvents(money, { "PLAYER_MONEY", "CHAT_MSG_MONEY" })
end

local function disable()
    L.enabled = false
    coinCancel()
    money:UnregisterAllEvents()
end

GP.Pearls.Register({
    key = L.KEY,
    name = "Faster loot",
    desc = "With auto loot on, takes your loot the moment the window opens.",
    help = "With auto loot on (the game's setting, or the auto-loot key held), everything that will fit in your bags is "
        .. "taken the moment the loot window opens, instead of one item at a time. Items that need a choice stay "
        .. "for you: bind-on-pickup asks you as usual, a group's rolls and master loot are left to the game, and so "
        .. "is anything that may not fit. When a corpse has only money, the amount floats up where you clicked "
        .. "(the money gained while the loot money came in). /gpearls fastloot shows the last pass. Unverified "
        .. "until the game is live.",
    default = true,
    category = "Loot & Bags",
    section = "Loot",
    defaults = { coins = true },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.FastLootFrame.Configure(panel, refreshers) end,
    onSettingChanged = function() if not setting("coins") then coinCancel() end end,
    commands = { fastloot = { help = "- faster loot's last pass: loot calls made, and what was left to the game",
        run = function() L.Report() end } },
})

L._test = { events = events, money = money }
