-- Auto gossip (#47): learning from the player. Only a click on Blizzard's own
-- option button counts, and only once the pick visibly went through (a new
-- page, an allowlisted service window); a confirmation instead marks the
-- option never offered, and a named one takes it off the always list. The
-- offer, its answers and its exclusions.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local G, P, SS, FR = GP.AutoGossip, GP.Pearls, GP.SettingsSync, GP.AutoGossipFrame
P.SetSetting("autogossip", "lone", "off")    -- nothing picked for us: we watch the player

local CHAT, BINDER, HEALER = 132053, 132052, 132054
local T = Enum.PlayerInteractionType
local function opt(id, index, icon, name)
    return { id = id, index = index, icon = icon or CHAT, status = 0, name = name or ("Option " .. tostring(id)) }
end
local function counts(id)
    local c = G._test.db().counts[id]
    return c and c.n or 0
end
-- Talk to an NPC with options a (index 1) and b (index 2), and click `index`.
local function visit(a, b, index)
    WoW.openGossip({ options = { a, b } })
    WoW.flushTimers(0)
    check(WoW.playerPicks(index), "the button for index " .. index .. " exists")
end
local function nextPage()
    WoW.closeGossip(true)
    WoW.openGossip({ options = { opt(9000 + math.random(999), 1), opt(9999, 2) } })
    WoW.flushTimers(0)
end
local function bye() WoW.closeGossip(false) end

-- A click, then a new page: counted.
visit(opt(10, 1), opt(11, 2, CHAT, "Teleport me"), 2)
eq(G.state.pending and G.state.pending.id, 11, "the click is pending")
eq(counts(11), 0, "  not counted yet")
nextPage()
eq(counts(11), 1, "a new page: counted")
eq(G.state.pending, nil, "  resolved")
bye()

-- A service window from the allowlist: counted; a close alone: never.
visit(opt(10, 1), opt(11, 2), 2)
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", T.Merchant)
eq(counts(11), 2, "a merchant window: counted")
bye()
visit(opt(12, 1), opt(13, 2), 2)
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", T.Trainer)
eq(counts(13), 1, "a trainer window: counted")
bye()
visit(opt(14, 1), opt(15, 2), 2)
WoW.closeGossip(true)
WoW.flushTimers(G.PENDING_SECONDS)
eq(counts(15), 0, "a close and then silence: never counted")
eq(G.state.pending, nil, "  the pick is dropped after the wait")

-- The excluded interactions: never a sign; their confirmations still name the pick.
for _, case in ipairs({ { T.TalentMaster, "CONFIRM_TALENT_WIPE", 21 }, { T.Binder, "CONFIRM_BINDER", 22 } }) do
    visit(opt(20, 1), opt(case[3], 2), 2)
    WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", case[1])
    eq(counts(case[3]), 0, case[2] .. ": its interaction first is not a sign")
    WoW.closeGossip(true)                       -- nested: Blizzard hides the gossip first
    WoW.fire(case[2], 100, 1)
    check(G._test.db().confirms[case[3]], "  the confirmation after a close still names the pick")
    eq(counts(case[3]), 0, "  and nothing counts")
    bye()
end
visit(opt(20, 1), opt(23, 2), 2)
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", T.SpiritHealer)
WoW.flushTimers(G.PENDING_SECONDS)
eq(counts(23), 0, "a spirit healer's interaction, then nothing: discarded, not counted")
bye()
-- A confirmation later than any wait, ID-less: the pick was already dropped.
visit(opt(20, 1), opt(24, 2), 2)
WoW.flushTimers(G.PENDING_SECONDS)
WoW.fire("CONFIRM_TALENT_WIPE", 100, 1)
eq(counts(24), 0, "a late ID-less confirmation: nothing counted either way")
bye()

-- GOSSIP_CONFIRM / GOSSIP_ENTER_CODE name the option: always marked, and off
-- the always list even long after.
SS.SetAdd(G.ALWAYS, 30)
G._test.db().names[30] = "Buy a pet"
newChat()
WoW.fire("GOSSIP_CONFIRM", 30, "Pay?", 1000)
check(G._test.db().confirms[30], "GOSSIP_CONFIRM marks the option")
check(not SS.SetHas(G.ALWAYS, 30), "  and takes it off the always list")
check(chatHas("Buy a pet"), "  and says so, by its text")
SS.SetAdd(G.ALWAYS, 31)
WoW.fire("GOSSIP_ENTER_CODE", 31)
check(G._test.db().confirms[31] and not SS.SetHas(G.ALWAYS, 31), "GOSSIP_ENTER_CODE does the same")
visit(opt(20, 1), opt(32, 2), 2)
WoW.fire("GOSSIP_CONFIRM", WoW.Secret("id"), "Pay?", 1000)
check(G._test.db().confirms[32], "a confirmation whose ID is secret: the pending pick's")
bye()

-- What never counts.
local function noCount(label, fn, id)
    local before = counts(id)
    fn()
    nextPage()
    eq(counts(id), before, label)
    bye()
end
noCount("a popup's Accept (confirmed, no button): never counted", function()
    WoW.openGossip({ options = { opt(40, 1), opt(41, 2) } })
    WoW.flushTimers(0)
    C_GossipInfo.SelectOption(41, "", true)
end, 41)
noCount("a code popup's Enter (no confirmed, no button): never counted", function()
    WoW.openGossip({ options = { opt(40, 1), opt(41, 2) } })
    WoW.flushTimers(0)
    C_GossipInfo.SelectOption(41, "1234")
end, 41)
noCount("Blizzard's own lone pick: never counted", function()
    WoW.openGossip({ options = { { id = 42, index = 1, icon = CHAT, status = 0, only = true } } })
    WoW.flushTimers(0)
end, 42)
noCount("an option with a hidden ID: never counted (not even by its index)", function()
    visit(opt(43, 1), { index = 2, icon = CHAT, status = 0 }, 2)
end, 2)
noCount("out of scope (a custom frame): never counted", function()
    WoW.openGossip({ options = { opt(44, 1), opt(45, 2) }, textureKit = "kit" })
    WoW.flushTimers(0)
    WoW.playerPicks(2)
end, 45)
WoW.fire("PLAYER_REGEN_DISABLED")
noCount("in combat: never counted", function() visit(opt(46, 1), opt(47, 2), 2) end, 47)
WoW.fire("PLAYER_REGEN_ENABLED")
-- Two clicks before a sign: neither counts.
WoW.openGossip({ options = { opt(48, 1), opt(49, 2) } })
WoW.flushTimers(0)
WoW.playerPicks(1)
WoW.playerPicks(2)
nextPage()
check(counts(48) == 0 and counts(49) == 0, "two clicks before a sign: neither counted")
bye()

-- Buttons made later by scrolling are hooked; a pooled button reads its own ID.
WoW.openGossip({ options = { opt(50, 1), opt(51, 2), opt(54, 3) }, visible = 0 })
WoW.flushTimers(0)
eq(#WoW.gossipScrollBox._frames, 2, "a greeting-only view: the third button doesn't exist yet")
WoW.scrollGossip()
WoW.playerPicks(3)
nextPage()
eq(counts(54), 1, "a button created by scrolling: hooked and counted")
bye()
-- Only option buttons are hooked, never quest rows.
local questRow = WoW.newWidget("Button", WoW.gossipScrollBox)
for _, cb in ipairs(WoW.gossipScrollBox._callbacks) do cb.fn(cb.owner, questRow, { buttonType = 1 }) end
check(not G._test.hooked[questRow] and questRow._scripts.PreClick == nil, "a quest row: never hooked")
-- A refresh is not a sign.
visit(opt(55, 1), opt(56, 2), 2)
WoW.refreshGossip({ opt(55, 1), opt(56, 2), opt(57, 3) })
WoW.flushTimers(G.PENDING_SECONDS)
eq(counts(56), 0, "a refresh after a pick: not a sign, not counted")
bye()
visit(opt(52, 7), opt(53, 9), 9)
nextPage()
eq(counts(53), 1, "a pooled button with a new index: the right option")
bye()

-- The offer after `repeats` (3) picks.
local function pick(id, icon)
    visit(opt(60, 1), opt(id, 2, icon, "Take me to the faire"), 2)
    nextPage()
    bye()
end
pick(61); pick(61)
check(not FR.IsShown(), "two picks: no offer yet")
pick(61)
check(FR.IsShown(), "the third: the offer")
local f = FR._test.frame()
check(f.text:GetText():find("Take me to the faire", 1, true), "  with the option's own text")
f.always:GetScript("OnClick")(f.always)
check(SS.SetHas(G.ALWAYS, 61), "Always: on the always list")
eq(counts(61), 0, "  the count reset")
check(not FR.IsShown(), "  the prompt gone")
P.SetSetting("autogossip", "lone", "most")
local before = #WoW.gossipSelects
WoW.openGossip({ options = { opt(60, 1), opt(61, 2) } })
WoW.flushTimers(0)
check(#WoW.gossipSelects == before + 1 and WoW.gossipSelects[#WoW.gossipSelects].arg == 61,
    "  and next time it is picked for you")
bye()
P.SetSetting("autogossip", "lone", "off")
pick(62); pick(62); pick(62)
f.later:GetScript("OnClick")(f.later)
check(not SS.SetHas(G.ALWAYS, 62) and counts(62) == 0, "Not now: nothing saved, the count reset")
pick(63); pick(63); pick(63)
f.never:GetScript("OnClick")(f.never)
check(SS.SetHas(G.NEVER, 63), "Never: on the never list")
pick(63); pick(63); pick(63)
check(not FR.IsShown(), "  and never offered again")
pick(64); pick(64); pick(64)
WoW.flushTimers(FR.SECONDS)
check(not FR.IsShown() and counts(64) == 0, "unanswered for 30 s: as Not now")

-- Never offered: binder, healer, confirmed, a lone option the rule picks.
pick(65, BINDER); pick(65, BINDER); pick(65, BINDER)
check(not FR.IsShown(), "a binder option: never offered")
pick(66, HEALER); pick(66, HEALER); pick(66, HEALER)
check(not FR.IsShown(), "a spirit healer option: never offered")
G._test.db().confirms[67] = true
pick(67); pick(67); pick(67)
check(not FR.IsShown(), "an option that asked for a confirmation: never offered")
P.SetSetting("autogossip", "offer", false)
pick(68); pick(68); pick(68)
check(not FR.IsShown(), "offers switched off: none")
P.SetSetting("autogossip", "offer", true)
P.SetSetting("autogossip", "repeats", 2)
pick(69); pick(69)
check(FR.IsShown(), "repeats 2: offered on the second")
FR.Withdraw()
P.SetSetting("autogossip", "repeats", 3)
-- An offer for an option confirmed meanwhile: withdrawn.
pick(70); pick(70); pick(70)
check(FR.IsShown(), "offered")
WoW.fire("GOSSIP_CONFIRM", 70, "Pay?", 10)
check(not FR.IsShown(), "  a confirmation for it withdraws the offer")
-- Combat: the prompt goes for the fight and comes back after.
pick(71); pick(71); pick(71)
WoW.fire("PLAYER_REGEN_DISABLED")
check(not FR.IsShown(), "combat hides the prompt")
WoW.fire("PLAYER_REGEN_ENABLED")
check(FR.IsShown(), "  and it comes back after")
FR.Withdraw()
-- A pick that resolves during combat: offered after it.
pick(72); pick(72)
visit(opt(60, 1), opt(72, 2), 2)
WoW.fire("PLAYER_REGEN_DISABLED")
nextPage()
check(not FR.IsShown(), "the third pick resolving in combat: not shown")
WoW.fire("PLAYER_REGEN_ENABLED")
check(FR.IsShown() and f.id == 72, "  shown when combat ends")
bye()
FR.Withdraw()
-- The counts keep at most COUNTS_MAX entries.
local c = G._test.db().counts
for i = 1, G.COUNTS_MAX + 5 do c[200000 + i] = { n = 1, t = i } end
G.Count(300000)
local total = 0
for _ in pairs(c) do total = total + 1 end
check(total <= G.COUNTS_MAX, "counts are pruned to their cap")
check(c[200001] == nil, "  the oldest first")

-- The commands.
newChat()
WoW.openGossip({ options = { opt(80, 1, CHAT, "Hello"), opt(81, 2) } })
WoW.flushTimers(0)
P.Command("gossip").run("")
check(chatHas("ID 80, index 1, icon 132053") and chatHas("Hello"), "/gpearls gossip lists the page's options")
check(chatHas("NPC 4567"), "  and the NPC's ID, when plain")
bye()
P.Command("gossip").run("always 90")
check(SS.SetHas(G.ALWAYS, 90), "/gpearls gossip always <id>")
P.Command("gossip").run("forget 90")
check(not SS.SetHas(G.ALWAYS, 90), "/gpearls gossip forget <id>")
newChat()
P.Command("gossip").run("trace")
check(chatHas("player picks"), "/gpearls gossip trace shows the events")

-- A full always list: said, nothing else changes.
for i = 1, GP.SettingsSync.SET_MAX do SS.SetAdd(G.NEVER, 100000 + i) end
pick(73); pick(73); pick(73)
newChat()
f.always:GetScript("OnClick")(f.always)
check(not SS.SetHas(G.ALWAYS, 73) and chatHas("full"), "a full list: not added, and said")
SS.SetClear(G.NEVER)

done("test_autogossip_learn")
