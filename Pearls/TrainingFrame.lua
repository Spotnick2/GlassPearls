-- Pearls/TrainingFrame.lua: the training reminder's toast and its
-- Configuration Panel (#27). The logic is Pearls/Training.lua; this file draws
-- the view it gives.
--
-- The toast: "Level 24", then "New at your trainer" with a row of icons (the
-- rank in the corner, the spell's tooltip on hover), "Also waiting" in a
-- smaller row, "Your other spec" lines, the talent points to spend and the
-- cost. OK closes it; it goes by itself after SECONDS unless the mouse is on
-- it. Drags and remembers where (per character); top centre otherwise.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.TrainingFrame = Frame

Frame.NAME = "GlassPearlsTrainingFrame"
Frame.SECONDS = 30
Frame.TEST_SECONDS = 15
Frame.MAX_ICONS = 10
local W, PAD, BIG, SMALL = 440, 18, 32, 24
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f       -- built on first show
local timerGen = 0

local function T() return GP.Training end
local function setting(name) return GP.Pearls.Setting("training", name) end

local function icon(id)
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and not API.IsSecret(t) and (type(t) == "number" or type(t) == "string") then return t end
    return QUESTION
end

-- "2g 30s", with the client's coin icons when it has them.
function Frame.Money(copper)
    local CI = rawget(_G, "C_CurrencyInfo")
    if CI and CI.GetCoinTextureString then
        local ok, s = pcall(CI.GetCoinTextureString, copper)
        if ok and not API.IsSecret(s) and type(s) == "string" then return s end
    end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.trainingToast
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

-- An icon button; its spell's tooltip on hover.
local function newIcon(size)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.rank:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b:SetScript("OnEnter", function(self)
        if not self.spell then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.spell) then
            GameTooltip:SetText(T().Label({ id = self.spell }))
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(W, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if GP.charDB and type(left) == "number" and type(top) == "number" then
            GP.charDB.trainingToast = { x = left, y = top }
        end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 44 })
    f.title = GP.UI.Header(f, "")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -16)
    f.ok = GP.UI.Button(f, "OK", 70, function() Frame.Hide() end)
    f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 14)
    f.labels, f.icons, f.more = {}, { big = {}, small = {} }, {}
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Frame.NAME) end
end

-- Lay out one line of text at y; returns the next y.
local function textLine(i, text, font, y)
    local l = f.labels[i]
    if not l then
        l = GP.UI.Label(f, "", font)
        f.labels[i] = l
    end
    l:SetFontObject(font)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    l:SetWidth(W - 2 * PAD)
    l:SetText(text)
    l:Show()
    return y + 18
end

