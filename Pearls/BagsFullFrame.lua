-- Pearls/BagsFullFrame.lua: the bags-full helper's window and its
-- Configuration Panel (#6). The logic is Pearls/BagsFull.lua; this file only
-- draws what BF.Decide returns and forwards clicks.
--
-- The window: beside Blizzard's loot window when it's shown (anchored to it,
-- never touching it), else where the player last dragged it (per character),
-- else above the centre. "Bags full!", a line saying what's going on, the
-- Destroy card (the item, its value, < n/N > through the candidates, an X to
-- never suggest it), the You get card (click: the next row that doesn't fit),
-- a net line, and one button. Blizzard's art in both looks: the alert icon
-- (UI-Dialog-Icon-AlertNew), the pass icon for the X (UI-GroupLoot-Pass-Up),
-- the next-page arrow (UI-SpellbookIcon-NextPage-Up).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.BagsFullFrame = Frame

Frame.NAME = "GlassPearlsBagsFullFrame"
local W, H, CARD_W, CARD_H = 380, 186, 170, 86
local ALERT = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local PASS = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local ARROW = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f   -- built on first show

local function BF() return GP.BagsFull end
local function money(v) return C_CurrencyInfo.GetCoinTextureString(v) end

local function qualityColor(q)
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q or 1)
    if ok and type(r) == "number" then return r, g, b end
    return 1, 1, 1
end

local function shortName(link, name)
    if type(name) == "string" and name ~= "" then return name end
    return type(link) == "string" and link:match("%[(.-)%]") or "?"
end

-- A card: a caption, an icon with a quality edge, the name, a value line, and
-- a message that replaces the item when there's none to show.
local function card(parent, caption)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(CARD_W, CARD_H)
    GP.Theme.Control(c)
    c.caption = GP.UI.Label(c, caption, "GameFontHighlightSmall")
    c.caption:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -7)
    c.edge = c:CreateTexture(nil, "BORDER")
    c.edge:SetSize(38, 38)
    c.edge:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -26)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", c.edge, "TOPLEFT", 1, -1)
    c.icon:SetPoint("BOTTOMRIGHT", c.edge, "BOTTOMRIGHT", -1, 1)
    c.count = c:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    c.count:SetPoint("BOTTOMRIGHT", c.edge, "BOTTOMRIGHT", -2, 2)
    c.name = GP.UI.Label(c, "", "GameFontHighlightSmall")
    c.name:SetPoint("TOPLEFT", c.edge, "TOPRIGHT", 7, -1)
    c.name:SetWidth(CARD_W - 64)
    c.name:SetWordWrap(true)
    c.value = GP.UI.Label(c, "", "GameFontHighlightSmall")
    c.value:SetPoint("BOTTOMLEFT", c.edge, "BOTTOMRIGHT", 7, 1)
    c.msg = GP.UI.Label(c, "", "GameFontHighlightSmall")
    c.msg:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -26)
    c.msg:SetWidth(CARD_W - 16)
    c.msg:SetWordWrap(true)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

local function showItem(c, e)
    for _, w in ipairs({ c.edge, c.icon, c.count, c.name, c.value }) do w:Show() end
    c.msg:Hide()
    local r, g, b = qualityColor(e.quality)
    c.edge:SetColorTexture(r * 0.8, g * 0.8, b * 0.8, 1)
    c.icon:SetTexture(e.icon or QUESTION)
    local n = e.count or e.qty or 1
    c.count:SetText(n > 1 and tostring(n) or "")
    c.name:SetText(shortName(e.link, e.name))
    c.name:SetTextColor(r, g, b)
    c.value:SetText(e.value and money(e.value) or "|cff9d9d9d…|r")
end

local function showMessage(c, text)
    for _, w in ipairs({ c.edge, c.icon, c.count, c.name, c.value }) do w:Hide() end
    c.msg:SetText(text)
    c.msg:Show()
