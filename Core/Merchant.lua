-- Core/Merchant.lua: the merchant session, for any pearl that acts at a
-- merchant (#15 sells junk and repairs; #14 may restock). Deliberately small:
-- whether a merchant is open, a counter that changes with each visit, the
-- pearls listening, and a delayed step that runs only if that same visit is
-- still open. What a pearl does there (selling, confirming, repairing) stays
-- in the pearl.
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
local events = CreateFrame("Frame")

events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        session, open = session + 1, true
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

Merchant._test = { events = events, reset = function() session, open, listeners = 0, false, {} end }
