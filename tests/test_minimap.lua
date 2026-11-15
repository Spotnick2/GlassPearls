-- The glass pearl on the minimap (#121): a hand-made button on Minimap,
-- named and with btn.icon (a collector's fields), placed on the ring at the
-- saved angle and following the minimap's size; a drag that stops when the
-- button hides or leaves Minimap, before writing; the clicks, the tooltip,
-- show/hide (Settings, /gpearls minimap) saved per account; junk saved
-- fields dropped one by one.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ db = { minimap = { hide = "false", angle = "junk", extra = 1 } } })
local M = GP.Minimap
local btn = M.Button()
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
local function center()
    local p = btn._points[#btn._points]
    return p[4], p[5], p
end

-- Made at login.
check(btn ~= nil, "made at login")
eq(_G[M.NAME], btn, "  named " .. M.NAME .. " (collectors find it)")
eq(btn:GetParent(), Minimap, "  on Minimap")
check(btn.icon and btn.icon._file == M.ICON, "  btn.icon is the pearl")
check(btn:IsShown(), "  shown")
-- The junk saved fields, dropped one by one.
local saved = GP.db.minimap
eq(saved.hide, nil, "a non-boolean hide dropped")
eq(saved.angle, nil, "a non-number angle dropped")
eq(saved.extra, nil, "an unknown field dropped")
local t = M.Clean({ hide = true, angle = 45 })
check(t.hide == true and t.angle == 45, "Clean keeps a plain hide and angle")
eq(M.Clean({ angle = 0 / 0 }).angle, nil, "Clean: NaN dropped")
eq(M.Clean({ angle = math.huge }).angle, nil, "Clean: infinity dropped")
eq(M.Clean({ hide = false }).hide, nil, "Clean: hide false is the default (nil)")
eq(type(M.Clean("x")), "table", "Clean: not a table -> a table")

-- On the ring: the default angle, 198 px minimap -> radius 99 + 10.
local x, y, p = center()
eq(p[1], "CENTER", "placed by its centre")
eq(p[2], Minimap, "  on Minimap's centre")
check(near(x, 109 * math.cos(math.rad(200))) and near(y, 109 * math.sin(math.rad(200))), "  at 200 degrees on the ring")
saved.angle = 90
M.Place()
x, y = center()
check(near(x, 0) and near(y, 109), "a saved angle: 90 degrees, straight up")
-- It follows the minimap's size; an unreadable size uses Forever's 99.
Minimap:SetSize(300, 300)
Minimap:GetScript("OnSizeChanged")(Minimap, 300, 300)
x, y = center()
check(near(y, 160), "the minimap grew: re-placed on the new ring")
Minimap:SetSize(300, 198)
saved.angle = 0
M.Place()
x, y = center()
check(near(x, 160), "  its width read for the horizontal radius")
saved.angle = 90
Minimap:SetSize(0, 0)
M.Place()
x, y = center()
check(near(y, 109), "a size of 0: the fallback radius")
Minimap:SetSize(198, 198)

-- A drag: the angle follows the cursor; stopping ends it.
WoW.mouse = { x = 1000 + 50, y = 500 }       -- right of the centre (1000, 500)
btn:GetScript("OnDragStart")(btn)
check(btn.isDragging and btn:GetScript("OnUpdate") ~= nil, "a drag starts its update")
btn:GetScript("OnUpdate")(btn)
check(near(saved.angle, 0), "  the cursor to the right: angle 0")
x, y = center()
check(near(x, 109) and near(y, 0), "  and placed there")
btn:GetScript("OnDragStop")(btn)
eq(btn:GetScript("OnUpdate"), nil, "OnDragStop ends it")
check(not btn.isDragging, "  not dragging")
-- Hidden mid-drag: stopped.
btn:GetScript("OnDragStart")(btn)
btn:Hide()
eq(btn:GetScript("OnUpdate"), nil, "hidden mid-drag: stopped")
btn:Show()
eq(btn:GetScript("OnUpdate"), nil, "  and shown again: still stopped")
-- Taken by a collector mid-drag (reparented, then hidden, then shown in its bar).
local bar = CreateFrame("Frame", "SomeBar", UIParent)
btn:GetScript("OnDragStart")(btn)
btn:SetParent(bar)
btn:Hide()
btn:Show()
eq(btn:GetScript("OnUpdate"), nil, "collected mid-drag: no update left")
local before = saved.angle
WoW.mouse = { x = 1000, y = 500 + 50 }
eq(saved.angle, before, "  the cursor moving changes nothing")
-- The parent check alone: reparented without hiding, the next update stops first.
btn:SetParent(Minimap)
btn:GetScript("OnDragStart")(btn)
btn:SetParent(bar)
btn:GetScript("OnUpdate")(btn)
eq(saved.angle, before, "reparented, not hidden: the update writes nothing")
eq(btn:GetScript("OnUpdate"), nil, "  and removes itself")
check(not btn.isDragging, "  not dragging")
btn:SetParent(Minimap)
local pts = #btn._points
M.Place()
check(#btn._points >= pts, "back on Minimap: placed again")
btn:SetParent(bar)
local last = btn._points[#btn._points]
saved.angle = 45
M.Place()
eq(btn._points[#btn._points], last, "while in a bar, Place leaves it alone")
btn:SetParent(Minimap)

-- Clicks.
local O = GP.Options
btn:GetScript("OnClick")(btn, "LeftButton")
check(O.IsOpen(), "left-click opens the options")
btn:GetScript("OnClick")(btn, "LeftButton")
check(not O.IsOpen(), "  and closes them")
btn:GetScript("OnClick")(btn, "RightButton")
check(O.IsOpen() and O._test.current() == "settings", "right-click opens Settings")
-- Settings: the check reads and writes the same switch.
local page = O._test.pages["settings"]
check(page.minimap ~= nil, "Settings has 'Show the minimap button'")
check(page.minimap:GetChecked(), "  checked while shown")
local function toggle(cb) cb:SetChecked(not cb:GetChecked()); cb:GetScript("OnClick")(cb) end
toggle(page.minimap)
check(not btn:IsShown(), "  unchecked: the button hides")
eq(GP.db.minimap.hide, true, "  saved")
toggle(page.minimap)
check(btn:IsShown() and GP.db.minimap.hide == nil, "  checked again: shown, nothing saved")
O._test.win():Hide()

-- The tooltip.
btn:GetScript("OnEnter")(btn)
eq(GameTooltip._lines[1], "Glass Pearls", "the tooltip names it")
eq(#GameTooltip._lines, 4, "  with the clicks and the drag")
btn.isDragging = true
GameTooltip._lines = {}
btn:GetScript("OnEnter")(btn)
eq(#GameTooltip._lines, 0, "  none while dragging")
btn.isDragging = nil

-- The command.
newChat()
GP._test.slash("minimap")
check(not btn:IsShown() and GP.db.minimap.hide == true, "/gpearls minimap hides it")
check(chatHas("minimap button hidden"), "  and says so")
GP._test.slash("minimap")
check(btn:IsShown() and GP.db.minimap.hide == nil, "  again: shown")

done("test_minimap")