end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.bagsfull
    if LootFrame and LootFrame:IsShown() and not (db and db.moved) then
        f:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 6, 0)
    elseif db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Remember where the player put it (per character), as a TOPLEFT offset.
        local left, top = self:GetLeft(), self:GetTop()
        if GP.charDB and type(left) == "number" and type(top) == "number" then
            GP.charDB.bagsfull = { moved = true, x = left, y = top }
        end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 44 })

    f.alert = f:CreateTexture(nil, "ARTWORK")
    f.alert:SetSize(34, 34)
    f.alert:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.alert:SetTexture(ALERT)
    f.title = GP.UI.Header(f, "Bags full!")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 54, -14)
    f.sub = GP.UI.Label(f, "", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.sub:SetWidth(W - 100)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() BF().Dismiss() end)

    -- Left: what goes.
    f.out = card(f, "Destroy:")
    f.out:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -56)
    f.out:SetScript("OnEnter", function(self)
        local c = self.entry
        if not c then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetBagItem, GameTooltip, c.bag, c.slot) then pcall(GameTooltip.SetHyperlink, GameTooltip, c.link) end
        GameTooltip:Show()
    end)
    f.prev = GP.UI.Button(f.out, "<", 22, function() BF().NextCandidate(-1) end)
    f.next = GP.UI.Button(f.out, ">", 22, function() BF().NextCandidate(1) end)
    f.next:SetPoint("TOPRIGHT", f.out, "TOPRIGHT", -5, -4)
    f.counter = GP.UI.Label(f.out, "", "GameFontDisableSmall")
    f.counter:SetPoint("RIGHT", f.next, "LEFT", -3, 0)
    f.prev:SetPoint("RIGHT", f.counter, "LEFT", -3, 0)
    f.never = CreateFrame("Button", nil, f.out)
    f.never:SetSize(18, 18)
    f.never:SetPoint("BOTTOMRIGHT", f.out, "BOTTOMRIGHT", -6, 6)
    f.never:SetNormalTexture(PASS)
    f.never:SetHighlightTexture(PASS)
    f.never:GetHighlightTexture():SetBlendMode("ADD")
    f.never:SetScript("OnClick", function() BF().Never(f.out.entry) end)
    GP.UI.Tooltip(f.never, "Never suggest this item",
        "It won't be suggested again, on any of your characters. Undo it in the helper's options (the gear).")

    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetSize(24, 24)
    f.arrow:SetPoint("CENTER", f, "TOP", 0, -56 - CARD_H / 2)
    f.arrow:SetTexture(ARROW)

    -- Right: what comes.
    f.inc = card(f, "You get:")
    f.inc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -56)
    f.inc.caption:SetTextColor(1, 0.82, 0)
    f.inc:SetScript("OnClick", function() BF().NextLoot() end)
    f.inc:SetScript("OnEnter", function(self)
        local r = self.entry
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetLootItem, GameTooltip, r.slot) then pcall(GameTooltip.SetHyperlink, GameTooltip, r.link) end
        if self.more then GameTooltip:AddLine(self.more, 0.6, 0.8, 1) end
        GameTooltip:Show()
    end)

    f.net = GP.UI.Label(f, "", "GameFontHighlightSmall")
    f.net:SetPoint("BOTTOM", f, "BOTTOM", 0, 40)
    f.button = GP.UI.Button(f, "Destroy & loot", 170, function()
        -- The destroy runs inside this click, a hardware event (BagsFull.lua).
        BF().Destroy()
    end)
    f.button:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    f.anyway = GP.UI.Button(f, "Choose anyway", 170, function() BF().ChooseAnyway() end)
    f.anyway:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    f.anyway:Hide()
end

