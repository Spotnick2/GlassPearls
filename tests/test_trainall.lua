-- Train all (#39): off by default; the button once Blizzard's trainer UI
-- loads, compact, parented and anchored, nothing written on Blizzard's
-- frames; only a class trainer's class spells (tooltip type before id, the
-- curated list, plainly unknown); the run cheapest first while the money
-- lasts, one purchase in flight, confirmed only by the exact money AND the
-- spell known, whatever order they arrive in; stale runs never buy.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local TA, P = GP.TrainAll, GP.Pearls
local AI, WATER, FROSTBOLT, SCROLL = 1459, 5504, 116, 1296017
local RIDING = 33388                                   -- not in the mage's list
local function frame() WoW.advance(0) end

local function trainer(list, opts)
    opts = opts or {}
    if TA.state.run then WoW.fire("TRAINER_CLOSED") end      -- end the last test's run
    local svc = {}
    for i, s in ipairs(list) do
        svc[i] = { id = s[1], cost = s[2], kind = s.kind, profession = s.profession, tipType = s.tipType,
            tip = s.tip, name = s.name or ("Spell " .. s[1]) }
    end
    WoW.trainer = { type = opts.type == nil and 0 or opts.type, services = svc }
    WoW.tradeTrainer = opts.tradeskill
    WoW.bought, WoW.trainPending, WoW.trainSettle, WoW.trainRefuses = {}, nil, nil, nil
    for _, s in ipairs(list) do WoW.known[s[1]] = nil end
