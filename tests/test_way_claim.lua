-- Waypoint routes (#139): /way is claimed only while no add-on owns it, a
-- frame after the registry's Start or a later switch-on, once a session.
-- Here the pearl starts off; test_way.lua covers the plain login claim.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ db = { pearls = { way = false } } })
local W, P = GP.Way, GP.Pearls

WoW.flushTimers(0)
eq(SlashCmdList.GLASSPEARLSWAY, nil, "off at login: /way not claimed")

-- Switched on while another add-on's SLASH_ global says /way (any case): not taken over.
_G.SLASH_OTHERWAY1 = "/WAY"
P.Set("way", true)
WoW.flushTimers(0)
eq(SlashCmdList.GLASSPEARLSWAY, nil, "another add-on's /way: not claimed")
_G.SLASH_OTHERWAY1 = WoW.Secret("s")
W.Claim()
check(SlashCmdList.GLASSPEARLSWAY ~= nil, "a secret SLASH_ global is no owner")
eq(_G.SLASH_GLASSPEARLSWAY1, "/way", "  claimed")
SlashCmdList.GLASSPEARLSWAY, _G.SLASH_GLASSPEARLSWAY1, _G.SLASH_OTHERWAY1 = nil, nil, nil
W.state.claimed = false

-- Blizzard's hash already holding /WAY: not taken over.
_G.hash_SlashCmdList = { ["/WAY"] = function() end }
W.Claim()
eq(SlashCmdList.GLASSPEARLSWAY, nil, "/WAY in Blizzard's hash: not claimed")
_G.hash_SlashCmdList = {}

-- Free: a switch-on claims it a frame later, once.
P.Set("way", false)
P.Set("way", true)
eq(SlashCmdList.GLASSPEARLSWAY, nil, "switched on: not at once")
P.Set("way", false)
WoW.flushTimers(0)
eq(SlashCmdList.GLASSPEARLSWAY, nil, "  switched off again before the frame: not claimed")
P.Set("way", true)
WoW.flushTimers(0)
eq(_G.SLASH_GLASSPEARLSWAY1, "/way", "  a frame later: claimed")
local handler = SlashCmdList.GLASSPEARLSWAY
_G.SLASH_GLASSPEARLSWAY1 = "/way"
P.Set("way", false)
P.Set("way", true)
WoW.flushTimers(0)
eq(SlashCmdList.GLASSPEARLSWAY, handler, "once a session")

done("test_way_claim")
