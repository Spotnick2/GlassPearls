-- Pearls/PaladinTank.lua: paladin tank reminders (#22). Out of combat, for a
-- paladin who knows Righteous Fury: "Righteous Fury is off" and a heads-up
-- before it ends. In combat the game hides auras, so these hide; Blizzard's
-- Cooldown Manager (Forever's paladin set tracks Righteous Fury, with
-- client-drawn alerts) is the in-combat half, and the help points to it.
-- There is no Salvation reminder any more: the client removed Salvation
-- (1038) and Mass Salvation (25895) in build 70862 (#98).
--
-- Every client language: spell IDs only, the client's own spell names; the
-- paladin by classFile, never a class name. Righteous Fury is 25780 (and
-- 407627, a rune variant; 407628 isn't Fury). The reads are
-- Core/AuraAlert.lua's three answers: "off" needs both Fury IDs proven
-- absent, and an unknown read changes nothing (the reminder is last
-- observed). Cleared and read again after a death. No client sounds: they
-- can't follow these gates. Unverified until 2026-11-04.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local AA = GP.AuraAlert
local T = {}
GP.PaladinTank = T

T.KEY = "paladintank"
T.FURY = { 25780, 407627 }
T.SOON = 60                     -- the heads-up, seconds before Fury ends
T.TEST_SECONDS = 10
T.DEFAULT_Y = -120               -- below the buff alerts (90) and the fixate alert (260)

local events = CreateFrame("Frame")
local state = {
    fury = nil,         -- "present" | "absent" | nil (never proven); last observed
    furyExp = 0,        -- its plain expiration while present (0: none)
    lastRead = {},
    test = false,
}
T.state = state
local f

local function setting(name) return GP.Pearls.Setting(T.KEY, name) end
local function now() return GetTime() end

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

local function spellName(id)
    local ok, n = pcall(C_Spell.GetSpellName, id)
    return ok and plain(n, "string") or ("spell " .. id)
end

local function icon(id)
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and not API.IsSecret(t) and (type(t) == "number" or type(t) == "string") then return t end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- "1:05", "0:45", "59:30".
function T.Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

--------------------------------------------------------------------------------
-- The gates

function T.IsPaladin()
    local ok, _, classFile = pcall(UnitClass, "player")
    return ok and plain(classFile, "string") == "PALADIN"
end

function T.KnowsFury()
    for _, id in ipairs(T.FURY) do
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and not API.IsSecret(v) and v == true then return true end
    end
    return false
end

local function shieldOK()
    if setting("noShield") then return true end
    local PD = rawget(_G, "C_PaperDollInfo")
    local ok, v = pcall(PD and PD.OffhandHasShield)
    return ok and not API.IsSecret(v) and v == true
end

-- May the reminders show right now?
function T.Active()
    return T.enabled and T.IsPaladin() and T.KnowsFury() and shieldOK() and not API.InCombat()
end

--------------------------------------------------------------------------------
-- Reading

-- present (any ID), absent (every ID proven absent), or nil (can't tell),
-- with the latest plain expiration.
local function readGroup(ids)
    local anyPresent, allAbsent, exp = false, true, 0
    for _, id in ipairs(ids) do
        local r, e = AA.Read(id)
        state.lastRead[id] = r
        if r == "present" then
            anyPresent = true
            if (e or 0) > exp then exp = e or 0 end
        end
        if r ~= "absent" then allAbsent = false end
    end
    if anyPresent then return "present", exp end
    if allAbsent then return "absent" end
    return nil
end

function T.Evaluate()
    if not T.enabled then return end
    local r, exp = readGroup(T.FURY)
    if r then state.fury, state.furyExp = r, r == "present" and exp or 0 end
    T.Render()
end

-- Forget everything (a death, switched off): the next read decides.
local function forget()
    state.fury, state.furyExp = nil, 0
end

--------------------------------------------------------------------------------
-- The lines

-- The lines to show now: { { id, text }, ... }, one at most (off, or ending
-- soon). Fury's expiry only drops the heads-up: "off" needs a proven read.
function T.Lines()
    local lines, t = {}, now()
    if state.test then
        lines[1] = { T.FURY[1], spellName(T.FURY[1]) .. " is off" }
        return lines
    end
    if not T.Active() then return lines end
    if setting("rf") then
        if state.fury == "absent" then
            lines[#lines + 1] = { T.FURY[1], spellName(T.FURY[1]) .. " is off" }
        elseif state.fury == "present" and setting("rfSoon") and state.furyExp > 0 then
            local left = state.furyExp - t
            -- At 0 it just goes: the next read says whether Fury is really off.
            if left > 0 and left <= T.SOON then
                lines[#lines + 1] = { T.FURY[1], spellName(T.FURY[1]) .. " ends in " .. T.Clock(left) }
            end
        end
    end
    return lines
end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.paladintank
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, T.DEFAULT_Y)
    end
end

local function build()
    f = CreateFrame("Frame", "GlassPearlsPaladinTankFrame", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if GP.charDB and type(x) == "number" and type(y) == "number" then GP.charDB.paladintank = { x = x, y = y } end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 0 })
    -- One row: Fury is off, or ends soon.
    local r = {}
    r.icon = f:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    r.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    f.rows = { r }
    -- The clock ticks between reads.
    f:SetScript("OnUpdate", function() T.Render() end)
end

function T.Render()
    local lines = T.Lines()
    if #lines == 0 then
        if f then f:Hide() end
        return
    end
    if not f then build() end
    for i, r in ipairs(f.rows) do
        local l = lines[i]
        if l then
            r.icon:SetTexture(icon(l[1]))
            r.text:SetText(l[2])
            r.icon:Show()
            r.text:Show()
        else
            r.icon:Hide()
            r.text:Hide()
        end
    end
    f:SetSize(340, 16 + #lines * 28)
    if not f:IsShown() then place() end
    f:Show()
end

function T.Frame() return f end

--------------------------------------------------------------------------------
-- Commands

function T.Report()
    if not T.IsPaladin() then return API.Print("Paladin tank reminders are for paladins.") end
    API.Print("Paladin tank reminders: the last reads (by spell ID, any language).")
    for _, id in ipairs(T.FURY) do
        API.Print(("  %s (%d): %s"):format(spellName(id), id, state.lastRead[id] or "not read yet"))
    end
    API.Print("  In combat: Blizzard's Cooldown Manager (Edit Mode) can alert when Righteous Fury drops.")
end

function T.Test()
    if not T.enabled then return API.Print("Paladin tank reminders are off: /gpearls paladintank on.") end
    state.test = true
    T.Render()
    f:EnableMouse(true)
    C_Timer.After(T.TEST_SECONDS, function()
        state.test = false
        if f then f:EnableMouse(false) end
        T.Render()
    end)
    API.Print("A test reminder for " .. T.TEST_SECONDS .. " s: drag it where you want it.")
end

local function command(arg)
    if arg == "test" then return T.Test() end
    T.Report()
end

--------------------------------------------------------------------------------
-- The pearl

events:SetScript("OnEvent", function(_, event)
    -- UNIT_AURA's arguments are never read (they can be secret).
    API.NoteCombat(event)
    if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then forget() end
    if API.InCombat() then return T.Render() end   -- hidden in combat
    T.Evaluate()
end)

local function enable()
    T.enabled = true
    if not T.IsPaladin() then return end   -- every other class: nothing registered, nothing shown
    local ok, registered = pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    if not ok then API.Fail("pearl paladintank UNIT_AURA", registered)
    elseif registered == false then API.Fail("pearl paladintank UNIT_AURA", "refused") end
    API.RegisterEvents(events, { "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED",
                                 "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" })
    T.Evaluate()
end

local function disable()
    T.enabled = false
    events:UnregisterAllEvents()
    forget()
    state.test = false
    if f then f:Hide() end
end

GP.Pearls.Register({
    key = T.KEY,
    name = "Paladin tank reminders",
    desc = "Out of combat: Righteous Fury is off, or about to end.",
    help = "For a paladin who knows Righteous Fury, with a shield: out of combat, a reminder when Righteous Fury "
        .. "is off, and a heads-up a minute before it ends. Hidden in combat, where the game hides auras: "
        .. "Blizzard's Cooldown Manager (Edit Mode) can alert when Righteous Fury drops. No group needed. "
        .. "/gpearls paladintank test shows the reminder to place it.",
    default = true,
    category = "Combat",
    section = "Tanking",
    defaults = { rf = true, rfSoon = true, noShield = false },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers)
        local P = GP.Pearls
        local function check(anchor, text, name, x, y)
            local cb, refresh = GP.UI.Check(panel, text,
                function() return P.Setting(T.KEY, name) end, function(v) P.SetSetting(T.KEY, name, v) end)
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
            refreshers[#refreshers + 1] = refresh
            return cb
        end
        local head = GP.UI.Header(panel, "Out of combat, remind me when")
        head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        local a = check(head, "Righteous Fury is off", "rf", -4, -6)
        a = check(a, "Righteous Fury ends within a minute", "rfSoon")
        a = check(a, "Even without a shield", "noShield")
        local test = GP.UI.Button(panel, "Test", 90, function() T.Test() end)
        test:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -10)
        local note = GP.UI.Label(panel,
            "Hidden in combat, where the game hides auras. For an alert in combat, Blizzard's Cooldown Manager "
                .. "(Edit Mode) tracks Righteous Fury.", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -8)
        note:SetWidth(380)
        note:SetWordWrap(true)
        panel.test = test
    end,
    onSettingChanged = function() if T.enabled then T.Evaluate() end end,
    commands = { paladintank = { help = "[test] - the paladin tank reminders' last reads, or show the reminder to place it", run = command } },
})

T._test = { events = events }
