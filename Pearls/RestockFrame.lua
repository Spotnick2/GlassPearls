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
-- Every line of a plan is shown (Buy buys them all, so none may be hidden,
-- audit #61): the largest reagent set of a class in Data/Restock.lua (nine, a
-- rogue's) plus water, food and ammunition. test_restock_data checks the data.
Frame.MAX_ROWS = 12
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

-- Show the lines of visit `s` for the player to confirm, under `limits`
-- (R.Limits() when the plan was made: what the text shows is what Buy runs under).
function Frame.Ask(s, lines, limits)
    if not f then build() end
    limits = limits or R().Limits()
    f.session, f.lines, f.bounds = s, lines, limits
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
    f.limits:SetText(("At most %d%% of your money and %dg this visit."):format(limits.budget, limits.maxSpend))
    f:SetHeight(y + 36 + 44)
    place()
    f:Show()
end

-- Buy, from the button's click.
function Frame.Buy()
    if not (f and f.lines) then return end
    local s, lines, limits = f.session, f.lines, f.bounds
    Frame.Hide()
    R().Run(s, lines, limits)
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

Frame.PANEL_COLUMN = 300      -- the right column's x (#107): a reagent's box and name fit right of it

function Frame.Configure(panel, refreshers)
    local P, key = GP.Pearls, "restock"
    local function get(name) return function() return P.Setting(key, name) end end
    local function put(name) return function(v) P.SetSetting(key, name, v) end end
    local function check(anchor, text, name, x, y, tip)
        local cb, refresh = GP.UI.Check(panel, text, get(name), put(name), tip)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local function number(text, name, lo, hi, width)
        local box, refresh = GP.UI.Number(panel, text, get(name), put(name), lo, hi, width)
        refreshers[#refreshers + 1] = refresh
        return box
    end
    -- A kind's switch and its target on one row (#107): the box's label says what it keeps.
    local function kind(anchor, name, title, text, hi, x, y)
        local cb = check(anchor, "", name, x, y, { title = title, tip = "Off: never bought." })
        local box = number(text, name .. "Target", 0, hi)
        box:SetPoint("LEFT", cb, "RIGHT", 8, 0)
        return cb
    end

    -- Left: what, how, how much.
    local head = GP.UI.Header(panel, "What to buy")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local a = kind(head, "food", "Food", "food to keep", 200, -4, -6)
    a = kind(a, "water", "Water (if you use mana)", "water to keep (mana users)", 200, 0, -2)
    a = kind(a, "ammo", "Ammunition (hunters)", "ammunition to keep (hunters)", 5000, 0, -2)

    local how = GP.UI.Header(panel, "How")
    how:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -12)
    local last, _, refreshMode = GP.UI.Radios(panel, how,
        { { "auto", "When the merchant opens" }, { "ask", "Ask first" } }, get("mode"), put("mode"), { across = true })
    refreshers[#refreshers + 1] = refreshMode

    -- Below the level cap (#84): food asks first by default.
    local cap = GP.UI.Header(panel, "Food below the level cap")
    cap:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -4, -12)
    local capLast, _, refreshCap = GP.UI.Radios(panel, cap,
        { { "ask", "Ask first" }, { "off", "Don't buy" }, { "buy", "As usual" } },
        get("foodUnderCap"), put("foodUnderCap"), { across = true })
    refreshers[#refreshers + 1] = refreshCap

    local limits = GP.UI.Header(panel, "Each visit, at most")
    limits:SetPoint("TOPLEFT", capLast, "BOTTOMLEFT", -4, -12)
    local budget = number("% of your money", "budget", 10, 100, 40)
    budget:SetPoint("TOPLEFT", limits, "BOTTOMLEFT", 6, -8)
    number("gold", "maxSpend", 1, 100, 40):SetPoint("LEFT", budget.label, "RIGHT", 16, 0)

    -- Right: this class's reagents.
    local class = R().Class()
    local mine = class and GP.RestockData and GP.RestockData.reagents[class]
    -- The reagents' switch heads the column (#107).
    local rhead, refreshReagents = GP.UI.Check(panel, "Class reagents to keep", get("reagents"), put("reagents"))
    rhead:SetPoint("TOPLEFT", panel, "TOPLEFT", Frame.PANEL_COLUMN - 4, 2)
    rhead.label:SetFontObject("GameFontNormal")
    GP.Theme.Accent(rhead.label)
    refreshers[#refreshers + 1] = refreshReagents
    local ids = {}
    for item in pairs(mine or {}) do ids[#ids + 1] = item end
    table.sort(ids)
    local ra = rhead
    for i, item in ipairs(ids) do
        local box = number(R().Name(item) .. (R().BuffyHas(item) and " (Buffy)" or ""), "r" .. item, 0, 200, 40)
        box:SetPoint("TOPLEFT", ra, "BOTTOMLEFT", i == 1 and 10 or 0, i == 1 and -4 or -6)
        ra = box
    end
    local note = GP.UI.Label(panel, #ids == 0 and "Your class has no reagents to restock."
        or "Only for the spells you know, at your highest rank. 0: never. \"(Buffy)\": Buffy restocks it.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", ra, "BOTTOMLEFT", ra == rhead and 4 or -6, -10)
    note:SetWidth(200)
    note:SetWordWrap(true)
end
