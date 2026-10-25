-- Pearls/FixateFrame.lua: the fixate alert's frame and its Configuration
-- Panel (#17). The logic is Pearls/Fixate.lua.
--
-- The alert: the spell's icon, its name in the client's language
-- (C_Spell.GetSpellName), and a countdown from the aura's own expiration time
-- (none for an aura without one). Above the centre by default; it can be
-- dragged during a test (/gpearls fixate test) and remembers where, per
-- character. Click-through otherwise. It wears the session's look.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.FixateFrame = Frame

Frame.NAME = "GlassPearlsFixateFrame"
Frame.SIZES = { small = 48, normal = 72, large = 110 }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f   -- built on first show

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

function Frame.SpellName(id)
    local ok, n = pcall(C_Spell.GetSpellName, id)
    return ok and plain(n, "string") or nil
end

local function icon(id)
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and not API.IsSecret(t) and (type(t) == "number" or type(t) == "string") then return t end
    return QUESTION
end

-- The countdown's text: tenths under 10 s, whole seconds above.
function Frame.CountdownText(remaining)
    if remaining < 10 then return ("%.1f"):format(remaining) end
    return ("%d"):format(math.floor(remaining + 0.5))
end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.fixate
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    end
end

local function onUpdate(self)
    local a = self.alert
    if not a then return end
    if a.expiration and a.expiration > 0 then
        local remaining = a.expiration - GetTime()
        if remaining <= 0 then return GP.Fixate.Expired() end
        self.countdown:SetText(Frame.CountdownText(remaining))
    else
        self.countdown:SetText("")
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
        if GP.charDB and type(x) == "number" and type(y) == "number" then
            GP.charDB.fixate = { x = x, y = y }
        end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 0 })
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.name:SetTextColor(1, 0.2, 0.1)
    f.countdown = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    f.countdown:SetTextColor(1, 0.13, 0.04)
    f:SetScript("OnUpdate", onUpdate)
end

-- Show an alert { id, expiration (0: none), duration, test }.
function Frame.Show(alert)
    if not f then build() end
    local size = Frame.SIZES[GP.Pearls.Setting("fixate", "size")] or Frame.SIZES.normal
    f:SetSize(size + 220, size + 24)
    f.icon:SetSize(size, size)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("LEFT", f, "LEFT", 12, 0)
    f.icon:SetTexture(icon(alert.id))
    f.name:ClearAllPoints()
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -4)
    -- The client's own name for the spell: no English word of ours.
    f.name:SetText(Frame.SpellName(alert.id) or "")
    f.countdown:ClearAllPoints()
    f.countdown:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 12, 4)
    f.alert = alert
    onUpdate(f)
    place()
    f:Show()
end

function Frame.Hide()
    if not f then return end
    f.alert = nil
    f:EnableMouse(false)
    f:Hide()
end

function Frame.IsShown() return f ~= nil and f:IsShown() end

-- During a test: draggable.
function Frame.Unlock()
    if f then f:EnableMouse(true) end
end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local KEY, P = "fixate", GP.Pearls
    local function check(anchor, text, name, tip, x, y)
        local cb, refresh = GP.UI.Check(panel, text,
            function() return P.Setting(KEY, name) end, function(on) P.SetSetting(KEY, name, on) end, { tip = tip })
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local head = GP.UI.Header(panel, "When a mob fixates on you")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local a = check(head, "Play a sound", "sound",
        "Played by the game itself when it allows it, even in combat; otherwise by Glass Pearls when the alert shows.",
        -4, -6)
    a = check(a, "Show the alert", "alert", "The spell's icon, its name in your game's language and a countdown.")
    local sizeHead = GP.UI.Header(panel, "Alert size", "GameFontNormal")
    sizeHead:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -12)
    local last, _, refreshSize = GP.UI.Radios(panel, sizeHead,
        { { "small", "Small" }, { "normal", "Normal" }, { "large", "Large" } },
        function() return P.Setting(KEY, "size") end, function(v) P.SetSetting(KEY, "size", v) end)
    refreshers[#refreshers + 1] = refreshSize
    local test = GP.UI.Button(panel, "Test", 90, function() GP.Fixate.Test() end)
    test:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
    GP.UI.Tooltip(test, "Show a test alert", "For a few seconds; drag it where you want it.")
    local note = GP.UI.Label(panel,
        "The game hides most aura details during combat. The alert shows only when the game says the fixate "
            .. "is there; /gpearls fixate tells what the game allowed. Unverified in combat until the game is live.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
    panel.test = test
end

Frame._test = { frame = function() return f end }
