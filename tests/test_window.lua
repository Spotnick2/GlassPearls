-- The options window (#3): pages, two columns of sections, the `*` and
-- Reload, gear -> Configuration Panel -> Reset / Help / Back, search,
-- refresh on show, Settings, Esc.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local configured, configureArgs = 0, nil
local resets = 0
local GP = loadAddon({ pearls = false,   -- only the pearls this test registers
    before = function(GP)
        local R = GP.Pearls.Register
        R({ key = "baghelp", name = "Bag helper", desc = "Makes room in full bags.", category = "Loot & Bags",
            section = "Bags", Enable = function() end, Disable = function() end,
            defaults = { mode = "grey" }, help = "Long help text.",
            onReset = function() resets = resets + 1 end,
            configure = function(panel, refreshers)
                configured = configured + 1
                configureArgs = { panel = panel, refreshers = refreshers }
                refreshers[#refreshers + 1] = function() configureArgs.refreshed = (configureArgs.refreshed or 0) + 1 end
            end })
        R({ key = "quickloot", name = "Quick loot", desc = "Loots faster.", category = "Loot & Bags",
            section = "Loot", default = true, Enable = function() end })   -- no Disable: needs a reload to stop
        R({ key = "autorepair", name = "Auto repair", desc = "Repairs at vendors.", category = "Automation",
            section = "Vendors", Enable = function() end, Disable = function() end })
        R({ key = "oddity", name = "Oddity", category = "Weird", Enable = function() end, Disable = function() end,
            configure = function() error("panel boom") end })
    end,
})
local O, P = GP.Options, GP.Pearls
local T = O._test

-- Pages in order: Home, the categories (listed ones first), Settings.
eq(table.concat(P.Categories(), ","), "Loot & Bags,Automation,Weird", "categories in the fixed order, then the rest")
O.Open()
local win = T.win()
check(win:IsShown(), "the window opens")
eq(win:GetName(), O.NAME, "it is named (Esc needs a name)")
for _, key in ipairs({ "home", "cat:Loot & Bags", "cat:Automation", "cat:Weird", "settings" }) do
    check(T.navItems[key] ~= nil, "nav: " .. key)
end
eq(T.current(), "home", "it opens on Home")

-- Every page is a child of the window's content area and fills it, so it
-- sits in the page area and hides with the window (Codex review of #7: the
-- category pages were made before that area existed, with no parent).
local function checkPages(when)
    local body = T.body()
    check(body ~= nil and body:GetParent() == win, when .. ": the content area is the window's")
    for name, page in pairs(T.pages) do
        eq(page.frame:GetParent(), body, when .. ": page " .. name .. " is the content area's child")
        local anchored = false
        for _, p in ipairs(page.frame._points) do
            if p[1] == "ALL" and p[2] == body then anchored = true end
        end
        check(anchored, when .. ": page " .. name .. " fills the content area")
    end
end
checkPages("at open")
for _, key in ipairs({ "cat:Loot & Bags", "cat:Automation", "cat:Weird" }) do
    check(T.pages[key] ~= nil, "a page for " .. key)
end

-- Esc: our name appended to Blizzard's table, which is never replaced.
check(UISpecialFrames == WoW.uiSpecialFrames, "UISpecialFrames is the same table")
local n = 0
for _, name in ipairs(UISpecialFrames) do if name == O.NAME then n = n + 1 end end
eq(n, 1, "our name is in it once")
eq(UISpecialFrames[1], "SettingsPanel", "Blizzard's entries untouched")
win:Hide(); O.Open()
n = 0
for _, name in ipairs(UISpecialFrames) do if name == O.NAME then n = n + 1 end end
eq(n, 1, "reopening doesn't add it again")

-- A category page: a section per column, a row per pearl.
local function click(b) b:GetScript("OnClick")(b) end
click(T.navItems["cat:Loot & Bags"])
eq(T.current(), "cat:Loot & Bags", "the Loot & Bags page")
check(T.navItems["cat:Loot & Bags"].selected:IsShown(), "  highlighted")
check(not T.navItems.home.selected:IsShown(), "  Home isn't")
local page = T.pages["cat:Loot & Bags"]
eq(#page.placed, 2, "two rows")
local byKey = {}
for _, p in ipairs(page.placed) do byKey[p.key] = p end
eq(byKey.baghelp.section, "Bags", "Bag helper under Bags")
eq(byKey.quickloot.section, "Loot", "Quick loot under Loot")
check(byKey.baghelp.column ~= byKey.quickloot.column, "the two sections in two columns")
eq(byKey.baghelp.row.label:GetText(), "Bag helper", "a pearl that switches live: no *")
eq(byKey.quickloot.row.label:GetText(), "Quick loot*", "a pearl that needs a reload: *")
check(byKey.baghelp.row.gear:IsShown(), "a gear where there are options")
check(not byKey.quickloot.row.gear:IsShown(), "none where there aren't")
check(byKey.quickloot.row.check:GetChecked(), "the boxes show the state (Quick loot on by default)")

-- The tooltip explains the *.
byKey.quickloot.row.check:GetScript("OnEnter")(byKey.quickloot.row.check)
local tip = table.concat(GameTooltip._lines, "\n")
check(tip:find("Loots faster.", 1, true) and tip:find("after a reload", 1, true), "the tooltip: description and the * line")

-- Ticking a live pearl: switched, no reload needed.
local reload = T.reloadButton()
check(not reload:IsEnabled(), "Reload is disabled with nothing pending")
byKey.baghelp.row.check:SetChecked(true)
click(byKey.baghelp.row.check)
check(P.IsOn("baghelp") and P.IsLive("baghelp"), "ticking Bag helper switches it on")
check(not reload:IsEnabled(), "  no reload needed")

-- Unticking a pearl that can't stop live: Reload lights up; its click reloads.
byKey.quickloot.row.check:SetChecked(false)
click(byKey.quickloot.row.check)
check(not P.IsOn("quickloot") and P.IsLive("quickloot"), "Quick loot off, still running")
check(reload:IsEnabled(), "Reload is enabled while a change waits")
click(reload)
eq(WoW.reloads, 1, "Reload's click reloads")

-- Refused by the client (unmeasured until day one): the text replaces the button.
WoW.reloadForbidden = true
click(reload)
eq(WoW.reloads, 1, "a refused reload does nothing")
check(T.forbidden(), "  noticed through ADDON_ACTION_FORBIDDEN")
check(not reload:IsShown(), "  the button goes")
check(T.reloadText():IsShown(), "  'Type /reload' instead")
check(GP.failures["reload button"] ~= nil, "  and it's recorded")
WoW.reloadForbidden = false

-- Back on: nothing pending, the text goes too.
byKey.quickloot.row.check:SetChecked(true)
click(byKey.quickloot.row.check)
check(not T.reloadText():IsShown(), "nothing pending: no reload text")

-- Gear -> Configuration Panel, built once, in the same window.
click(byKey.baghelp.row.gear)
eq(T.current(), "config:baghelp", "the gear opens the pearl's panel")
eq(configured, 1, "  its configure ran once")
check(configureArgs.panel ~= nil and type(configureArgs.refreshers) == "table", "  with a panel and the page's refreshers")
check(T.navItems["cat:Loot & Bags"].selected:IsShown(), "  its category stays highlighted")
local cfg = T.pages["config:baghelp"]
eq(cfg.title, "Bag helper", "  titled with the pearl's name")
eq(cfg.sub, "Configuration Panel", "  'Configuration Panel' under it")
local refreshedBefore = configureArgs.refreshed
-- Reset: the settings back to defaults, onReset, and the panel re-read.
P.SetSetting("baghelp", "mode", "white")
click(cfg.reset)
eq(P.Setting("baghelp", "mode"), "grey", "Reset puts the settings back")
eq(resets, 1, "  calls onReset")
check(configureArgs.refreshed > refreshedBefore, "  and refreshes the panel")
-- Help shows and hides the long text.
check(not cfg.help:IsShown(), "Help text hidden at first")
click(cfg.helpButton)
check(cfg.help:IsShown() and cfg.help:GetText() == "Long help text.", "Help shows the pearl's help")
click(cfg.helpButton)
check(not cfg.help:IsShown(), "  and hides it")
-- Back to Main Menu: the pearl's page.
click(cfg.back)
eq(T.current(), "cat:Loot & Bags", "Back returns to the pearl's page")
click(byKey.baghelp.row.gear)
eq(configured, 1, "reopening doesn't build the panel again")

-- A panel that fails to build: recorded, and a line says so.
click(T.navItems["cat:Weird"])
local odd = T.pages["cat:Weird"].placed[1]
click(odd.row.gear)
eq(T.current(), "config:oddity", "the failing panel still opens")
check(GP.failures["pearl oddity configure"] ~= nil, "  its error is recorded")

-- Search: every pearl, by name or description, in the same layout.
local box = T.search()
box:SetText("repair")
eq(T.current(), "search", "typing searches")
local found = T.pages.search.placed
eq(#found, 1, "  one match")
eq(found[1].key, "autorepair", "  Auto repair")
box:SetText("LOOT")
eq(#T.pages.search.placed, 1, "case-insensitive")
eq(T.pages.search.placed[1].key, "quickloot", "  Quick loot")
check(not T.pages.search.empty:IsShown(), "  no 'nothing matches'")
box:SetText("zzz")
eq(#T.pages.search.placed, 0, "no match")
check(T.pages.search.empty:IsShown(), "  says so")
box:SetText("")
eq(T.current(), "cat:Weird", "clearing the search returns to the last page")
-- A nav click clears the search box.
box:SetText("bag")
click(T.navItems.home)
eq(box:GetText(), "", "a page click clears the search")

-- Every show re-reads the boxes: a change from a slash command shows.
click(T.navItems["cat:Automation"])
local ar = T.pages["cat:Automation"].placed[1].row.check
check(not ar:GetChecked(), "Auto repair off")
SlashCmdList.GLASSPEARLS("autorepair on")
check(ar:GetChecked(), "a slash command's change shows at once")

-- The panels and search made since: the same rule; and closing the window
-- hides whatever page was showing.
checkPages("after the panels and search")
local shownPage = T.pages[T.current()].frame
check(shownPage:IsVisible(), "the current page is visible")
win:Hide()
check(not shownPage:IsVisible(), "  and hides with the window")
O.Open()

-- Settings without Glass UI: no Glass switch; the sharing switch works.
click(T.navItems.settings)
local s = T.pages.settings
eq(s.useGlass, nil, "no Glass UI: no 'Use Glass UI appearance'")
check(s.share:GetChecked(), "sharing on (the library's default)")
s.share:SetChecked(false)
click(s.share)
check(not GP.AccountSync.IsEnabled(), "unticking stops sharing")

-- With Glass UI: the switch, and changing it waits for a reload.
win:Hide()
T.reset()
WoW.installGlassUI({})
O.Open("settings")
s = T.pages.settings
check(s.useGlass ~= nil, "Glass UI here: 'Use Glass UI appearance'")
check(s.useGlass:GetChecked(), "  on by default")
check(not T.reloadButton():IsEnabled(), "  nothing pending")
s.useGlass:SetChecked(false)
click(s.useGlass)
eq(GP.db.useGlassUI, false, "unticking saves the choice")
check(O.LookPending(), "  the look waits for a reload")
check(T.reloadButton():IsEnabled(), "  Reload lights up")
s.useGlass:SetChecked(true)
click(s.useGlass)
check(not O.LookPending(), "back: nothing pending")

done("test_window")
