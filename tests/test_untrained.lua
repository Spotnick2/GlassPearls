-- Untrained gear (#86): the judgement on an item tooltip's data (the slot
-- line's right side the only red side; a class and race that can still learn
-- the skill; starting and never-trainable skills left alone; secrets), the
-- recolour on the post-call's own tooltip by Blizzard's lineIndex, the note
-- (who teaches it, from which level), and the generated data's key decisions
-- (Codex's fixtures: race masks, starting-skill vetoes, NOT_TRAINABLE).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local RED, WHITE = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
-- Items: id -> class, subclass, equip location.
WoW.items[101] = { name = "Sword", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" }
WoW.items[102] = { name = "Axe", classID = 2, subclassID = 0, equipLoc = "INVTYPE_WEAPON" }
WoW.items[103] = { name = "Staff", classID = 2, subclassID = 10, equipLoc = "INVTYPE_2HWEAPON" }
WoW.items[104] = { name = "Breastplate", classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST" }
WoW.items[105] = { name = "Halberd", classID = 2, subclassID = 6, equipLoc = "INVTYPE_2HWEAPON" }
WoW.items[106] = { name = "Maul", classID = 2, subclassID = 5, equipLoc = "INVTYPE_2HWEAPON" }
WoW.items[107] = { name = "Potion", classID = 0, subclassID = 1, equipLoc = "" }

local GP = loadAddon()
local UT, P, D = GP.Untrained, GP.Pearls, GP.GearSkillData
check(P.IsOn("untrained"), "on by default")
eq(#(WoW.tooltipPostCalls[Enum.TooltipDataType.Item] or {}), 1, "one item post-call")
P.Set("untrained", false)
P.Set("untrained", true)
eq(#WoW.tooltipPostCalls[Enum.TooltipDataType.Item], 1, "  registered once, kept across off and on")

local function as(class, race, level) WoW.class, WoW.player.raceID, WoW.playerLevel = class, race, level end
-- A tooltip of ours, named like Blizzard's (its right font strings by index).
local recoloured, added
local function tooltip(name)
    recoloured, added = {}, {}
    local t = { AddLine = function(_, text, r, g, b) added[#added + 1] = { text = text, r = r, g = g, b = b } end }
    if name then
        t.GetName = function() return name end
        for i = 1, 6 do
            rawset(_G, name .. "TextRight" .. i, { SetTextColor = function(_, r, g, b) recoloured[i] = { r, g, b } end })
        end
    end
    return t
end
-- The tooltip data a weapon's tooltip carries: its name, the slot line, a level line.
local function lines(id, opts)
    opts = opts or {}
    local slot = ({ INVTYPE_WEAPON = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_CHEST = "Chest" })[WoW.items[id].equipLoc]
    local l = {
        { leftText = WoW.items[id].name, lineIndex = 1 },
        { leftText = opts.slotLeft or slot, rightText = "Type", rightColor = opts.typeColor or RED,
          leftColor = opts.slotColor, lineIndex = opts.index == nil and 2 or opts.index },
        { leftText = "Requires Level 10", leftColor = opts.levelColor or WHITE, lineIndex = 3 },
    }
    return { type = Enum.TooltipDataType.Item, id = id, lines = l }
end
local function show(tip, data)
    for _, fn in ipairs(WoW.tooltipPostCalls[Enum.TooltipDataType.Item]) do fn(tip, data) end
end

-- A human mage's first sword: yellow, and the note.
as("MAGE", 1, 20)
local tip = tooltip("GameTooltip")
show(tip, lines(101))
eq(recoloured[2] and table.concat(recoloured[2], ","), "1,1,0", "a mage's sword: the slot line's red type turned yellow")
eq(added[1] and added[1].text, "Not trained yet: a weapon master teaches One-Handed Swords.", "  and the note")
eq(added[1] and added[1].b, 0, "  in yellow")

local function untouched(label, data, name)
    tip = tooltip(name or "GameTooltip")
    show(tip, data)
    check(next(recoloured) == nil and #added == 0, label .. ": left as the client shows it")
end
untouched("a mage's axe (never learnable)", lines(102))
untouched("a mage's staff (a starting skill, red for another reason)", lines(103))
untouched("a potion", lines(107))
untouched("another red side too (the level)", lines(101, { levelColor = RED }))
untouched("the slot line's left side red", lines(101, { slotColor = RED, typeColor = WHITE }))
untouched("both sides of the slot line red", lines(101, { slotColor = RED }))
untouched("a red right side on another line than the slot's", lines(101, { slotLeft = "Something" }))
untouched("nothing red", lines(101, { typeColor = WHITE }))
local twoRight = lines(101)
table.insert(twoRight.lines, { leftText = "Durability", rightText = "0 / 50", rightColor = RED, lineIndex = 4 })
untouched("another line's right side red too", twoRight)
local twoSlots = lines(101)
table.insert(twoSlots.lines, { leftText = "One-Hand", rightText = "Type", rightColor = RED, lineIndex = 4 })
untouched("two red slot lines (only one may be red)", twoSlots)
untouched("a secret colour elsewhere (the type red)", lines(101, { levelColor = WoW.Secret("color") }))
untouched("a secret colour", lines(101, { typeColor = WoW.Secret("color") }))
local secretText = lines(101)
secretText.lines[2].leftText = WoW.Secret("text")
untouched("a secret slot text", secretText)
local secretId = lines(101)
secretId.id = WoW.Secret("id")
untouched("a secret item ID", secretId)
untouched("not tooltip data", WoW.Secret("data"))
WoW.player.raceID = WoW.Secret("race")
untouched("a secret race", lines(101))
WoW.player.raceID = 1

-- Where the recolour can't go, the note still comes.
tip = tooltip(nil)
show(tip, lines(101))
check(next(recoloured) == nil and #added == 1, "a nameless tooltip: only the note")
tip = tooltip("GameTooltip")
local noIndex = lines(101)
noIndex.lines[2].lineIndex = nil
show(tip, noIndex)
check(next(recoloured) == nil and #added == 1, "no rendered index: only the note")
tip = tooltip("GameTooltip")
show(tip, lines(101, { index = 5 }))
check(recoloured[5] ~= nil and recoloured[2] == nil, "the rendered index, not the data's position (a skipped line)")
for _, name in ipairs({ "ItemRefTooltip", "ShoppingTooltip1" }) do
    tip = tooltip(name)
    show(tip, lines(101))
    check(recoloured[2] ~= nil, name .. ": its own font string")
end

-- A warrior's plate below and at 40; a polearm below 20.
as("WARRIOR", 1, 30)
tip = tooltip("GameTooltip")
show(tip, lines(104))
eq(added[1] and added[1].text, "Not trained yet: your class trainer teaches Plate from level 40.",
    "a level-30 warrior's plate: the class trainer, from level 40")
as("WARRIOR", 1, 40)
tip = tooltip("GameTooltip")
show(tip, lines(104))
eq(added[1] and added[1].text, "Not trained yet: your class trainer teaches Plate.", "  at 40: no level")
as("WARRIOR", 1, 15)
tip = tooltip("GameTooltip")
show(tip, lines(105))
eq(added[1] and added[1].text, "Not trained yet: a weapon master teaches Polearms from level 20.",
    "a level-15 warrior's polearm: from level 20")
as("WARRIOR", 1, WoW.Secret("level"))
tip = tooltip("GameTooltip")
show(tip, lines(105))
eq(added[1] and added[1].text, "Not trained yet: a weapon master teaches Polearms from level 20.",
    "  the level unreadable: the level said anyway")
as("SHAMAN", 2, 40)
untouched("an orc shaman's two-handed mace (not trainable)", lines(106))

-- Switched off: nothing.
as("MAGE", 1, 20)
P.Set("untrained", false)
untouched("switched off", lines(101))
P.Set("untrained", true)

-- The generated data's decisions (Codex's fixtures, build 70790).
local function can(class, race, line) return D.learn[class] and D.learn[class][race] and D.learn[class][race][line] end
eq(can("MAGE", 1, 43), 0, "data: a human mage can learn swords")
eq(can("MAGE", 1, 44), nil, "  never axes")
eq(can("MAGE", 95, 43), 0, "  a Skyborne mage swords (a race mask in the second word)")
eq(can("WARRIOR", 95, 55), nil, "  a Skyborne warrior's two-handed swords: a starting skill there")
eq(can("WARRIOR", 1, 55), 0, "  a human warrior's two-handed swords: learnable")
eq(can("WARRIOR", 1, 293), 40, "  plate at 40")
eq(can("WARRIOR", 1, 229), 20, "  polearms at 20")
eq(can("HUNTER", 4, 45), nil, "  a night elf hunter's bows: a starting skill")
eq(can("HUNTER", 2, 173), nil, "  an orc hunter's daggers: a starting skill")
eq(can("SHAMAN", 2, 160), nil, "  a shaman's two-handed maces: not trainable (0x100)")
eq(can("SHAMAN", 2, 413), 40, "  a shaman's mail at 40")
eq(D.subclass[2][7], 43, "  a one-handed sword is Swords")
eq(D.subclass[4][4], 293, "  plate armor is Plate Mail")
eq(D.subclass[2][20], nil, "  fishing poles are left out")

done("test_untrained")
