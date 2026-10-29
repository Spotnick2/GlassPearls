-- Pearls/AutoGossipFrame.lua: auto gossip's offer prompt and its
-- Configuration Panel (#47). The logic is Pearls/AutoGossip.lua.
--
-- The prompt: 'Always choose "<the option's own text>"?' with Always, Not now
-- and Never. One at a time; gone after SECONDS (as Not now); hidden for a
-- fight and offered again after it; drags and remembers where (per
-- character), top centre otherwise. It wears the session's look.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local Frame = {}
GP.AutoGossipFrame = Frame

Frame.NAME = "GlassPearlsAutoGossipPrompt"
Frame.SECONDS = 30
local W, H, PAD = 360, 112, 16

local f        -- built on first offer
local gen = 0  -- one per offer; a timer ends only its own

local function G() return GP.AutoGossip end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.autogossipPrompt
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
end

local function answer(which)
    if not (f and f.id) then return end
    local id = f.id
    f.id = nil
    f:Hide()
    G().Answer(id, which)
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
        local left, top = self:GetLeft(), self:GetTop()
        if GP.charDB and type(left) == "number" and type(top) == "number" then
            GP.charDB.autogossipPrompt = { x = left, y = top }
        end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 36 })
    f.title = GP.UI.Header(f, "Auto gossip", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -14)
    f.text = GP.UI.Label(f, "")
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.text:SetWidth(W - 2 * PAD)
    f.text:SetWordWrap(true)
    f.always = GP.UI.Button(f, "Always", 96, function() answer("always") end)
    f.always:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    GP.UI.Tooltip(f.always, "Always pick it", "From now on, this option is picked for you, on all your characters.")
    f.later = GP.UI.Button(f, "Not now", 96, function() answer("later") end)
    f.later:SetPoint("LEFT", f.always, "RIGHT", 8, 0)
    f.never = GP.UI.Button(f, "Never", 96, function() answer("never") end)
    f.never:SetPoint("LEFT", f.later, "RIGHT", 8, 0)
    GP.UI.Tooltip(f.never, "Never ask", "Don't offer this option again.")
end

-- Offer to always pick option `id` (`name`: its own text, or nil).
function Frame.Offer(id, name)
    if not f then build() end
    if f:IsShown() and f.id and f.id ~= id then return end   -- one at a time
    gen = gen + 1
    local mine = gen
    f.id = id
    f.text:SetText(name and ('Always choose "' .. name .. '"?')
        or ("Always choose option " .. id .. "?"))
    place()
    f:Show()
    C_Timer.After(Frame.SECONDS, function()
        if gen == mine and f.id == id and f:IsShown() then answer("later") end
    end)
end

-- Take the prompt away: for option `id`, or whatever it shows when nil.
function Frame.Withdraw(id)
    if not (f and f:IsShown()) or (id and f.id ~= id) then return end
    gen = gen + 1
    f.id = nil
    f:Hide()
end

-- A fight starts: hide it and give back the option it showed.
function Frame.Hold()
    if not (f and f:IsShown() and f.id) then return nil end
    local id = f.id
    Frame.Withdraw()
    return id
end

function Frame.IsShown() return f ~= nil and f:IsShown() end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local KEY, P, AG = "autogossip", GP.Pearls, GP.AutoGossip
    local head = GP.UI.Header(panel, "When an NPC has a single option")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local last, _, refreshLone = GP.UI.Radios(panel, head, {
        { "most", "Pick it, except binding your hearthstone and the spirit healer" },
        { "services", "Pick it only at a vendor, trainer, banker or flight master" },
        { "any", "Always pick it" },
        { "off", "Never pick it" },
    }, function() return P.Setting(KEY, "lone") end, function(v) P.SetSetting(KEY, "lone", v) end)
    refreshers[#refreshers + 1] = refreshLone
    local learn = GP.UI.Header(panel, "When you keep choosing the same option", "GameFontNormal")
    learn:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -4, -14)
    local offer, refreshOffer = GP.UI.Check(panel, "Offer to always pick it",
        function() return P.Setting(KEY, "offer") end, function(on) P.SetSetting(KEY, "offer", on) end,
        { tip = "Only options that never asked for a confirmation, and never binding or the spirit healer." })
    offer:SetPoint("TOPLEFT", learn, "BOTTOMLEFT", -4, -6)
    refreshers[#refreshers + 1] = refreshOffer
    local repeats, refreshRepeats = GP.UI.Number(panel, "times before offering",
        function() return P.Setting(KEY, "repeats") end, function(n) P.SetSetting(KEY, "repeats", n) end, 2, 10, 40)
    repeats:SetPoint("TOPLEFT", offer, "BOTTOMLEFT", 10, -6)
    refreshers[#refreshers + 1] = refreshRepeats
    local function nameOf(id) return AG.OptionText(id) end
    local after, alwaysList = GP.UI.SetList(panel, repeats, "Always picked", AG.ALWAYS,
        "none yet", nameOf, "option(s)")
    local _, neverList = GP.UI.SetList(panel, after, "Never offered", AG.NEVER, "none", nameOf, "option(s)")
    refreshers[#refreshers + 1] = alwaysList.refresh
    refreshers[#refreshers + 1] = neverList.refresh
    local note = GP.UI.Label(panel,
        "Never in combat, with Shift held, or while the NPC has a quest for you. Paid options, binding and talent "
            .. "resets still ask you first. Unverified until the game is live.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", neverList.prev, "BOTTOMLEFT", 0, -12)
    note:SetWidth(380)
    note:SetWordWrap(true)
    panel.alwaysList, panel.neverList = alwaysList, neverList
end

Frame._test = { frame = function() return f end }