function Frame.Show(view)
    if not f then build() end
    local bf = BF()
    local c, t = view.candidate, view.target
    -- The line under the title.
    if view.byHand then
        f.sub:SetText("Drag the item out of your bag to destroy it (Blizzard asks to confirm).")
    elseif view.mode == "room" then
        f.sub:SetText("Destroy a low-value item, then loot again.")
    elseif view.notWorth then
        f.sub:SetText("This loot is worth less than anything in your bags.")
    else
        f.sub:SetText("Destroy a low-value item to loot.")
    end
    -- The Destroy card.
    f.out.entry = (not view.notWorth) and c or nil
    local browse = c ~= nil and not view.notWorth
    for _, w in ipairs({ f.prev, f.next, f.counter, f.never }) do w:SetShown(browse) end
    if view.notWorth then
        showMessage(f.out, "|cffffd27fNot worth picking up.|r Everything in your bags is worth more.")
    elseif c then
        showItem(f.out, c)
        f.counter:SetText(bf.state.choice.index .. "/" .. #view.candidates)
        local many = #view.candidates > 1
        f.prev:SetEnabled(many)
        f.next:SetEnabled(many)
    else
        showMessage(f.out, "Nothing in your bags can be suggested: quest items, tools and kept items stay.")
    end
    -- The You get card.
    f.inc.entry = t
    if t then
        showItem(f.inc, t)
        local n = view.rows and #view.rows or 1
        f.inc.caption:SetText(n > 1 and ("You get (" .. view.targetIndex .. "/" .. n .. "):") or "You get:")
        f.inc.more = n > 1 and (n .. " items don't fit: click for the next one") or nil
    else
        showMessage(f.inc, "Loot it again after making room.")
        f.inc.caption:SetText("You get:")
        f.inc.more = nil
    end
    -- The net line, when both values are known.
    if c and t and t.value and not view.notWorth then
        f.net:SetText("You lose " .. money(c.value) .. ", you get " .. money(t.value) .. ".")
    else
        f.net:SetText("")
    end
    -- The button.
    local armed = bf.state.armed ~= nil
    f.anyway:SetShown(view.notWorth and not view.byHand)
    f.button:SetShown(browse and not view.byHand)
    if armed then
        f.button:SetText("Click again to destroy")
    else
        f.button:SetText(view.mode == "room" and "Destroy" or "Destroy & loot")
    end
    place()
    f:Show()
end

function Frame.Hide()
    if f then f:Hide() end
end

function Frame.IsShown() return f ~= nil and f:IsShown() end

--------------------------------------------------------------------------------
-- The Configuration Panel: which items it may offer, and the never-suggest list.

local PAGE = 8

function Frame.Configure(panel, refreshers)
    local KEY, P, SS = "bagsfull", GP.Pearls, GP.SettingsSync
    local scope = GP.UI.Header(panel, "Which items it may offer")
    scope:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local last, _, refreshScope = GP.UI.Radios(panel, scope, {
        { "grey", "Grey items only" },
        { "white", "Grey and white items (white needs a second click)" },
    }, function() return P.Setting(KEY, "scope") end, function(v) P.SetSetting(KEY, "scope", v) end)
    refreshers[#refreshers + 1] = refreshScope
    local greys, refreshGreys = GP.UI.Check(panel, "Greys first",
        function() return P.Setting(KEY, "greysFirst") end, function(on) P.SetSetting(KEY, "greysFirst", on) end,
        { tip = "With white items allowed: offer every grey item before any white one, whatever the values." })
    greys:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -4, -10)
    refreshers[#refreshers + 1] = refreshGreys

    local listHead = GP.UI.Header(panel, "Never suggested")
    listHead:SetPoint("TOPLEFT", greys, "BOTTOMLEFT", 4, -18)
    local count = GP.UI.Label(panel, "", "GameFontDisableSmall")
    count:SetPoint("LEFT", listHead, "RIGHT", 10, 0)
    local rows, page = {}, 1
    local function refreshList()
        local ids = SS.SetMembers(GP.BagsFull.KEEP)
        local pages = math.max(1, math.ceil(#ids / PAGE))
        if page > pages then page = pages end
        count:SetText(#ids == 0 and "the X in the helper adds an item here" or (#ids .. " item(s)"))
        for i = 1, PAGE do
            local row = rows[i]
            local id = ids[(page - 1) * PAGE + i]
            row.id = id
            if id then
                local name = C_Item.GetItemNameByID(id)
                if not name then pcall(C_Item.RequestLoadItemDataByID, id) end
                row.label:SetText(name or ("item " .. id))
                row.label:Show()
                row.remove:Show()
            else
                row.label:Hide()
                row.remove:Hide()
            end
        end
        panel.pageText:SetText(pages > 1 and (page .. "/" .. pages) or "")
        panel.prevPage:SetShown(pages > 1)
        panel.nextPage:SetShown(pages > 1)
        panel.clear:SetEnabled(#ids > 0)
    end
    for i = 1, PAGE do
        local row = {}
        row.remove = GP.UI.Button(panel, "Remove", 70, function()
            if row.id then SS.SetRemove(GP.BagsFull.KEEP, row.id) end
            refreshList()
        end)
        row.remove:SetPoint("TOPLEFT", listHead, "BOTTOMLEFT", 0, -6 - (i - 1) * 24)
        row.label = GP.UI.Label(panel, "")
        row.label:SetPoint("LEFT", row.remove, "RIGHT", 8, 0)
        rows[i] = row
    end
    panel.rows = rows
    panel.prevPage = GP.UI.Button(panel, "<", 24, function() page = math.max(1, page - 1); refreshList() end)
    panel.prevPage:SetPoint("TOPLEFT", rows[PAGE].remove, "BOTTOMLEFT", 0, -8)
    panel.pageText = GP.UI.Label(panel, "", "GameFontHighlightSmall")
    panel.pageText:SetPoint("LEFT", panel.prevPage, "RIGHT", 6, 0)
    panel.nextPage = GP.UI.Button(panel, ">", 24, function() page = page + 1; refreshList() end)
    panel.nextPage:SetPoint("LEFT", panel.pageText, "RIGHT", 6, 0)
    panel.clear = GP.UI.Button(panel, "Clear all", 90, function()
        SS.SetClear(GP.BagsFull.KEEP)
        refreshList()
    end)
    panel.clear:SetPoint("LEFT", panel.nextPage, "RIGHT", 16, 0)
    refreshers[#refreshers + 1] = refreshList
    panel.refreshList = refreshList
end

Frame._test = { frame = function() return f end, reset = function() if f then f:Hide() end end }
