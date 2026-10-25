-- harness.lua: assertions and the addon loader. dofile it after wow_stubs.lua.
-- GlassChat's harness, trimmed: no plugins, no probe (yet).

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function done(name)
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

TOC = "GlassPearls.toc"

-- Every file line of the TOC, in load order (our .lua files and the embedded
-- libraries' .xml).
function tocLines()
    local lines = {}
    for line in io.lines(TOC) do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then lines[#lines + 1] = line end
    end
    return lines
end

-- Lua files listed in the TOC, in load order.
function tocFiles()
    local files = {}
    for _, line in ipairs(tocLines()) do
        if line:match("%.lua$") then files[#files + 1] = line:gsub("\\", "/") end
    end
    return files
end

-- The embedded libraries come from checkouts, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS / $LIBACCOUNTSYNC, else the sibling
-- folder. No checkout fails the run loudly; a silently skipped library would
-- test nothing. (GlassUnitFrames' harness, #64.)
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
LIBACCOUNTSYNC_XML = "Libs\\LibAccountSync-1.0\\LibAccountSync-1.0.xml"
LIBS = {
    [LIBGLASS_XML] = { env = "LIBGLASS", dir = "../LibGlass", xml = "LibGlass-1.0.xml" },
    [LIBACCOUNTSYNC_XML] = { env = "LIBACCOUNTSYNC", dir = "../LibAccountSync", xml = "LibAccountSync-1.0.xml" },
}

function libRoot(line)
    local L = LIBS[line]
    local root = (os.getenv(L.env) or L.dir):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/" .. L.xml, "rb")
    if not f then
        error(L.xml .. " checkout not found at " .. root .. ": clone it there or set " .. L.env, 0)
    end
    f:close()
    return root
end
function libGlassRoot() return libRoot(LIBGLASS_XML) end

-- The third-party libraries committed in Libs/ (not .pkgmeta externals),
-- with the notice each folder ships. HereBeDragons needs the client's whole map
-- system to load, so the tests replace it with a recording fake (fake = true);
-- test_toc checks the vendored files themselves.
VENDORED = {
    ["Libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua"] = { notice = "Libs/CallbackHandler-1.0/LICENSE.txt", fake = true },
    ["Libs\\HereBeDragons-2.0\\HereBeDragons-2.0.lua"] = { notice = "Libs/HereBeDragons-2.0/NOTICE.txt", fake = true },
    ["Libs\\HereBeDragons-2.0\\HereBeDragons-Pins-2.0.lua"] = { notice = "Libs/HereBeDragons-2.0/NOTICE.txt", fake = true },
}

-- The Lua files a library's XML loads, as paths, in order: what the client
-- runs for that TOC line. A listed file that is missing fails here.
function libScripts(line)
    local L, root = LIBS[line], libRoot(line)
    local f = assert(io.open(root .. "/" .. L.xml, "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error(L.xml .. " at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error(L.xml .. " at " .. root .. " lists no Script files", 0) end
    return files
end

-- Load the addon the way the client does: every TOC file with (name, ns), the
-- libraries' XML expanded in place, then ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD (initial login). opts.before(), when given, runs
-- after the files and before ADDON_LOADED: where a test registers a pearl, as
-- a pearl file would at file scope. opts.pearls = false leaves out the shipped
-- pearls (TOC lines under Pearls\): for a test of the framework, which counts
-- only the pearls it registers itself.
function loadAddon(opts)
    opts = opts or {}
    local ns = {}
    for _, line in ipairs(tocLines()) do
        local files = { line }
        if LIBS[line] then
            files = libScripts(line)
        elseif not line:match("%.lua$") then
            error("the harness can't load TOC line " .. line, 0)
        elseif opts.pearls == false and line:match("^Pearls\\") then
            files = {}
        elseif VENDORED[line] and VENDORED[line].fake then
            files = {}   -- replaced by its recording fake (wow_stubs: WoW.installFakeHBD)
        end
        for _, file in ipairs(files) do
            assert(loadfile((file:gsub("\\", "/"))))("GlassPearls", ns)
        end
    end
    WoW.installFakeHBD()
    if opts.before then opts.before(GlassPearls) end
    if opts.db then GlassPearlsDB = opts.db end
    if opts.charDB then GlassPearlsCharDB = opts.charDB end
    WoW.fire("ADDON_LOADED", "GlassPearls")
    WoW.loggedIn = true
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", opts.initialLogin ~= false, false)
    WoW.tick()
    return GlassPearls
end

-- Chat lines printed since the last call.
local seenChat = 0
function newChat()
    local lines = {}
    for i = seenChat + 1, #WoW.chat do lines[#lines + 1] = WoW.chat[i] end
    seenChat = #WoW.chat
    return lines
end

function chatHas(pattern)
    for _, line in ipairs(WoW.chat) do
        if line:find(pattern) then return true end
    end
    return false
end
