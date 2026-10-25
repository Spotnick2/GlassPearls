-- Choices saved before settings sync existed travel (Codex review of #8):
-- an upgrade with GlassPearlsDB choices and no sync stamps seeds them at
-- SEED_TIME, so the first snapshot carries them, an account that never set
-- them takes them, and any real edit (always later) still wins.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({
    -- What a pre-sync GlassPearls left: non-default choices, no `sync` table.
    db = { useGlassUI = false, pearls = { beta = true }, settings = { beta = { size = 7 } } },
    before = function(GP)
        GP.Pearls.Register({ key = "alpha", name = "Alpha", Enable = function() end, Disable = function() end })
        GP.Pearls.Register({ key = "beta", name = "Beta", Enable = function() end, Disable = function() end,
            defaults = { size = 3, mode = "grey" }, choices = { mode = { "grey", "white" } } })
    end,
})
local SS, C = GP.SettingsSync, GP.SettingsSync.Core
local store = GP.db.sync

-- Seeded: exactly the non-default choices, at SEED_TIME, by this character.
for _, id in ipairs({ "core.glassui", "on.beta", "beta.size" }) do
    local st = store.stamps[id]
    check(st ~= nil and st.t == SS.SEED_TIME and st.o == WoW.playerGUID, "seeded: " .. id)
end
for _, id in ipairs({ "on.alpha", "beta.mode" }) do
    eq(store.stamps[id], nil, "a default isn't seeded: " .. id)
end

-- The login snapshot carries them.
local sent
GP.AccountSync.Send = function(kind, body) sent = body; return 1 end
WoW.flushTimers(SS.LOGIN_DELAY)
check(sent and sent:find("V\tcore.glassui\t1\t", 1, true), "the login snapshot carries 'Use Glass UI appearance'")
check(sent:find("V\ton.beta\t1\t", 1, true) and sent:find("V\tbeta.size\t1\t", 1, true), "  and the saved pearl choices")

-- An account that never set them takes them (any stamp beats none).
local values = { glassui = true, beta = false, size = 3 }
local reg = { keys = {}, sets = {} }
reg.keys["core.glassui"] = { kind = "bool", get = function() return values.glassui end, set = function(v) values.glassui = v end }
reg.keys["on.beta"] = { kind = "bool", get = function() return values.beta end, set = function(v) values.beta = v end }
reg.keys["beta.size"] = { kind = "int", min = -999999999, max = 999999999,
    get = function() return values.size end, set = function(v) values.size = v end }
local other = C.Clean({})
C.Merge(reg, other, assert(C.Decode(sent)), function(spec, v) spec.set(v) end)
check(values.glassui == false and values.beta == true and values.size == 7, "an account with defaults takes the seeded choices")

-- A real edit on the other account (later than SEED_TIME) wins over a seed.
local later = "GPS1\nV\tbeta.size\t500\tPlayer-1-BBB\t1\ti9"
GP.SettingsSync.Receive(later, { name = "Alt" })
eq(GP.Pearls.Setting("beta", "size"), 9, "a real edit elsewhere beats the seed here")

-- Seeding runs once per key: a second start leaves the stamps alone.
local before = store.stamps["core.glassui"].s
eq(C.Seed(SS.reg, store, WoW.playerGUID), 0, "nothing left to seed")
eq(store.stamps["core.glassui"].s, before, "  the seed stamps are kept")

done("test_sync_seed")
