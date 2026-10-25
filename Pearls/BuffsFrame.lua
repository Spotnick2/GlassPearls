-- Pearls/BuffsFrame.lua: the buff alerts' frame and Configuration Panel (#21).
-- The logic is Pearls/Buffs.lua.
--
-- One frame, a row of slots: one per buff shown, each with the spell's icon,
-- its name in the client's language, its time left ("~" when estimated) and
-- "from <name>" when known. An optional pulse on the icons. Below the fixate
-- alert by default (centres 170 apart: neither can cover the other at any
-- size), draggable during a test, its position per character. Click-through
-- otherwise; it wears the session's look.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.BuffsFrame = Frame

Frame.NAME = "GlassPearlsBuffsFrame"
Frame.SIZES = { small = 36, normal = 48, large = 64 }
Frame.DEFAULT_Y = 90           -- the fixate alert's centre is at 260
Frame.SLOT_W = 120
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f

local function setting(name) return GP.Pearls.Setting("buffs", name) end

local function spellName(id)
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and not API.IsSecret(n) and type(n) == "string" then return n end
end

local function icon(id)
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and not API.IsSecret(t) and (type(t) == "number" or type(t) == "string") then return t end
    return QUESTION
end

-- "12", "4.5", "~12"; "" without a time.
function Frame.TimeText(view, t)
    if not view.expiration or view.expiration <= 0 then return "" end
    local left = view.expiration - t
    if left <= 0 then return "" end
    local text = left < 10 and ("%.1f"):format(left) or ("%d"):format(math.floor(left + 0.5))
    return (view.approximate and "~" or "") .. text
end

-- The frame's height at a size: the icon and two lines of text.
function Frame.Height(size) return size + 40 end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.buffs
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, Frame.DEFAULT_Y)
    end
end

local function newSlot(i)
    local s = CreateFrame("Frame", nil, f)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.time = s:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    s.time:SetPoint("CENTER", s.icon, "CENTER", 0, 0)
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.name:SetPoint("TOP", s.icon, "BOTTOM", 0, -2)
    s.from = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.from:SetPoint("TOP", s.name, "BOTTOM", 0, -1)
    s.pulse = s.icon:CreateAnimationGroup()
    s.pulse:SetLooping("BOUNCE")
    local a = s.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.55)
    a:SetDuration(0.6)
    return s
end

local function onUpdate(self)
    local t = GetTime()
    for _, s in ipairs(self.slots) do
        if s:IsShown() and s.view then s.time:SetText(Frame.TimeText(s.view, t)) end
    end
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if GP.charDB and type(x) == "number" and type(y) == "number" then GP.charDB.buffs = { x = x, y = y } end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 0 })
    f.slots = {}
    f:SetScript("OnUpdate", onUpdate)
end

-- Show these views: { key, id, expiration (0: none), approximate, from }.
function Frame.Show(views, opts)
    if not f then build() end
    local size = Frame.SIZES[setting("size")] or Frame.SIZES.normal
    local n = #views
    f:SetSize(math.max(1, n) * Frame.SLOT_W + 16, Frame.Height(size))
    local t = GetTime()
    for i = 1, math.max(n, #f.slots) do
        local s = f.slots[i]
        local v = views[i]
        if v then
            if not s then s = newSlot(i); f.slots[i] = s end
            s:SetSize(Frame.SLOT_W, Frame.Height(size))
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (i - 1) * Frame.SLOT_W, -4)
            s.icon:SetSize(size, size)
            s.icon:ClearAllPoints()
            s.icon:SetPoint("TOP", s, "TOP", 0, 0)
            s.icon:SetTexture(icon(v.id))
            -- The client's own name for the spell: no English word of ours.
            s.name:SetText(spellName(v.id) or "")
            s.from:SetText(v.from and ("from " .. v.from) or "")
            s.view = v
            s.time:SetText(Frame.TimeText(v, t))
            if setting("pulse") then s.pulse:Play() else s.pulse:Stop() end
            s:Show()
        elseif s then
            s.view = nil
            s.pulse:Stop()
            s:Hide()
        end
    end
    place()
    f:Show()
end

function Frame.Hide()
    if not f then return end
    f:EnableMouse(false)
    f:Hide()
end

function Frame.IsShown() return f ~= nil and f:IsShown() end
function Frame.Unlock() if f then f:EnableMouse(true) end end

--------------------------------------------------------------------------------
-- The Configuration Panel: each buff and its sound, the alert, pulse, size, Test.

local LABELS = {
    clearcasting = 12536, innervate = 29166, powerinfusion = 10060,
    protection = 1022, sacrifice = 6940, freedom = 1044,
}

function Frame.Configure(panel, refreshers)
    local KEY, P = "buffs", GP.Pearls
    local function check(text, name, tip)
        local cb, refresh = GP.UI.Check(panel, text,
            function() return P.Setting(KEY, name) end, function(v) P.SetSetting(KEY, name, v) end, { tip = tip })
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local head = GP.UI.Header(panel, "Alert me for")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local last = head
    panel.entryChecks, panel.soundChecks = {}, {}
    for i, e in ipairs(GP.Buffs.ENTRIES) do
        local name = spellName(LABELS[e.key] or e.ids[1]) or e.key
        local cb = check(name, e.key)
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", i == 1 and -4 or 0, i == 1 and -6 or -2)
        local snd = check("sound", e.key .. "Sound", "Played by the game itself when it allows it, even in combat.")
        snd:SetPoint("LEFT", cb, "LEFT", 220, 0)
        panel.entryChecks[i], panel.soundChecks[i] = cb, snd
        last = cb
    end
    local look = GP.UI.Header(panel, "The alert")
    look:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4, -14)
    local alert = check("Show the alerts", "alert")
    alert:SetPoint("TOPLEFT", look, "BOTTOMLEFT", -4, -6)
    local pulse = check("Pulse", "pulse")
    pulse:SetPoint("LEFT", alert, "LEFT", 220, 0)
    local sizeLast, _, refreshSize = GP.UI.Radios(panel, alert,
        { { "small", "Small" }, { "normal", "Normal" }, { "large", "Large" } },
        function() return P.Setting(KEY, "size") end, function(v) P.SetSetting(KEY, "size", v) end)
    refreshers[#refreshers + 1] = refreshSize
    local test = GP.UI.Button(panel, "Test", 90, function() GP.Buffs.Test() end)
    test:SetPoint("TOPLEFT", sizeLast, "BOTTOMLEFT", 0, -10)
    local note = GP.UI.Label(panel,
        "The game hides most aura details in combat: the alert shows when the game says the buff is there "
            .. "(\"~\" marks an estimated time). /gpearls buffs tells what the game allowed.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -8)
    note:SetWidth(380)
    note:SetWordWrap(true)
    panel.test = test
end

Frame._test = { frame = function() return f end }