end
local function ids(list)
    local out = {}
    for _, s in ipairs(list) do out[#out + 1] = s.id end
    return table.concat(out, ",")
end
local function run()
    newChat()
    TA.Start()
    for _ = 1, 10 do frame() end
end

WoW.money = 100000
check(not P.IsOn("trainall"), "off by default")
WoW.loadTrainerUI()
check(GP.TrainAllFrame.Button() == nil or not GP.TrainAllFrame.Button():IsShown(), "  off: no button shown")
P.Set("trainall", true)
local b = GP.TrainAllFrame.Button()
check(b ~= nil, "on with the trainer UI loaded: the button")
eq(b:GetParent(), ClassTrainerFrame, "  parented to Blizzard's trainer frame")
eq(b:GetWidth(), 80, "  compact: 80 px")
check(b._points[1] and b._points[1][2] == ClassTrainerTrainButton, "  anchored beside Blizzard's Train button")

-- The selection.
trainer({ { FROSTBOLT, 100 }, { AI, 10 }, { RIDING, 900000 }, { WATER, 100, kind = "unavailable" },
    { SCROLL, 50, profession = true } })
local list, why = TA.List()
eq(ids(list), AI .. "," .. FROSTBOLT, "ours: class spells, available, cheapest first")
eq(why["not a class spell"], 1, "  riding left: not in the list")
eq(why["not available"], 1, "  unavailable left")
eq(why["a profession"], 1, "  a profession left")
trainer({ { AI, 10, tipType = 0 } })
eq(#TA.List(), 0, "a non-spell tooltip whose id equals a class spell: rejected")
trainer({ { AI, 10, tipType = WoW.Secret("t") } })
eq(#TA.List(), 0, "a secret tooltip type: rejected")
trainer({ { AI, 10, tip = "secret" } })
eq(#TA.List(), 0, "a secret tooltip: rejected")
trainer({ { AI, WoW.Secret("cost") } })
eq(#TA.List(), 0, "a secret cost: rejected")
trainer({ { AI, 10.5 } })
eq(#TA.List(), 0, "an odd cost: rejected")
trainer({ { AI, 10 } })
WoW.known[AI] = true
eq(#TA.List(), 0, "already known: not ours")
WoW.known[AI] = nil
WoW.knownSecret[AI] = true
eq(#TA.List(), 0, "known unreadable: not ours")
WoW.knownSecret[AI] = nil
trainer({ { AI, 10 } }, { type = 2 })
local _, _, not1 = TA.List()
eq(not1, "not a class trainer", "a tradeskill trainer type: nothing")
trainer({ { AI, 10 } }, { tradeskill = true })
local _, _, not2 = TA.List()
eq(not2, "a profession trainer", "IsTradeskillTrainer: nothing")
trainer({ { AI, 10 } }, { type = 3 })
eq(#TA.List(), 0, "a pet trainer: nothing")

-- The button's state and tooltip.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
GP.TrainAllFrame.Refresh()
check(b:IsEnabled(), "something affordable: enabled")
b:GetScript("OnEnter")(b)
check(table.concat(GameTooltip._lines, "|"):find("Available now: 2 spells", 1, true), "  the tooltip: count and cost")
WoW.money = 5
GP.TrainAllFrame.Refresh()
check(not b:IsEnabled(), "nothing affordable: disabled")
WoW.money = 100000
trainer({})
GP.TrainAllFrame.Refresh()
check(not b:IsEnabled(), "nothing to train: disabled")

-- The run: all settled inside the buy.
trainer({ { FROSTBOLT, 100 }, { AI, 10 }, { WATER, 100 } })
run()
eq(table.concat(WoW.bought, ","), AI .. "," .. FROSTBOLT .. "," .. WATER, "a run: cheapest first, then by index")
check(chatHas("Train all: trained 3 spells for " .. GP.TrainingFrame.Money(210):gsub("%p", "%%%0") .. "%."), "  said")
check(TA.state.run == nil, "  over")
-- Stops at the money.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.money = 50
run()
eq(table.concat(WoW.bought, ","), tostring(AI), "stops when the next costs more than you have")
check(chatHas("not enough money for the next"), "  says why")
WoW.money = 100000

-- Manual settling: each part on its own, in any order.
local function manual(order, label)
    trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
    WoW.trainSettle = "manual"
    newChat()
    TA.Start()
    eq(#WoW.bought, 1, label .. ": one purchase in flight")
    for _, what in ipairs(order) do WoW.settleTrain(what) end
    eq(#WoW.bought, 1, label .. ": nothing bought from inside the callbacks")
    frame()
    return #WoW.bought
end
eq(manual({ "money", "known", "row" }, "money, known, row"), 2, "  then the next")
eq(manual({ "known", "money" }, "known, then money"), 2, "known first: the next too")
eq(manual({ "row", "money", "known" }, "the row first"), 2, "the row first: the next")
-- A stale "available" row after the learn: never bought twice.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
TA.Start()
WoW.settleTrain("money"); WoW.settleTrain("known")
frame()
eq(table.concat(WoW.bought, ","), AI .. "," .. FROSTBOLT, "a stale available row: not bought again")
WoW.settleTrain("money"); WoW.settleTrain("known")
frame()
-- Money only: never confirmed; the deadline stops it.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
newChat()
TA.Start()
WoW.settleTrain("money")
WoW.advance(2.1)
eq(#WoW.bought, 1, "money without the learn: not confirmed")
check(chatHas("a purchase wasn't confirmed"), "  stopped at the deadline")
-- The learn without the money: not confirmed.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
TA.Start()
WoW.settleTrain("known")
WoW.advance(2.1)
eq(#WoW.bought, 1, "known without the money: not confirmed")
-- A second Start during a run: ignored.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
TA.Start()
TA.Start()
eq(#WoW.bought, 1, "a second Start during a run: one purchase in flight")
-- The first purchase's deadline passing during the second: the second goes on.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
TA.Start()
WoW.advance(0.5)
WoW.settleTrain("money"); WoW.settleTrain("known")
frame()
eq(#WoW.bought, 2, "the second bought")
WoW.advance(1.7)                                       -- the first's deadline, 2.2 s after it
check(TA.state.run ~= nil, "  the first's deadline doesn't judge the second")
WoW.settleTrain("money"); WoW.settleTrain("known")
frame()
-- Settled inside the buy without any event: the check after the buy sees it.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "silent"
TA.Start()
frame()
eq(#WoW.bought, 2, "settled silently inside the buy: the next at once")
WoW.advance(3)
-- Knowledge arriving just at the deadline.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
TA.Start()
WoW.settleTrain("money")
WoW.advance(1.9)
WoW.known[AI] = true                                   -- no event
WoW.advance(0.2)
frame()
eq(#WoW.bought, 2, "known just at the deadline: confirmed by the last check")
WoW.trainPending.kind = "used"; WoW.settleTrain("money"); WoW.settleTrain("known")
frame()
-- An unrelated equal debit without the learn, then the money changing otherwise.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
newChat()
TA.Start()
WoW.money = WoW.money - 7
WoW.fire("PLAYER_MONEY")
check(chatHas("the money changed otherwise"), "the money changing otherwise: stopped")
eq(#WoW.bought, 1, "  nothing more bought")
-- A refused zero-cost purchase with the filter changed (the row vanishes): not success.
trainer({ { AI, 0 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
newChat()
TA.Start()
table.remove(WoW.trainer.services, 1)
WoW.fire("TRAINER_UPDATE")
WoW.advance(2.1)
eq(#WoW.bought, 1, "a vanished free row without the learn: not success")
check(chatHas("trained") == false or chatHas("nothing trained"), "  nothing claimed")
-- A throw.
trainer({ { AI, 10 } })
WoW.trainRefuses = true
newChat()
run()
check(chatHas("the purchase was refused"), "a refused buy: stopped")
-- Stale runs.
local function staleRun(label, between)
    trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
    WoW.trainSettle = "manual"
    TA.Start()
    between()
    WoW.settleTrain("money"); WoW.settleTrain("known")
    WoW.advance(3)
    eq(#WoW.bought, 1, label .. ": no further purchase")
end
staleRun("the trainer closed", function() WoW.fire("TRAINER_CLOSED") end)
staleRun("combat", function() WoW.fire("PLAYER_REGEN_DISABLED"); WoW.fire("PLAYER_REGEN_ENABLED") end)
staleRun("switched off and on", function() P.Set("trainall", false); P.Set("trainall", true) end)
staleRun("closed and reopened quickly", function() WoW.fire("TRAINER_CLOSED"); WoW.fire("TRAINER_SHOW") end)
-- Closed between a confirmation and the next step: nothing more bought.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
TA.Start()
WoW.settleTrain("money"); WoW.settleTrain("known")
WoW.fire("TRAINER_CLOSED")
frame()
eq(#WoW.bought, 1, "closed before the next step: no further purchase")
-- An old run's deadline during a newer run's purchase.
trainer({ { AI, 10 }, { FROSTBOLT, 100 } })
WoW.trainSettle = "manual"
TA.Start()
WoW.fire("TRAINER_CLOSED")
WoW.advance(1)
TA.Start()                                             -- a new run buys AI again (still unknown)
WoW.advance(1.2)                                       -- the old deadline passes
check(TA.state.run ~= nil, "an old run's deadline: the newer run goes on")
WoW.settleTrain("money"); WoW.settleTrain("known")
frame()
eq(#WoW.bought, 3, "  and continues")
-- In combat: no run.
trainer({ { AI, 10 } })
WoW.fire("PLAYER_REGEN_DISABLED")
run()
eq(#WoW.bought, 0, "in combat: no run")
WoW.fire("PLAYER_REGEN_ENABLED")

-- Enable with the trainer open: the button made then.
P.Set("trainall", false)
check(not b:IsShown(), "off: the button hidden")
P.Set("trainall", true)
check(b:IsShown(), "on again: shown")

-- The report.
trainer({ { AI, 10 }, { RIDING, 9 } })
newChat()
P.Command("trainall").run()
check(chatHas("Train all: 1 spell here for") and chatHas("Left out: not a class spell 1%."), "the report")

done("test_trainall")
