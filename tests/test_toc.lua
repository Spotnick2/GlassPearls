-- The manifest, the pinned build and the embedded libraries.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- WowTestKit's: interface 16001, the version token, every listed file exists
-- and is listed once.
Kit.checkToc(TOC)
local toc = io.open(TOC):read("*a")
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
-- The embedded libraries load before any of our files: Glass.lua and
-- AccountSync.lua call LibStub at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocLines()[2], LIBACCOUNTSYNC_XML, "LibAccountSync-1.0 loads second")
local own = {}
for _, f in ipairs(tocFiles()) do if not f:match("^Libs/") then own[#own + 1] = f end end
eq(own[1], "Compat.lua", "Compat is the first of our own files")
-- Every library loads before our own files.
local seenOwn = false
for _, line in ipairs(tocLines()) do
    if line:match("^Libs\\") then
        check(not seenOwn, "a library before our own files: " .. line)
    else
        seenOwn = true
    end
end
eq(tocFiles()[#tocFiles()], "GlassPearls.lua", "the bootstrap loads last")
local pearlsAt, syncAt
for i, f in ipairs(tocFiles()) do
    if f == "Pearls.lua" then pearlsAt = i end
    if f == "SettingsSync.lua" then syncAt = i end
    -- A pearl registers itself (Pearls.lua) and its sets (SettingsSync.lua) at
    -- file scope, so it loads after both.
    if f:match("^Pearls/") then
        check(pearlsAt and i > pearlsAt, "after Pearls.lua: " .. f)
        check(syncAt and i > syncAt, "after SettingsSync.lua: " .. f)
    end
end

-- Bindings.xml (the raid mark wheel's key, #34): a category, never a header
-- (porting guide, "Key bindings"); not in the TOC (the client finds it by
-- name), so the deploy copies and keeps it and the package check expects it.
local bindings = io.open("Bindings.xml"):read("*a")
check(bindings:find('<Binding name="GLASSPEARLS_MARKWHEEL" category="Glass Pearls">', 1, true),
    "Bindings.xml: the mark wheel's key, in the Glass Pearls category")
check(not bindings:find("header=", 1, true), "  no header attribute")
check(bindings:find("GlassPearls.MarkWheel.OnKey()", 1, true), "  it calls the pearl's key handler")
check(bindings:find('<Binding name="GLASSPEARLS_FISH" category="Glass Pearls">', 1, true),
    "Bindings.xml: easy fishing's key (#64), in the Glass Pearls category")
check(bindings:find("GlassPearls.Fishing.OnKey()", 1, true), "  it calls the pearl's key handler")
check(not toc:find("Bindings.xml", 1, true), "  not listed in the TOC")
local deploy = io.open("Tools/deploy.ps1"):read("*a")
check(deploy:find('@("GlassPearls.toc", "Bindings.xml")', 1, true), "deploy.ps1 copies and keeps Bindings.xml")
local workflow = io.open(".github/workflows/package-check.yml"):read("*a")
check(workflow:find("echo GlassPearls/Bindings.xml", 1, true), "the package check expects Bindings.xml in the zip")
-- Media\*.tga (the quest sparkle's stars, #79): read by path, so the deploy copies and keeps
-- them, the package check expects them, and .pkgmeta doesn't drop them.
check(deploy:find('+ $media +', 1, true), "deploy.ps1 copies and keeps Media\\*.tga")
check(deploy:find("restart the game client", 1, true), "  and says a new texture needs a client restart")
check(workflow:find("ls Media/*.tga | sed 's|^|GlassPearls/|'", 1, true), "the package check expects Media/*.tga")
check(not io.open(".pkgmeta"):read("*a"):find("Media", 1, true), ".pkgmeta doesn't ignore Media")
for _, name in ipairs({ "MarkerStar", "MarkerVapor", "SonarGlow" }) do
    local f = io.open("Media/" .. name .. ".tga", "rb")
    check(f ~= nil, "Media/" .. name .. ".tga is there (the stars' art)")
    if f then f:close() end
end

-- Every .pkgmeta external is a library the TOC loads, and the other way round.
local pkgmeta = io.open(".pkgmeta"):read("*a")
check(not pkgmeta:find("Bindings", 1, true), ".pkgmeta doesn't ignore Bindings.xml")
for line in pairs(LIBS) do
    local dir = line:match("^(Libs\\[^\\]+)\\"):gsub("\\", "/")
    check(pkgmeta:find("\n  " .. dir .. ":", 1, true), ".pkgmeta pins " .. dir)
end

-- Every Libs\ line is an external (.pkgmeta, gitignored) or vendored
-- (committed, unmodified, with its notice), and every vendored file is loaded.
local inToc = {}
for _, line in ipairs(tocLines()) do
    if line:match("^Libs\\") then
        inToc[line] = true
        check(LIBS[line] or VENDORED[line], "a known library: " .. line)
    end
end
for line, v in pairs(VENDORED) do
    check(inToc[line], "the vendored file is loaded: " .. line)
    check(io.open((line:gsub("\\", "/")), "rb") ~= nil, "  and committed: " .. line)
    check(io.open(v.notice, "rb") ~= nil, "  with its notice: " .. v.notice)
    local dir = line:match("^(Libs\\[^\\]+)\\"):gsub("\\", "/")
    check(not pkgmeta:find("\n  " .. dir .. ":", 1, true), "  not also an external: " .. dir)
    check(license:find(dir, 1, true), "  and LICENSE lists it: " .. dir)
end
-- The vendored versions, and their order: CallbackHandler, HereBeDragons, Pins.
local function minor(path, major)
    local src = io.open(path, "rb"):read("*a")
    return tonumber(src:match('MAJOR, MINOR = "' .. major:gsub("%-", "%%-") .. '", (%d+)'))
end
eq(minor("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", "CallbackHandler-1.0"), 8, "CallbackHandler-1.0 minor 8")
eq(minor("Libs/HereBeDragons-2.0/HereBeDragons-2.0.lua", "HereBeDragons-2.0"), 35, "HereBeDragons-2.0 minor 35 (2.18-release)")
eq(minor("Libs/HereBeDragons-2.0/HereBeDragons-Pins-2.0.lua", "HereBeDragons-Pins-2.0"), 17, "HereBeDragons-Pins-2.0 minor 17")
local at = {}
for i, line in ipairs(tocLines()) do at[line] = i end
check(at["Libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua"] < at["Libs\\HereBeDragons-2.0\\HereBeDragons-2.0.lua"]
    and at["Libs\\HereBeDragons-2.0\\HereBeDragons-2.0.lua"] < at["Libs\\HereBeDragons-2.0\\HereBeDragons-Pins-2.0.lua"],
    "CallbackHandler, then HereBeDragons, then its Pins")
check(at["Data\\Landmarks.lua"] < at["Pearls\\Landmarks.lua"], "the landmark data before its pearl")

-- Two places that must agree, never derived from each other (porting guide section 0).
loadAddon()
eq(GlassPearls.MEASURED_ON_BUILD, "1.60.1.70532", "MEASURED_ON_BUILD")


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
