-- The manifest, the pinned build, the event fixture and the embedded libraries.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open(TOC):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassPearlsDB, GlassPearlsSyncDB", 1, true), "saved variables declared")
check(toc:find("## SavedVariablesPerCharacter: GlassPearlsCharDB", 1, true), "per-character saved variables declared")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
-- The embedded libraries load before any of our files: Glass.lua and
-- AccountSync.lua call LibStub at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocLines()[2], LIBACCOUNTSYNC_XML, "LibAccountSync-1.0 loads second")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
eq(tocFiles()[#tocFiles()], "GlassPearls.lua", "the bootstrap loads last")
local seen, pearlsAt = {}, nil
for i, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
    if f == "Pearls.lua" then pearlsAt = i end
    -- A pearl registers at file scope, so it loads after the registry.
    if f:match("^Pearls/") then check(pearlsAt and i > pearlsAt, "after Pearls.lua: " .. f) end
end

-- Every .pkgmeta external is a library the TOC loads, and the other way round.
local pkgmeta = io.open(".pkgmeta"):read("*a")
for line in pairs(LIBS) do
    local dir = line:match("^(Libs\\[^\\]+)\\"):gsub("\\", "/")
    check(pkgmeta:find("\n  " .. dir .. ":", 1, true), ".pkgmeta pins " .. dir)
end

-- Two places that must agree, never derived from each other (porting guide section 0).
loadAddon()
eq(GlassPearls.MEASURED_ON_BUILD, "1.60.1.70532", "MEASURED_ON_BUILD")

-- The checked-in event list matches the dump, when the dump is here.
if WoW.dumpAvailable then
    local fixture = {}
    for line in io.lines("tests/events-70532.txt") do
        local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
        if name then fixture[name] = true end
    end
    local missing, extra = 0, 0
    for e in pairs(WoW.KNOWN_EVENTS) do if not fixture[e] then missing = missing + 1 end end
    for e in pairs(fixture) do if not WoW.KNOWN_EVENTS[e] then extra = extra + 1 end end
    eq(missing + extra, 0, "tests/events-70532.txt matches the dump (regenerate it)")
end

-- Every texture the material names ships with the library.
local root = libGlassRoot()
for size, S in pairs(GlassPearls.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
-- The Pearl preset (LibGlass r11), and MEDIA points into the embedded copy,
-- where the packager puts it.
eq(GlassPearls.glassPreset, "pearl", "the Pearl preset (LibGlass r11+)")
eq(GlassPearls.Glass.MEDIA, "Interface\\AddOns\\GlassPearls\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")
for _, k in ipairs({ "Apply", "MEDIA", "SIZES" }) do
    check(GlassPearls.Glass[k] ~= nil, "the instance has Glass." .. k)
end

done("test_toc")
