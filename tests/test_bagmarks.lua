-- Core/BagMarks.lua: two kinds of marks on one set of hooks (hooked once);
-- an inactive kind hides only its own marks; prepare once per pass; pooled
-- buttons read again; the combined bags; combat deferral by the core's own
-- listener (only test kinds here: pet care is a hunter's, this is a mage);
-- nothing written on Blizzard's buttons.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon()
local BM = GP.BagMarks
local CF1, COMBINED = WoW.containerFrames[1], ContainerFrameCombinedBags

WoW.bags[0] = { size = 16, items = { [1] = { id = 10, count = 1 }, [2] = { id = 20, count = 1 } } }
local on = { a = true, b = true }
local prepared = 0
BM.Add("a", { anchor = "TOPLEFT", active = function() return on.a end,
    prepare = function() prepared = prepared + 1; return { want = 10 } end,
    shows = function(bag, slot, ctx) return C_Container.GetContainerItemID(bag, slot) == ctx.want end })
BM.Add("b", { anchor = "BOTTOMLEFT", active = function() return on.b end,
    shows = function(bag, slot) return slot == 2 end })
local A, B = BM.Marks("a"), BM.Marks("b")

BM.Hook()
BM.Hook()
eq(WoW.hooked[CF1].UpdateItems, 1, "hooked once")
eq(WoW.hooked[COMBINED].UpdateItems, 1, "  the combined bags too")
prepared = 0
WoW.showBag(CF1, { { 0, 1 }, { 0, 2 } })
local b1, b2 = CF1.Items[1], CF1.Items[2]
eq(prepared, 1, "prepare once per pass")
check(A[b1] and A[b1]:IsShown() and not A[b2], "kind a: its item")
check(B[b2] and B[b2]:IsShown() and not B[b1], "kind b: its slot")
check(A[b1] ~= B[b2] and A[b1]:GetParent() == b1, "  each kind its own child frame")
local keys = {}
for k in pairs(b1) do if type(k) ~= "string" or k:sub(1, 1) ~= "_" then keys[#keys + 1] = tostring(k) end end
table.sort(keys)
eq(table.concat(keys, ","), "GetBagID", "nothing written on Blizzard's button")

-- Inactive: only that kind hidden.
on.a = false
BM.Refresh("a")
check(not A[b1]:IsShown() and B[b2]:IsShown(), "a inactive: only a's marks hidden")
WoW.showBag(CF1, { { 0, 1 }, { 0, 2 } })
check(not A[b1]:IsShown(), "  Blizzard's update doesn't bring it back")
on.a = true
BM.Refresh("a")
check(A[b1]:IsShown(), "active again: shown")

-- Pooled buttons.
WoW.showBag(CF1, { { 0, 2 }, { 0, 1 } })
check(not A[b1]:IsShown() and A[b2] and A[b2]:IsShown(), "a pooled button reused: read again")
check(B[b1] and B[b1]:IsShown() and not B[b2]:IsShown(), "  for every kind")

-- The combined bags.
CF1:Hide()
WoW.showBag(COMBINED, { { 0, 1 } })
check(A[COMBINED.Items[1]] and A[COMBINED.Items[1]]:IsShown(), "the combined bags")

-- Combat: no mark created; the core's own listener decorates after it.
local CF2 = WoW.containerFrames[2]
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.combat = true
WoW.showBag(CF2, { { 0, 1 } })
local c1 = CF2.Items[1]
eq(A[c1], nil, "in combat: no mark created")
check(BM._test.pending[c1], "  noted")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(A[c1] and A[c1]:IsShown(), "  decorated after the fight, by the core itself")
check(next(BM._test.pending) == nil, "  nothing pending")

done("test_bagmarks")
