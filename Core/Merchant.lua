-- Core/Merchant.lua: the merchant session, for any pearl that acts at a
-- merchant (#15 sells junk and repairs; #14 restocks). Deliberately small:
-- whether a merchant is open, a counter that changes with each visit, the
-- pearls listening, a delayed step that runs only if that same visit is
-- still open, and one pearl's outcome for a visit that another waits for
-- (restock waits for the junk seller: "ready" or "skip"). What a pearl does
-- there (selling, confirming, repairing, buying) stays in the pearl.
--
-- MERCHANT_SHOW / MERCHANT_CLOSED (MerchantFrameDocumentation). The events are
-- registered when the first pearl listens (its Enable), never at load.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Merchant = {}
GP.Merchant = Merchant

local session, open = 0, false
local listeners = {}
local outcomes, waiters = {}, {}   -- this visit's: key -> outcome, key -> { fn, ... }
local events = CreateFrame("Frame")

events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        session, open = session + 1, true
        outcomes, waiters = {}, {}
    elseif event == "MERCHANT_CLOSED" then
        if not open then return end   -- the client sends it more than once
        open = false
    end
    for key, fn in pairs(listeners) do
        local ok, err = pcall(fn, event, session)
        if not ok then API.Fail("merchant " .. key, err) end
    end
end)

function Merchant.IsOpen() return open end
function Merchant.Session() return session end

-- Listen under a key (a pearl's); fn(event, session) on MERCHANT_SHOW and
-- MERCHANT_CLOSED. nil stops listening.
function Merchant.On(key, fn)
    listeners[key] = fn
    if fn and not events:IsEventRegistered("MERCHANT_SHOW") then
        API.RegisterEvents(events, { "MERCHANT_SHOW", "MERCHANT_CLOSED" })
    end
end

-- Is this visit still the open one?
function Merchant.Current(s) return open and s == session end

-- fn() after `delay` seconds, only if visit `s` is still open.
function Merchant.After(delay, s, fn)
    C_Timer.After(delay, function()
        if Merchant.Current(s) then fn() end
    end)
end

-- A pearl's outcome for visit `s` (the first one counts; another visit's is
-- ignored). Whoever waits for it is told now.
function Merchant.Report(key, s, outcome)
    if not Merchant.Current(s) or outcomes[key] then return end
    outcomes[key] = outcome
    local list = waiters[key]
    waiters[key] = nil
    for _, fn in ipairs(list or {}) do
        local ok, err = pcall(fn, outcome)
        if not ok then API.Fail("merchant await " .. key, err) end
    end
end

-- fn(outcome) once `key` reports for visit `s`, or fn("skip") after
-- `seconds` without one; nothing if the visit closes first.
function Merchant.Await(key, s, seconds, fn)
    if not Merchant.Current(s) then return end
    if outcomes[key] then return fn(outcomes[key]) end
    local done = false
    local function once(outcome)
        if done then return end
        done = true
        fn(outcome)
    end
    waiters[key] = waiters[key] or {}
    table.insert(waiters[key], once)
    Merchant.After(seconds, s, function() once("skip") end)
end

Merchant._test = { events = events, reset = function()
    session, open, listeners, outcomes, waiters = 0, false, {}, {}, {}
end }
