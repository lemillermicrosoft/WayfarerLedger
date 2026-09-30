local ADDON_NAME, WL = ...
_G.WayfarerLedger = WL

WL.VERSION = "0.2.0-rc.1"
WL.SCHEMA = 3
WL.MARKERS = { positive = "Positive", neutral = "Neutral", caution = "Caution" }
WL.APPEARANCES = { blizzard = "Blizzard / native", bronze = "Bronze / custom" }
WL.MAX_ENCOUNTERS = 40
WL.MAX_TIMELINE = 100
WL.MAX_PLAYERS = 5000
WL.callbacks, WL.appearanceCallbacks = {}, {}
WL.seenThisSession, WL.groupPresence = {}, {}
WL.activeGroupSession = nil

local defaults = {
    schema = WL.SCHEMA,
    players = {},
    timeline = {},
    backups = {},
    options = {
        appearance = "blizzard",
        storageScope = "account",
        tooltip = true,
        tooltipNotes = false,
        notifyTarget = false,
        recordParties = true,
        recordRaid = true,
        muteChat = false,
        guildPatterns = {},
        windowPosition = { x = 0, y = 0 },
        sort = "recent",
        markerFilter = "all",
    },
}
local charDefaults = { schema = WL.SCHEMA, players = {}, timeline = {}, backups = {} }

