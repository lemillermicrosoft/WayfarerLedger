local ADDON_NAME, WL = ...
_G.WayfarerLedger = WL

WL.VERSION = "0.1.0-alpha"
WL.MARKERS = { positive = "Positive", neutral = "Neutral", caution = "Caution" }
WL.callbacks = {}
WL.seenThisSession = {}
WL.groupPresence = {}

local defaults = {
    schema = 1,
    players = {},
    options = {
        storageScope = "account",
        tooltip = true,
        notifyTarget = false,
        recordParties = true,
        muteChat = false,
        guildPatterns = {},
        windowPosition = { x = 0, y = 0 },
    },
}

local charDefaults = { schema = 1, players = {} }

local function copyDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                copyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            copyDefaults(target[key], value)
        end
    end
end

function WL:IsSecretValue(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or type(secret) ~= "boolean" or secret then return true end
    end
    return false
end

function WL:IsSafeText(value)
    if type(value) ~= "string" or self:IsSecretValue(value) then return false end
    local ok, length = pcall(string.len, value)
    return ok and type(length) == "number" and length > 0
end

function WL:SafeBooleanValue(value)
    if type(value) ~= "boolean" or self:IsSecretValue(value) then return nil end
    return value
end

function WL:SafeBooleanCall(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if not ok then return nil end
    return self:SafeBooleanValue(value)
end

function WL:SafeNumberCall(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if not ok or type(value) ~= "number" or self:IsSecretValue(value) or value ~= value then return nil end
    return value
end

function WL:CleanText(value, maxLength)
    if not self:IsSafeText(value) then return nil end
    local ok, clean = pcall(function()
        value = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return value:sub(1, maxLength or 200)
    end)
    return ok and clean ~= "" and clean or nil
end

function WL:NormalizeName(name, realm)
    name = self:CleanText(name, 80)
    realm = self:CleanText(realm, 80)
    if not name then return nil end
    if not realm or realm == "" then
        local realmFunction = GetNormalizedRealmName or GetRealmName
        local ok, localRealm = realmFunction and pcall(realmFunction)
        if ok then
            realm = self:CleanText(localRealm, 80)
            if realm then realm = realm:gsub("%s+", "") end
        end
    end
    if name:find("-", 1, true) then return name end
    return realm and (name .. "-" .. realm) or name
end

function WL:NameFromUnit(unit)
    local exists = self:SafeBooleanCall(UnitExists, unit)
    local player = self:SafeBooleanCall(UnitIsPlayer, unit)
    local selfUnit = self:SafeBooleanCall(UnitIsUnit, unit, "player")
    if exists ~= true or player ~= true or selfUnit ~= false then return nil end
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or self:IsSecretValue(name) or self:IsSecretValue(realm) then return nil end
    return self:NormalizeName(name, realm), self:CleanText(name, 80)
end

function WL:GetStore(scope)
    if scope == "character" then return WayfarerLedgerCharDB.players end
    return WayfarerLedgerDB.players
end

function WL:GetScope()
    return WayfarerLedgerDB.options.storageScope == "character" and "character" or "account"
end

function WL:GetRecord(key, scope)
    if not self:IsSafeText(key) then return nil end
    if scope then return self:GetStore(scope)[key] end
    return WayfarerLedgerCharDB.players[key] or WayfarerLedgerDB.players[key]
end

function WL:FireChanged()
    for _, callback in ipairs(self.callbacks) do pcall(callback) end
end

function WL:RegisterCallback(callback)
    self.callbacks[#self.callbacks + 1] = callback
end

local function safeContext()
    local parts = {}
    local ok, zone = pcall(GetZoneText)
    zone = ok and WL:CleanText(zone, 100) or nil
    if zone then parts[#parts + 1] = zone end
    local okInstance, inInstance, instanceType = pcall(IsInInstance)
    if okInstance and WL:SafeBooleanValue(inInstance) == true and WL:IsSafeText(instanceType) then parts[#parts + 1] = instanceType end
    return #parts > 0 and table.concat(parts, " · ") or "World"
end

function WL:AddUnit(unit, context, manual)
    local key, displayName = self:NameFromUnit(unit)
    if not key then return false, "Select a non-secret player target first." end
    local scope = self:GetScope()
    local store = self:GetStore(scope)
    local record = store[key] or { key = key, marker = "neutral", tags = "", note = "", metCount = 0 }
    record.name = displayName or key
    local ok, guild = pcall(GetGuildInfo, unit)
    guild = ok and not self:IsSecretValue(guild) and self:CleanText(guild, 120) or nil
    if guild then record.guild = guild end
    record.lastSeen = time()
    record.context = self:CleanText(context, 140) or safeContext()
    record.metCount = math.min((tonumber(record.metCount) or 0) + 1, 999999)
    record.manual = manual and true or record.manual
    store[key] = record
    self:FireChanged()
    return true, record
end

function WL:RecordGroup()
    if not WayfarerLedgerDB.options.recordParties then return end
    local raidCount = self:SafeNumberCall(GetNumRaidMembers) or 0
    local raidFlag = self:SafeBooleanCall(IsInRaid)
    local inRaid = raidFlag == true or raidCount > 0
    local prefix = inRaid and "raid" or "party"
    local count
    if inRaid then count = self:SafeNumberCall(GetNumGroupMembers) or raidCount
    else count = self:SafeNumberCall(GetNumSubgroupMembers) or self:SafeNumberCall(GetNumPartyMembers) or 0 end
    count = math.max(0, math.min(40, math.floor(count)))
    local present = {}
    for index = 1, count do
        local unit = prefix .. index
        local key = self:NameFromUnit(unit)
        if key then
            present[key] = true
            if not self.groupPresence[key] then self:AddUnit(unit, "Grouped · " .. safeContext(), false) end
        end
    end
    self.groupPresence = present
end

function WL:Forget(key, scope)
    local store = self:GetStore(scope or self:GetScope())
    if store[key] then store[key] = nil; self:FireChanged(); return true end
    return false
end

function WL:SaveRecord(key, fields, scope)
    local store = self:GetStore(scope or self:GetScope())
    local record = store[key]
    if not record then return false end
    record.note = self:CleanText(fields.note or "", 2000) or ""
    record.tags = self:CleanText(fields.tags or "", 300) or ""
    record.marker = self.MARKERS[fields.marker] and fields.marker or "neutral"
    self:FireChanged()
    return true
end

function WL:GuildMatches(guild)
    guild = self:CleanText(guild, 120)
    if not guild then return false end
    local folded = guild:lower()
    for _, pattern in ipairs(WayfarerLedgerDB.options.guildPatterns) do
        pattern = self:CleanText(pattern, 80)
        if pattern and folded:find(pattern:lower(), 1, true) then return true, pattern end
    end
    return false
end

function WL:FindByAuthor(author)
    local key = self:NormalizeName(author)
    if not key then return nil end
    return self:GetRecord(key)
end

local function chatFilter(_, _, _, author)
    if not WayfarerLedgerDB.options.muteChat then return false end
    local record = WL:FindByAuthor(author)
    if record and WL:GuildMatches(record.guild) then return true end
    return false
end

local function installChatFilters()
    if type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
    for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER" }) do
        ChatFrame_AddMessageEventFilter(event, chatFilter)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        WayfarerLedgerDB = type(WayfarerLedgerDB) == "table" and WayfarerLedgerDB or {}
        WayfarerLedgerCharDB = type(WayfarerLedgerCharDB) == "table" and WayfarerLedgerCharDB or {}
        copyDefaults(WayfarerLedgerDB, defaults)
        copyDefaults(WayfarerLedgerCharDB, charDefaults)
        WL.DB, WL.CharDB = WayfarerLedgerDB, WayfarerLedgerCharDB
        installChatFilters()
        WL:FireChanged()
    elseif event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" then
        WL:RecordGroup()
    elseif event == "PLAYER_TARGET_CHANGED" and WayfarerLedgerDB.options.notifyTarget then
        local key = WL:NameFromUnit("target")
        local record = key and WL:GetRecord(key)
        if record and not WL.seenThisSession[key] then
            WL.seenThisSession[key] = true
            print("|cFFC69B55Wayfarer Ledger:|r Met before — " .. (record.name or key))
        end
    end
end)

SLASH_WAYFARERLEDGER1 = "/wayfarer"
SLASH_WAYFARERLEDGER2 = "/wl"
SlashCmdList.WAYFARERLEDGER = function(message)
    message = WL:CleanText(message, 100) or ""
    if message == "add" then
        local ok, result = WL:AddUnit("target", "Manual target · " .. safeContext(), true)
        print(ok and "|cFFC69B55Wayfarer Ledger:|r Added current target." or ("|cFFC69B55Wayfarer Ledger:|r " .. result))
    elseif message == "options" and WL.OpenOptions then WL:OpenOptions()
    elseif message == "reset" and WL.ResetWindowPosition then
        WL:ResetWindowPosition()
        print("|cFFC69B55Wayfarer Ledger:|r Window position reset.")
    else WL:ToggleLedger() end
end
