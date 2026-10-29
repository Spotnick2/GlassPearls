-- Pearls/AutoGossip.lua: auto gossip (#47). Picks an NPC's gossip option for
-- the player when it is safe to, and learns the options the player keeps
-- choosing. Its offer prompt and panel are Pearls/AutoGossipFrame.lua.
--
-- Gossip only: nothing while the NPC has a quest to accept or turn in. IDs
-- only: an option is known by its gossipOptionID; its text is shown, never
-- compared. Scope: ordinary gossip with an NPC (GOSSIP_SHOW's textureKit
-- plainly nil, which may route to a custom frame otherwise, and
-- UnitExists("npc") plainly true, since objects and books open gossip too).
--
-- A page is one set of options (GOSSIP_SHOW, GOSSIP_OPTIONS_REFRESHED; ended
-- by every GOSSIP_CLOSED). The decision waits one frame, so Blizzard's own
-- frame handles the show first, and is made once per page:
-- 1. never in combat, with Shift, with quest business, past the chain's cap,
--    or when Blizzard's own lone pick applies (GossipFrameShared.lua:191);
-- 2. an option the player chose to always pick (sync set autogossip.always),
--    unless two of them are on the page;
-- 3. else the lone option, by the `lone` setting and its icon.
-- The same decision runs again on fresh state just before selecting and must
-- give the same option. Selected by ID (else by index), never with
-- `confirmed`: paid options, binding the hearthstone and wiping talents all
-- keep Blizzard's confirmation popup, which this pearl never answers.
--
-- A chain is one conversation with an NPC: at most CHAIN_MAX automatic picks,
-- never the same option twice, none after a pick by index only. It ends at a
-- GOSSIP_CLOSED whose interactionIsContinuing is plainly false, when the NPC
-- is plainly gone a second after a close, after ABSENCE_SECONDS without a
-- page, at a loading screen, or when switched off.
--
-- Learning counts only a click on Blizzard's own option button (a PreClick
-- hooked on GossipFrame.GreetingPanel.ScrollBox's option buttons), and only
-- once the pick visibly went through, in the same conversation: a new page, or
-- an ordinary service window (SERVICE_TYPES). A confirmation instead marks the option as one
-- never offered; GOSSIP_CONFIRM / GOSSIP_ENTER_CODE name it and also take it
-- off the always list. After `repeats` such picks the prompt offers to always
-- pick it.
-- Unmeasured until 2026-11-04: all of it (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local G = {}
GP.AutoGossip = G

G.KEY = "autogossip"
G.ALWAYS = "autogossip.always"
G.NEVER = "autogossip.never"
G.CHAIN_MAX = 3
G.PENDING_SECONDS = 10
G.ABSENCE_SECONDS = 60
G.NPC_CHECK_SECONDS = 1
G.COUNTS_MAX = 200
G.TRACE_MAX = 40
-- Gossip icons (fileIDs) from the references; checked on day one.
G.BINDER = { [132052] = true, [136458] = true }
G.HEALER = { [132054] = true }
G.SERVICE_FIXED = { [132057] = true, [132058] = true }      -- taxi, trainer
-- Blizzard's gossip icon files, resolved with GetFileIDFromPath. The client's
-- set has no auctioneer or stable master icon: those NPCs aren't `services`.
G.SERVICE_PATHS = { "Interface\\GossipFrame\\VendorGossipIcon", "Interface\\GossipFrame\\TrainerGossipIcon",
    "Interface\\GossipFrame\\BankerGossipIcon", "Interface\\GossipFrame\\TaxiGossipIcon" }
-- Interactions that show a pick went through (Enum.PlayerInteractionType
-- names). Never Binder, TalentMaster, SpiritHealer, AreaSpiritHealer, Gossip
-- or QuestGiver: their confirmations come through those interactions.
G.SERVICE_TYPES = { "Merchant", "Vendor", "TaxiNode", "Trainer", "Banker", "GuildBanker", "Auctioneer",
    "StableMaster", "MailInfo", "PetitionVendor", "GuildTabardVendor", "BattleMaster" }
G.LONE = { "off", "services", "most", "any" }

local state = {
    page = nil,          -- the current page
    pageToken = 0,
    scope = false,       -- the last show's scope (a refresh keeps it)
    chain = nil,
    chainToken = 0,
    pending = nil,       -- the player's pick waiting for a sign
    pendingGen = 0,
    own = false,         -- our own select is running
    services = {},       -- the `services` icons, resolved at Enable
    iconReport = {},
    serviceTypes = {},   -- [interaction type] = true
    meta = {},           -- [optionID] = { icon, lone }: what the offer checks
    heldOffer = nil,     -- an offer waiting for combat to end
    trace = {},
    last = "nothing yet",
}
G.state = state

local events = CreateFrame("Frame")
local hooked = setmetatable({}, { __mode = "k" })
local installed = false

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(G.KEY, name) end
local function SS() return GP.SettingsSync end
local function Frame() return GP.AutoGossipFrame end

local function db()
    local d = GP.db
    if not d then return { counts = {}, names = {}, confirms = {} } end
    d.autogossip = type(d.autogossip) == "table" and d.autogossip or {}
    local a = d.autogossip
    for _, k in ipairs({ "counts", "names", "confirms" }) do
        if type(a[k]) ~= "table" then a[k] = {} end
    end
    return a
end

local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- One client call: its value, or nil when it threw or is secret.
local function ask(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

local function trace(what)
    local t = state.trace
    t[#t + 1] = ("%.1f %s"):format(GetTime(), what)
    if #t > G.TRACE_MAX then table.remove(t, 1) end
end

local function available()
    local E = rawget(_G, "Enum")
    local s = E and E.GossipOptionStatus
    return s and plainNumber(s.Available) or 0
end

--------------------------------------------------------------------------------
-- Reading a page

-- A field: its value, and whether it could be read (secret or the wrong
-- kind: false; absent: nil, true).
local function field(o, key, kind)
    local v = o[key]
    if API.IsSecret(v) then return nil, false end
    if v == nil then return nil, true end
    if type(v) ~= kind then return nil, false end
    return v, true
end

-- Every option, or nil when any can't be read.
function G.ReadOptions()
    local list = ask(C_GossipInfo.GetOptions)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, o in ipairs(list) do
        if API.IsSecret(o) or type(o) ~= "table" then return nil end
        local id, okID = field(o, "gossipOptionID", "number")
        local index, okIndex = field(o, "orderIndex", "number")
        local status, okStatus = field(o, "status", "number")
        local only, okOnly = field(o, "selectOptionWhenOnlyOption", "boolean")
        local icon = field(o, "icon", "number")
        local override = field(o, "overrideIconID", "number")
        local flags = field(o, "flags", "number")
        local name = field(o, "name", "string")
        if not (okID and okIndex and okStatus and okOnly) or index == nil or status == nil then return nil end
        out[#out + 1] = { id = id, index = index, status = status, only = only == true, icon = override or icon,
            flags = flags, name = name }
    end
    return out
end

local function questCount()
    local a, b = ask(C_GossipInfo.GetNumAvailableQuests), ask(C_GossipInfo.GetNumActiveQuests)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    return a + b
end

local function forced()
    local v = ask(C_GossipInfo.ForceGossip)
    if type(v) ~= "boolean" then return nil end
    return v
end

-- The state a decision reads: fresh from the client.
function G.Fresh()
    return { options = G.ReadOptions(), quests = questCount(), force = forced() }
end

--------------------------------------------------------------------------------
-- Deciding (pure, given a state)

-- May the `lone` setting pick an option with this icon?
function G.LoneAllowed(icon)
    local rule = setting("lone")
    if rule == "any" then return true end
    if rule == "off" or not icon then return false end
    if rule == "services" then return state.services[icon] == true end
    return not (G.BINDER[icon] or G.HEALER[icon])     -- "most"
end

-- The option to pick on state `s` ({ options, quests, force }), and why; or
-- nil and why not.
function G.Decide(s)
    if not s.options or s.quests == nil or s.force == nil then return nil, "unreadable" end
    if s.quests > 0 then return nil, "quest business" end
    local opts = s.options
    if #opts == 1 and opts[1].only and not s.force then return nil, "Blizzard picks it" end
    local found
    for _, o in ipairs(opts) do
        if o.id and SS().SetHas(G.ALWAYS, o.id) then
            if found then return nil, "two always options" end
            found = o
        end
    end
    if found then
        if found.status ~= available() then return nil, "not available" end
        return found, "always"
    end
    if #opts ~= 1 then return nil, "several options" end
    if s.force then return nil, "the NPC forces its gossip" end
    local o = opts[1]
    if o.status ~= available() then return nil, "not available" end
    if not G.LoneAllowed(o.icon) then return nil, "the lone rule" end
    return o, "lone"
end

--------------------------------------------------------------------------------
-- Chains

local function endChain(why)
    if state.chain then trace("chain ends: " .. why) end
    state.chain = nil
end

local function newChain()
    state.chainToken = state.chainToken + 1
    state.chain = { token = state.chainToken, picks = 0, ids = {}, locked = false, absence = 0 }
    return state.chain
end

-- After a close: end the chain once the NPC is plainly gone, or after a long
-- absence of pages. Timers carry the chain's token; a page interrupts them.
local function watchChain()
    local chain = state.chain
    if not chain then return end
    chain.absence = chain.absence + 1
    local token, absence = chain.token, chain.absence
    C_Timer.After(G.NPC_CHECK_SECONDS, function()
        local c = state.chain
        if not c or c.token ~= token or c.absence ~= absence or state.page then return end
        if ask(UnitExists, "npc") == false then endChain("the NPC is gone") end
    end)
    C_Timer.After(G.ABSENCE_SECONDS, function()
        local c = state.chain
        if c and c.token == token and c.absence == absence and not state.page then endChain("no page for a while") end
    end)
end

--------------------------------------------------------------------------------
-- The player's option buttons (learning's only evidence)

local function optionType()
    local t = rawget(_G, "GOSSIP_BUTTON_TYPE_OPTION")
    return plainNumber(t) or 3      -- GossipFrameShared.lua:3
end

local function isOptionData(elementData)
    if API.IsSecret(elementData) or type(elementData) ~= "table" then return false end
    local t = elementData.buttonType
    return not API.IsSecret(t) and t == optionType()
end

local function scrollBox()
    local f = rawget(_G, "GossipFrame")
    local panel = f and f.GreetingPanel
    return panel and panel.ScrollBox
end

-- The pending pick resolves: counted (clean), or dropped.
-- The NPC's GUID, when plain (it may be secret: then nothing is known).
local function npcGUID()
    local g = ask(UnitGUID, "npc")
    if type(g) == "string" then return g end
end

-- A sign that the pending pick went through: counted only when it comes in
-- the conversation the pick was made in (the same chain, and the same NPC
-- when both GUIDs are plain). Anything else is no evidence: the pick stays
-- pending, for a late confirmation, until its wait ends.
local function resolveClean()
    local p = state.pending
    if not p then return end
    local chain = state.chain
    if not (chain and chain.token == p.chain) then return end
    local guid = npcGUID()
    if p.npc and guid and guid ~= p.npc then return end
    state.pending = nil
    trace("pick counted: " .. p.id)
    G.Count(p.id)
end

local function onPreClick(self)
    if not G.enabled then return end
    local okData, data = pcall(self.GetElementData, self)
    if okData and data ~= nil and not isOptionData(data) then return end
    local index = ask(self.GetID, self)
    if type(index) == "number" then G.PlayerClicked(index) end
end

local function hookButton(frame, elementData)
    if hooked[frame] or not isOptionData(elementData) then return end
    hooked[frame] = true
    frame:HookScript("PreClick", onPreClick)
end

local function scanButtons()
    local sb = scrollBox()
    if not (sb and sb.ForEachFrame) then return end
    local ok, err = pcall(sb.ForEachFrame, sb, function(frame, elementData) hookButton(frame, elementData) end)
    if not ok then API.Fail("pearl autogossip scan", err) end
end

-- A click on option `index` of the current page.
function G.PlayerClicked(index)
    local page = state.page
    if not (page and page.inScope and page.options) or API.InCombat() then return end
    local opt
    for _, o in ipairs(page.options) do
        if o.index == index then opt = o end
    end
    if not (opt and opt.id) then return end
    if opt.name then db().names[opt.id] = opt.name end
    state.meta[opt.id] = { icon = opt.icon, lone = #page.options == 1 }
    if state.pending then
        -- Two picks before either resolved: neither can be told apart.
        trace("two picks before a sign: neither counted")
        state.pending = nil
        return
    end
    state.pendingGen = state.pendingGen + 1
    local gen = state.pendingGen
    state.pending = { id = opt.id, pageToken = page.token, gen = gen, chain = state.chain and state.chain.token,
        npc = npcGUID() }
    trace("player picks " .. opt.id)
    C_Timer.After(G.PENDING_SECONDS, function()
        if state.pending and state.pending.gen == gen then
            state.pending = nil
            trace("pick " .. opt.id .. ": no sign, not counted")
        end
    end)
end

--------------------------------------------------------------------------------
-- Counting and offering

-- May option `id` be offered?
function G.Offerable(id)
    if not setting("offer") then return false end
    if SS().SetHas(G.ALWAYS, id) or SS().SetHas(G.NEVER, id) or db().confirms[id] then return false end
    local m = state.meta[id]
    if not m then return false end
    if m.icon and (G.BINDER[m.icon] or G.HEALER[m.icon]) then return false end
    if m.lone and G.LoneAllowed(m.icon) then return false end
    return true
end

-- At most COUNTS_MAX entries: the oldest go first.
local function prune(counts)
    local list = {}
    for id, c in pairs(counts) do list[#list + 1] = { id = id, t = type(c) == "table" and tonumber(c.t) or 0 } end
    if #list <= G.COUNTS_MAX then return end
    table.sort(list, function(a, b) return a.t < b.t end)
    for i = 1, #list - G.COUNTS_MAX do counts[list[i].id] = nil end
end

function G.Count(id)
    local counts = db().counts
    local c = counts[id]
    if type(c) ~= "table" then c = { n = 0 } end
    c.n, c.t = (tonumber(c.n) or 0) + 1, GetServerTime()
    counts[id] = c
    prune(counts)
    if c.n >= (setting("repeats") or 3) and G.Offerable(id) then G.Offer(id) end
end

function G.Offer(id)
    if API.InCombat() then
        state.heldOffer = id
        return
    end
    Frame().Offer(id, db().names[id])
end

-- The prompt's answer for option `id`: "always", "later" or "never".
function G.Answer(id, answer)
    local counts = db().counts
    if answer == "always" then
        if not G.Offerable(id) then return false end
        local ok, why = SS().SetAdd(G.ALWAYS, id)
        if not ok then
            say(why == "full" and "Auto gossip: the always list is full." or "Auto gossip: not saved.")
            return false
        end
        counts[id] = nil
        state.last = "always picks " .. id
    elseif answer == "never" then
        local ok, why = SS().SetAdd(G.NEVER, id)
        if not ok then
            say(why == "full" and "Auto gossip: the never list is full." or "Auto gossip: not saved.")
            return false
        end
        counts[id] = nil
    else
        counts[id] = nil
    end
    return true
end

-- Option `id` asks for a confirmation: never offered again, and off the
-- always list.
local function confirmed(id, why)
    db().confirms[id] = true
    db().counts[id] = nil
    if state.pending and state.pending.id == id then state.pending = nil end
    Frame().Withdraw(id)
    if state.heldOffer == id then state.heldOffer = nil end
    if SS().SetHas(G.ALWAYS, id) then
        SS().SetRemove(G.ALWAYS, id)
        say(("Auto gossip: %s asks for a confirmation (%s), so it is no longer picked by itself.")
            :format(db().names[id] and ('"' .. db().names[id] .. '"') or ("option " .. id), why))
    end
    trace("confirmation for " .. id .. " (" .. why .. ")")
end

-- A confirmation that names no option: the single pending pick's.
local function confirmedPending(why)
    local p = state.pending
    if p then confirmed(p.id, why) end
end

--------------------------------------------------------------------------------
-- Pages and the decision

local function attempt(token)
    scanButtons()
    local page = state.page
    if not (G.enabled and page and page.token == token) or page.selected then return end
    if not page.inScope then return end
    if API.InCombat() then state.last = "in combat"; return end
    if IsShiftKeyDown() then state.last = "Shift held"; return end
    local chain = state.chain
    if not chain or chain.locked or chain.picks >= G.CHAIN_MAX then state.last = "the chain's cap"; return end
    local cand, why = G.Decide(page)
    if not cand then state.last = why; return end
    if cand.id and chain.ids[cand.id] then state.last = "already picked in this chain"; return end
    local again = G.Decide(G.Fresh())
    if not again or again.id ~= cand.id or again.index ~= cand.index then state.last = "changed"; return end
    -- Charged before the call: a page shown inside the select is a new one.
    page.selected = true
    chain.picks = chain.picks + 1
    if cand.id then chain.ids[cand.id] = true else chain.locked = true end
    state.own = true
    local ok, err
    if cand.id then ok, err = pcall(C_GossipInfo.SelectOption, cand.id)
    else ok, err = pcall(C_GossipInfo.SelectOptionByIndex, cand.index) end
    state.own = false
    if not ok then API.Fail("pearl autogossip select", err) end
    state.last = ("picked %s (%s)"):format(cand.id or ("index " .. cand.index), why)
    trace(state.last)
end

local function newPage(kind, textureKit)
    if kind == "show" then
        state.scope = not API.IsSecret(textureKit) and textureKit == nil and ask(UnitExists, "npc") == true
    end
    state.pageToken = state.pageToken + 1
    local page = { token = state.pageToken, inScope = state.scope, selected = false }
    local s = G.Fresh()
    page.options, page.quests, page.force = s.options, s.quests, s.force
    state.page = page
    trace(kind .. (page.inScope and "" or " (out of scope)"))
    -- A chain starts with its first page. (An absence ends with a page: its
    -- timers need no page open, and every close starts a new count.)
    if page.inScope and not state.chain then newChain() end
    -- A new page shows the player's pick went through.
    if kind == "show" and state.pending and state.pending.pageToken ~= page.token then resolveClean() end
    local token = page.token
    C_Timer.After(0, function() attempt(token) end)
end

-- Selections seen on the current page cancel its pending decision; ours are
-- marked before they're made, so a page shown inside them keeps its own.
local function onSelect()
    if state.own or not G.enabled then return end
    if state.page then state.page.selected = true end
end

local function serviceTypes()
    local E = rawget(_G, "Enum")
    local T = E and E.PlayerInteractionType
    local set = {}
    if type(T) == "table" then
        for _, name in ipairs(G.SERVICE_TYPES) do
            local v = plainNumber(T[name])
            if v then set[v] = true end
        end
    end
    return set
end

local function resolveIcons()
    local services, report = {}, {}
    for id in pairs(G.SERVICE_FIXED) do services[id] = true end
    for _, path in ipairs(G.SERVICE_PATHS) do
        local id = ask(GetFileIDFromPath, path)
        if type(id) == "number" and id > 0 then
            services[id] = true
            report[#report + 1] = path .. " = " .. id
        else
            report[#report + 1] = path .. ": not found"
        end
    end
    state.services, state.iconReport = services, report
end

-- Once, at the first Enable: none of these can be undone, so each checks
-- that the pearl is on.
local function install()
    if installed then return end
    installed = true
    hooksecurefunc(C_GossipInfo, "SelectOption", onSelect)
    hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", onSelect)
    local sb = scrollBox()
    local SU = rawget(_G, "ScrollUtil")
    if sb and SU and SU.AddInitializedFrameCallback then
        local ok, err = pcall(SU.AddInitializedFrameCallback, sb,
            function(_, frame, elementData) hookButton(frame, elementData) end, G, false)
        if not ok then API.Fail("pearl autogossip scroll callback", err) end
    else
        API.Fail("pearl autogossip scroll callback", "GossipFrame's ScrollBox or ScrollUtil missing")
    end
end

events:SetScript("OnEvent", function(_, event, a1)
    API.NoteCombat(event)
    if event == "GOSSIP_SHOW" then
        newPage("show", a1)
    elseif event == "GOSSIP_OPTIONS_REFRESHED" then
        newPage("refresh")
    elseif event == "GOSSIP_CLOSED" then
        state.page = nil
        local continuing = not (not API.IsSecret(a1) and a1 == false)
        trace("close" .. (continuing and " (continuing or unknown)" or ""))
        if not continuing then endChain("closed") else watchChain() end
    elseif event == "GOSSIP_CONFIRM" or event == "GOSSIP_ENTER_CODE" then
        local id = plainNumber(a1)
        if id then confirmed(id, event == "GOSSIP_CONFIRM" and "a confirmation" or "a code")
        else confirmedPending("a confirmation") end
    elseif event == "CONFIRM_BINDER" or event == "CONFIRM_TALENT_WIPE" or event == "CONFIRM_XP_LOSS" then
        confirmedPending(event == "CONFIRM_BINDER" and "binding" or event == "CONFIRM_TALENT_WIPE" and "talents"
            or "the spirit healer")
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local t = plainNumber(a1)
        trace("interaction " .. tostring(t))
        if t and state.serviceTypes[t] then resolveClean() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        endChain("loading screen")
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- An open prompt goes away for the fight and comes back after it.
        local id = Frame().Hold()
        if id then state.heldOffer = id end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local id = state.heldOffer
        state.heldOffer = nil
        if id and G.Offerable(id) then G.Offer(id) end
    end
end)

--------------------------------------------------------------------------------
-- Commands

local function npcID()
    local guid = npcGUID()
    return guid and tonumber(guid:match("%-(%d+)%-%x+$"))
end

local function optionText(id)
    local n = db().names[id]
    return n and ('"' .. n .. '"') or ("option " .. id)
end
G.OptionText = optionText

function G.Report()
    local page = state.page
    say(("Auto gossip: %s; lone options: %s; last: %s."):format(G.enabled and "on" or "off",
        tostring(setting("lone")), state.last))
    if page and page.options then
        say(("  This page (NPC %s, quests %s, forced %s):"):format(tostring(npcID() or "unknown"),
            tostring(page.quests), tostring(page.force)))
        for _, o in ipairs(page.options) do
            say(("    ID %s, index %d, icon %s, status %d, flags %s, Blizzard picks %s: %s"):format(
                tostring(o.id or "hidden"), o.index, tostring(o.icon), o.status, tostring(o.flags),
                o.only and "yes" or "no", o.name or "?"))
        end
    else
        say("  No gossip page open: talk to an NPC, then /gpearls gossip.")
    end
    for _, line in ipairs(state.iconReport) do say("  Icon " .. line) end
end

function G.Trace()
    say("Auto gossip: the last events.")
    for _, line in ipairs(state.trace) do say("  " .. line) end
end

function G.List()
    local always, never = SS().SetMembers(G.ALWAYS), SS().SetMembers(G.NEVER)
    say(("Auto gossip: %d always picked, %d never offered."):format(#always, #never))
    for _, id in ipairs(always) do say("  Always " .. optionText(id) .. " (" .. id .. ")") end
    for _, id in ipairs(never) do say("  Never offered " .. optionText(id) .. " (" .. id .. ")") end
end

local function command(arg)
    local verb, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local id = tonumber(rest)
    if verb == "always" and id then
        local ok, why = SS().SetAdd(G.ALWAYS, id)
        if ok then SS().SetRemove(G.NEVER, id) end
        return say(ok and ("Auto gossip: always picks " .. optionText(id) .. ".") or ("Auto gossip: not added (" .. tostring(why) .. ")."))
    elseif verb == "forget" and id then
        SS().SetRemove(G.ALWAYS, id)
        SS().SetRemove(G.NEVER, id)
        db().counts[id] = nil
        return say("Auto gossip: forgot " .. optionText(id) .. ".")
    elseif verb == "list" then
        return G.List()
    elseif verb == "trace" then
        return G.Trace()
    end
    G.Report()
end

--------------------------------------------------------------------------------
-- The pearl

-- Anything pending is dropped: a decision, a pick, a prompt.
local function cancel()
    if state.page then state.page.selected = true end
    state.pending = nil
    state.heldOffer = nil
    Frame().Withdraw()
end

local function enable()
    G.enabled = true
    resolveIcons()
    state.serviceTypes = serviceTypes()
    install()
    API.RegisterEvents(events, { "GOSSIP_SHOW", "GOSSIP_OPTIONS_REFRESHED", "GOSSIP_CLOSED", "GOSSIP_CONFIRM",
        "GOSSIP_ENTER_CODE", "CONFIRM_BINDER", "CONFIRM_TALENT_WIPE", "CONFIRM_XP_LOSS",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED" })
end

local function disable()
    G.enabled = false
    cancel()
    state.page = nil
    endChain("switched off")
    events:UnregisterAllEvents()
end

GP.SettingsSync.RegisterSet(G.ALWAYS)
GP.SettingsSync.RegisterSet(G.NEVER)

GP.Pearls.Register({
    key = G.KEY,
    name = "Auto gossip",
    desc = "Picks an NPC's gossip option for you when it's safe, and learns the ones you keep choosing.",
    help = "When an NPC has a single gossip option, it is picked for you (the setting decides which: never the "
        .. "hearthstone binding or the spirit healer by default). When you choose the same option at an NPC a few "
        .. "times, it offers to always pick it. Never in combat, never with Shift held, never while the NPC has a "
        .. "quest for you, and at most three picks in a row. Anything that costs money, binds your hearthstone or "
        .. "resets talents still asks you first. /gpearls gossip shows the options of the NPC you're talking to; "
        .. "/gpearls gossip list, always <id>, forget <id>. Unverified until the game is live.",
    default = true,
    category = "Automation",
    section = "NPCs",
    defaults = { lone = "most", offer = true, repeats = 3 },
    choices = { lone = G.LONE },
    ranges = { repeats = { 2, 10 } },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.AutoGossipFrame.Configure(panel, refreshers) end,
    onSettingChanged = function() if G.enabled then cancel() end end,
    commands = { gossip = { help = "[list | trace | always <id> | forget <id>] - the gossip options of the NPC "
        .. "you're talking to, and auto gossip's lists", run = command } },
})

G._test = { events = events, onPreClick = onPreClick, hooked = hooked, db = db }
