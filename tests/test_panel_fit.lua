-- A Configuration Panel taller than its space scrolls (#107): the panel in a
-- clipping scroll frame, inset for what sits past its edge, the scroll child
-- measured from what is shown (nested children included, hidden ones not)
-- on every show and a frame later, never shorter than the view, left alone
-- while the layout can't be read; the bar only while there is a range. And
-- UI.Radios' one-row form.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local parts = {}
local GP = loadAddon({ pearls = false,
    before = function(GP)
        GP.Pearls.Register({ key = "tall", name = "Tall", category = "Loot & Bags", section = "Bags",
            Enable = function() end, Disable = function() end,
            configure = function(panel)
                parts.top = GP.UI.Label(panel, "Top")
                parts.top:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
                parts.low = GP.UI.Label(panel, "Low")
                parts.hidden = GP.UI.Label(panel, "Hidden")
                parts.hidden:Hide()
                parts.box = CreateFrame("Frame", nil, panel)
                parts.inner = GP.UI.Label(parts.box, "Inside a child frame")
            end })
    end,
})
local O, T = GP.Options, GP.Options._test

local function bottom(w, v) w.GetBottom = function() return v end end

O.Open()
check(O.ShowConfig("tall"), "the panel opens")
local page = T.pages["config:tall"]
local scroll, holder, content = page.scroll, page.holder, page.content

-- The structure: the panel in a holder, the scroll frame's child.
eq(scroll._template, "UIPanelScrollFrameTemplate", "a scroll frame")
eq(scroll:GetParent(), page.frame, "  on the page")
eq(holder:GetParent(), scroll, "the holder is the scroll frame's")
eq(content:GetParent(), holder, "the panel is the holder's")
check(parts.top:GetParent() == content or parts.top._parent == content, "the pearl builds into the panel")
local function point(w, name)
    for _, p in ipairs(w._points) do if p[1] == name then return p end end
end
local sp, cp = point(scroll, "TOPLEFT"), point(content, "TOPLEFT")
eq(sp[4], -O.PANEL_INSET, "the scroll frame starts left of the panel")
eq(sp[5], O.PANEL_INSET, "  and above it")
eq(cp[4], O.PANEL_INSET, "the panel inset back: where it was")
eq(cp[5], -O.PANEL_INSET, "  both ways")
local br = point(scroll, "BOTTOMRIGHT")
eq(br[4], -O.PANEL_BAR, "room for the bar on the right")
eq(br[5], O.PANEL_BOTTOM, "  and above Reset and Help")

-- No geometry yet (the stubs, or a layout not resolved): left alone.
local before = holder:GetHeight()
O.FitPanel(page)
eq(holder:GetHeight(), before, "unreadable layout: the height left alone")

-- Taller than the view: the holder grows to the panel.
scroll.GetHeight = function() return 300 end
holder.GetTop = function() return 1000 end
bottom(parts.top, 980)
bottom(parts.low, 600)
bottom(parts.hidden, 100)
bottom(parts.box, 950)
O.FitPanel(page)
eq(holder:GetHeight(), 400 + 2 * O.PANEL_INSET, "taller: measured to the lowest shown part, plus the insets")
-- A hidden part never counts; a shown one in a child frame does.
bottom(parts.inner, 500)
O.FitPanel(page)
eq(holder:GetHeight(), 500 + 2 * O.PANEL_INSET, "a part inside a child frame counts")
parts.box:Hide()
O.FitPanel(page)
eq(holder:GetHeight(), 400 + 2 * O.PANEL_INSET, "  not once its frame is hidden")
parts.box:Show()
-- Shorter than the view: the view's height (nothing to scroll).
bottom(parts.low, 900)
bottom(parts.inner, 900)
O.FitPanel(page)
eq(holder:GetHeight(), 300, "shorter: the view's height")

-- Every show measures, and again a frame later (text sized by then).
bottom(parts.low, 500)
O.ShowConfig("tall")
eq(holder:GetHeight(), 500 + 2 * O.PANEL_INSET, "shown again: measured")
bottom(parts.low, 400)
WoW.advance(0)
eq(holder:GetHeight(), 600 + 2 * O.PANEL_INSET, "  and a frame later")
-- Reset runs the refreshers, the fit among them.
bottom(parts.low, 800)
page.reset:GetScript("OnClick")(page.reset)
eq(holder:GetHeight(), 300, "Reset measures too")

-- The bar: only while there is something to scroll.
local bar = scroll.ScrollBar
local onRange = scroll:GetScript("OnScrollRangeChanged")
onRange(scroll, 0, 0)
check(not bar:IsShown(), "no range: no bar")
onRange(scroll, 0, 40)
check(bar:IsShown(), "a range: the bar")
onRange(scroll, 0, 0.6)
check(not bar:IsShown(), "under a whole pixel: no bar (floored like the template)")

-- UI.Radios across: one row, each after the previous label, the row's first returned.
local value = "b"
local first, group, refresh = GP.UI.Radios(content, parts.top, { { "a", "A" }, { "b", "B" }, { "c", "C" } },
    function() return value end, function(v) value = v end, { across = true })
eq(first, group[1], "across: the first is returned, to anchor below the row")
local p1 = group[1]._points[1]
eq(p1[2], parts.top, "  the first under the anchor")
eq(p1[1], "TOPLEFT", "  by its top left")
local p2 = group[2]._points[1]
eq(p2[1], "LEFT", "  the second on the same row")
eq(p2[2], group[1].text or group[1].label, "  after the first one's label")
eq(group[3]._points[1][2], group[2].text or group[2].label, "  the third after the second's")
refresh()
check(group[2]:GetChecked() and not group[1]:GetChecked(), "  the current value checked")
group[3]:GetScript("OnClick")(group[3])
eq(value, "c", "  a click sets it")
local last, down = GP.UI.Radios(content, parts.top, { { "a", "A" }, { "b", "B" } },
    function() return value end, function(v) value = v end)
eq(last, down[2], "stacked: the last is returned")
eq(down[2]._points[1][2], down[1], "  each under the previous")

done("test_panel_fit")
