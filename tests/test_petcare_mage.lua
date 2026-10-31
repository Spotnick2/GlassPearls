-- Hunter pet care (#38) for another class: nothing registered, hooked or
-- built, nothing said.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ before = function()
    WoW.pet = { happiness = 1, level = 60, guid = "Pet-1" }   -- a warlock's demon, say
    WoW.known[883] = true
end })
local PC, P, FR = GP.PetCare, GP.Pearls, GP.PetCareFrame
P.SetSetting("petcare", "food", "both")
P.SetSetting("petcare", "away", true)

check(P.IsOn("petcare"), "on by default")
check(not PC.state.hunter, "a mage: not a hunter")
for _, e in ipairs(PC.EVENTS) do
    check(not PC._test.events:IsEventRegistered(e), "  not registered: " .. e)
end
eq(WoW.tooltipPostCalls[Enum.TooltipDataType.Item], nil, "  no tooltip hook")
for _, cf in ipairs(WoW.containerFrames) do
    check(not (WoW.hooked[cf] and WoW.hooked[cf].UpdateItems), "  no bag hook")
end
eq(FR._test.frame(), nil, "  no window")
newChat()
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.fire("READY_CHECK", "Leader", 35)
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.advance(20)
eq(#newChat(), 0, "  nothing said")
P.Command("petcare").run("")
check(chatHas("for hunters only"), "/gpearls petcare: for hunters only")

done("test_petcare_mage")
