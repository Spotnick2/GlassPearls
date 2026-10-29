-- The raid mark wheel's click (#34): both edges reach PreClick and PostClick,
-- exactly one acts (the release), the down edge never closes the wheel, the
-- button is disarmed between clicks, and the release's position is the
-- choice. Under every setting of the two CVars Blizzard's dispatch reads
-- (SecureTemplates.lua:802), for a mouse press and for a key press.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local M = GP.MarkWheel

local CX, CY = 500, 400
local function at(dx, dy) WoW.mouse = { x = CX + dx, y = CY + dy } end
WoW.units.mouseover = { id = "A", guid = "Creature-0-1-A" }
WoW.units.target = WoW.units.mouseover
local function open()
    WoW.marks.A = nil
    at(0, 0)
    M.OnKey()
    return M._test.button()
end

for _, keyDown in ipairs({ false, true }) do
    for _, held in ipairs({ false, true }) do
        for _, isKey in ipairs({ false, true }) do
            local label = ("ActionButtonUseKeyDown %s, KeyHeldSpell %s, %s: "):format(tostring(keyDown),
                tostring(held), isKey and "key press" or "mouse press")
            WoW.cvars.ActionButtonUseKeyDown, WoW.cvars.ActionButtonUseKeyHeldSpell = keyDown, held
            WoW.secureActions = {}
            local before = #WoW.raidCalls
            local b = open()
            at(0, 100)
            WoW.click(b, "LeftButton", true, isKey)
            eq(#WoW.secureActions, 0, label .. "the down edge does nothing")
            check(M.IsOpen() and b:IsShown(), label .. "the down edge doesn't close the wheel")
            eq(b:GetAttribute("type"), nil, label .. "still disarmed after the down edge")
            WoW.click(b, "LeftButton", false, isKey)
            eq(#WoW.secureActions, 1, label .. "exactly one action")
            check(WoW.secureActions[1] and WoW.secureActions[1].down == false, label .. "  on the release")
            eq(#WoW.raidCalls - before, 1, label .. "one mark")
            eq(WoW.marks.A, 8, label .. "  skull")
            check(not M.IsOpen() and not b:IsShown(), label .. "closed after the release")
            eq(b:GetAttribute("type"), nil, label .. "  and disarmed")
        end
    end
end
WoW.cvars = {}

-- The release's position is the choice, not the press's.
local b = open()
at(0, 100)
WoW.click(b, "LeftButton", true)
at(100, 0)
WoW.click(b, "LeftButton", false)
eq(WoW.marks.A, 2, "pressed on skull, released on circle: circle")

-- Pressed on a mark, released outside the disc: nothing.
b = open()
local before = #WoW.raidCalls
at(0, 100)
WoW.click(b, "LeftButton", true)
at(0, 170)
WoW.click(b, "LeftButton", false)
eq(#WoW.raidCalls, before, "released outside the disc: no mark")
check(not M.IsOpen(), "  closed")

-- Every mark, clockwise from the top.
local spots = { { 0, 100, 8 }, { 70, 70, 1 }, { 100, 0, 2 }, { 70, -70, 3 }, { 0, -100, 4 }, { -70, -70, 5 },
    { -100, 0, 6 }, { -70, 70, 7 } }
for _, s in ipairs(spots) do
    b = open()
    at(s[1], s[2])
    WoW.click(b, "LeftButton", true)
    WoW.click(b, "LeftButton", false)
    eq(WoW.marks.A, s[3], ("at (%d, %d): mark %d"):format(s[1], s[2], s[3]))
end

-- A middle click is not a choice.
b = open()
before = #WoW.raidCalls
at(0, 100)
WoW.click(b, "MiddleButton", true)
WoW.click(b, "MiddleButton", false)
eq(#WoW.raidCalls, before, "a middle click marks nothing")
check(not M.IsOpen(), "  and closes")

-- The unit changed between the press and the release: nothing.
b = open()
before = #WoW.raidCalls
at(0, 100)
WoW.click(b, "LeftButton", true)
WoW.units.target.guid = "Creature-0-1-B"
WoW.click(b, "LeftButton", false)
eq(#WoW.raidCalls, before, "the unit changed before the release: nothing")
WoW.units.target.guid = "Creature-0-1-A"

-- The button at a UI scale: the cursor's pixels are divided by it.
WoW.uiScale = 2
WoW.mouse = { x = CX * 2, y = CY * 2 }
M.OnKey()
b = M._test.button()
local p = b._points[#b._points]
check(p[4] == CX and p[5] == CY, "at scale 2: placed at the cursor in UI units")
WoW.mouse = { x = CX * 2, y = (CY + 100) * 2 }
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
eq(WoW.marks.A, 8, "  and the release read in UI units: skull")
WoW.uiScale = nil

-- Kept whole on screen: near a corner, the centre moves in; the choice is
-- from the actual centre.
UIParent._width, UIParent._height = 1920, 1080
WoW.marks.A = nil
WoW.mouse = { x = 10, y = 10 }
M.OnKey()
b = M._test.button()
p = b._points[#b._points]
check(p[4] == M.R_OUTER and p[5] == M.R_OUTER, "near the corner: placed whole on screen")
WoW.mouse = { x = M.R_OUTER, y = M.R_OUTER + 100 }
WoW.click(b, "LeftButton", true)
WoW.click(b, "LeftButton", false)
eq(WoW.marks.A, 8, "  the choice read from the actual centre")
UIParent._width, UIParent._height = 0, 0

eq(#WoW.forbidden, 0, "SetRaidTarget only ever from Blizzard's secure action")
done("test_markwheel_click")
