local _, WL = ...

local BRONZE = { 0.78, 0.55, 0.30 }
local markerColors = { positive = "|cFF62C97B", neutral = "|cFFD2B48C", caution = "|cFFE08A62" }
local ROWS, ROW_HEIGHT = 13, 27
local frame, selectedKey, visibleRecords
local skinnedFrames = {}
local sortLabels = { recent = "Recent", name = "Name", count = "Met count" }
local filterOrder = { "all", "positive", "neutral", "caution" }
local sortOrder = { "recent", "name", "count" }

local function selectedScope() return WL:GetScope() end
local function store() return WL:GetStore(selectedScope()) end
local function setVisible(region, visible) if visible then region:Show() else region:Hide() end end
local function setSize(region, width, height)
    if region.SetSize then region:SetSize(width, height) else region:SetWidth(width); region:SetHeight(height) end
end

local function makeLabel(parent, text, size)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText(text)
    if size then label:SetFont(STANDARD_TEXT_FONT, size) end
    return label
end

local function makeColorTexture(parent, layer)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture(1, 1, 1, 1)
    return texture
end

local function addBronzeSkin(target)
    local skin = {}
    skin.fill = makeColorTexture(target, "BACKGROUND"); skin.fill:SetPoint("TOPLEFT", 4, -4); skin.fill:SetPoint("BOTTOMRIGHT", -4, 4)
    skin.top = makeColorTexture(target, "BORDER"); skin.top:SetPoint("TOPLEFT", 4, -4); skin.top:SetPoint("TOPRIGHT", -4, -4); skin.top:SetHeight(2)
    skin.bottom = makeColorTexture(target, "BORDER"); skin.bottom:SetPoint("BOTTOMLEFT", 4, 4); skin.bottom:SetPoint("BOTTOMRIGHT", -4, 4); skin.bottom:SetHeight(2)
    skin.left = makeColorTexture(target, "BORDER"); skin.left:SetPoint("TOPLEFT", 4, -4); skin.left:SetPoint("BOTTOMLEFT", 4, 4); skin.left:SetWidth(2)
    skin.right = makeColorTexture(target, "BORDER"); skin.right:SetPoint("TOPRIGHT", -4, -4); skin.right:SetPoint("BOTTOMRIGHT", -4, 4); skin.right:SetWidth(2)
    target.wayfarerSkin = skin
    skinnedFrames[#skinnedFrames + 1] = target
end

local function showSkin(target, shown)
    local skin = target and target.wayfarerSkin
    if not skin then return end
    skin.fill:SetVertexColor(0.055, 0.035, 0.018, 0.94)
    for _, edge in ipairs({ skin.top, skin.bottom, skin.left, skin.right }) do edge:SetVertexColor(0.62, 0.39, 0.16, 0.95) end
    for _, texture in pairs(skin) do setVisible(texture, shown) end
end

local function applyAppearance(appearance)
    local bronze = appearance == "bronze"
    for _, target in ipairs(skinnedFrames) do showSkin(target, bronze) end
    if not frame then return end
    frame.titleText:SetTextColor(bronze and BRONZE[1] or 1, bronze and BRONZE[2] or 0.82, bronze and BRONZE[3] or 0)
    frame.status:SetTextColor(bronze and BRONZE[1] or 1, bronze and BRONZE[2] or 1, bronze and BRONZE[3] or 1)
    frame.patternText:SetTextColor(bronze and 0.9 or 1, bronze and 0.65 or 0.82, bronze and 0.35 or 0)
    frame.listTexture:SetTexture(bronze and 0.04 or 0.03, bronze and 0.03 or 0.04, bronze and 0.02 or 0.06, bronze and 0.65 or 0.72)
    for _, row in ipairs(frame.rows) do
        row.selected:SetTexture(bronze and 0.35 or 0.12, bronze and 0.20 or 0.28, bronze and 0.08 or 0.50, 0.55)
    end
    if WL.transferDialog and WL.transferDialog.title then
        WL.transferDialog.title:SetTextColor(bronze and BRONZE[1] or 1, bronze and BRONZE[2] or 0.82, bronze and BRONZE[3] or 0)
    end
end

local function formatSeen(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 then return "Unknown" end
    return date("%Y-%m-%d %H:%M", timestamp)
end

local function currentRecord() return selectedKey and store()[selectedKey] end

local function safeFiniteNumber(value)
    return not WL:IsSecretValue(value) and type(value) == "number" and value == value and math.abs(value) < 100000
end

local function restorePosition()
    local position = WayfarerLedgerDB.options.windowPosition
    local x = type(position) == "table" and position.x or 0
    local y = type(position) == "table" and position.y or 0
    if not safeFiniteNumber(x) then x = 0 end
    if not safeFiniteNumber(y) then y = 0 end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", math.max(-2000, math.min(2000, x)), math.max(-1200, math.min(1200, y)))
end

local function savePosition()
    local ok, frameX, frameY = pcall(frame.GetCenter, frame)
    local parentOK, parentX, parentY = pcall(UIParent.GetCenter, UIParent)
    local frameScale = WL:SafeNumberCall(frame.GetEffectiveScale, frame) or 1
    local parentScale = WL:SafeNumberCall(UIParent.GetEffectiveScale, UIParent) or 1
    if ok and parentOK and safeFiniteNumber(frameX) and safeFiniteNumber(frameY) and safeFiniteNumber(parentX) and safeFiniteNumber(parentY) and parentScale > 0 then
        WayfarerLedgerDB.options.windowPosition = {
            x = math.max(-2000, math.min(2000, (frameX * frameScale - parentX * parentScale) / parentScale)),
            y = math.max(-1200, math.min(1200, (frameY * frameScale - parentY * parentScale) / parentScale)),
        }
    end
end

function WL:ResetWindowPosition()
    WayfarerLedgerDB.options.windowPosition = { x = 0, y = 0 }
    if frame then restorePosition() end
end

local function saveEditor()
    local record = currentRecord()
    if not record then return end
    WL:SaveRecord(selectedKey, {
        note = frame.noteBox:GetText(),
        tags = frame.tagsBox:GetText(),
        marker = frame.marker,
    }, selectedScope())
end

local function recentEncounterText(record)
    local lines = {}
    for index, encounter in ipairs(record.encounters or {}) do
        if index > 3 then break end
        lines[#lines + 1] = (encounter.kind or "other") .. " · " .. formatSeen(encounter.at) .. " · " .. (encounter.context or "Unknown")
    end
    return #lines > 0 and table.concat(lines, "\n") or "No encounter details available"
end

local function recentTimelineText()
    local lines = {}
    for index, session in ipairs(WL:GetTimeline(selectedScope())) do
        if index > 4 then break end
        lines[#lines + 1] = formatSeen(session.started) .. " · " .. (session.kind or "party") .. " · " .. (session.context or "Unknown") .. " · " .. #(session.members or {}) .. " saved"
    end
    return #lines > 0 and table.concat(lines, "\n") or "No party or raid sessions recorded yet."
end

local function loadEditor()
    local record = currentRecord()
    setVisible(frame.emptyTitle, not record)
    setVisible(frame.emptyText, not record)
    setVisible(frame.emptyExamples, not record)
    setVisible(frame.editor, record ~= nil)
    if not record then
        frame.emptyExamples:SetText("Recent group timeline\n" .. recentTimelineText() .. "\n\nStarter ideas (not saved): helpful crafter · reliable tank · roleplayer · friend\nEverything remains local unless you copy an export.")
        return
    end
    frame.nameText:SetText(record.name or selectedKey)
    frame.metaText:SetText((record.guild and ("<" .. record.guild .. "> · ") or "") .. "Last seen " .. formatSeen(record.lastSeen) .. " · Met " .. (tonumber(record.metCount) or 0) .. " time(s)\n" .. recentEncounterText(record))
    frame.tagsBox:SetText(record.tags or "")
    frame.noteBox:SetText(record.note or "")
    frame.marker = WL.MARKERS[record.marker] and record.marker or "neutral"
    frame.markerButton:SetText("Marker: " .. WL.MARKERS[frame.marker])
    local matches, pattern = WL:GuildMatches(record.guild)
    frame.patternText:SetText(matches and ("Local guild pattern match: “" .. pattern .. "”") or "")
end

local function refresh()
    if not frame then return end
    local query = WL:CleanText(frame.search:GetText(), 100)
    query = query and query:lower() or ""
    visibleRecords = {}
    local markerFilter = WayfarerLedgerDB.options.markerFilter or "all"
    for key, record in pairs(store()) do
        local haystack = table.concat({ key, record.name or "", record.guild or "", record.tags or "", record.note or "", record.context or "" }, " "):lower()
        if (markerFilter == "all" or record.marker == markerFilter) and (query == "" or haystack:find(query, 1, true)) then visibleRecords[#visibleRecords + 1] = record end
    end
    local sortMode = WayfarerLedgerDB.options.sort or "recent"
    table.sort(visibleRecords, function(a, b)
        if sortMode == "name" then return (a.name or a.key):lower() < (b.name or b.key):lower() end
        if sortMode == "count" then
            local ac, bc = tonumber(a.metCount) or 0, tonumber(b.metCount) or 0
            if ac ~= bc then return ac > bc end
        end
        local at, bt = tonumber(a.lastSeen) or 0, tonumber(b.lastSeen) or 0
        if at ~= bt then return at > bt end
        return (a.key or "") < (b.key or "")
    end)
    FauxScrollFrame_Update(frame.scroll, #visibleRecords, ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(frame.scroll)
    for index, row in ipairs(frame.rows) do
        local record = visibleRecords[index + offset]
        row.record = record
        if record then
            local color = markerColors[record.marker] or markerColors.neutral
            row.name:SetText(color .. (record.name or record.key) .. "|r")
            row.details:SetText((record.guild and ("<" .. record.guild .. "> · ") or "") .. formatSeen(record.lastSeen))
            row:Show()
            setVisible(row.selected, record.key == selectedKey)
        else row:Hide() end
    end
    frame.count:SetText(#visibleRecords .. " player" .. (#visibleRecords == 1 and "" or "s") .. " · " .. selectedScope())
    if frame.filterButton then frame.filterButton:SetText("Filter: " .. (markerFilter == "all" and "All" or WL.MARKERS[markerFilter])) end
    if frame.sortButton then frame.sortButton:SetText("Sort: " .. (sortLabels[sortMode] or "Recent")) end
    loadEditor()
end

local function createEditBox(parent, multiline)
    local box = CreateFrame("EditBox", nil, parent, multiline and "InputBoxTemplate" or "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 4, 4)
    if multiline then box:SetMultiLine(true); box:SetMaxLetters(2000) end
    return box
end

local function createTransferDialog()
    local dialog = CreateFrame("Frame", "WayfarerLedgerTransferFrame", UIParent, "UIPanelDialogTemplate")
    addBronzeSkin(dialog)
    setSize(dialog, 620, 430); dialog:SetPoint("CENTER"); dialog:SetFrameStrata("DIALOG"); dialog:Hide()
    dialog.title = makeLabel(dialog, "Wayfarer Ledger — Export / Import", 16); dialog.title:SetPoint("TOP", 0, -14)
    local help = makeLabel(dialog, "Exports stay local until you copy them. Import merges by player key; it never transmits data.")
    help:SetPoint("TOPLEFT", 22, -42); help:SetPoint("RIGHT", -22, 0); help:SetJustifyH("LEFT")
    local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -72); scroll:SetPoint("BOTTOMRIGHT", -44, 55)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject("ChatFontNormal"); edit:SetWidth(540); edit:SetMaxLetters(1024 * 1024)
    scroll:SetScrollChild(edit); dialog.edit = edit
    local export = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"); setSize(export, 100, 24); export:SetPoint("BOTTOMLEFT", 24, 20); export:SetText("Export all")
    export:SetScript("OnClick", function() edit:SetText(WL:ExportData()); edit:HighlightText(); edit:SetFocus() end)
    local import = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"); setSize(import, 82, 24); import:SetPoint("LEFT", export, "RIGHT", 8, 0); import:SetText("Import")
    import:SetScript("OnClick", function()
        local ok, result = WL:ImportData(edit:GetText())
        dialog.status:SetText(ok and ("Imported " .. result .. " record(s); backup created.") or result)
        if ok then refresh() end
    end)
    local backup = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"); setSize(82, 24); backup:SetPoint("LEFT", import, "RIGHT", 8, 0); backup:SetText("Backup"); backup:SetScript("OnClick", function() dialog.status:SetText(WL:CreateBackup("Manual backup") and "Local backup created." or "Backup could not be created.") end)
    local restore = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"); setSize(105, 24); restore:SetPoint("LEFT", backup, "RIGHT", 8, 0); restore:SetText("Restore latest"); restore:SetScript("OnClick", function() StaticPopup_Show("WAYFARER_LEDGER_RESTORE") end)
    local reset = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"); setSize(95, 24); reset:SetPoint("LEFT", restore, "RIGHT", 8, 0); reset:SetText("Reset scope"); reset:SetScript("OnClick", function() StaticPopup_Show("WAYFARER_LEDGER_RESET") end)
    dialog.status = makeLabel(dialog, ""); dialog.status:SetPoint("BOTTOMLEFT", 24, 4); dialog.status:SetPoint("RIGHT", -24, 0); dialog.status:SetJustifyH("LEFT")
    table.insert(UISpecialFrames, dialog:GetName())
    return dialog
end

local function createFrame()
    frame = CreateFrame("Frame", "WayfarerLedgerFrame", UIParent, "UIPanelDialogTemplate")
    addBronzeSkin(frame)
    setSize(frame, 850, 570); frame:SetMovable(true); frame:EnableMouse(true)
    restorePosition()
    frame:RegisterForDrag("LeftButton"); frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
    table.insert(UISpecialFrames, frame:GetName())

    local title = makeLabel(frame, "Wayfarer Ledger", 20); title:SetPoint("TOP", 0, -15); frame.titleText = title
    frame.search = createEditBox(frame); setSize(frame.search, 190, 28); frame.search:SetPoint("TOPLEFT", 22, -48); frame.search:SetMaxLetters(100)
    frame.search:SetScript("OnTextChanged", refresh)
    frame.searchLabel = makeLabel(frame, "Search local ledger"); frame.searchLabel:SetPoint("BOTTOMLEFT", frame.search, "TOPLEFT", 4, 2)
    frame.filterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(frame.filterButton, 95, 26); frame.filterButton:SetPoint("LEFT", frame.search, "RIGHT", 8, 0)
    frame.filterButton:SetScript("OnClick", function()
        local current = WayfarerLedgerDB.options.markerFilter or "all"; local nextValue = filterOrder[1]
        for index, value in ipairs(filterOrder) do if value == current then nextValue = filterOrder[(index % #filterOrder) + 1] break end end
        WayfarerLedgerDB.options.markerFilter = nextValue; refresh()
    end)
    frame.sortButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(frame.sortButton, 100, 26); frame.sortButton:SetPoint("LEFT", frame.filterButton, "RIGHT", 6, 0)
    frame.sortButton:SetScript("OnClick", function()
        local current = WayfarerLedgerDB.options.sort or "recent"; local nextValue = sortOrder[1]
        for index, value in ipairs(sortOrder) do if value == current then nextValue = sortOrder[(index % #sortOrder) + 1] break end end
        WayfarerLedgerDB.options.sort = nextValue; refresh()
    end)
    frame.scopeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(frame.scopeButton, 112, 26); frame.scopeButton:SetPoint("LEFT", frame.sortButton, "RIGHT", 6, 0)
    frame.scopeButton:SetScript("OnClick", function()
        saveEditor(); WL:SetScope(selectedScope() == "account" and "character" or "account"); selectedKey = nil; frame.scopeButton:SetText("Scope: " .. selectedScope()); refresh()
    end)
    frame.scopeButton:SetText("Scope: " .. selectedScope())
    local add = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(add, 92, 26); add:SetPoint("LEFT", frame.scopeButton, "RIGHT", 6, 0); add:SetText("Add target")
    add:SetScript("OnClick", function() local ok, result = WL:AddUnit("target", "Manual target", true); frame.status:SetText(ok and "Target added locally." or result); if ok then selectedKey = result.key; refresh() end end)
    local options = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(options, 66, 26); options:SetPoint("LEFT", add, "RIGHT", 6, 0); options:SetText("Options"); options:SetScript("OnClick", function() WL:OpenOptions() end)
    local transfer = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(transfer, 82, 26); transfer:SetPoint("LEFT", options, "RIGHT", 6, 0); transfer:SetText("Transfer"); transfer:SetScript("OnClick", function() WL.transferDialog:Show(); WL.transferDialog.edit:SetText(WL:ExportData()) end)

    local listBg = CreateFrame("Frame", nil, frame); listBg:SetPoint("TOPLEFT", 20, -86); setSize(listBg, 385, 425)
    local listTexture = listBg:CreateTexture(nil, "BACKGROUND"); listTexture:SetAllPoints(); frame.listTexture = listTexture
    frame.rows = {}
    for index = 1, ROWS do
        local row = CreateFrame("Button", nil, listBg)
        setSize(row, 355, ROW_HEIGHT); row:SetPoint("TOPLEFT", 8, -8 - (index - 1) * ROW_HEIGHT)
        row.selected = row:CreateTexture(nil, "BACKGROUND"); row.selected:SetAllPoints(); row.selected:SetTexture(0.35, 0.20, 0.08, 0.55); row.selected:Hide()
        row.name = makeLabel(row, ""); row.name:SetPoint("TOPLEFT", 4, -2); row.name:SetJustifyH("LEFT")
        row.details = makeLabel(row, ""); row.details:SetPoint("BOTTOMLEFT", 4, 2); row.details:SetTextColor(0.65, 0.65, 0.65); row.details:SetFont(STANDARD_TEXT_FONT, 10)
        row:SetScript("OnClick", function(self) saveEditor(); selectedKey = self.record.key; refresh() end)
        frame.rows[index] = row
    end
    frame.scroll = CreateFrame("ScrollFrame", "WayfarerLedgerScrollFrame", listBg, "FauxScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 0, -7); frame.scroll:SetPoint("BOTTOMRIGHT", -2, 7); frame.scroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refresh) end)
    frame.count = makeLabel(frame, ""); frame.count:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 4, -7)

    frame.editor = CreateFrame("Frame", nil, frame); frame.editor:SetPoint("TOPLEFT", 425, -92); frame.editor:SetPoint("BOTTOMRIGHT", -22, 55)
    frame.nameText = makeLabel(frame.editor, "", 18); frame.nameText:SetPoint("TOPLEFT", 0, 0); frame.nameText:SetPoint("RIGHT", 0, 0); frame.nameText:SetJustifyH("LEFT")
    frame.metaText = makeLabel(frame.editor, ""); frame.metaText:SetPoint("TOPLEFT", frame.nameText, "BOTTOMLEFT", 0, -8); frame.metaText:SetPoint("RIGHT", 0, 0); frame.metaText:SetJustifyH("LEFT"); frame.metaText:SetJustifyV("TOP"); frame.metaText:SetHeight(72)
    local tagsLabel = makeLabel(frame.editor, "Tags (comma separated)"); tagsLabel:SetPoint("TOPLEFT", frame.metaText, "BOTTOMLEFT", 0, -18)
    frame.tagsBox = createEditBox(frame.editor); setSize(frame.tagsBox, 390, 28); frame.tagsBox:SetPoint("TOPLEFT", tagsLabel, "BOTTOMLEFT", 0, -3); frame.tagsBox:SetMaxLetters(300)
    frame.markerButton = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(frame.markerButton, 145, 25); frame.markerButton:SetPoint("TOPLEFT", frame.tagsBox, "BOTTOMLEFT", 0, -10)
    frame.markerButton:SetScript("OnClick", function() frame.marker = frame.marker == "neutral" and "positive" or (frame.marker == "positive" and "caution" or "neutral"); frame.markerButton:SetText("Marker: " .. WL.MARKERS[frame.marker]) end)
    frame.patternText = makeLabel(frame.editor, ""); frame.patternText:SetPoint("LEFT", frame.markerButton, "RIGHT", 10, 0)
    local noteLabel = makeLabel(frame.editor, "Private note"); noteLabel:SetPoint("TOPLEFT", frame.markerButton, "BOTTOMLEFT", 0, -14)
    local noteScroll = CreateFrame("ScrollFrame", nil, frame.editor, "UIPanelScrollFrameTemplate"); noteScroll:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -4); setSize(noteScroll, 370, 180)
    frame.noteBox = createEditBox(noteScroll, true); frame.noteBox:SetWidth(350); frame.noteBox:SetHeight(180); noteScroll:SetScrollChild(frame.noteBox)
    local save = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(save, 72, 25); save:SetPoint("TOPLEFT", noteScroll, "BOTTOMLEFT", 0, -10); save:SetText("Save"); save:SetScript("OnClick", function() saveEditor(); frame.status:SetText("Saved locally."); refresh() end)
    local move = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(move, 104, 25); move:SetPoint("LEFT", save, "RIGHT", 8, 0); move:SetText("Move scope"); move:SetScript("OnClick", function() StaticPopup_Show("WAYFARER_LEDGER_MOVE") end)
    local copy = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(copy, 104, 25); copy:SetPoint("LEFT", move, "RIGHT", 8, 0); copy:SetText("Copy scope"); copy:SetScript("OnClick", function() local destination = selectedScope() == "account" and "character" or "account"; local ok, message = WL:MoveRecord(selectedKey, selectedScope(), destination, true); frame.status:SetText(ok and ("Copied to " .. destination .. ".") or message) end)
    local forget = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(forget, 72, 25); forget:SetPoint("LEFT", copy, "RIGHT", 8, 0); forget:SetText("Forget"); forget:SetScript("OnClick", function() StaticPopup_Show("WAYFARER_LEDGER_FORGET") end)
    frame.emptyTitle = makeLabel(frame, "Your private travel notebook", 18); frame.emptyTitle:SetPoint("TOPLEFT", 446, -138)
    frame.emptyText = makeLabel(frame, "Target a player and choose Add target, or let Wayfarer Ledger quietly remember visible party and raid members. Select a saved player to add private notes, tags, and a marker. Tooltip reminders can show when you meet them again.")
    frame.emptyText:SetPoint("TOPLEFT", frame.emptyTitle, "BOTTOMLEFT", 0, -14); frame.emptyText:SetWidth(355); frame.emptyText:SetJustifyH("LEFT"); frame.emptyText:SetJustifyV("TOP"); frame.emptyText:SetTextColor(0.78, 0.78, 0.78)
    frame.emptyExamples = makeLabel(frame, "Starter ideas (not saved):\nTags — helpful crafter · reliable tank · roleplayer · friend\nMarkers — Positive: good experience · Neutral: context only · Caution: personal reminder\n\nEverything stays in SavedVariables on this computer unless you copy an export.")
    frame.emptyExamples:SetPoint("TOPLEFT", frame.emptyText, "BOTTOMLEFT", 0, -20); frame.emptyExamples:SetWidth(355); frame.emptyExamples:SetJustifyH("LEFT"); frame.emptyExamples:SetJustifyV("TOP"); frame.emptyExamples:SetTextColor(0.68, 0.68, 0.68)
    frame.status = makeLabel(frame, ""); frame.status:SetPoint("BOTTOMLEFT", 24, 20)

    StaticPopupDialogs.WAYFARER_LEDGER_FORGET = {
        text = "Forget this player from the selected local scope? This cannot be undone.", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() if selectedKey then WL:Forget(selectedKey, selectedScope()); selectedKey = nil; refresh() end end,
    }
    StaticPopupDialogs.WAYFARER_LEDGER_MOVE = {
        text = "Move this player to the other local scope? Existing destination history will be merged.", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() if selectedKey then local from = selectedScope(); local destination = from == "account" and "character" or "account"; local ok, message = WL:MoveRecord(selectedKey, from, destination, false); frame.status:SetText(ok and ("Moved to " .. destination .. ".") or message); selectedKey = nil; refresh() end end,
    }
    StaticPopupDialogs.WAYFARER_LEDGER_RESET = {
        text = "Reset the selected ledger scope? A local backup is created first.", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() local ok, message = WL:ResetScope(selectedScope()); if ok then selectedKey = nil end; WL.transferDialog.status:SetText(ok and "Scope reset; backup created." or message); refresh() end,
    }
    StaticPopupDialogs.WAYFARER_LEDGER_RESTORE = {
        text = "Restore the latest local backup by merging it into both scopes?", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() local ok, result = WL:RestoreLatestBackup(); WL.transferDialog.status:SetText(ok and ("Restored " .. result .. " record(s).") or result); refresh() end,
    }
    WL.transferDialog = createTransferDialog()
    applyAppearance(WL:GetAppearance())
    frame:SetScript("OnShow", refresh)
    frame:SetScript("OnHide", saveEditor)
    WL:RegisterCallback(refresh)
end

WL:RegisterAppearanceCallback(applyAppearance)

function WL:ToggleLedger()
    if not frame then createFrame() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

local function addTooltip(tooltip)
    if not WayfarerLedgerDB or not WayfarerLedgerDB.options.tooltip then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not WL:IsSafeText(unit) then return end
    local key = WL:NameFromUnit(unit)
    local record = key and WL:GetRecord(key)
    if record then
        local color = markerColors[record.marker] or markerColors.neutral
        local bronze = WL:GetAppearance() == "bronze"
        tooltip:AddLine("Wayfarer Ledger: " .. color .. (WL.MARKERS[record.marker] or "Neutral") .. "|r", bronze and BRONZE[1] or 1, bronze and BRONZE[2] or 0.82, bronze and BRONZE[3] or 0)
        tooltip:AddLine("Last seen: " .. formatSeen(record.lastSeen) .. (record.context and (" · " .. record.context) or ""), 0.8, 0.8, 0.8, true)
        if record.tags and record.tags ~= "" then tooltip:AddLine("Tags: " .. record.tags, 0.8, 0.8, 0.8, true) end
        if WayfarerLedgerDB.options.tooltipNotes and record.note and record.note ~= "" then tooltip:AddLine("Private note: " .. record.note, 0.75, 0.75, 0.75, true) end
        tooltip:Show()
    end
end

if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, addTooltip)
elseif GameTooltip and type(GameTooltip.HookScript) == "function" then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", addTooltip)
end
