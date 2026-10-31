-- Trade summary (#45): off by default; the line only for a confirmed trade
-- (ERR_TRADE_COMPLETE), the money the observed net change, the window's offers
-- only choosing the wording when they agree; items frozen at the close; two
-- records kept apart and a message taken only when one record can own it; a
-- trade opened while an earlier one is unresolved never reported; the log.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local T, P = GP.Trades, GP.Pearls
local M = GP.TrainingFrame.Money
local SWORD = "|cff1eff00|Hitem:2000|h[Sword]|h|r"
local POTION = "|cffffffff|Hitem:118|h[Potion]|h|r"

local function open(partner, mine, theirs)
    WoW.fullNames.NPC = partner or "Mira Stormwind"
    WoW.trade = { mine = mine or { items = {} }, theirs = theirs or { items = {} } }
    WoW.fire("TRADE_SHOW")
end
local function update() WoW.fire("TRADE_UPDATE") end
local function close() WoW.fire("TRADE_CLOSED") end
local function complete() WoW.fire("UI_INFO_MESSAGE", WoW.TRADE_COMPLETE, "Trade complete.") end
local function pay(delta) WoW.money = WoW.money + delta; WoW.fire("PLAYER_MONEY") end
local function lines() return newChat() end
local function only(pattern)
    local l = lines()
    return #l == 1 and l[1]:find(pattern) ~= nil, l[1]
end
local function silent() return #lines() == 0 end
local function settle() WoW.advance(T.WAIT + 0.1) end
local function esc(s) return (s:gsub("%p", "%%%0")) end

WoW.money = 1000000
check(not P.IsOn("trades"), "off by default")
open(); update(); close(); complete(); pay(-120000)
check(silent(), "  off: nothing said")
P.Set("trades", true)

-- Gave money.
open(nil, { money = 120000, items = {} })
close(); complete(); pay(-120000)
check(only("You gave " .. esc(M(120000)) .. " to Mira Stormwind%.$"), "gave money: said")
settle()
check(silent(), "  once")
-- Received money, the message before the close.
open(nil, nil, { money = 35000, items = {} })
complete(); close(); pay(35000)
check(only("You received " .. esc(M(35000)) .. " from Mira Stormwind%.$"), "received, the message first: said")
settle()

-- Both offered: the net change.
WoW.advance(3)
open(nil, { money = 120000, items = {} }, { money = 30000, items = {} })
close(); complete(); pay(-90000)
check(only("Trade with Mira Stormwind completed: your money changed by %-" .. esc(M(90000)) .. "%.$"),
    "both offered: the net change")
settle(); WoW.advance(3)
open(nil, { money = 50000, items = {} }, { money = 50000, items = {} })
close(); complete(); settle()
check(only("no net money change%.$"), "equal both ways: no net money change")
WoW.advance(3)
-- An unrelated change in the interval.
open(nil, { money = 120000, items = {} })
pay(500)
close(); complete(); pay(-120000)
check(only("your money changed by %-" .. esc(M(119500))), "an unrelated change: the net wording, never 'You gave'")
settle(); WoW.advance(3)
-- Both offered, the purse falling by your offer (an unrelated change): never "You gave".
open(nil, { money = 120000, items = {} }, { money = 30000, items = {} })
close(); complete(); pay(-120000)
check(only("your money changed by %-" .. esc(M(120000))), "both offered, the purse matching one: the net wording")
settle(); WoW.advance(3)
-- They offered, the purse moving otherwise.
open(nil, nil, { money = 35000, items = {} })
close(); complete(); pay(20000)
check(only("your money changed by %+" .. esc(M(20000))), "their offer not matching the purse: the net wording")
settle(); WoW.advance(3)
-- Completion by the message's name alone (a localized text that differs), and another message.
open(nil, { money = 100, items = {} })
close()
WoW.fire("UI_INFO_MESSAGE", 3, "Inventory is full.")
pay(-100)
check(silent(), "another info message: not a completion")
settle(); WoW.advance(3)
open(nil, { money = 100, items = {} })
close()
WoW.fire("UI_INFO_MESSAGE", WoW.TRADE_COMPLETE, "Handel abgeschlossen.")
pay(-100)
check(only("You gave"), "completion by its name, whatever the text")
settle(); WoW.advance(3)
-- The money already moved before the message, no PLAYER_MONEY after: the 2 s end.
open(nil, { money = 10000, items = {} })
close()
WoW.money = WoW.money - 10000
complete()
check(silent(), "money moved before the message: waits")
settle()
check(only("You gave " .. esc(M(10000))), "  said at the 2 s end")
WoW.advance(3)
-- Money unreadable.
open(nil, { money = 10000, items = {} })
close(); complete()
local saved = WoW.money
WoW.money = WoW.Secret("money")
WoW.fire("PLAYER_MONEY")
WoW.money = saved - 10000
check(only("completed: money unknown"), "a secret purse: money unknown")
settle(); WoW.advance(3)

-- Items, frozen at the close.
open(nil, { items = { [1] = { link = SWORD, count = 1 }, [7] = { link = POTION, count = 1 } } },
    { items = { [2] = { link = POTION, count = 5 } } })
update()
close()
WoW.trade.mine.items[1] = nil                     -- a later read never changes the record
WoW.fire("TRADE_UPDATE")
complete(); settle()
check(only("Trade with Mira Stormwind completed; you gave " .. esc(SWORD) .. "; you received " .. esc(POTION)
    .. " x5%.$"), "items both ways, slot 7 ignored, frozen at the close")
WoW.advance(3)
open(nil, { items = { [1] = { link = SWORD, count = 1 } } })
WoW.trade.mine.items[1] = { link = POTION, count = 2 }
WoW.fire("TRADE_PLAYER_ITEM_CHANGED", 1)
close(); complete(); settle()
check(only("you gave " .. esc(POTION) .. " x2%.$"), "a replaced item: the last read")
WoW.advance(3)
open(nil, nil, { items = { [3] = "secret" } })
close(); complete(); settle()
check(only("completed; 1 slot unread%.$"), "a secret slot: counted unread")
WoW.advance(3)
open(nil, { items = { [1] = { count = 1 }, [2] = { link = SWORD, count = "secret" } } })
close(); complete(); settle()
check(only("completed; 2 slots unread%.$"), "an item without a link, a secret count: unread")
WoW.advance(3)
open()
close(); complete(); settle()
check(only("^.-Trade with Mira Stormwind completed%.$"), "nothing either way")
WoW.advance(3)
WoW.fullNames.NPC = WoW.Secret("name")
WoW.trade = { mine = { money = 100, items = {} }, theirs = { items = {} } }
WoW.fire("TRADE_SHOW")
close(); complete(); pay(-100)
check(only("to someone%.$"), "a secret partner: someone")
settle(); WoW.advance(3)

-- Cancelled: closed with no message.
open(nil, { money = 5000, items = {} })
close(); settle(); complete()
check(silent(), "closed without the message: silent, a late message too")
WoW.advance(3)
WoW.fire("TRADE_REQUEST_CANCEL")
check(T.state.active == nil, "TRADE_REQUEST_CANCEL never ends a trade (none open)")
-- A request cancel during an open trade: still reported.
open(nil, { money = 5000, items = {} })
WoW.fire("TRADE_REQUEST_CANCEL")
close(); complete(); pay(-5000)
check(only("You gave"), "a request cancel mid-trade: the trade still reported")
settle(); WoW.advance(3)
-- A duplicate message.
open(nil, { money = 5000, items = {} })
close(); complete(); complete(); pay(-5000)
check(only("You gave"), "a duplicate message: one line")
settle(); WoW.advance(3)

--------------------------------------------------------------------------------
-- Two trades

-- A confirmed first, waiting for money, then a second opens: the first said, with its own data.
open("First One", { money = 7000, items = {} })
close(); complete()
WoW.money = WoW.money - 7000                       -- moved, PLAYER_MONEY not yet
open("Second Two", { money = 999, items = { [1] = { link = SWORD, count = 1 } } })
local ok1 = only("You gave " .. esc(M(7000)) .. " to First One%.$")
check(ok1, "a second trade opening: the first finalized first, with its own data")
close(); complete(); pay(-999)
check(silent(), "  the second, opened within 2 s of the first's line: ambiguous, never said")
settle(); WoW.advance(3)
-- An unconfirmed first, a second opening, then a message, then the second cancelled.
open("First One", { money = 7000, items = {} })
close()
open("Second Two", nil, { items = { [1] = { link = POTION, count = 1 } } })
complete()
close()
for _ = 1, 5 do WoW.advance(1) end
check(silent(), "unconfirmed first, a second, a message, the second cancelled: neither said")
WoW.advance(3)
-- A duplicate after the first was finalized and the second opened.
open("First One", { money = 7000, items = {} })
close(); complete(); pay(-7000)
lines()
open("Second Two", { money = 1, items = {} })
complete()
close(); pay(-1); settle()
check(silent(), "a duplicate after the first's line, the second open: the second not confirmed")
WoW.advance(3)
-- Past both guards (no record waiting, no line in the last 2 s): a clean start.
open("Clean Start", { money = 100, items = {} })
check(not T.state.active.ambiguous, "later, past both guards: a clean start")
close(); complete(); pay(-100)
check(only("to Clean Start"), "  and reported")
settle(); WoW.advance(3)

-- Disable with a result pending.
open(nil, { money = 100, items = {} })
close(); complete()
P.Set("trades", false)
pay(-100); settle()
check(silent(), "Disable with a result pending: nothing said")
P.Set("trades", true)
WoW.advance(3)

--------------------------------------------------------------------------------
-- The log

for i = 1, 12 do
    open("Buyer " .. i, nil, { money = i, items = {} })
    close(); complete(); pay(i); settle(); WoW.advance(3)
end
lines()
local logged = GP.charDB.trades
eq(#logged, 10, "the log keeps 10")
check(logged[1].line:find("Buyer 12", 1, true) and logged[10].line:find("Buyer 3", 1, true), "  newest first")
P.Command("trades").run()
check(chatHas("Trade summary, newest first:"), "/gpearls trades")
GP.Options.Open("cat:Social")
local page = GP.Options._test.pages["cat:Social"]
local row
for _, pl in ipairs(page.placed) do if pl.key == "trades" then row = pl.row end end
check(row ~= nil, "on the Social page")
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:trades"].frame._children[1]
local clear, body
for _, w in ipairs(content._children) do
    if w.GetText and w:GetText() == "Clear" then clear = w end
end
for _, r in ipairs(content._regions or {}) do
    if r.GetText and type(r:GetText()) == "string" and r:GetText():find("Buyer 12", 1, true) then body = r end
end
check(body ~= nil, "the panel lists them")
clear:GetScript("OnClick")(clear)
eq(#GP.charDB.trades, 0, "  Clear empties the log")

done("test_trades")
