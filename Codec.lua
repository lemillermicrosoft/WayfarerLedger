local _, WL = ...

local MAX_BYTES = 1024 * 1024
local MAX_RECORDS = 5000
local MAX_LINES = 200000
local MAX_LINE_BYTES = 8192
local fields = { "key", "name", "guild", "lastSeen", "context", "metCount", "marker", "tags", "note", "manual" }

local function encode(value)
    if WL:IsSecretValue(value) or value == nil then return "" end
    local kind = type(value)
    if kind == "boolean" then value = value and "true" or "false"
    elseif kind == "number" then
        if value ~= value or math.abs(value) == math.huge then return "" end
        value = string.format("%.17g", value)
    elseif kind ~= "string" then return "" end
    if WL:IsSecretValue(value) then return "" end
    return (value:gsub("%%", "%%25"):gsub("\t", "%%09"):gsub("\r", "%%0D"):gsub("\n", "%%0A"))
end

local function decode(value)
    if WL:IsSecretValue(value) or type(value) ~= "string" then return nil end
    local cursor = 1
    while true do
        local position = value:find("%", cursor, true)
        if not position then break end
        local pair = value:sub(position + 1, position + 2)
        if #pair ~= 2 or not pair:match("^%x%x$") then return nil end
        cursor = position + 3
    end
    local ok, decoded = pcall(string.gsub, value, "%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    if not ok or WL:IsSecretValue(decoded) then return nil end
    return decoded
end

local function splitTabs(line)
    local cells, start = {}, 1
    while true do
        local position = line:find("\t", start, true)
        if not position then cells[#cells + 1] = line:sub(start); return cells end
        cells[#cells + 1] = line:sub(start, position - 1)
        start = position + 1
    end
end

local function safeRecordKeys(store)
    local keys = {}
    for key, record in pairs(store) do
        if #keys < MAX_RECORDS and WL:IsSafeText(key) and not WL:IsSecretValue(record) and type(record) == "table" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

function WL:ExportData(scopeOnly)
    local lines, exported = { "WAYFARER_LEDGER\t2" }, 0
    local scopes = scopeOnly and { scopeOnly } or { "account", "character" }
    for _, scope in ipairs(scopes) do
        if scope == "account" or scope == "character" then
            local store = self:GetStore(scope)
            for _, key in ipairs(safeRecordKeys(store)) do
                if exported >= MAX_RECORDS then break end
                local record, row = store[key], { "R", scope }
                for _, field in ipairs(fields) do row[#row + 1] = encode(record[field]) end
                local line = table.concat(row, "\t")
                if #line <= MAX_LINE_BYTES then
                    lines[#lines + 1], exported = line, exported + 1
                    local encounters = not self:IsSecretValue(record.encounters) and type(record.encounters) == "table" and record.encounters or {}
                    for index = #encounters, 1, -1 do
                        local item = encounters[index]
                        if not self:IsSecretValue(item) and type(item) == "table" then
                            local eventLine = table.concat({ "E", scope, encode(key), encode(item.at), encode(item.kind), encode(item.context) }, "\t")
                            if #eventLine <= MAX_LINE_BYTES then lines[#lines + 1] = eventLine end
                        end
                    end
                end
            end
            for index, session in ipairs(self:GetTimeline(scope)) do
                if index > self.MAX_TIMELINE then break end
                local row = { "S", scope, encode(session.started), encode(session.ended), encode(session.kind), encode(session.context) }
                for _, member in ipairs(session.members or {}) do if #row < 46 then row[#row + 1] = encode(member) end end
                local line = table.concat(row, "\t")
                if #line <= MAX_LINE_BYTES then lines[#lines + 1] = line end
            end
        end
    end
    return table.concat(lines, "\n")
end

local function parseRecord(cells)
    local record = {}
    for index, field in ipairs(fields) do
        local value = decode(cells[index + 2])
        if value == nil then return nil, "Import contains invalid escaping." end
        record[field] = value
    end
    record.lastSeen = tonumber(record.lastSeen)
    record.metCount = tonumber(record.metCount)
    record.manual = record.manual == "true"
    record.encounters = {}
    local clean = WL.SanitizeRecord(record, record.key)
    if not clean then return nil, "Import contains an invalid player record." end
    return clean
end

function WL:ImportData(text)
    if self:IsSecretValue(text) or type(text) ~= "string" then return false, "Import must be non-secret plain text." end
    local sizeOK, size = pcall(string.len, text)
    if not sizeOK or size > MAX_BYTES then return false, "Import must be plain text under 1 MB." end

    local first, version, lineCount, recordCount = true, nil, 0, 0
    local staged = { account = {}, character = {} }
    local stagedTimeline = { account = {}, character = {} }
    local eventSeen = { account = {}, character = {} }
    for line in text:gmatch("[^\r\n]+") do
        lineCount = lineCount + 1
        if lineCount > MAX_LINES then return false, "Import has too many lines." end
        if #line > MAX_LINE_BYTES then return false, "Import contains an overlong line." end
        if first then
            first = false
            if line == "WAYFARER_LEDGER\t1" then version = 1
            elseif line == "WAYFARER_LEDGER\t2" then version = 2
            else return false, "Not a supported Wayfarer Ledger export." end
        else
            local cells = splitTabs(line)
            local scope = cells[2]
            if scope ~= "account" and scope ~= "character" then return false, "Import contains an invalid scope." end
            if cells[1] == "R" and #cells == 12 then
                local record, err = parseRecord(cells)
                if not record then return false, err end
                staged[scope][record.key] = self.MergeRecord(staged[scope][record.key], record)
                recordCount = recordCount + 1
                if recordCount > MAX_RECORDS then return false, "Import exceeds the 5,000-record limit." end
            elseif version == 2 and cells[1] == "E" and #cells == 6 then
                local rawKey, rawAt, rawKind, rawContext = decode(cells[3]), decode(cells[4]), decode(cells[5]), decode(cells[6])
                if rawKey == nil or rawAt == nil or rawKind == nil or rawContext == nil then return false, "Import contains invalid encounter escaping." end
                local key = self:NormalizeName(rawKey)
                local record = key and staged[scope][key]
                local stamp = tonumber(rawAt)
                local context, kind = self:CleanText(rawContext, 140), self:CleanText(rawKind, 20)
                if not record or not self:SafeNumber(stamp, 0, 4102444800) or not context or (kind ~= "party" and kind ~= "raid" and kind ~= "target" and kind ~= "other") then
                    return false, "Import contains an invalid or out-of-order encounter."
                end
                if not eventSeen[scope][key] then record.encounters = {}; eventSeen[scope][key] = true end
                table.insert(record.encounters, 1, { at = math.floor(stamp), context = context, kind = kind })
                while #record.encounters > self.MAX_ENCOUNTERS do table.remove(record.encounters) end
            elseif version == 2 and cells[1] == "S" and #cells >= 6 and #cells <= 46 then
                local rawStarted, rawEnded, rawKind, rawContext = decode(cells[3]), decode(cells[4]), decode(cells[5]), decode(cells[6])
                local started, ended = tonumber(rawStarted), tonumber(rawEnded)
                local kind, context = self:CleanText(rawKind, 20), self:CleanText(rawContext, 140)
                if not self:SafeNumber(started, 0, 4102444800) or not self:SafeNumber(ended, 0, 4102444800) or (kind ~= "party" and kind ~= "raid") or not context then return false, "Import contains an invalid group session." end
                local members, seen = {}, {}
                for index = 7, #cells do
                    local rawMember = decode(cells[index]); local key = rawMember and self:NormalizeName(rawMember)
                    if not key then return false, "Import contains an invalid group member." end
                    if not seen[key] then members[#members + 1], seen[key] = key, true end
                end
                if #stagedTimeline[scope] >= self.MAX_TIMELINE then return false, "Import exceeds the group-session limit." end
                stagedTimeline[scope][#stagedTimeline[scope] + 1] = { started = math.floor(started), ended = math.floor(ended), kind = kind, context = context, members = members }
            else return false, "Import contains a malformed record." end
        end
    end
    if first then return false, "Import is empty." end

    local destinationCount = 0
    for _, scope in ipairs({ "account", "character" }) do
        local destination = self:GetStore(scope)
        for _ in pairs(destination) do destinationCount = destinationCount + 1 end
        for key in pairs(staged[scope]) do if not destination[key] then destinationCount = destinationCount + 1 end end
    end
    if destinationCount > self.MAX_PLAYERS then return false, "Import would exceed the 5,000-player database limit." end

    if not self:CreateBackup("Before import") then return false, "Import is valid, but a safety backup could not be created." end
    for _, scope in ipairs({ "account", "character" }) do
        local destination = self:GetStore(scope)
        for key, record in pairs(staged[scope]) do destination[key] = self.MergeRecord(destination[key], record) end
        local timeline, known = self:GetTimeline(scope), {}
        for _, session in ipairs(timeline) do known[(session.started or 0) .. "\31" .. (session.kind or "") .. "\31" .. (session.context or "")] = true end
        for _, session in ipairs(stagedTimeline[scope]) do
            local token = session.started .. "\31" .. session.kind .. "\31" .. session.context
            if not known[token] then timeline[#timeline + 1], known[token] = session, true end
        end
        table.sort(timeline, function(a, b) return (a.started or 0) > (b.started or 0) end)
        while #timeline > self.MAX_TIMELINE do table.remove(timeline) end
    end
    self:FireChanged()
    return true, recordCount
end

function WL:CreateBackup(reason)
    local db = WayfarerLedgerDB
    if not db or self:IsSecretValue(db.backups) or type(db.backups) ~= "table" then return false end
    local text = self:ExportData()
    if #text > MAX_BYTES then return false end
    table.insert(db.backups, 1, { created = self:SafeNumberCall(time) or 0, reason = self:CleanText(reason, 80) or "Manual backup", data = text })
    while #db.backups > 3 do table.remove(db.backups) end
    return true
end

function WL:GetLatestBackup()
    local backups = WayfarerLedgerDB and WayfarerLedgerDB.backups
    if self:IsSecretValue(backups) or type(backups) ~= "table" then return nil end
    local backup = backups[1]
    if self:IsSecretValue(backup) or type(backup) ~= "table" or not self:IsSafeText(backup.data) then return nil end
    return backup
end

function WL:RestoreLatestBackup()
    local backup = self:GetLatestBackup()
    if not backup then return false, "No valid local backup is available." end
    return self:ImportData(backup.data)
end

function WL:ResetScope(scope)
    scope = scope == "character" and "character" or "account"
    if not self:CreateBackup("Before " .. scope .. " reset") then return false, "Reset cancelled because a safety backup could not be created." end
    local db = scope == "character" and WayfarerLedgerCharDB or WayfarerLedgerDB
    db.players, db.timeline = {}, {}
    self:FireChanged()
    return true
end
