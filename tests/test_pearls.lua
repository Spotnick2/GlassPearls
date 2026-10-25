-- The pearl registry: registration rules, saved choices, enable/disable, a
-- pearl that throws, /gpearls <pearl> and the options checkboxes.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local calls = {}
local function pearl(key, default, opts)
    opts = opts or {}
    local def = {
        key = key, name = opts.name or key, desc = opts.desc, default = default,
        Enable = function() calls[#calls + 1] = key .. "+"; if opts.boom then error("boom") end end,
    }
    if not opts.noDisable then def.Disable = function() calls[#calls + 1] = key .. "-" end end
    return def
end

-- A pearl registers at file scope, before the saved variables load. The saved
-- table: "beta" switched on (default off), "alpha" saved at its default
-- (dropped), a pearl no file claims (kept), a non-boolean (dropped).
local GP = loadAddon({
    db = { pearls = { beta = true, alpha = true, gone = false, junk = "yes" } },
    before = function(GP)
        local R = GP.Pearls.Register
        R(pearl("alpha", true, { name = "Alpha" }))
        R(pearl("beta", false, { name = "Beta", desc = "the second" }))
        R(pearl("gamma", false, { name = "gamma", noDisable = true }))
        R(pearl("boom", true, { name = "Boom", boom = true }))
    end,
})
local P = GP.Pearls

-- Registration rules.
check(not pcall(P.Register, pearl("alpha", true)), "a duplicate key is refused")
check(not pcall(P.Register, pearl("Bad-Key", true)), "a key must be lower-case letters or digits")
check(not pcall(P.Register, { key = "noenable", name = "x" }), "a pearl needs Enable")
local names = {}
for _, def in ipairs(P.List()) do names[#names + 1] = def.name end
eq(table.concat(names, ","), "Alpha,Beta,Boom,gamma", "listed by name, case-insensitively")

-- Saved choices, cleaned at load.
eq(rawget(GP.db.pearls, "alpha"), nil, "a choice equal to the default is dropped")
eq(GP.db.pearls.beta, true, "a real choice is kept")
eq(GP.db.pearls.gone, false, "a key no pearl claims is kept")
eq(GP.db.pearls.junk, nil, "a non-boolean is dropped")

-- Login: every pearl that is on, once; a pearl that throws doesn't stop the rest.
eq(table.concat(calls, ","), "alpha+,beta+,boom+", "login enables the pearls that are on")
check(P.IsLive("alpha") and P.IsLive("beta"), "they are live")
check(not P.IsLive("boom"), "a pearl whose Enable threw is not live")
check(GP.failures["pearl boom enable"]:find("boom", 1, true), "  and its error is recorded")
check(not P.IsLive("gamma"), "an off pearl isn't started")

-- Set: saved only when it differs from the default, applied at once.
calls = {}
check(P.Set("alpha", false), "Set alpha off")
eq(GP.db.pearls.alpha, false, "  saved, since it differs from the default")
check(not P.IsLive("alpha"), "  and disabled")
P.Set("alpha", true)
eq(rawget(GP.db.pearls, "alpha"), nil, "back to the default: nothing saved")
eq(table.concat(calls, ","), "alpha-,alpha+", "Disable then Enable")
check(not P.Set("nope", true), "an unknown pearl is refused")
P.Set("alpha", true)
eq(#calls, 2, "switching on a live pearl doesn't enable it twice")

-- Without Disable, a pearl stays live until /reload.
P.Set("gamma", true)
check(P.IsLive("gamma"), "gamma on")
P.Set("gamma", false)
check(P.IsLive("gamma"), "gamma has no Disable: still live")
check(not P.IsOn("gamma"), "  though it is off")

-- /gpearls
newChat()
SlashCmdList.GLASSPEARLS("list")
local lines = newChat()
eq(#lines, 4, "/gpearls list: one line per pearl")
check(lines[4]:find("gamma - gamma (off (after /reload))", 1, true), "  a pending change says so")
SlashCmdList.GLASSPEARLS("beta off")
check(not P.IsOn("beta") and not P.IsLive("beta"), "/gpearls beta off")
check(newChat()[1]:find("Beta off", 1, true), "  confirmed")
SlashCmdList.GLASSPEARLS("beta")
check(newChat()[1]:find("Beta is off", 1, true), "/gpearls beta reports its state")

-- The options page: one checkbox per pearl, synced on every show.
local panel = GP.Options._test.panel
panel:Show()
local boxes = GP.Options._test.pearls
check(boxes.alpha and boxes.beta and boxes.gamma and boxes.boom, "a checkbox per pearl")
check(boxes.alpha:GetChecked() and not boxes.beta:GetChecked(), "the boxes show each pearl's state")
boxes.beta:SetChecked(true)
boxes.beta:GetScript("OnClick")(boxes.beta)
check(P.IsOn("beta") and P.IsLive("beta"), "ticking a box switches the pearl on")

done("test_pearls")
