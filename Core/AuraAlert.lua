-- Core/AuraAlert.lua: what aura-alert pearls share (#21; the fixate alert,
-- buff alerts, the paladin reminders). Forever hides auras in combat, for the
-- player too (porting guide, "Auras go dark for the WHOLE GROUP"), so:
--
-- AA.Read(id): one player aura by spell ID, inside one pcall, answering
--   present (a plain table, every field read plain: expiration, duration,
--   source unit), absent (a nil AND C_Secrets.ShouldSpellAuraBeSecret(id)
--   plainly false: this aura is readable now; a spell can be always secret),
--   or unknown (anything else). Never a name.
-- AA.Sounds.New(failKey): the client's own aura sounds
--   (C_UnitAuras.AddAuraSound), registered out of combat (held otherwise),
--   removed when switched off, a refusal recorded under failKey. Unverified
--   for addons until 2026-11-04.
-- AA.Source(unit): "from <name>" material: the source unit's name, or nil
--   whenever anything is secret, missing or not a non-empty string.
-- AA.Entry.New(ids): the evidence of one alert made of several IDs (Buff
--   alerts' rules): per ID an aura answer and an overlay answer kept apart, an
--   ID resolving to present / gone / unknown, the entry shown while any ID is
--   present and cleared only once every ID that made it show is gone; expiry
--   is evidence, never a forced clear.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local AA = {}
GP.AuraAlert = AA

--------------------------------------------------------------------------------
-- Reading one aura

local function tryRead(id)
    local a = C_UnitAuras.GetPlayerAuraBySpellID(id)
    if API.IsSecret(a) then return "unknown" end
    if a == nil then
        local per = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
        if not per then return "unknown" end
        local secret = per(id)
        if API.IsSecret(secret) then return "unknown" end
        if secret == false then return "absent" end
        return "unknown"
    end
    if type(a) ~= "table" then return "unknown" end
    local exp, dur, src = a.expirationTime, a.duration, a.sourceUnit
    if API.IsSecret(exp) or API.IsSecret(dur) then return "unknown" end
    if API.IsSecret(src) or type(src) ~= "string" then src = nil end
    return "present", type(exp) == "number" and exp or 0, type(dur) == "number" and dur or 0, src
end

-- result, expiration (0: none), duration, source unit (or nil).
function AA.Read(id)
    local ok, result, exp, dur, src = pcall(tryRead, id)
    if not ok then return "unknown" end
    return result, exp, dur, src
end

-- The name of whoever applied it, or nil.
function AA.Source(unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    local ok, name = pcall(UnitName, unit)
    if not ok or API.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

--------------------------------------------------------------------------------
-- The client's aura sounds

AA.Sounds = {}
local SoundsMT = { __index = {} }

function AA.Sounds.New(failKey)
    return setmetatable({ failKey = failKey, sounds = {}, status = {}, pending = false }, SoundsMT)
end

-- Register a sound per ID (opts: fileID, throttle, trigger). In combat it is
-- held: Register again at PLAYER_REGEN_ENABLED when `pending`.
function SoundsMT.__index:Register(ids, opts)
    if API.InCombat() then self.pending = true; return end
    self.pending = false
    local trigger = opts.trigger
        or (Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added) or 0
    for _, id in ipairs(ids) do
        if not self.sounds[id] then
            local ok, soundID = pcall(C_UnitAuras.AddAuraSound, trigger, {
                unitToken = "player", spellID = id, soundFileID = opts.fileID,
                outputChannel = "Master", throttleSeconds = opts.throttle,
            })
            if ok and not API.IsSecret(soundID) and type(soundID) == "number" then
                self.sounds[id], self.status[id] = soundID, "registered"
            else
                self.status[id] = "refused"
                API.Fail(self.failKey, ok and "no sound ID" or tostring(soundID))
            end
        end
    end
end

-- Remove the sounds of these IDs (all when nil), marking them `status`.
function SoundsMT.__index:Remove(ids, status)
    for id, soundID in pairs(self.sounds) do
        local listed = ids == nil
        if not listed then for _, x in ipairs(ids) do if x == id then listed = true end end end
        if listed then
            pcall(C_UnitAuras.RemoveAuraSound, soundID)
            self.sounds[id] = nil
        end
    end
    for _, id in ipairs(ids or {}) do self.status[id] = status end
    if ids == nil then for id in pairs(self.status) do self.status[id] = status end end
    self.pending = false
end

--------------------------------------------------------------------------------
-- The evidence of one entry

AA.Entry = {}
local EntryMT = { __index = {} }

function AA.Entry.New(ids)
    local e = setmetatable({ ids = ids, aura = {}, exp = {}, src = {}, overlay = {}, active = {}, shown = false,
                             since = nil }, EntryMT)
    for _, id in ipairs(ids) do e.aura[id], e.overlay[id] = "unknown", "none" end
    return e
end

-- An aura answer for one ID (AA.Read's). Unknown keeps what was known: a plain
-- expiration read before keeps the countdown running by arithmetic.
function EntryMT.__index:SetAura(id, result, exp, src)
    self.aura[id] = result
    if result == "present" then
        self.exp[id] = exp or 0
        self.src[id] = src
    elseif result == "absent" then
        self.exp[id], self.src[id] = nil, nil
    end
end

-- The IDs whose known plain expiration has passed (now >= it).
function EntryMT.__index:ExpiredIDs(now)
    local out = {}
    for id, exp in pairs(self.exp) do
        if exp > 0 and now >= exp then out[#out + 1] = id end
    end
    return out
end

-- An overlay answer for one ID: "shown" | "hidden".
function EntryMT.__index:SetOverlay(id, state) self.overlay[id] = state end

-- A HIDE with no ID: every overlay shown is now hidden; aura answers stay.
function EntryMT.__index:HideAllOverlays()
    for id, s in pairs(self.overlay) do if s == "shown" then self.overlay[id] = "hidden" end end
end

-- An ID's own plain expiration passed: its aura is absent (expired), whether
-- the last read was present or unknown. Its overlay, if shown, still holds it.
function EntryMT.__index:Expire(id)
    if self.exp[id] then
        self.aura[id] = "absent"
        self.exp[id], self.src[id] = nil, nil
    end
end

-- present / gone / unknown for one ID.
function EntryMT.__index:Resolve(id)
    local a, o = self.aura[id], self.overlay[id]
    if a == "present" or o == "shown" then return "present" end
    if (a == "absent" and o ~= "shown") or (o == "hidden" and a ~= "present") then return "gone" end
    return "unknown"
end

-- Reconcile: "show" (newly shown), "keep", "clear" (newly cleared) or "hidden".
function EntryMT.__index:Update(now)
    local anyPresent = false
    for _, id in ipairs(self.ids) do
        if self:Resolve(id) == "present" then
            anyPresent = true
            self.active[id] = true
        end
    end
    if anyPresent then
        if self.shown then return "keep" end
        self.shown, self.since = true, now
        return "show"
    end
    if not self.shown then return "hidden" end
    for id in pairs(self.active) do
        if self:Resolve(id) ~= "gone" then return "keep" end
    end
    self.shown, self.active, self.since = false, {}, nil
    return "clear"
end

-- The latest plain expiration among the present IDs (0: none), and whether
-- any present ID rests on the overlay alone (no aura read).
function EntryMT.__index:Expiration()
    local latest, overlayOnly = 0, false
    for _, id in ipairs(self.ids) do
        local known = self.exp[id]
        if known and known > latest then latest = known end
        if self.overlay[id] == "shown" and not known then overlayOnly = true end
    end
    return latest, overlayOnly and latest == 0
end

-- Who applied it: the first present ID's source unit.
function EntryMT.__index:SourceUnit()
    for _, id in ipairs(self.ids) do
        if self.aura[id] == "present" and self.src[id] then return self.src[id] end
    end
end

-- Forget everything (switched off, death).
function EntryMT.__index:Reset()
    for _, id in ipairs(self.ids) do self.aura[id], self.overlay[id] = "unknown", "none" end
    self.exp, self.src, self.active, self.shown, self.since = {}, {}, {}, false, nil
end