function WL:IsSecretValue(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    if not ok then return true end
    return secret ~= false
end

function WL:SafeType(value)
    if self:IsSecretValue(value) then return nil end
    return type(value)
end

function WL:IsSafeText(value)
    if self:IsSecretValue(value) or type(value) ~= "string" then return false end
    local ok, length = pcall(string.len, value)
    return ok and type(length) == "number" and length > 0
end

function WL:SafeBooleanValue(value)
    if self:IsSecretValue(value) or type(value) ~= "boolean" then return nil end
    return value
end

function WL:SafeBooleanCall(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if not ok or self:IsSecretValue(value) or type(value) ~= "boolean" then return nil end
    return value
end

function WL:SafeNumber(value, minimum, maximum)
    if self:IsSecretValue(value) or type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
    if minimum and value < minimum then return minimum end
    if maximum and value > maximum then return maximum end
    return value
end

function WL:SafeNumberCall(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if not ok then return nil end
    return self:SafeNumber(value)
end

function WL:CleanText(value, maxLength, allowEmpty)
    if self:IsSecretValue(value) or type(value) ~= "string" then return nil end
    local ok, clean = pcall(function()
        local result = value:gsub("[%z\1-\8\11\12\14-\31\127]", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return result:sub(1, maxLength or 200)
    end)
    if not ok or type(clean) ~= "string" then return nil end
    if clean == "" and not allowEmpty then return nil end
    return clean
end

local function copyDefaults(target, source)
    for key, value in pairs(source) do
        local current = target[key]
        if WL:IsSecretValue(current) or current == nil then
            if type(value) == "table" then target[key] = {}; copyDefaults(target[key], value) else target[key] = value end
        elseif type(value) == "table" and type(current) == "table" then
            copyDefaults(current, value)
        end
    end
end

function WL:NormalizeAppearance(value)
    value = self:CleanText(value, 20)
    return (value == "bronze") and "bronze" or "blizzard"
end

function WL:GetAppearance()
    local options = WayfarerLedgerDB and WayfarerLedgerDB.options
    return self:NormalizeAppearance(options and options.appearance)
end
function WL:RegisterAppearanceCallback(callback) if type(callback) == "function" then self.appearanceCallbacks[#self.appearanceCallbacks + 1] = callback end end
function WL:ApplyAppearance() local value = self:GetAppearance(); for _, callback in ipairs(self.appearanceCallbacks) do pcall(callback, value) end end
function WL:SetAppearance(value)
    if type(WayfarerLedgerDB) ~= "table" or type(WayfarerLedgerDB.options) ~= "table" then return false end
    WayfarerLedgerDB.options.appearance = self:NormalizeAppearance(value); self:ApplyAppearance(); return true
end

local function localRealm()
    local api = GetNormalizedRealmName or GetRealmName
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api)
    if not ok then return nil end
    value = WL:CleanText(value, 80)
    return value and value:gsub("%s+", "") or nil
end

-- Canonical keys are case-folded Name-Realm strings. Display casing remains in record.name.
function WL:NormalizeName(name, realm)
    name = self:CleanText(name, 80)
    realm = self:CleanText(realm, 80)
    if not name then return nil end
    local embeddedName, embeddedRealm = name:match("^([^%-]+)%-(.+)$")
    if embeddedName and embeddedRealm then name, realm = embeddedName, embeddedRealm end
    realm = realm or localRealm()
    if realm then realm = realm:gsub("%s+", "") end
    name = name:gsub("%s+", "")
    if name == "" then return nil end
    local full = realm and (name .. "-" .. realm) or name
    return full:lower(), name
end

function WL:NameFromUnit(unit)
    unit = self:CleanText(unit, 40)
    if not unit then return nil end
    local exists = self:SafeBooleanCall(UnitExists, unit)
    local player = self:SafeBooleanCall(UnitIsPlayer, unit)
    local selfUnit = self:SafeBooleanCall(UnitIsUnit, unit, "player")
    if exists ~= true or player ~= true or selfUnit ~= false then return nil end
    if type(UnitName) ~= "function" then return nil end
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or self:IsSecretValue(name) or self:IsSecretValue(realm) then return nil end
    return self:NormalizeName(name, realm)
end

local function now()
    local value = WL:SafeNumberCall(time)
    return value and math.floor(value) or 0
end

local function safeContext()
    local parts = {}
    if type(GetZoneText) == "function" then
        local ok, zone = pcall(GetZoneText)
        zone = ok and WL:CleanText(zone, 100) or nil
        if zone then parts[#parts + 1] = zone end
    end
    if type(IsInInstance) == "function" then
        local ok, inInstance, instanceType = pcall(IsInInstance)
        if ok and WL:SafeBooleanValue(inInstance) == true then
            instanceType = WL:CleanText(instanceType, 30)
            if instanceType then parts[#parts + 1] = instanceType end
        end
    end
    return #parts > 0 and table.concat(parts, " · ") or "World"
end
WL.SafeContext = safeContext

local function sanitizeEncounter(item)
    if WL:IsSecretValue(item) or type(item) ~= "table" then return nil end
    local stamp = WL:SafeNumber(item.at, 0, 4102444800)
    local context = WL:CleanText(item.context, 140)
    local kind = WL:CleanText(item.kind, 20)
    if not stamp then return nil end
    return { at = math.floor(stamp), context = context or "Unknown", kind = (kind == "raid" or kind == "party" or kind == "target") and kind or "other" }
end

local function sanitizeRecord(record, fallbackKey)
    if WL:IsSecretValue(record) or type(record) ~= "table" then return nil end
    local rawKey = WL:CleanText(record.key, 180) or WL:CleanText(fallbackKey, 180)
    local key, fallbackName = WL:NormalizeName(rawKey)
    local name = WL:CleanText(record.name, 80) or fallbackName
    if not key or not name then return nil end
    local clean = {
        key = key, name = name, guild = WL:CleanText(record.guild, 120),
        lastSeen = math.floor(WL:SafeNumber(record.lastSeen, 0, 4102444800) or 0),
        context = WL:CleanText(record.context, 140) or "Unknown",
        metCount = math.floor(WL:SafeNumber(record.metCount, 0, 999999) or 0),
        marker = "neutral",
        tags = WL:CleanText(record.tags, 300, true) or "",
        note = WL:CleanText(record.note, 2000, true) or "",
        manual = WL:SafeBooleanValue(record.manual) == true,
        encounters = {},
    }
    local marker = WL:CleanText(record.marker, 20)
    if marker and WL.MARKERS[marker] then clean.marker = marker end
    if not WL:IsSecretValue(record.encounters) and type(record.encounters) == "table" then
        for _, item in ipairs(record.encounters) do
            local encounter = sanitizeEncounter(item)
            if encounter then clean.encounters[#clean.encounters + 1] = encounter end
            if #clean.encounters >= WL.MAX_ENCOUNTERS then break end
        end
    end
    if #clean.encounters == 0 and clean.lastSeen > 0 then
        clean.encounters[1] = { at = clean.lastSeen, context = clean.context, kind = clean.manual and "target" or "other" }
    end
    return clean
end
WL.SanitizeRecord = sanitizeRecord

local function mergeText(preferred, other, delimiter, limit)
    preferred, other = preferred or "", other or ""
    if preferred == "" then return other:sub(1, limit) end
    if other == "" or preferred == other or preferred:find(other, 1, true) then return preferred:sub(1, limit) end
    if other:find(preferred, 1, true) then return other:sub(1, limit) end
    return (preferred .. delimiter .. other):sub(1, limit)
end

local function mergeRecord(first, second)
    if not first then return second end
    if not second then return first end
    local newer, older = first, second
    if (second.lastSeen or 0) > (first.lastSeen or 0) then newer, older = second, first end
    local merged = {
        key = newer.key, name = newer.name or older.name, guild = newer.guild or older.guild,
        lastSeen = math.max(first.lastSeen or 0, second.lastSeen or 0), context = newer.context or older.context,
        metCount = math.max(first.metCount or 0, second.metCount or 0),
        marker = newer.marker ~= "neutral" and newer.marker or older.marker or "neutral",
        tags = mergeText(newer.tags, older.tags, ", ", 300),
        note = mergeText(newer.note, older.note, "\n---\n", 2000),
        manual = first.manual or second.manual, encounters = {},
    }
    local all = {}
    for _, source in ipairs({ first.encounters or {}, second.encounters or {} }) do
        for _, item in ipairs(source) do
            local token = (item.at or 0) .. "\31" .. (item.kind or "") .. "\31" .. (item.context or "")
            if not all[token] then all[token] = item; merged.encounters[#merged.encounters + 1] = item end
        end
    end
    table.sort(merged.encounters, function(a, b) return a.at > b.at end)
    while #merged.encounters > WL.MAX_ENCOUNTERS do table.remove(merged.encounters) end
    return merged
end
WL.MergeRecord = mergeRecord

local function sanitizeTimeline(db)
    local clean = {}
    if WL:IsSecretValue(db.timeline) or type(db.timeline) ~= "table" then db.timeline = clean; return end
    for _, session in ipairs(db.timeline) do
        if not WL:IsSecretValue(session) and type(session) == "table" then
            local started = WL:SafeNumber(session.started, 0, 4102444800)
            local ended = WL:SafeNumber(session.ended, 0, 4102444800)
            local context = WL:CleanText(session.context, 140)
            local kind = WL:CleanText(session.kind, 20)
            local members, seen = {}, {}
            if not WL:IsSecretValue(session.members) and type(session.members) == "table" then
                for _, raw in ipairs(session.members) do
                    local key = WL:NormalizeName(raw)
                    if key and not seen[key] and #members < 40 then members[#members + 1] = key; seen[key] = true end
                end
            end
            if started then clean[#clean + 1] = { started = math.floor(started), ended = math.floor(ended or started), context = context or "Unknown", kind = kind == "raid" and "raid" or "party", members = members } end
        end
        if #clean >= WL.MAX_TIMELINE then break end
    end
    table.sort(clean, function(a, b) return a.started > b.started end)
    db.timeline = clean
end

local function migrateDB(db)
    local migrated = {}
    if not WL:IsSecretValue(db.players) and type(db.players) == "table" then
        for rawKey, rawRecord in pairs(db.players) do
            if not WL:IsSecretValue(rawKey) then
                local clean = sanitizeRecord(rawRecord, rawKey)
                if clean then migrated[clean.key] = mergeRecord(migrated[clean.key], clean) end
            end
        end
    end
    db.players = migrated
    sanitizeTimeline(db)
    db.schema = WL.SCHEMA
end

function WL:GetStore(scope)
    local db = scope == "character" and WayfarerLedgerCharDB or WayfarerLedgerDB
    return db.players
end
function WL:GetTimeline(scope)
    local db = scope == "character" and WayfarerLedgerCharDB or WayfarerLedgerDB
    return db.timeline
end
function WL:GetScope() return self:CleanText(WayfarerLedgerDB.options.storageScope, 20) == "character" and "character" or "account" end
function WL:SetScope(scope) WayfarerLedgerDB.options.storageScope = scope == "character" and "character" or "account"; self:FireChanged() end
function WL:GetRecord(key, scope)
    key = self:NormalizeName(key)
    if not key then return nil end
    if scope then return self:GetStore(scope)[key] end
    return WayfarerLedgerCharDB.players[key] or WayfarerLedgerDB.players[key]
end
function WL:RegisterCallback(callback) if type(callback) == "function" then self.callbacks[#self.callbacks + 1] = callback end end
function WL:FireChanged() for _, callback in ipairs(self.callbacks) do pcall(callback) end end

local function addEncounter(record, kind, context, stamp)
    record.encounters = type(record.encounters) == "table" and record.encounters or {}
    local previous = record.encounters[1]
    -- Coalesce event bursts for the same context and kind within five minutes.
    if previous and previous.kind == kind and previous.context == context and stamp - (previous.at or 0) < 300 then previous.at = stamp
    else table.insert(record.encounters, 1, { at = stamp, kind = kind, context = context }) end
    while #record.encounters > WL.MAX_ENCOUNTERS do table.remove(record.encounters) end
end

function WL:AddUnit(unit, context, manual, kind)
    local key, displayName = self:NameFromUnit(unit)
    if not key then return false, "Select a visible, non-secret player target first." end
    local scope, store = self:GetScope(), self:GetStore(self:GetScope())
    local record = store[key] or { key = key, marker = "neutral", tags = "", note = "", metCount = 0, encounters = {} }
    record.name = displayName or record.name or key
    if type(GetGuildInfo) == "function" then
        local ok, guild = pcall(GetGuildInfo, unit)
        guild = ok and self:CleanText(guild, 120) or nil
        if guild then record.guild = guild end
    end
    local stamp, cleanContext = now(), self:CleanText(context, 140) or safeContext()
    record.lastSeen, record.context = stamp, cleanContext
    record.metCount = math.min((self:SafeNumber(record.metCount, 0, 999999) or 0) + 1, 999999)
    record.manual = manual == true or record.manual == true
    addEncounter(record, kind or (manual and "target" or "party"), cleanContext, stamp)
    store[key] = record
    self:FireChanged()
    return true, record, scope
end

local function finishGroupSession()
    local active = WL.activeGroupSession
    if not active then return end
    local timeline = WL:GetTimeline(active.scope)
    table.insert(timeline, 1, active.session)
    while #timeline > WL.MAX_TIMELINE do table.remove(timeline) end
    WL.activeGroupSession = nil
end

function WL:RecordGroup()
    if not WayfarerLedgerDB or not WayfarerLedgerDB.options then return end
    local raidCount = self:SafeNumberCall(GetNumRaidMembers) or 0
    local raidFlag = self:SafeBooleanCall(IsInRaid)
    local inRaid = raidFlag == true or raidCount > 0
    local recordRaid = self:SafeBooleanValue(WayfarerLedgerDB.options.recordRaid) == true
    local recordParties = self:SafeBooleanValue(WayfarerLedgerDB.options.recordParties) == true
    if (inRaid and not recordRaid) or (not inRaid and not recordParties) then finishGroupSession(); self.groupPresence = {}; return end
    local count = inRaid and (self:SafeNumberCall(GetNumGroupMembers) or raidCount) or (self:SafeNumberCall(GetNumSubgroupMembers) or self:SafeNumberCall(GetNumPartyMembers) or 0)
    count = math.max(0, math.min(40, math.floor(count)))
    if count == 0 then finishGroupSession(); self.groupPresence = {}; self:FireChanged(); return end
    local kind, prefix, context = inRaid and "raid" or "party", inRaid and "raid" or "party", safeContext()
    local scope, present, members = self:GetScope(), {}, {}
    local active = self.activeGroupSession
    local sessionChanged = not active or active.scope ~= scope or active.session.kind ~= kind or active.session.context ~= context
    for index = 1, count do
        local unit = prefix .. index
        local key = self:NameFromUnit(unit)
        if key then
            present[key], members[#members + 1] = true, key
            if not self.groupPresence[key] or sessionChanged then self:AddUnit(unit, (inRaid and "Raid" or "Party") .. " · " .. context, false, kind) end
        end
    end
    active = self.activeGroupSession
    if sessionChanged then
        finishGroupSession()
        active = { scope = scope, session = { started = now(), ended = now(), context = context, kind = kind, members = {} } }
        self.activeGroupSession = active
    end
    active.session.ended, active.session.members = now(), members
    self.groupPresence = present
    self:FireChanged()
end

function WL:Forget(key, scope)
    key = self:NormalizeName(key)
    if not key then return false end
    local store = self:GetStore(scope or self:GetScope())
    if store[key] then store[key] = nil; self:FireChanged(); return true end
    return false
end

function WL:SaveRecord(key, fields, scope)
    key = self:NormalizeName(key)
    if not key or self:IsSecretValue(fields) or type(fields) ~= "table" then return false end
    local record = self:GetStore(scope or self:GetScope())[key]
    if not record then return false end
    record.note = self:CleanText(fields.note, 2000, true) or ""
    record.tags = self:CleanText(fields.tags, 300, true) or ""
    local marker = self:CleanText(fields.marker, 20)
    record.marker = marker and self.MARKERS[marker] and marker or "neutral"
    self:FireChanged(); return true
end

function WL:MoveRecord(key, fromScope, toScope, keepSource)
    key = self:NormalizeName(key)
    if not key or fromScope == toScope then return false, "Choose a different destination scope." end
    local source, destination = self:GetStore(fromScope), self:GetStore(toScope)
    local record = source[key]
    if not record then return false, "The selected record no longer exists." end
    destination[key] = mergeRecord(destination[key], sanitizeRecord(record, key))
    if not keepSource then source[key] = nil end
    self:FireChanged(); return true
end

function WL:GuildMatches(guild)
    guild = self:CleanText(guild, 120)
    if not guild then return false end
    local folded = guild:lower()
    local patterns = WayfarerLedgerDB.options.guildPatterns
    if self:IsSecretValue(patterns) or type(patterns) ~= "table" then return false end
    for _, raw in ipairs(patterns) do
        local pattern = self:CleanText(raw, 80)
        if pattern and folded:find(pattern:lower(), 1, true) then return true, pattern end
    end
    return false
end

function WL:FindByAuthor(author)
    local key = self:NormalizeName(author)
    return key and self:GetRecord(key) or nil
end

-- Message text is intentionally ignored and never persisted.
local function chatFilter(_, _, _, author)
    if not WayfarerLedgerDB.options.muteChat then return false end
    local record = WL:FindByAuthor(author)
    return record ~= nil and WL:GuildMatches(record.guild) == true
end
local function installChatFilters()
    if type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
    for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER" }) do ChatFrame_AddMessageEventFilter(event, chatFilter) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "PLAYER_LOGOUT" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and WL:CleanText(arg1, 100) == ADDON_NAME then
        if WL:IsSecretValue(WayfarerLedgerDB) or type(WayfarerLedgerDB) ~= "table" then WayfarerLedgerDB = {} end
        if WL:IsSecretValue(WayfarerLedgerCharDB) or type(WayfarerLedgerCharDB) ~= "table" then WayfarerLedgerCharDB = {} end
        if WL:IsSecretValue(WayfarerLedgerDB.options) or type(WayfarerLedgerDB.options) ~= "table" then WayfarerLedgerDB.options = {} end
        copyDefaults(WayfarerLedgerDB, defaults); copyDefaults(WayfarerLedgerCharDB, charDefaults)
        migrateDB(WayfarerLedgerDB); migrateDB(WayfarerLedgerCharDB)
        local options = WayfarerLedgerDB.options
        options.appearance = WL:NormalizeAppearance(options.appearance)
        options.storageScope = WL:CleanText(options.storageScope, 20) == "character" and "character" or "account"
        for _, key in ipairs({ "tooltip", "tooltipNotes", "notifyTarget", "recordParties", "recordRaid", "muteChat" }) do
            local safe = WL:SafeBooleanValue(options[key]); if safe == nil then options[key] = defaults.options[key] else options[key] = safe end
        end
        options.sort = ({ recent = true, name = true, count = true })[WL:CleanText(options.sort, 20)] and options.sort or "recent"
        options.markerFilter = (WL:CleanText(options.markerFilter, 20) == "positive" or WL:CleanText(options.markerFilter, 20) == "neutral" or WL:CleanText(options.markerFilter, 20) == "caution") and options.markerFilter or "all"
        if WL:IsSecretValue(options.guildPatterns) or type(options.guildPatterns) ~= "table" then options.guildPatterns = {} end
        WL.DB, WL.CharDB = WayfarerLedgerDB, WayfarerLedgerCharDB
        installChatFilters(); WL:ApplyAppearance(); WL:FireChanged()
    elseif event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        WL:RecordGroup()
    elseif event == "PLAYER_LOGOUT" then
        finishGroupSession()
    elseif event == "PLAYER_TARGET_CHANGED" and WayfarerLedgerDB and WayfarerLedgerDB.options and WayfarerLedgerDB.options.notifyTarget then
        local key = WL:NameFromUnit("target")
        local record = key and WL:GetRecord(key)
        if record and not WL.seenThisSession[key] then
            WL.seenThisSession[key] = true
            local safeName = WL:CleanText(record.name, 80) or "saved player"
            print("|cFFC69B55Wayfarer Ledger:|r Met before — " .. safeName)
        end
    end
end)

SLASH_WAYFARERLEDGER1, SLASH_WAYFARERLEDGER2 = "/wayfarer", "/wl"
SlashCmdList.WAYFARERLEDGER = function(message)
    message = WL:CleanText(message, 100, true) or ""
    if message == "add" then
        local ok, result = WL:AddUnit("target", "Manual target · " .. safeContext(), true, "target")
        print(ok and "|cFFC69B55Wayfarer Ledger:|r Added current target locally." or ("|cFFC69B55Wayfarer Ledger:|r " .. result))
    elseif message == "options" and WL.OpenOptions then WL:OpenOptions()
    elseif message == "reset" and WL.ResetWindowPosition then WL:ResetWindowPosition(); print("|cFFC69B55Wayfarer Ledger:|r Window position reset.")
    else WL:ToggleLedger() end
end
