-- The low spell ranks popup and Configuration Panel (#12): the title and line,
-- each row's text ("Rank 1 > Rank 4", buttons, stance, macro, cast), "+ N
-- more", Keep, Later, the close X, Update all (shown only with bar rows,
-- disabled by hand), Esc, the drag position, the tooltip, and the panel's
-- switches, Check now and kept list. In both looks.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- tests/test_spellranks_frame_glass.lua runs this file again with arg[1] = "glass".
local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
for _, id in ipairs({ 8042, 8044, 8045, 8046 }) do WoW.spells[id] = { name = "Earth Shock", icon = 136026 } end
for _, id in ipairs({ 8042, 8044, 8045, 8046 }) do WoW.known[id] = true end
WoW.actions = { [1] = { kind = "spell", id = 8042 }, [2] = { kind = "spell", id = 8042 } }

local GP = loadAddon()
local SR, F, P, SS = GP.SpellRanks, GP.SpellRanksFrame, GP.Pearls, GP.SettingsSync
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))
WoW.flushTimers()
local f = F._test.frame()
check(f and f:IsShown(), "the popup at login")
eq(f.title:GetText(), "Low spell ranks", "titled")
eq(f.sub:GetText(), "These action buttons use a lower rank than you know.", "  the line")
local row = f.rows[1]
check(row:IsShown(), "one row")
eq(row.text:GetText(), "Earth Shock   |cff9d9d9dRank 1|r  >  |cffffd35aRank 4|r  |cff9d9d9d(2 buttons)|r",
    "  'Earth Shock  Rank 1 > Rank 4 (2 buttons)'")
eq(row.icon._file, 136026, "  the spell's icon")
check(f.rows[2] == nil or not f.rows[2]:IsShown(), "  no second row")
eq(f.more:GetText(), "", "no '+ N more'")
check(f.update:IsShown() and f.update:IsEnabled(), "Update all, enabled")
check(f.later:IsShown(), "Later")
check(f.close ~= nil, "the close X")
local inEsc = false
for _, n in ipairs(UISpecialFrames) do if n == F.NAME then inEsc = true end end
check(inEsc, "Esc closes it (UISpecialFrames)")
-- The tooltip: the rank it would get.
row:GetScript("OnEnter")(row)
eq(GameTooltip._lines[1], "spell:8046", "the row's tooltip is the rank it would get")

-- Each kind of row.
local base = { id = 8042, best = 8046, rank = 1, bestRank = 4 }
local function with(t) local r = {} for k, v in pairs(base) do r[k] = v end for k, v in pairs(t) do r[k] = v end return r end
eq(F.RowNote(with({ kind = "bar", slots = { 1 } })), "", "one button: no note")
eq(F.RowNote(with({ kind = "bar", slots = { 1, 2, 3 }, stance = true })), "3 buttons, a stance or form bar", "buttons and a stance bar")
eq(F.RowNote(with({ kind = "macro", slots = { 3 }, macro = "Shock" })), "in a macro (Shock): edit by hand", "a macro")
eq(F.RowNote(with({ kind = "cast", slots = {} })), "was cast: not on your bars", "a cast")
-- Only macro or cast rows: no Update all; the line says "used".
F.Show({ with({ kind = "macro", slots = { 3 } }) })
check(not f.update:IsShown(), "only a macro row: no Update all")
eq(f.sub:GetText(), "These spells were used in a lower rank than you know.", "  the line says used")
-- Past MAX_ROWS: "+ N more".
local many = {}
for i = 1, F.MAX_ROWS + 3 do many[i] = with({ kind = "bar", slots = { i }, id = 8042 }) end
F.Show(many)
eq(f.more:GetText(), "+ 3 more", "'+ 3 more' past eight")
check(f.rows[F.MAX_ROWS]:IsShown(), "  eight rows")
F.Show({ many[1] })
check(not f.rows[2]:IsShown(), "fewer rows again: the rest hidden")
eq(f.more:GetText(), "", "  no '+ N more'")
-- By hand: Update all disabled, the line says how.
F.Show({ many[1] }, { byHand = true })
check(f.update:IsShown() and not f.update:IsEnabled(), "by hand: Update all shown, disabled")
check(f.sub:GetText():find("Drag the highest rank from your spellbook", 1, true), "  the line says how")

