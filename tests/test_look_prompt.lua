-- Choosing the own look (#119): the Settings radios, what waits for a reload
-- (chosen is not pending: an unanswered look reads as WoW Forever), the sync
-- key core.look (the first answer travels, a received one counts as
-- chosen), and the question: 10 s after a first login while unchosen and not
-- following Glass UI, after combat, once a session; any chosen look closes or
-- cancels it; Pearl says to /reload and never calls ReloadUI.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local reloads = 0
local GP = loadAddon({ before = function() end })
ReloadUI = function() reloads = reloads + 1 end
local O, S, SS = GP.Options, GP.Settings, GP.SettingsSync
local store = GP.db.sync
local function look() return rawget(GP.db, "look") end

-- Registered for sync, right after the Glass UI switch.
check(SS.reg.keys["core.look"] ~= nil, "core.look is a sync key")
eq(SS.reg.keys["core.look"].kind, "enum", "  an enum")
eq(SS.reg.keys["core.look"].default, "forever", "  default WoW Forever")
eq(store.stamps["core.look"], nil, "an unanswered look isn't seeded")

-- The question: not before 10 s, then shown.
eq(look(), nil, "nothing chosen yet")
WoW.advance(9)
check(not (O._test.prompt() and O._test.prompt():IsShown()), "no question before 10 s")
WoW.advance(1.5)
local p = O._test.prompt()
check(p and p:IsShown(), "the question at 10 s after a first login")
eq(GP.Theme.Active(), "forever", "  in the session's look (WoW Forever while unchosen)")

-- A choice arriving by sync closes it, and nothing of ours is written.
local hi = 9999999999
SS.Receive("GPS1\nV\tcore.look\t" .. hi .. "\tPlayer-9-ZZZ\t1\tepearl", { name = "Alt" })
eq(look(), "pearl", "a received Pearl counts as chosen")
check(not p:IsShown(), "  and closes the question")
eq(store.stamps["core.look"].o, "Player-9-ZZZ", "  with the sender's stamp, not ours")
eq(reloads, 0, "  nothing reloads")
check(O.LookPending(), "  a reload waits (the session is WoW Forever)")
-- A button clicked after that writes nothing.
p.forever:GetScript("OnClick")(p.forever)
eq(look(), "pearl", "a button after a sync choice writes nothing")
eq(store.stamps["core.look"].o, "Player-9-ZZZ", "  no stamp of ours")

-- Settings: the radios, enabled while Glass UI isn't driving the look.
O.Open("settings")
local page = O._test.pages["settings"]
local radios = page.lookRadios
eq(#radios, 2, "two looks offered")
eq(radios[1].value, "forever", "  WoW Forever")
eq(radios[2].value, "pearl", "  and Pearl")
check(radios[2]:GetChecked(), "  Pearl checked")
check(radios[1]:IsEnabled(), "  enabled without Glass UI")
-- Back to the session's own look: nothing waits any more.
local before = store.stamps["core.look"]
radios[1]:GetScript("OnClick")(radios[1])
eq(look(), "forever", "Forever chosen in Settings")
check(not O.LookPending(), "  back to the session's look: no reload waiting")
check(store.stamps["core.look"] ~= before and store.stamps["core.look"].o == WoW.playerGUID, "  stamped by us")
radios[2]:GetScript("OnClick")(radios[2])
check(O.LookPending(), "Pearl again: a reload waits")
check(O._test.reloadButton():IsEnabled(), "  the Reload button says so")
O._test.win():Hide()

done("test_look_prompt")