-- A row of icons at y; returns the next y.
local function iconRow(kind, list, size, y)
    local pool = f.icons[kind]
    local shown = math.min(#list, Frame.MAX_ICONS)
    for i = 1, math.max(shown, #pool) do
        local b = pool[i]
        if i <= shown then
            if not b then
                b = newIcon(size)
                pool[i] = b
            end
            local e = list[i]
            b.spell = e.id
            b.icon:SetTexture(icon(e.id))
            b.rank:SetText(T().Rank(e.id) or "")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (size + 4), -y)
            b:Show()
        elseif b then
            b.spell = nil
            b:Hide()
        end
    end
    local more = f.more[kind]
    if not more then
        more = GP.UI.Label(f, "", "GameFontHighlightSmall")
        f.more[kind] = more
    end
    more:ClearAllPoints()
    more:SetPoint("LEFT", f, "TOPLEFT", PAD + shown * (size + 4) + 4, -(y + size / 2))
    more:SetText(#list > shown and ("+" .. (#list - shown)) or "")
    more:SetShown(#list > shown)
    return y + size + 8
end

local function hideFrom(i)
    for j = i, #f.labels do f.labels[j]:Hide() end
end

local function names(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = T().Rank(e.id) end
    return out
end

-- Draw a view (Pearls/Training.lua's T.Collect). refresh: the open toast
-- read again, its timer kept.
function Frame.Show(view, refresh)
    if not f then build() end
    local word = rawget(_G, "LEVEL") or "Level"
    if view.kind == "swap" then
        f.title:SetText("Your spec changed")
    elseif view.kind == "test" then
        f.title:SetText(word .. " " .. view.level .. "  (test)")
    else
        f.title:SetText(word .. " " .. view.level)
    end
    local y, n = 46, 0
    local function line(text, font)
        n = n + 1
        y = textLine(n, text, font, y)
    end
    if #view.new > 0 then
        line("New at your trainer", "GameFontNormal")
        y = iconRow("big", view.new, BIG, y)
    else
        iconRow("big", {}, BIG, y)
    end
    if #view.waiting > 0 then
        line(#view.new > 0 and "Also waiting" or "Waiting at your trainer", "GameFontNormalSmall")
        y = iconRow("small", view.waiting, SMALL, y)
    else
        iconRow("small", {}, SMALL, y)
    end
    for _, o in ipairs(view.other) do
        local ranks = names(o.spells)
        local which = #ranks > 0 and (" (" .. (rawget(_G, "RANK") or "Rank"):lower() .. " " .. ranks[1]
            .. (#ranks > 1 and ("-" .. ranks[#ranks]) or "") .. ")") or ""
        line(("Your other spec: %s%s, as last seen"):format(T().Label({ id = o.talent }), which),
            "GameFontHighlightSmall")
    end
    if view.points then
        line(view.points == 1 and "1 talent point to spend" or (view.points .. " talent points to spend"),
            "GameFontHighlightSmall")
    end
    if setting("cost") and view.cost > 0 then
        line("About " .. Frame.Money(view.cost) .. " at the trainer", "GameFontDisableSmall")
    end
    hideFrom(n + 1)
    f:SetHeight(y + 44)
    f.view = view
    if not f:IsShown() then place() end
    f:Show()
    if not refresh then Frame.Arm(view.kind == "test" and Frame.TEST_SECONDS or Frame.SECONDS) end
end

-- Hide after `seconds`, unless the mouse is on it (then try again).
function Frame.Arm(seconds)
    timerGen = timerGen + 1
    local gen = timerGen
    C_Timer.After(seconds, function()
        if gen ~= timerGen or not (f and f:IsShown()) then return end
        if f:IsMouseOver() then return Frame.Arm(5) end
        Frame.Hide()
    end)
end

function Frame.Hide()
    timerGen = timerGen + 1
    if f then f:Hide() end
    if GP.Training then GP.Training.state.shown = nil end
end

function Frame.IsShown() return f ~= nil and f:IsShown() end
function Frame.Get() return f end

-- A sample toast to place it: your class's first trainer spells.
function Frame.Test()
    local d = GP.TrainingData and GP.TrainingData.classes[T().Class() or ""]
    if not (T().enabled and d) then
        return API.Print("Training reminder is off, or has no list for your class: /gpearls training on.")
    end
    local view = { kind = "test", level = T().Level() or 1, new = {}, waiting = {}, other = {}, cost = 0, points = 1 }
    for i, e in ipairs(d.spells) do
        if i <= 3 then view.new[#view.new + 1] = e elseif i <= 7 then view.waiting[#view.waiting + 1] = e end
    end
    for _, e in ipairs(view.new) do view.cost = view.cost + e.cost end
    for _, e in ipairs(view.waiting) do view.cost = view.cost + e.cost end
    Frame.Show(view)
    API.Print("A sample toast for " .. Frame.TEST_SECONDS .. " s: drag it where you want it.")
end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local P = GP.Pearls
    local function check(anchor, text, name, x, y)
        local cb, refresh = GP.UI.Check(panel, text,
            function() return P.Setting("training", name) end, function(v) P.SetSetting("training", name, v) end)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local head = GP.UI.Header(panel, "The toast")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local a = check(head, "When I level up", "toast", -4, -6)
    a = check(a, "Also what was already waiting", "waiting")
    a = check(a, "When my spec changes", "swap")
    a = check(a, "Talent points to spend", "points")
    a = check(a, "What it costs", "cost")
    local tips = GP.UI.Header(panel, "Tooltips")
    tips:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -12)
    a = check(tips, "Show when a spell's next ranks come", "tooltip", -4, -6)
    local test = GP.UI.Button(panel, "Test", 90, function() Frame.Test() end)
    test:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -10)
    local note = GP.UI.Label(panel,
        "Trainer lists: WhatsTraining's, by Sveng. A spell is listed only when you can learn it now: its level, "
            .. "the spells it needs and its talent. Rogue poisons need the Poisons skill, which isn't read: they "
            .. "aren't listed.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -8)
    note:SetWidth(380)
    note:SetWordWrap(true)
    panel.test = test
end
