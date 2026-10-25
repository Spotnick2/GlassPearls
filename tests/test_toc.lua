-- The manifest, the pinned build, the event fixture and the embedded libraries.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open(TOC):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassPearlsDB, GlassPearlsSyncDB", 1, true), "saved variables declared")
check(toc:find("## SavedVariablesPerCharacter: GlassPearlsCharDB", 1, true), "per-character saved variables declared")
-- The release targets: CurseForge's packager and the Wago app match on these,
-- and CI's wago job uploads to the packaged TOC's X-Wago-ID.
check(toc:find("## X%-Curse%-Project%-ID: 1764704\r?\n"), "the CurseForge project ID")
check(toc:find("## X%-Wago%-ID: kGr9LxKy\r?\n"), "the Wago project ID")
-- Glass UI loads first when it's enabled, so its suite answers at our
-- ADDON_LOADED (GlassUI docs/SUITE.md); the AddOn list groups the Glass family.
check(toc:find("## OptionalDeps: GlassUI\r?\n"), "OptionalDeps: GlassUI")
check(not toc:find("## Dependencies", 1, true), "no hard dependency on another Glass addon")
check(toc:find("## Category: |cff7fd4ffGlass|r", 1, true), "the Glass category")

-- The LICENSE ships in the zip: ours, with one notice for exactly what's
-- bundled (RELEASING.md section 1; the copied GlassMail notice was caught in
-- the Codex review of #2).
local license = io.open("LICENSE"):read("*a")
check(license:find("^MIT License"), "LICENSE is MIT")
check(license:find("Glass Pearls' own code", 1, true), "its notice names Glass Pearls")
for _, other in ipairs({ "Glass Mail", "GlassMail", "Glass Chat", "GlassChat" }) do
    check(not license:find(other, 1, true), "no other addon named in LICENSE: " .. other)
end
local _, sections = license:lower():gsub("third%-party", "")
eq(sections, 1, "one third-party notice (any case)")
for line in pairs(LIBS) do
    local dir = line:match("^(Libs\\[^\\]+)\\"):gsub("\\", "/")
    check(license:find(dir, 1, true), "LICENSE lists " .. dir)
end
for _, bundled in ipairs({ "LibStub", "ChatThrottleLib" }) do
    check(license:find(bundled, 1, true), "LICENSE credits the bundled " .. bundled)
end
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

-- Without Glass UI there is no glass: the WoW Forever look, and no instance.
eq(GlassPearls.Theme.Active(), "forever", "no Glass UI: the WoW Forever look")
eq(GlassPearls.Theme.Glass(), nil, "  and no LibGlass instance")

-- The embedded material, as Glass UI's Pearl answer would build it: every
-- texture it names ships with the library, and MEDIA points into the
-- embedded copy, where the packager puts it.
local inst = GlassPearls.Theme.NewGlass("pearl")
check(inst ~= nil, "the embedded LibGlass builds Pearl (r11+)")
local root = libGlassRoot()
for size, S in pairs(inst.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
eq(inst.MEDIA, "Interface\\AddOns\\GlassPearls\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")
for _, k in ipairs({ "Apply", "Reflect", "SetSurfaceAlpha", "Mask", "MEDIA", "SIZES" }) do
    check(inst[k] ~= nil, "the instance has Glass." .. k)
end

done("test_toc")
