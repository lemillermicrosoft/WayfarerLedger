local _, WL = ...

local MAX_BYTES = 1024 * 1024
local MAX_RECORDS = 5000
local MAX_LINES = MAX_RECORDS + 1
local MAX_LINE_BYTES = 4096

local function encode(value)
    if value == nil then return "" end
    if WL:IsSecretValue(value) then return "" end
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
    if not WL:IsSafeText(value) then return "" end
    local ok, decoded = pcall(string.gsub, value, "%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    return ok and decoded or ""
end

local fields = { "key", "name", "guild", "lastSeen", "context", "metCount", "marker", "tags", "note", "manual" }

function WL:ExportData()
    local lines, exported = { "WAYFARER_LEDGER\t1" }, 0
    for _, scope in ipairs({ "account", "character" }) do
        local store = self:GetStore(scope)
        local keys = {}
        for key, record in pairs(store) do
            if #keys < MAX_RECORDS and self:IsSafeText(key) and type(record) == "table" and not self:IsSecretValue(record) then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            if exported >= MAX_RECORDS then break end
            local record, row = store[key], { "R", scope }
            for _, field in ipairs(fields) do row[#row + 1] = encode(record[field]) end
            local line = table.concat(row, "\t")
            if #line <= MAX_LINE_BYTES then
                lines[#lines + 1] = line
                exported = exported + 1
            end
        end
    end
    return table.concat(lines, "\n")
end

function WL:ImportData(text)
    if type(text) ~= "string" or self:IsSecretValue(text) then return false, "Import must be non-secret plain text." end
    local sizeOK, size = pcall(string.len, text)
    if not sizeOK or size > MAX_BYTES then return false, "Import must be plain text under 1 MB." end

    local first, lineCount, recordCount = true, 0, 0
    local staged = { account = {}, character = {} }
    for line in text:gmatch("[^\r\n]+") do
        lineCount = lineCount + 1
        if lineCount > MAX_LINES then return false, "Import exceeds the 5,000-record limit." end
        if #line > MAX_LINE_BYTES then return false, "Import contains an overlong line." end
        if first then
            first = false
            if line ~= "WAYFARER_LEDGER\t1" then return false, "Not a Wayfarer Ledger v1 export." end
        else
            local cells = {}
            for cell in (line .. "\t"):gmatch("(.-)\t") do cells[#cells + 1] = cell end
            if cells[1] ~= "R" or (cells[2] ~= "account" and cells[2] ~= "character") or #cells ~= 12 then
                return false, "Import contains a malformed record."
            end
            local record = {}
            for index, field in ipairs(fields) do record[field] = decode(cells[index + 2]) end
            local key = self:CleanText(record.key, 180)
            local name = self:CleanText(record.name, 80)
            if not key or not name then return false, "Import contains an invalid player identity." end
            record.key, record.name = key, name
            record.guild = self:CleanText(record.guild, 120)
            record.context = self:CleanText(record.context, 140) or "Imported"
            record.tags = self:CleanText(record.tags, 300) or ""
            record.note = self:CleanText(record.note, 2000) or ""
            record.lastSeen = math.max(0, math.min(4102444800, tonumber(record.lastSeen) or 0))
            record.metCount = math.max(0, math.min(999999, tonumber(record.metCount) or 0))
            record.marker = self.MARKERS[record.marker] and record.marker or "neutral"
            record.manual = record.manual == "true"
            staged[cells[2]][key] = record
            recordCount = recordCount + 1
            if recordCount > MAX_RECORDS then return false, "Import exceeds the 5,000-record limit." end
        end
    end
    if first then return false, "Import is empty." end
    for scope, records in pairs(staged) do
        local destination = self:GetStore(scope)
        for key, record in pairs(records) do destination[key] = record end
    end
    self:FireChanged()
    return true, recordCount
end
