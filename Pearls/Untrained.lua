-- Pearls/Untrained.lua: untrained gear (#86). A weapon or a piece of armor you
-- can't use only because you haven't learned its skill yet (a warrior's plate
-- before 40, a mage's first sword) shows that in yellow instead of red, with a
-- note saying who teaches it, in every item tooltip (bags, vendors, loot).
--
-- The judgement, on the tooltip's own data (Codex review of the plan, #86):
-- - the item is a weapon or armor whose subclass maps to a skill line
--   (Data/GearSkills.lua's subclass), and this character's class and race can
--   still learn that line (its learn table: trainable, not a starting skill);
-- - exactly one side of one line in the tooltip data is red, and it is the
--   right side of the slot line: the line whose left text is the client's own
--   string for the item's equip location (_G[itemEquipLoc], e.g. "Two-Hand"),
--   where the client prints the gear's type ("Sword", "Plate"). Any other red
--   side (a level, a class, a reputation), even on that same line, vetoes.
--   (The client's GetItemSubClassInfo name is the long one, "One-Handed
--   Swords", not the tooltip's "Sword": the slot line is how it's found.)
-- Anything secret or unreadable: left as the client shows it.
--
-- Shown: that red text turned yellow (the post-call's own tooltip, its line by
-- Blizzard's rendered lineIndex; a nameless tooltip or a missing font string
-- only gets the note), and a yellow note line. Nothing written into the
-- tooltip data or as a field. Unmeasured in game.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local UT = {}
GP.Untrained = UT

UT.KEY = "untrained"
UT.YELLOW = { 1, 1, 0 }
UT.RED = { 1, 0.125, 0.125 }        -- RED_FONT_COLOR
UT.TOLERANCE = 0.02

local state = { hooked = false }
UT.state = state

local function data() return GP.GearSkillData end

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

-- One call's first values, or nil when it threw.
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, table.maxn(r))
end

-- A colour from tooltip data: true (red), false (not red, or absent), nil (unreadable).
local function red(c)
    if c == nil then return false end
    if API.IsSecret(c) or type(c) ~= "table" then return nil end
    local r, g, b = c.r, c.g, c.b
    if API.IsSecret(r) or API.IsSecret(g) or API.IsSecret(b) then return nil end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
    local R, t = UT.RED, UT.TOLERANCE
    return math.abs(r - R[1]) <= t and math.abs(g - R[2]) <= t and math.abs(b - R[3]) <= t
end

-- What this character could still learn for this item: skillLine, minLevel, kind, or nil.
function UT.Learnable(classID, subclassID)
    local d = data()
    local sl = d and d.subclass[classID] and d.subclass[classID][subclassID]
    if not sl then return nil end
    local _, classFile = call(UnitClass, "player")
    local _, _, raceID = call(UnitRace, "player")
    classFile, raceID = plain(classFile, "string"), plain(raceID, "number")
    local byRace = classFile and raceID and d.learn[classFile] and d.learn[classFile][raceID]
    local minLevel = byRace and byRace[sl]
    if not minLevel then return nil end
    return sl, minLevel, d.kind[classID]
end

-- The judgement on one item tooltip's data: { line, classID, subclassID, minLevel, kind } or nil.
function UT.Judge(tooltipData)
    if API.IsSecret(tooltipData) or type(tooltipData) ~= "table" then return nil end
    local id = plain(tooltipData.id, "number")
    local lines = tooltipData.lines
    if not id or API.IsSecret(lines) or type(lines) ~= "table" then return nil end
    local _, _, _, equipLoc, _, classID, subclassID = call(C_Item.GetItemInfoInstant, id)
    equipLoc, classID, subclassID = plain(equipLoc, "string"), plain(classID, "number"), plain(subclassID, "number")
    if not (equipLoc and classID and subclassID) then return nil end
    local sl, minLevel, kind = UT.Learnable(classID, subclassID)
    if not sl then return nil end
    local slot = plain(rawget(_G, equipLoc), "string")
    if not slot or slot == "" then return nil end
    local found
    for _, line in ipairs(lines) do
        if API.IsSecret(line) or type(line) ~= "table" then return nil end
        for _, side in ipairs({ "left", "right" }) do
            local isRed = red(line[side .. "Color"])
            if isRed == nil then return nil end
            if isRed then
                if found or side ~= "right" then return nil end
                local left = line.leftText
                if API.IsSecret(left) or API.IsSecret(line.rightText) or left ~= slot then return nil end
                found = line
            end
        end
    end
    if not found then return nil end
    return { line = found, classID = classID, subclassID = subclassID, minLevel = minLevel, kind = kind }
end

-- The note: who teaches it, and from which level when this character is below it.
function UT.Note(j)
    local name = plain((call(C_Item.GetItemSubClassInfo, j.classID, j.subclassID)), "string") or "it"
    local who = j.kind == "armor" and "your class trainer" or "a weapon master"
    local text = ("Not trained yet: %s teaches %s"):format(who, name)
    local level = plain((call(UnitLevel, "player")), "number")
    if j.minLevel > 0 and (not level or level < j.minLevel) then
        text = text .. (" from level %d"):format(j.minLevel)
    end
    return text .. "."
end

local function onTooltip(tooltip, tooltipData)
    if not GP.Pearls.IsOn(UT.KEY) or type(tooltip) ~= "table" then return end
    local j = UT.Judge(tooltipData)
    if not j then return end
    local Y = UT.YELLOW
    local index = plain(j.line.lineIndex, "number")
    local name = tooltip.GetName and plain((call(tooltip.GetName, tooltip)), "string")
    if index and name then
        local fs = rawget(_G, name .. "TextRight" .. index)
        if type(fs) == "table" and fs.SetTextColor then fs:SetTextColor(Y[1], Y[2], Y[3]) end
    end
    if tooltip.AddLine then tooltip:AddLine(UT.Note(j), Y[1], Y[2], Y[3], true) end
end
UT.OnTooltip = onTooltip

-- Once, at the first Enable; the callback checks the switch (a post-call can't be removed).
local function hook()
    if state.hooked then return end
    state.hooked = true
    local TDP = rawget(_G, "TooltipDataProcessor")
    local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if not (TDP and TDP.AddTooltipPostCall and kind) then
        return API.Fail("pearl untrained tooltip", "TooltipDataProcessor missing")
    end
    local ok, err = pcall(TDP.AddTooltipPostCall, kind, function(...)
        local ok2, err2 = pcall(onTooltip, ...)
        if not ok2 then API.Fail("pearl untrained tooltip", err2) end
    end)
    if not ok then API.Fail("pearl untrained tooltip", err) end
end

GP.Pearls.Register({
    key = UT.KEY,
    name = "Untrained gear",
    desc = "A weapon or armor you can't use only because you haven't learned its skill yet shows in yellow, "
        .. "not red, with a note saying who teaches it.",
    help = "When an item's only problem is a weapon or armor skill your class and race can still learn (a "
        .. "warrior's plate before level 40, a mage's first sword), its tooltip shows the gear's type in yellow "
        .. "instead of red, and a note: a weapon master teaches weapons, your class trainer armor, with the level "
        .. "when you're below it. Anything else red (a level, a class, a reputation) is left as it is, and so is "
        .. "gear your class can never use. Bags, vendors and loot alike.",
    default = true,
    category = "Loot & Bags",
    section = "Bags",
    Enable = hook,
    Disable = function() end,   -- the post-call checks the switch
})

UT._test = { red = red }
