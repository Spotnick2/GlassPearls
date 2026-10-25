-- Bootstrap: saved settings, the login build warning, /gpearls and the options page.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Missing SavedVariables still load.
GlassPearlsDB = nil
local GP = loadAddon()
eq(type(GlassPearlsDB), "table", "missing saved variables become a table")
eq(GP.db, GlassPearlsDB, "the addon keeps the saved table")
eq(type(GlassPearlsDB.pearls), "table", "  with a pearls table")
eq(type(GlassPearlsCharDB), "table", "missing per-character saved variables become a table")
eq(type(GlassPearlsSyncDB), "table", "the sync store becomes a table")
check(not chatHas("differs from"), "no build warning on the measured build")
check(next(GP.failures) == nil, "nothing failed to load")
eq(#GP.eventFailures, 0, "every event registered")

-- The Esc > Options > AddOns page: registered once at login, and blank-proof
-- (hidden at creation, built on its first OnShow), with a button to the window.
eq(#WoW.categories, 1, "one options category")
check(WoW.categories[1].registered, "it is an AddOns category")
local panel = GP.Options._test.panel
check(not panel:IsShown(), "the page is hidden at creation")
panel:Show()
check(panel.built and panel.open, "the page builds on its first show, with an Open button")
check(not GP.Options.IsOpen(), "the window isn't open yet")
panel.open:GetScript("OnClick")(panel.open)
check(GP.Options.IsOpen(), "its button opens the window")
GP.Options._test.win():Hide()

-- /gpearls
newChat()
SlashCmdList.GLASSPEARLS("")
check(GP.Options.IsOpen(), "/gpearls opens the window")
eq(#newChat(), 0, "  and prints nothing")
SlashCmdList.GLASSPEARLS("")
check(not GP.Options.IsOpen(), "/gpearls again closes it")
SlashCmdList.GLASSPEARLS("help")
eq(#newChat(), #GP.HelpLines(), "/gpearls help prints the help list")
SlashCmdList.GLASSPEARLS("list")
local lines = newChat()
check(lines[1] and lines[1]:find("no pearls yet", 1, true), "/gpearls list without pearls")
SlashCmdList.GLASSPEARLS("failures")
lines = newChat()
check(lines[1] and lines[1]:find("no failures"), "/gpearls failures reports none")
SlashCmdList.GLASSPEARLS("version")
lines = newChat()
check(lines[1] and lines[1]:find("1.60.1.70532", 1, true), "/gpearls version names the measured build")
check(lines[1] and lines[1]:find("version dev", 1, true), "a deployed copy reports dev")
check(lines[1] and lines[1]:find("look forever", 1, true), "  and the look in use")
SlashCmdList.GLASSPEARLS("options")
check(GP.Options.IsOpen(), "/gpearls options opens the window")
GP.Options._test.win():Hide()
SlashCmdList.GLASSPEARLS("sync")
lines = newChat()
check(lines[1] and lines[1]:find("LibAccountSync-1.0", 1, true), "/gpearls sync prints the library's readout")

-- A failure recorded anywhere shows up in /gpearls failures.
GP.API.Fail("demo", "boom")
newChat()
SlashCmdList.GLASSPEARLS("failures")
lines = newChat()
check(lines[1] and lines[1]:find("demo: boom", 1, true), "/gpearls failures lists recorded failures")
GP.failures.demo = nil

-- The build warning: at a real login on another build, in a dev build only.
-- Never on /reload.
local realBuild = GetBuildInfo
GetBuildInfo = function() return "1.60.1", "99999", "Oct 20 2026", 16001 end
local function warned()
    for _, l in ipairs(newChat()) do if l:find("differs from") then return true end end
    return false
end
newChat()
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(warned(), "a dev build warns at login on another build")
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(not warned(), "never on /reload")
WoW.addonVersion = "1.2.0"
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(not warned(), "a release never warns")
eq(GP.VersionText(), "1.2.0", "a release shows its version")
WoW.addonVersion = "dev"
GetBuildInfo = realBuild

done("test_boot")
