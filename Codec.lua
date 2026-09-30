local _, WL = ...

local function encode(value)
    value = tostring(value or "")
    return (value:gsub("%%", "%%25"):gsub("\t", "%%09"):gsub("\r", "%%0D"):gsub("\n", "%%0A"))
end

local function decode(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local fields = { "key", "name", "guild", "lastSeen", "context", "metCount", "marker", "tags", "note", "manual" }

function WL:ExportData()
    local lines = { "WAYFARER_LEDGER\t1" }
    for _, scope in ipairs({ "account", "character" }) do
        local store = self:GetStore(scope)
        local keys = {}
        for key in pairs(store) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local record, row = store[key], { "R", scope }
            for _, field in ipairs(fields) do row[#row + 1] = encode(record[field]) end
            lines[#lines + 1] = table.concat(row, "\t")
        end
    end
    return table.concat(lines, "\n")
end

function WL:ImportData(text)
    if type(text) ~= "string" or #text > 1024 * 1024 then return false, "Import must be plain text under 1 MB." end
    local first, count = true, 0
    for line in text:gmatch("[^\r\n]+") do
        if first then
            first = false
            if line ~= "WAYFARER_LEDGER\t1" then return false, "Not a Wayfarer Ledger v1 export." end
        else
            local cells = {}
            for cell in (line .. "\t"):gmatch("(.-)\t") do cells[#cells + 1] = cell end
            if cells[1] == "R" and (cells[2] == "account" or cells[2] == "character") and #cells == 12 then
                local record = {}
                for index, field in ipairs(fields) do record[field] = decode(cells[index + 2]) end
                local key = self:CleanText(record.key, 180)
                local name = self:CleanText(record.name, 80)
                if key and name then
                    record.key, record.name = key, name
                    record.guild = self:CleanText(record.guild, 120)
                    record.context = self:CleanText(record.context, 140) or "Imported"
                    record.tags = self:CleanText(record.tags, 300) or ""
                    record.note = self:CleanText(record.note, 2000) or ""
                    record.lastSeen = math.max(0, tonumber(record.lastSeen) or 0)
                    record.metCount = math.max(0, math.min(999999, tonumber(record.metCount) or 0))
                    record.marker = self.MARKERS[record.marker] and record.marker or "neutral"
                    record.manual = record.manual == "true"
                    self:GetStore(cells[2])[key] = record
                    count = count + 1
                end
            end
        end
    end
    if first then return false, "Import is empty." end
    self:FireChanged()
    return true, count
end
