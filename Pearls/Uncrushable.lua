-- Pearls/Uncrushable.lua: are you uncrushable? (#19). A line in the footer of
-- the character panel's stats pane, with a tooltip, and /gpearls uncrushable
-- in chat (the "Uncrush" macro's replacement).
--
-- The math is Blizzard's own Forever paper doll (Camelot/PaperDollFrameStats.lua:
-- base enemy miss 5%, 5 skill ranks per level, 0.04% per point, crushing blows
-- from a 15-point gap). Against a boss three levels up: miss = 5 - ((level+3)*5
-- - defense) * 0.04 (clamped 0-100), and dodge, parry and block each lose 15 *
-- 0.04 = 0.6, never below 0; block is 0 without a shield. Uncrushable when the
-- four reach 100%: the usual 102.4% on the equal-level numbers. Defense is
-- UnitDefenseSkill's base + modifier, as Blizzard's panel reads it; the sheet's
-- dodge, parry and block already include it. Combat ratings are always 0 here
-- (no ratings in Vanilla), which is why the macro's defense term never moved.
-- No crushing-blow percentage is claimed: only how far short of 100% it is.
--
-- The line is addon-owned, parented to Forever's stats pane
-- (CharacterStatsPaneScrollBox, CharacterFrameMixin:GetStatsPane()), in the
-- footer under its ScrollBox; refreshed by a hooksecurefunc on
-- PaperDollFrame_UpdateStats and the stat events. Blizzard's frames, pools and
-- stat tables are never touched. Shown when a shield is equipped (Blizzard's
-- own rule for its Block row; Forever has no measured spec), or always by
-- option. Every value is checked for secrecy before any use.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local U = {}
GP.Uncrushable = U

U.KEY = "uncrushable"
U.BASE_MISS = 5.0               -- BASE_ENEMY_MISS_CHANCE
U.RANKS_PER_LEVEL = 5           -- SKILL_RANKS_PER_SKILL_LEVEL
U.PER_POINT = 0.04
U.BOSS_OFFSET = 3
U.NEED = 100
U.EPSILON = 1e-9

local events = CreateFrame("Frame")
local line, hooked

local function setting(name) return GP.Pearls.Setting(U.KEY, name) end
local function word(global, fallback)
    local v = rawget(_G, global)
    return type(v) == "string" and v ~= "" and v or fallback
end

local function num(v)
    if API.IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
    return v
end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- Everything against a +3 attacker: { level, defense, miss, dodge, parry,
-- block, total, short, uncrushable, shield, reduce }, or nil and why.
function U.Compute()
    local okL, level = call(UnitLevel, "player")
    local okD, base, mod = call(UnitDefenseSkill, "player")
    local okDo, dodge = call(GetDodgeChance)
    local okP, parry = call(GetParryChance)
    local okB, block = call(GetBlockChance)
    local PD = rawget(_G, "C_PaperDollInfo")
    local okS, shield = call(PD and PD.OffhandHasShield)
    level, base, mod = okL and num(level), okD and num(base), okD and num(mod)
    dodge, parry, block = okDo and num(dodge), okP and num(parry), okB and num(block)
    if not (level and base and mod and dodge and parry and block) then return nil, "unreadable" end
    if not okS or API.IsSecret(shield) then return nil, "unreadable" end
    shield = shield == true
    local defense = math.max(0, base + mod)
    local gap = (level + U.BOSS_OFFSET) * U.RANKS_PER_LEVEL - level * U.RANKS_PER_LEVEL
    local reduce = gap * U.PER_POINT
    local miss = clamp(U.BASE_MISS - ((level + U.BOSS_OFFSET) * U.RANKS_PER_LEVEL - defense) * U.PER_POINT, 0, 100)
    local d = math.max(0, dodge - reduce)
    local p = math.max(0, parry - reduce)
    local b = shield and math.max(0, block - reduce) or 0
    local total = miss + d + p + b
    return {
        level = level, defense = defense, miss = miss, dodge = d, parry = p, block = b,
        total = total, short = math.max(0, U.NEED - total), uncrushable = total >= U.NEED - U.EPSILON,
        shield = shield, reduce = reduce,
    }
end

-- The macro's own number, for comparison: dodge + block + parry + 5 + (the
-- defense rating bonus + 20) * 0.04 (it needs 102.4).
function U.MacroTotal()
    local ok, cr = call(GetCombatRatingBonus, rawget(_G, "CR_DEFENSE_SKILL") or 2)
    cr = ok and num(cr) or 0
    local _, dodge = call(GetDodgeChance)
    local _, parry = call(GetParryChance)
    local _, block = call(GetBlockChance)
    return (num(dodge) or 0) + (num(block) or 0) + (num(parry) or 0) + 5 + (cr + 20) * 0.04
end

local function pct(x) return ("%.2f%%"):format(x) end

-- The headline: text, r, g, b.
function U.Headline(c, why)
    if not c then
        return why == "unreadable" and API.InCombat() and "Uncrushable: stats unavailable in combat"
            or "Uncrushable: stats unavailable", 0.6, 0.6, 0.6
    end
    if c.uncrushable then return "Uncrushable (" .. pct(c.total) .. ")", 0.25, 1, 0.25 end
    return "Crushable: " .. pct(c.short) .. " short", 1, 0.55, 0.1
end

