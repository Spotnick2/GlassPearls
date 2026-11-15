-- SettingsSync's registry when full (#112): the look choice registers first,
-- so a full registry refuses a pearl's key and never it; each pearl's switch
-- before its settings, the settings by name, so the refused keys are always
-- the same; and every refusal, a switch's included, is recorded.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local EXTRA = 20      -- test pearls, seven keys each: well past KNOWN_MAX with the shipped ones
local NAMES = { "zeta", "alpha", "mike", "bravo", "yank", "kilo" }
local order = {}      -- every id offered to the registry, in order
local GP = loadAddon({
    before = function(GP)
        for i = 1, EXTRA do
            local defaults = {}
            for _, n in ipairs(NAMES) do defaults[n] = true end
            GP.Pearls.Register({ key = ("zfull%02d"):format(i), name = "Full " .. i,
                Enable = function() end, Disable = function() end, defaults = defaults })
        end
        local register = GP.SettingsSync.Register
        GP.SettingsSync.Register = function(id, spec)
            order[#order + 1] = id
            return register(id, spec)
        end
    end,
})
local SS, P = GP.SettingsSync, GP.Pearls
local keys = SS.reg.keys

eq(SS.Core.Count(keys), SS.KNOWN_MAX, "the registry is full: " .. SS.KNOWN_MAX .. " keys")
check(keys["core.glassui"] ~= nil, "the look choice registered all the same")
check(GP.failures["settings sync core.glassui"] == nil, "  and isn't recorded as refused")

-- Every key a pearl offers is registered or recorded as refused.
local refused, onRefused = 0, 0
for _, def in ipairs(P.List()) do
    local ids = { SS.PearlOnId(def.key) }
    for name in pairs(def.defaults) do ids[#ids + 1] = SS.SettingId(def.key, name) end
    for _, id in ipairs(ids) do
        if not keys[id] then
            refused = refused + 1
            if id:find("^on%.") then onRefused = onRefused + 1 end
            check(GP.failures["settings sync " .. id] ~= nil, "refused and recorded: " .. id)
        end
    end
end
check(refused > 0, "some test pearls' keys were refused (" .. refused .. ")")
check(onRefused > 0, "  a switch among them, recorded too")

-- The order offered: the look first, then each test pearl's switch and its settings by name.
eq(order[1], "core.glassui", "the look choice is offered first")
local at = {}
for i, id in ipairs(order) do at[id] = i end
local sorted = { "alpha", "bravo", "kilo", "mike", "yank", "zeta" }
local inOrder = true
for i = 1, EXTRA do
    local key = ("zfull%02d"):format(i)
    local prev = at[SS.PearlOnId(key)]
    for _, n in ipairs(sorted) do
        local here = at[SS.SettingId(key, n)]
        if not (prev and here and here == prev + 1) then inOrder = false end
        prev = here
    end
end
check(inOrder, "each pearl: its switch, then its settings by name, one after another")

-- In order: a pearl's settings only after its switch, and by name.
local orderOk = true
for _, def in ipairs(P.List()) do
    if keys[SS.SettingId(def.key, "zeta")] and not keys[SS.SettingId(def.key, "alpha")] then orderOk = false end
    for name in pairs(def.defaults) do
        if keys[SS.SettingId(def.key, name)] and not keys[SS.PearlOnId(def.key)] then orderOk = false end
    end
end
check(orderOk, "a pearl's switch before its settings, its settings by name")
-- The pearls in order: once one is refused its switch, none after it registers.
local closed, later = false, false
for _, def in ipairs(P.List()) do
    if closed and keys[SS.PearlOnId(def.key)] then later = true end
    if not keys[SS.PearlOnId(def.key)] then closed = true end
end
check(closed and not later, "  and the pearls in their order: the refused ones are the last")

done("test_sync_registry")
