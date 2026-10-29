-- Pearls/JunkFrame.lua: the Configuration Panel of "Sell junk & repair" (#15).
-- The logic is Pearls/Junk.lua. Selling (grey items, the sell list,
-- buyback-safe), repairing (on/off, guild funds first or my money only), the
-- sell list and the keep list, and the Shift note.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.JunkFrame = Frame

local function itemName(id)
    local ok, n = pcall(C_Item.GetItemNameByID, id)
    if ok and not API.IsSecret(n) and type(n) == "string" then return n end
    pcall(C_Item.RequestLoadItemDataByID, id)
    return "item " .. id
end

function Frame.Configure(panel, refreshers)
    local KEY, P, J = "junk", GP.Pearls, GP.Junk
    local function check(anchor, text, name, tip, x, y)
        local cb, refresh = GP.UI.Check(panel, text,
            function() return P.Setting(KEY, name) end, function(on) P.SetSetting(KEY, name, on) end, { tip = tip })
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local sell = GP.UI.Header(panel, "Selling")
    sell:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local a = check(sell, "Sell junk when a merchant opens", "autoSell",
        "Cheapest first. Hold Shift as you open the merchant to skip a visit.", -4, -6)
    a = check(a, "Sell grey items", "sellGrey",
        "Grey items with a price. Not unbound grey gear, nor greys with a use: list one to sell it anyway.")
    a = check(a, "Buyback-safe", "safe",
        "Sell at most as many as the buyback page has room for, so everything sold this visit can be bought back, "
        .. "provided you sell nothing yourself meanwhile. The rest waits for the next visit.")
    local rep = GP.UI.Header(panel, "Repairing")
    rep:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -14)
    a = check(rep, "Repair when a merchant can", "autoRepair", "After selling, so the sale helps pay.", -4, -6)
    local last, _, refreshFunds = GP.UI.Radios(panel, a, {
        { "guild", "Guild funds first, then my money" },
        { "mine", "My money only" },
    }, function() return P.Setting(KEY, "repairFunds") end, function(v) P.SetSetting(KEY, "repairFunds", v) end)
    refreshers[#refreshers + 1] = refreshFunds
    local note = GP.UI.Label(panel,
        "Guild repair works like Blizzard's guild repair button: what the guild doesn't cover comes from your money.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -6)
    note:SetWidth(380)
    note:SetWordWrap(true)
    local after, sellList = GP.UI.SetList(panel, note, "Always sell", J.SELL, "/gpearls sell <item> adds one",
        itemName, "item(s)")
    local _, keepList = GP.UI.SetList(panel, after, "Never sell", J.KEEP, "/gpearls keep <item> adds one",
        itemName, "item(s)")
    refreshers[#refreshers + 1] = sellList.refresh
    refreshers[#refreshers + 1] = keepList.refresh
    panel.sellList, panel.keepList = sellList, keepList
end
