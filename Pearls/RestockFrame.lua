-- Pearls/RestockFrame.lua: the restock pearl's "ask first" window and its
-- Configuration Panel (#14). The logic is Pearls/Restock.lua.
--
-- The window: beside Blizzard's merchant frame (read for its position, never
-- written), one row per line (icon, count, name, cost), the total and the
-- limits, Buy (buys from its own click, the shown counts as the most) and
-- Not now. Gone when the merchant closes.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.RestockFrame = Frame

Frame.NAME = "GlassPearlsRestockFrame"
Frame.MAX_ROWS = 8
local W, PAD, ROW = 300, 16, 22
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f   -- built on first use

local function R() return GP.Restock end
local function coins(v) return C_CurrencyInfo.GetCoinTextureString(v) end

local function icon(id)
    local ok, _, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, id)
    if ok and not API.IsSecret(tex) and (type(tex) == "number" or type(tex) == "string") then return tex end
    return QUESTION
end

local function place()
    f:ClearAllPoints()
    local mf = rawget(_G, "MerchantFrame")
    local ok, shown = pcall(function() return mf:IsShown() end)
    if mf and ok and shown == true then
        f:SetPoint("TOPLEFT", mf, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(W, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    GP.Theme.Window(f, { header = 40 })
    f.title = GP.UI.Header(f, "Restock")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -14)
    f.rows = {}
    for i = 1, Frame.MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(W - 2 * PAD, ROW - 2)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(40 + (i - 1) * ROW))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW - 4, ROW - 4)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.text = GP.UI.Label(row, "")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.cost = GP.UI.Label(row, "", "GameFontHighlightSmall")
        row.cost:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        f.rows[i] = row
    end
    f.total = GP.UI.Label(f, "", "GameFontNormal")
    f.limits = GP.UI.Label(f, "", "GameFontDisableSmall")
    f.buy = GP.UI.Button(f, "Buy", 90, function() Frame.Buy() end)
    f.later = GP.UI.Button(f, "Not now", 90, function() Frame.Hide() end)
    f.later:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 12)
    f.buy:SetPoint("RIGHT", f.later, "LEFT", -8, 0)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Frame.NAME) end
end

-- Show the lines of visit `s` for the player to confirm.
function Frame.Ask(s, lines)
    if not f then build() end
    f.session, f.lines = s, lines
    local shown = math.min(#lines, Frame.MAX_ROWS)
    for i, row in ipairs(f.rows) do
        local l = lines[i]
        if l and i <= shown then
            row.icon:SetTexture(icon(l.id))
            row.text:SetText((l.packs * l.pack) .. " " .. R().Name(l.id))
            row.cost:SetText(coins(l.packs * l.price))
            row:Show()
        else
            row:Hide()
        end
    end
    local y = 40 + shown * ROW + 6
    f.total:ClearAllPoints()
    f.total:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    f.total:SetText("Total: " .. coins(R().Cost(lines)))
    f.limits:ClearAllPoints()
    f.limits:SetPoint("TOPLEFT", f.total, "BOTTOMLEFT", 0, -4)
    f.limits:SetText(("At most %d%% of your money and %dg this visit."):format(
        GP.Pearls.Setting(R().KEY, "budget"), GP.Pearls.Setting(R().KEY, "maxSpend")))
    f:SetHeight(y + 36 + 44)
    place()
    f:Show()
end

-- Buy, from the button's click.
function Frame.Buy()
    if not (f and f.lines) then return end
    local s, lines = f.session, f.lines
    Frame.Hide()
    R().Run(s, lines)
end

function Frame.Hide()
    if f then
        f:Hide()
        f.lines = nil
    end
end

function Frame.IsShown() return f ~= nil and f:IsShown() end
function Frame.Get() return f end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local P, key = GP.Pearls, "restock"
    local function get(name) return function() return P.Setting(key, name) end end
    local function put(name) return function(v) P.SetSetting(key, name, v) end end
    local function check(anchor, text, name, x, y)
        local cb, refresh = GP.UI.Check(panel, text, get(name), put(name))
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local function number(anchor, text, name, lo, hi, x, y)
        local box, refresh = GP.UI.Number(panel, text, get(name), put(name), lo, hi)
        box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -6)
        refreshers[#refreshers + 1] = refresh
        return box
    end

    -- Left: what, how much, how.
    local head = GP.UI.Header(panel, "What to buy")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local a = check(head, "Food", "food", -4, -6)
    a = number(a, "food to keep", "foodTarget", 0, 200, 30, -2)
    a = check(a, "Water (if you use mana)", "water", -30)
    a = number(a, "water to keep", "waterTarget", 0, 200, 30, -2)
    a = check(a, "Ammunition (hunters)", "ammo", -30)
    a = number(a, "arrows or bullets to keep", "ammoTarget", 0, 5000, 30, -2)
    a = check(a, "Class reagents (set each on the right)", "reagents", -30)

    local how = GP.UI.Header(panel, "How")
    how:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -12)
    local last, _, refreshMode = GP.UI.Radios(panel, how,
        { { "auto", "Buy when the merchant opens" }, { "ask", "Ask first" } }, get("mode"), put("mode"))
    refreshers[#refreshers + 1] = refreshMode

    local limits = GP.UI.Header(panel, "Each visit, at most")
    limits:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -4, -12)
    a = number(limits, "% of your money", "budget", 10, 100, 6, -8)
    number(a, "gold", "maxSpend", 1, 100)

    -- Right: this class's reagents.
    local class = R().Class()
    local mine = class and GP.RestockData and GP.RestockData.reagents[class]
    local rhead = GP.UI.Header(panel, "Reagents to keep")
    rhead:SetPoint("TOPLEFT", panel, "TOPLEFT", 300, 0)
    local ids = {}
    for item in pairs(mine or {}) do ids[#ids + 1] = item end
    table.sort(ids)
    local ra = rhead
    for i, item in ipairs(ids) do
        ra = number(ra, R().Name(item) .. (R().BuffyHas(item) and " (Buffy)" or ""), "r" .. item, 0, 200,
            i == 1 and 6 or 0, i == 1 and -8 or -6)
    end
    local note = GP.UI.Label(panel, #ids == 0 and "Your class has no reagents to restock."
        or "Only for the spells you know, at your highest rank. 0: never. \"(Buffy)\": Buffy restocks it.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", ra, "BOTTOMLEFT", ra == rhead and 0 or -6, -10)
    note:SetWidth(270)
    note:SetWordWrap(true)
end
