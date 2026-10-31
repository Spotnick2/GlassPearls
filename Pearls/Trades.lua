-- Pearls/Trades.lua: trade summary (#45). After each completed trade, one
-- line in chat: what your money did and the items that changed hands.
--
-- The money is the observed net change of your purse (GetMoney when the
-- window opened, then after completion), never taken from the window: the
-- window's offers only choose the wording, and only when they agree with the
-- observation ("You gave 12g to Name" when only you offered 12g and your
-- purse fell by exactly that); otherwise "your money changed by".
--
-- Completion is the info message named ERR_TRADE_COMPLETE; TRADE_CLOSED fires
-- for a cancel too. The message names no trade, so two records are kept
-- apart, the active one (window open) and at most one closed one waiting 2 s
-- for its message (a new window ends that wait), so a message has at most one
-- owner. A trade that opens while an earlier one is unresolved (or just
-- reported) is born ambiguous and is never reported: a late or duplicate
-- message might be the earlier one's. The window's items are read at every
-- update and frozen at TRADE_CLOSED.
--
-- The log (the last 10 lines) stays on this character, never synced.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local T = {}
GP.Trades = T

T.KEY = "trades"
T.WAIT = 2                -- for the message after a close, and for the money after it
T.SLOTS = 6               -- slot 7 is the enchant slot, never traded (TradeFrame.lua:3)
T.LOG_MAX = 10
T.EVENTS = { "TRADE_SHOW", "TRADE_UPDATE", "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED",
    "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "UI_INFO_MESSAGE", "PLAYER_MONEY" }

local events = CreateFrame("Frame")
local state = { token = 0, active = nil, closed = nil, lastFinal = nil }
T.state = state

local function say(msg) API.Print(msg) end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

local function money(v)
    v = ask(v)
    if type(v) ~= "number" or v < 0 then return nil end
    return v
end

local function coins(c) return GP.TrainingFrame.Money(c) end

local function log()
    local db = GP.charDB
    if not db then return {} end
    db.trades = type(db.trades) == "table" and db.trades or {}
    return db.trades
end

--------------------------------------------------------------------------------
-- The window

-- One side's slots: { items = { { link, count } }, unread = n }.
local function side(infoFn, linkFn)
    local out = { items = {}, unread = 0 }
    for i = 1, T.SLOTS do
        local okI, name, _, count = pcall(infoFn, i)
        if not okI or API.IsSecret(name) or API.IsSecret(count) then
            out.unread = out.unread + 1
        elseif name ~= nil then
            local link = ask(linkFn, i)
            if type(link) == "string" and link ~= "" and type(count) == "number" and count >= 1 then
                out.items[#out.items + 1] = { link = link, count = count }
            else
                out.unread = out.unread + 1
            end
        end
    end
    return out
end

-- Only the active record is read: what a closed one holds is frozen.
local function readWindow(rec)
    rec.mine = side(GetTradePlayerItemInfo, GetTradePlayerItemLink)
    rec.theirs = side(GetTradeTargetItemInfo, GetTradeTargetItemLink)
    rec.mine.money = money(GetPlayerTradeMoney)
    rec.theirs.money = money(GetTargetTradeMoney)
end

--------------------------------------------------------------------------------
-- The line

local function list(s)
    local parts = {}
    for _, it in ipairs(s.items) do parts[#parts + 1] = it.count > 1 and (it.link .. " x" .. it.count) or it.link end
    return table.concat(parts, ", ")
end

function T.Line(rec, delta)
    local who = rec.partner or "someone"
    local mine, theirs = rec.mine or { items = {}, unread = 0 }, rec.theirs or { items = {}, unread = 0 }
    local head
    if delta == nil then
        head = ("Trade with %s completed: money unknown"):format(who)
    elseif mine.money and theirs.money and mine.money > 0 and theirs.money == 0 and delta == -mine.money then
        head = ("You gave %s to %s"):format(coins(mine.money), who)
    elseif mine.money and theirs.money and theirs.money > 0 and mine.money == 0 and delta == theirs.money then
        head = ("You received %s from %s"):format(coins(theirs.money), who)
    elseif delta == 0 then
        local offered = (mine.money or 0) > 0 or (theirs.money or 0) > 0 or not (mine.money and theirs.money)
        head = offered and ("Trade with %s completed: no net money change"):format(who)
            or ("Trade with %s completed"):format(who)
    else
        head = ("Trade with %s completed: your money changed by %s%s"):format(who, delta < 0 and "-" or "+",
            coins(math.abs(delta)))
    end
    local parts = {}
    if #mine.items > 0 then parts[#parts + 1] = "you gave " .. list(mine) end
    if #theirs.items > 0 then parts[#parts + 1] = "you received " .. list(theirs) end
    local unread = mine.unread + theirs.unread
    if unread > 0 then parts[#parts + 1] = unread .. (unread == 1 and " slot unread" or " slots unread") end
    if #parts == 0 then return head .. "." end
    return head .. "; " .. table.concat(parts, "; ") .. "."
end

--------------------------------------------------------------------------------
-- The records

local function newToken()
    state.token = state.token + 1
    return state.token
end

-- Say a confirmed record's line, once (callers pass only confirmed records,
-- and an ambiguous one is never confirmed).
local function finalize(rec)
    if rec.final then return end
    rec.final = true
    state.lastFinal = GetTime()
    local now = money(GetMoney)
    local delta = (now and rec.before) and (now - rec.before) or nil
    local line = T.Line(rec, delta)
    say(line)
    local l = log()
    table.insert(l, 1, { t = ask(GetServerTime), line = line })
    while #l > T.LOG_MAX do table.remove(l) end
    if state.closed == rec then state.closed = nil end
end

local function confirm(rec)
    rec.confirmed = true
    local token = rec.token
    C_Timer.After(T.WAIT, function()
        if rec.token == token then finalize(rec) end      -- the money's last chance
    end)
end

local function onShow()
    local c = state.closed
    local ambiguous = state.active ~= nil                  -- a window never closed: can't tell
    if c then
        if c.confirmed then finalize(c) else ambiguous = true end
        state.closed = nil
    end
    if state.lastFinal and GetTime() - state.lastFinal < T.WAIT then ambiguous = true end
    local name = ask(GetUnitName, "NPC", false)
    local rec = { token = newToken(), before = money(GetMoney), ambiguous = ambiguous,
        partner = type(name) == "string" and name ~= "" and name or nil }
    state.active = rec
    readWindow(rec)
end

local function onClosed()
    local rec = state.active
    if not rec then return end                             -- a second TRADE_CLOSED
    state.active = nil
    state.closed = rec
    if rec.confirmed then return end                      -- its money is on its way
    local token = rec.token
    C_Timer.After(T.WAIT, function()
        if state.closed == rec and rec.token == token and not rec.confirmed then state.closed = nil end
    end)
end

local function isComplete(errorType, message)
    local name = ask(GetGameMessageInfo, errorType)
    if name == "ERR_TRADE_COMPLETE" then return true end
    local text = rawget(_G, "ERR_TRADE_COMPLETE")
    return not API.IsSecret(message) and type(text) == "string" and message == text
end

-- TRADE_SHOW empties the closed slot first, so at most one record can own it.
local function onComplete()
    local rec = state.closed or state.active
    if not rec or rec.ambiguous or rec.confirmed then return end   -- a duplicate confirms nothing
    confirm(rec)
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "TRADE_SHOW" then
        onShow()
    elseif event == "TRADE_CLOSED" then
        onClosed()
    elseif event == "UI_INFO_MESSAGE" then
        if isComplete(...) then onComplete() end
    elseif event == "PLAYER_MONEY" then
        local rec = (state.closed and state.closed.confirmed and state.closed)
            or (state.active and state.active.confirmed and state.active)
        if rec then finalize(rec) end
    elseif state.active then                               -- the window changed
        readWindow(state.active)
    end
end)

--------------------------------------------------------------------------------
-- The log, the panel, the pearl

function T.Report()
    local l = log()
    if #l == 0 then return say("Trade summary: no trade logged on this character.") end
    say("Trade summary, newest first:")
    for _, e in ipairs(l) do say("  " .. e.line) end
end

local function configure(panel, refreshers)
    local head = GP.UI.Header(panel, "The last trades on this character")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local body = GP.UI.Label(panel, "")
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -8)
    body:SetWidth(560)
    body:SetWordWrap(true)
    body:SetJustifyH("LEFT")
    local function refresh()
        local lines = {}
        for _, e in ipairs(log()) do lines[#lines + 1] = e.line end
        body:SetText(#lines > 0 and table.concat(lines, "\n") or "No trade logged yet.")
    end
    local clear = GP.UI.Button(panel, "Clear", 80, function()
        if GP.charDB then GP.charDB.trades = {} end
        refresh()
    end)
    clear:SetPoint("TOPLEFT", body, "BOTTOMLEFT", -4, -10)
    refreshers[#refreshers + 1] = refresh
    refresh()
end

local function enable()
    T.enabled = true
    API.RegisterEvents(events, T.EVENTS)
end

local function disable()
    T.enabled = false
    events:UnregisterAllEvents()
    if state.active then state.active.token = -1 end      -- its timers go stale
    if state.closed then state.closed.token = -1 end
    state.active, state.closed = nil, nil
end

GP.Pearls.Register({
    key = T.KEY,
    name = "Trade summary",
    desc = "After a trade, one line in chat: the money and the items that changed hands.",
    help = "After each completed trade, a line in your chat: \"You gave 12g to Name\" or \"You received 3g from "
        .. "Name\" when only one side offered money and your purse moved by exactly that, otherwise how your money "
        .. "changed, from opening the trade to a moment (up to 2 seconds) after it completed; then the items each "
        .. "way. A trade opened right after another one is left out when it can't be told apart. The last 10 are "
        .. "kept here, on this character only. /gpearls trades lists them. Unverified until the game is live.",
    default = false,
    category = "Social",
    section = "Trade",
    Enable = enable,
    Disable = disable,
    configure = configure,
    commands = { trades = { help = "- the last trades on this character", run = function() T.Report() end } },
})

T._test = { events = events }
