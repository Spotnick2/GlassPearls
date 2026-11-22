-- Pearls/CampFrame.lua: camp timers' bars, countdown digits and Configuration
-- Panel (#149). The logic is Pearls/Camp.lua.
--
-- The bars: one frame, a bar per view (the bag, then the campfire), each with
-- the spell's icon, its name in the client's language (and the bag's stacks),
-- its fill over the period and the time left ("..." while waiting). Click-
-- through, draggable only during a test, its position per character; it wears
-- the session's look. The digits: our own click-through number in the middle of
-- the screen, above the centre text (Core/Notice.lua).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.CampFrame = Frame

Frame.NAME, Frame.DIGIT_NAME = "GlassPearlsCampFrame", "GlassPearlsCampCount"
Frame.WIDTH, Frame.ROW, Frame.PAD = 240, 22, 8
Frame.DEFAULT_Y = -140          -- under the middle of the screen, clear of the alerts above it
Frame.DIGIT_Y = 260             -- above the centre text (+200)
Frame.COLORS = { bag = { 0.25, 0.55, 1 }, camp = { 1, 0.55, 0.15 } }
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f, digit

local function spellName(id)
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and not API.IsSecret(n) and type(n) == "string" then return n end
end

local function icon(id)
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and not API.IsSecret(t) and (type(t) == "number" or type(t) == "string") then return t end
    return QUESTION
end

-- "1:05", "0:42"; "..." while waiting.
function Frame.TimeText(view, t)
    if not view.endsAt then return "..." end
    local left = math.max(0, math.ceil(view.endsAt - t - 1e-6))   -- 60.0000001 is 1:00
    return ("%d:%02d"):format(math.floor(left / 60), left % 60)
end

-- The label: the client's name, and the bag's stacks when known.
function Frame.Label(view)
    local name = spellName(view.id) or ""
    if view.count then name = ("%s %d/%d"):format(name, view.count, view.max) end
    return name
end

-- The fill: how far into the period (0 while waiting).
function Frame.Fill(view, t)
    if not view.endsAt or not view.span or view.span <= 0 then return 0 end
    local done = 1 - (view.endsAt - t) / view.span
    return math.max(0, math.min(1, done))
end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.camp
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, Frame.DEFAULT_Y)
    end
end

local function newRow(i)
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(Frame.WIDTH - 2 * Frame.PAD, Frame.ROW)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", Frame.PAD, -Frame.PAD - (i - 1) * (Frame.ROW + 4))
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(Frame.ROW, Frame.ROW)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 4, 0)
    r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.bar:SetStatusBarTexture(BAR_TEXTURE)
    r.bar:SetMinMaxValues(0, 1)
    r.back = r.bar:CreateTexture(nil, "BACKGROUND")
    r.back:SetAllPoints(r.bar)
    r.back:SetColorTexture(0, 0, 0, 0.5)
    r.label = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetPoint("LEFT", r.bar, "LEFT", 4, 0)
    r.time = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.time:SetPoint("RIGHT", r.bar, "RIGHT", -4, 0)
    return r
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if GP.charDB and type(x) == "number" and type(y) == "number" then GP.charDB.camp = { x = x, y = y } end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 0 })
    f.rows = {}
end

-- Show these views ({ kind, id, count, max, span, endsAt }) at time t.
function Frame.Show(views, t)
    if not f then build() end
    local n = #views
    f:SetSize(Frame.WIDTH, 2 * Frame.PAD + n * Frame.ROW + (n - 1) * 4)
    for i = 1, math.max(n, #f.rows) do
        local r, v = f.rows[i], views[i]
        if v then
            if not r then r = newRow(i); f.rows[i] = r end
            local c = Frame.COLORS[v.kind] or Frame.COLORS.bag
            r.icon:SetTexture(icon(v.id))
            r.bar:SetStatusBarColor(c[1], c[2], c[3], v.endsAt and 1 or 0.4)
            r.bar:SetValue(Frame.Fill(v, t))
            r.label:SetText(Frame.Label(v))
            r.time:SetText(Frame.TimeText(v, t))
            r.view = v
            r:Show()
        elseif r then
            r.view = nil
            r:Hide()
        end
    end
    if not f:IsShown() then place() end
    f:Show()
end

function Frame.Hide()
    if f then f:Hide() end
end

function Frame.IsShown() return f ~= nil and f:IsShown() end
function Frame.Unlock() if f then f:EnableMouse(true) end end
function Frame.Lock() if f then f:EnableMouse(false) end end

-- The countdown's number; nil hides it.
function Frame.Digit(d)
    if not d then
        if digit then digit:Hide() end
        return
    end
    if not digit then
        digit = CreateFrame("Frame", Frame.DIGIT_NAME, UIParent)
        digit:SetSize(200, 120)
        digit:SetPoint("CENTER", UIParent, "CENTER", 0, Frame.DIGIT_Y)
        digit:SetFrameStrata("HIGH")
        digit:EnableMouse(false)
        digit.text = digit:CreateFontString(nil, "OVERLAY", "GameFont_Gigantic")
        digit.text:SetPoint("CENTER", digit, "CENTER")
        digit.text:SetShadowOffset(2, -2)
    end
    digit.text:SetText(tostring(d))
    digit:Show()
end

function Frame.DigitText() return digit and digit:IsShown() and digit.text:GetText() or nil end

--------------------------------------------------------------------------------
-- The Configuration Panel: the two bars, the countdown and its sound, Test.

function Frame.Configure(panel, refreshers)
    local KEY, P = "camp", GP.Pearls
    local function check(text, name, tip)
        local cb, refresh = GP.UI.Check(panel, text,
            function() return P.Setting(KEY, name) end, function(v) P.SetSetting(KEY, name, v) end, { tip = tip })
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local head = GP.UI.Header(panel, "Bars")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local bag = check("Sleeping bag: the next Well-Rested stack", "bag",
        "While you rest in a Cozy Sleeping Bag: your stacks and the time to the next one (one a minute, up to 3).")
    bag:SetPoint("TOPLEFT", head, "BOTTOMLEFT", -4, -6)
    local camp = check("Campfire: the time to its benefits", "campfire",
        "Next to a Welcoming Campfire: the time left until its camp benefits, gone once they're given.")
    camp:SetPoint("TOPLEFT", bag, "BOTTOMLEFT", 0, -2)
    local head2 = GP.UI.Header(panel, "Countdown")
    head2:SetPoint("TOPLEFT", camp, "BOTTOMLEFT", 4, -14)
    local count = check("Count down the last 10 seconds before the bag tops you up", "countdown",
        "Before the third stack, or at 3 stacks before the minute that brings them back to 2 hours: a large "
        .. "number in the middle of the screen, then \"3/3\": time to get up.")
    count:SetPoint("TOPLEFT", head2, "BOTTOMLEFT", -4, -6)
    local sound = check("With the game's countdown sound", "sound")
    sound:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -2)
    local note = GP.UI.Label(panel,
        "After a /reload the bag's time waits for the next stack: the game doesn't say when you lay down.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", sound, "BOTTOMLEFT", 4, -10)
    note:SetWidth(480)
    note:SetWordWrap(true)
    local test = GP.UI.Button(panel, "Test", 90, function() GP.Camp.Test() end)
    test:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    panel.test = test
    panel.checks = { bag = bag, campfire = camp, countdown = count, sound = sound }
end

Frame._test = { frame = function() return f end, digit = function() return digit end }
