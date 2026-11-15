-- The look question's cases (#119), each from a fresh first login: Forever
-- and Pearl answers, combat, closed unanswered, and when it isn't asked.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local reloads = 0
local GP = loadAddon()
ReloadUI = function() reloads = reloads + 1 end
local O, SS = GP.Options, GP.SettingsSync
local store = GP.db.sync
local function look() return rawget(GP.db, "look") end
local function shown() local p = O._test.prompt() return p ~= nil and p:IsShown() end

-- A fresh first login with nothing chosen.
local function login(chosen)
    O._test.resetPrompt()
    GP.db.look = chosen
    store.stamps["core.look"] = nil
    newChat()
    WoW.fire("PLAYER_ENTERING_WORLD", true, false)
end

-- Forever: saved, stamped (the first answer travels), nothing waits, closed.
login(nil)
WoW.advance(10.5)
check(shown(), "asked")
local p = O._test.prompt()
p.forever:GetScript("OnClick")(p.forever)
eq(look(), "forever", "Forever: saved")
check(store.stamps["core.look"] and store.stamps["core.look"].o == WoW.playerGUID, "  stamped: it travels")
check(not O.LookPending(), "  nothing waits for a reload")
check(not shown(), "  closed")
check(not chatHas("Pearl is saved"), "  no /reload line")

-- Pearl: saved and stamped once, closed, one /reload line, never ReloadUI.
login(nil)
WoW.advance(10.5)
local seq = store.seq
p.pearl:GetScript("OnClick")(p.pearl)
eq(look(), "pearl", "Pearl: saved")
eq(store.seq, seq + 1, "  stamped once")
check(not shown(), "  closed")
check(chatHas("Pearl is saved; type /reload to apply."), "  says to /reload")
eq(reloads, 0, "  never calls ReloadUI")
check(O.LookPending(), "  a reload waits")
newChat()
O.Refresh()
check(not shown() and #newChat() == 0, "an unrelated refresh afterwards: nothing")
-- A later Forever from Settings: stays closed, no new line, nothing waits.
GP.Settings.SetLook("forever")
check(not shown() and #newChat() == 0, "a later Forever: still closed, no new line")
check(not O.LookPending(), "  back to the session's look: nothing waits")

-- Combat: deferred, shown after; a choice meanwhile cancels it.
login(nil)
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.advance(10.5)
check(not shown() and O._test.promptPending(), "in combat at 10 s: deferred")
WoW.fire("PLAYER_REGEN_ENABLED")
check(shown(), "  shown after the fight")
login(nil)
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.advance(10.5)
GP.Settings.SetLook("pearl")
check(not O._test.promptPending(), "a choice during the wait cancels it")
WoW.fire("PLAYER_REGEN_ENABLED")
check(not shown(), "  nothing shown after the fight")

-- Closed unanswered: nothing saved; never twice in a session.
login(nil)
WoW.advance(10.5)
O._test.prompt():Hide()
eq(look(), nil, "closed unanswered: nothing saved")
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
WoW.advance(10.5)
check(not shown(), "  not asked again this session")

-- Not asked: a reload, a chosen look, a choice arriving within the 10 s.
O._test.resetPrompt()
GP.db.look = nil
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
WoW.advance(10.5)
check(not shown(), "a reload doesn't ask")
login("forever")
WoW.advance(10.5)
check(not shown(), "a chosen look isn't asked")
login(nil)
WoW.advance(5)
GP.db.look = "pearl"          -- arrived (by sync) before the 10 s
WoW.advance(5.5)
check(not shown(), "a look chosen within the 10 s: not asked")

-- Glass UI driving the look: not asked, the radios disabled, an own look received isn't pending.
local following = GP.Theme.Following
GP.Theme.Following = function() return true end
login(nil)
WoW.advance(10.5)
check(not shown(), "following Glass UI: not asked")
GP.Settings.SetLook("pearl")
check(not GP.Options.LookPending(), "  an own look chosen while following: no reload waiting")
GP.Theme.Following = following

-- The radios follow the "Use Glass UI appearance" box at once, labels greyed too (the owner).
WoW.installGlassUI({})
GP.db.useGlassUI = true
O.Open("settings")
local page = O._test.pages["settings"]
local radios, box = page.lookRadios, page.useGlass
local function label(rb) return rb.text or rb.label end
check(box and box:GetChecked(), "the Glass UI box, ticked")
check(not radios[1]:IsEnabled() and not radios[2]:IsEnabled(), "  the radios disabled")
eq(label(radios[1])._fontObject, "GameFontDisable", "  their labels greyed")
check(page.lookNote:GetText():find("Set in Glass UI", 1, true), "  'Set in Glass UI'")
box:SetChecked(false)
box:GetScript("OnClick")(box)
check(radios[1]:IsEnabled() and radios[2]:IsEnabled(), "unticked: the radios enabled at once")
eq(label(radios[2])._fontObject, "GameFontHighlight", "  their labels bright")
check(page.lookNote:GetText():find("without Glass UI", 1, true), "  the note says so")
box:SetChecked(true)
box:GetScript("OnClick")(box)
check(not radios[2]:IsEnabled(), "ticked again: disabled again")
O._test.win():Hide()

done("test_look_prompt_cases")
