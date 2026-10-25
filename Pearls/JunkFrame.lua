-- Pearls/JunkFrame.lua: the Configuration Panel of "Sell junk & repair" (#15).
-- The logic is Pearls/Junk.lua. Selling (grey items, the sell list,
-- buyback-safe), repairing (on/off, guild funds first or my money only), the
-- sell list and the keep list, and the Shift note.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.JunkFrame = Frame

Frame.PAGE = 4

local function itemName(id)
    local ok, n = pcall(C_Item.GetItemNameByID, id)
    if ok and not API.IsSecret(n) and type(n) == "string" then return n end
    pcall(C_Item.RequestLoadItemDataByID, id)
    return "item " .. id
end

-- A paged list of one sync set under `anchor`: Remove per row, < n/N >, Clear
-- all. Returns its last control (to anchor what follows) and its refresh.
local function setList(panel, anchor, title, setID, empty)
    local SS = GP.SettingsSync
    local head = GP.UI.Header(panel, title, "GameFontNormal")
    head:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    local count = GP.UI.Label(panel, "", "GameFontDisableSmall")
    count:SetPoint("LEFT", head, "RIGHT", 10, 0)
    local list = { rows = {}, page = 1, head = head, count = count }
    local function refresh()
        local ids = SS.SetMembers(setID)
        local pages = math.max(1, math.ceil(#ids / Frame.PAGE))
        if list.page > pages then list.page = pages end
        count:SetText(#ids == 0 and empty or (#ids .. " item(s)"))
        for i = 1, Frame.PAGE do
            local row = list.rows[i]
            local id = ids[(list.page - 1) * Frame.PAGE + i]
            row.id = id
            if id then
                row.label:SetText(itemName(id))
                row.label:Show()
                row.remove:Show()
            else
                row.label:Hide()
                row.remove:Hide()
            end
        end
        list.pageText:SetText(pages > 1 and (list.page .. "/" .. pages) or "")
        list.prev:SetShown(pages > 1)
        list.next:SetShown(pages > 1)
        list.clear:SetEnabled(#ids > 0)
    end
    for i = 1, Frame.PAGE do
        local row = {}
        row.remove = GP.UI.Button(panel, "Remove", 70, function()
            if row.id then SS.SetRemove(setID, row.id) end
            refresh()
        end)
        row.remove:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6 - (i - 1) * 24)
        row.label = GP.UI.Label(panel, "")
        row.label:SetPoint("LEFT", row.remove, "RIGHT", 8, 0)
        list.rows[i] = row
    end
    list.prev = GP.UI.Button(panel, "<", 24, function() list.page = math.max(1, list.page - 1); refresh() end)
    list.prev:SetPoint("TOPLEFT", list.rows[Frame.PAGE].remove, "BOTTOMLEFT", 0, -6)
    list.pageText = GP.UI.Label(panel, "", "GameFontHighlightSmall")
    list.pageText:SetPoint("LEFT", list.prev, "RIGHT", 6, 0)
    list.next = GP.UI.Button(panel, ">", 24, function() list.page = list.page + 1; refresh() end)
    list.next:SetPoint("LEFT", list.pageText, "RIGHT", 6, 0)
    list.clear = GP.UI.Button(panel, "Clear all", 90, function()
        SS.SetClear(setID)
        refresh()
    end)
    list.clear:SetPoint("LEFT", list.next, "RIGHT", 16, 0)
    list.refresh = refresh
    return list.prev, list
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
    local after, sellList = setList(panel, note, "Always sell", J.SELL, "/gpearls sell <item> adds one")
    local _, keepList = setList(panel, after, "Never sell", J.KEEP, "/gpearls keep <item> adds one")
    refreshers[#refreshers + 1] = sellList.refresh
    refreshers[#refreshers + 1] = keepList.refresh
    panel.sellList, panel.keepList = sellList, keepList
end