-- The buttons call the logic.
SR.Check("button")
local updated
local realUpdate = SR.Update
SR.Update = function(rows) updated = rows; return 0 end
f.update:GetScript("OnClick")(f.update)
eq(updated, f.entries, "Update all passes the rows shown")
SR.Update = realUpdate
f.rows[1].keep:GetScript("OnClick")(f.rows[1].keep)
check(SS.SetHas(SR.KEEP, 8042), "Keep keeps the row's rank")
check(not f:IsShown(), "  nothing left: the popup closes")
SS.SetRemove(SR.KEEP, 8042)
SR.Check("button")
f.later:GetScript("OnClick")(f.later)
check(not f:IsShown(), "Later closes it")
SR.Check("button")
f.close:GetScript("OnClick")(f.close)
check(not f:IsShown(), "the X closes it")

-- Dragged: remembered per character, used next time.
SR.Check("button")
f._left, f._top = 300, 700
function f:GetLeft() return self._left end
function f:GetTop() return self._top end
f:GetScript("OnDragStop")(f)
eq(GP.charDB.spellranks and GP.charDB.spellranks.x, 300, "the drag is saved per character")
SR.Later()
SR.Check("button")
local p = f._points[#f._points]
check(p and p[1] == "TOPLEFT" and p[4] == 300 and p[5] == 700, "  and used when it shows again")
SR.Later()

-- The Configuration Panel, through the options window's gear.
GP.Options.Open("cat:Combat")
local page = GP.Options._test.pages["cat:Combat"]
local prow
for _, pl in ipairs(page.placed) do if pl.key == "spellranks" then prow = pl.row end end
check(prow ~= nil, "on the Combat page")
eq(prow.label:GetText(), "Low spell ranks", "  switches live (no *)")
prow.gear:GetScript("OnClick")(prow.gear)
local content = GP.Options._test.pages["config:spellranks"].frame._children[1]
local checks, buttons = {}, {}
for _, w in ipairs(content._children) do
    if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end
    if w._template == "UIPanelButtonTemplate" then buttons[w:GetText()] = buttons[w:GetText()] or w end
end
eq(#checks, 5, "five switches")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("spellranks", "afterLearning"), false, "the first: after learning")
checks[5]:SetChecked(false)
checks[5]:GetScript("OnClick")(checks[5])
eq(P.Setting("spellranks", "macros"), false, "the last: macros")
P.ResetSettings("spellranks")
newChat()
WoW.actions = { [1] = { kind = "spell", id = 8046 } }
buttons["Check now"]:GetScript("OnClick")(buttons["Check now"])
check(chatHas("No low spell ranks on your action bars."), "Check now checks")
-- The kept list: names with their rank, Remove, Clear all.
SS.SetAdd(SR.KEEP, 8042)
SS.SetAdd(SR.KEEP, 8044)
content.refreshList()
eq(content.rows[1].label:GetText(), "Earth Shock  |cff9d9d9d(Rank 1)|r", "a kept rank: its name and rank")
check(content.rows[2].label:IsShown() and not content.rows[3].label:IsShown(), "  two rows")
content.rows[1].remove:GetScript("OnClick")(content.rows[1].remove)
eq(#SS.SetMembers(SR.KEEP), 1, "Remove takes one off")
check(content.clear:IsEnabled(), "Clear all enabled")
content.clear:GetScript("OnClick")(content.clear)
eq(#SS.SetMembers(SR.KEEP), 0, "Clear all empties it")
check(not content.clear:IsEnabled(), "  then disabled")
GP.Options._test.win():Hide()

done("test_spellranks_frame" .. (glass and " (glass)" or ""))