-- The tooltip's lines: { left, right }.
function U.Lines(c)
    local lines = {}
    local function add(l, r) lines[#lines + 1] = { l, r } end
    add(("Against a level %d attacker (a boss)"):format(c.level + U.BOSS_OFFSET), "")
    add(word("MISS", "Miss"), pct(c.miss))
    add(word("STAT_DODGE", "Dodge"), pct(c.dodge))
    add(word("STAT_PARRY", "Parry"), pct(c.parry))
    add(word("STAT_BLOCK", "Block"), c.shield and pct(c.block) or "no shield")
    add("Total", pct(c.total))
    add("Needs", pct(U.NEED))
    if c.uncrushable then
        add("Crushing blows are pushed off the table.", "")
    else
        add(("%s short of pushing crushing blows off the table."):format(pct(c.short)), "")
    end
    add(("%s %d. Each of dodge, parry and block counts %.1f%% less against a boss."):format(
        word("DEFENSE", "Defense"), c.defense, c.reduce), "")
    add("Shield Block and Holy Shield raise block while active.", "")
    return lines
end

--------------------------------------------------------------------------------
-- The line in the stats pane's footer

local function pane() return rawget(_G, "CharacterStatsPaneScrollBox") end

local function onEnter(self)
    local c = U.Compute()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not c then
        GameTooltip:SetText((U.Headline(nil, "unreadable")))
        GameTooltip:AddLine("The game doesn't give these values right now.", 1, 1, 1, true)
    else
        GameTooltip:SetText((U.Headline(c)))
        for _, l in ipairs(U.Lines(c)) do
            if l[2] ~= "" then GameTooltip:AddDoubleLine(l[1], l[2], 1, 0.82, 0, 1, 1, 1)
            else GameTooltip:AddLine(l[1], 0.8, 0.8, 0.8, true) end
        end
    end
    GameTooltip:Show()
end

local function ensureLine()
    if line then return line end
    local p = pane()
    if not p then return nil end
    line = CreateFrame("Frame", nil, p)
    line:SetHeight(20)
    -- The footer: the 30 pixels under the pane's ScrollBox (CharacterFrame.xml:143-147).
    line:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 6)
    line:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -30, 6)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
    line:EnableMouse(true)
    line:SetScript("OnEnter", onEnter)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return line
end

function U.Refresh()
    if not U.enabled then return end
    local f = ensureLine()
    if not f then return end
    local c, why = U.Compute()
    if c and not c.shield and not setting("always") then return f:Hide() end
    local text, r, g, b = U.Headline(c, why)
    f.text:SetText(text)
    f.text:SetTextColor(r, g, b)
    f:Show()
end

local function hook()
    if hooked or type(rawget(_G, "PaperDollFrame_UpdateStats")) ~= "function" then return end
    hooksecurefunc("PaperDollFrame_UpdateStats", function() U.Refresh() end)   -- Refresh checks it's on
    hooked = true
end

--------------------------------------------------------------------------------
-- The command

local function command()
    if not U.enabled then return API.Print("Uncrushable is off: /gpearls uncrushable on.") end
    local c, why = U.Compute()
    API.Print((U.Headline(c, why)))
    if not c then return end
    for _, l in ipairs(U.Lines(c)) do
        API.Print("  " .. l[1] .. (l[2] ~= "" and (": " .. l[2]) or ""))
    end
end

--------------------------------------------------------------------------------
-- The pearl

local STAT_EVENTS = { "UNIT_DEFENSE", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
                      "UPDATE_SHAPESHIFT_FORM", "PLAYER_LEVEL_UP", "ADDON_LOADED",
                      "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

events:SetScript("OnEvent", function(_, event)
    -- No argument is read (UNIT_AURA's can be secret; the unit events are
    -- registered for the player only).
    API.NoteCombat(event)
    if event == "ADDON_LOADED" then hook() end
    local p = pane()
    if p and p:IsShown() then U.Refresh() end
end)

local function enable()
    U.enabled = true
    API.RegisterEvents(events, STAT_EVENTS)
    for _, e in ipairs({ "UNIT_STATS", "UNIT_AURA" }) do
        local ok, registered = pcall(events.RegisterUnitEvent, events, e, "player")
        if not ok or registered == false then API.Fail("pearl uncrushable " .. e, ok and "refused" or registered) end
    end
    hook()
    U.Refresh()
end

local function disable()
    U.enabled = false
    events:UnregisterAllEvents()
    if line then line:Hide() end
end

GP.Pearls.Register({
    key = U.KEY,
    name = "Uncrushable",
    desc = "On the character panel: whether you are uncrushable against a boss, with the numbers in its tooltip.",
    help = "A line at the bottom of the character panel's stats says whether a boss three levels above you can "
        .. "crush you: miss, dodge, parry and block against it must reach 100% (the usual 102.4% rule). Shown "
        .. "when you carry a shield, or always if you prefer. /gpearls uncrushable prints it in chat.",
    default = true,
    category = "Combat",
    section = "Tanking",
    defaults = { always = false },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers)
        local cb, refresh = GP.UI.Check(panel, "Show it without a shield",
            function() return setting("always") end, function(on) GP.Pearls.SetSetting(U.KEY, "always", on) end,
            { tip = "Without a shield, block counts as 0, so the table can't usually be filled." })
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", -4, 0)
        refreshers[#refreshers + 1] = refresh
        local note = GP.UI.Label(panel,
            "The line sits at the bottom of the stats on the character panel (C). Its tooltip shows miss, dodge, "
                .. "parry and block against a boss three levels above you.", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 4, -8)
        note:SetWidth(380)
        note:SetWordWrap(true)
    end,
    onSettingChanged = function() if U.enabled then U.Refresh() end end,
    commands = { uncrushable = { help = "- whether you are uncrushable, and the numbers", run = command } },
})

U._test = { events = events, line = function() return line end }
