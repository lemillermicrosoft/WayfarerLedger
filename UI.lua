local _, WL = ...

local BRONZE = { 0.78, 0.55, 0.30 }
local markerColors = { positive = "|cFF62C97B", neutral = "|cFFD2B48C", caution = "|cFFE08A62" }
local ROWS, ROW_HEIGHT = 13, 27
local frame, selectedKey, visibleRecords

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

local function formatSeen(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 then return "Unknown" end
    return date("%Y-%m-%d %H:%M", timestamp)
end

local function currentRecord() return selectedKey and store()[selectedKey] end

local function saveEditor()
    local record = currentRecord()
    if not record then return end
    WL:SaveRecord(selectedKey, {
        note = frame.noteBox:GetText(),
        tags = frame.tagsBox:GetText(),
        marker = frame.marker,
    }, selectedScope())
end

local function loadEditor()
    local record = currentRecord()
    setVisible(frame.emptyText, not record)
    setVisible(frame.editor, record ~= nil)
    if not record then return end
    frame.nameText:SetText(record.name or selectedKey)
    frame.metaText:SetText((record.guild and ("<" .. record.guild .. "> · ") or "") .. "Last seen " .. formatSeen(record.lastSeen) .. "\n" .. (record.context or "Unknown context"))
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
    for key, record in pairs(store()) do
        local haystack = table.concat({ key, record.name or "", record.guild or "", record.tags or "", record.note or "", record.context or "" }, " "):lower()
        if query == "" or haystack:find(query, 1, true) then visibleRecords[#visibleRecords + 1] = record end
    end
    table.sort(visibleRecords, function(a, b) return (tonumber(a.lastSeen) or 0) > (tonumber(b.lastSeen) or 0) end)
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
    local import = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"); setSize(import, 100, 24); import:SetPoint("LEFT", export, "RIGHT", 8, 0); import:SetText("Import")
    import:SetScript("OnClick", function()
        local ok, result = WL:ImportData(edit:GetText())
        dialog.status:SetText(ok and ("Imported " .. result .. " record(s).") or result)
        if ok then refresh() end
    end)
    dialog.status = makeLabel(dialog, ""); dialog.status:SetPoint("LEFT", import, "RIGHT", 12, 0)
    table.insert(UISpecialFrames, dialog:GetName())
    return dialog
end

local function createFrame()
    frame = CreateFrame("Frame", "WayfarerLedgerFrame", UIParent, "UIPanelDialogTemplate")
    setSize(frame, 850, 570); frame:SetPoint("CENTER"); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton"); frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    table.insert(UISpecialFrames, frame:GetName())

    local title = makeLabel(frame, "Wayfarer Ledger", 20); title:SetTextColor(unpack(BRONZE)); title:SetPoint("TOP", 0, -15)
    frame.search = createEditBox(frame); setSize(frame.search, 275, 28); frame.search:SetPoint("TOPLEFT", 22, -48); frame.search:SetMaxLetters(100)
    frame.search:SetScript("OnTextChanged", refresh)
    frame.searchLabel = makeLabel(frame, "Search name, guild, tags, notes, or context"); frame.searchLabel:SetPoint("BOTTOMLEFT", frame.search, "TOPLEFT", 4, 2)
    frame.scopeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(frame.scopeButton, 135, 26); frame.scopeButton:SetPoint("LEFT", frame.search, "RIGHT", 10, 0)
    frame.scopeButton:SetScript("OnClick", function()
        saveEditor(); WayfarerLedgerDB.options.storageScope = selectedScope() == "account" and "character" or "account"; selectedKey = nil; frame.scopeButton:SetText("Scope: " .. selectedScope()); refresh()
    end)
    frame.scopeButton:SetText("Scope: " .. selectedScope())
    local add = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(add, 110, 26); add:SetPoint("LEFT", frame.scopeButton, "RIGHT", 8, 0); add:SetText("Add target")
    add:SetScript("OnClick", function() local ok, result = WL:AddUnit("target", "Manual target", true); frame.status:SetText(ok and "Target added locally." or result); if ok then selectedKey = result.key; refresh() end end)
    local options = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(options, 80, 26); options:SetPoint("LEFT", add, "RIGHT", 8, 0); options:SetText("Options"); options:SetScript("OnClick", function() WL:OpenOptions() end)
    local transfer = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); setSize(transfer, 105, 26); transfer:SetPoint("LEFT", options, "RIGHT", 8, 0); transfer:SetText("Export / Import"); transfer:SetScript("OnClick", function() WL.transferDialog:Show(); WL.transferDialog.edit:SetText(WL:ExportData()) end)

    local listBg = CreateFrame("Frame", nil, frame); listBg:SetPoint("TOPLEFT", 20, -86); setSize(listBg, 385, 425)
    local listTexture = listBg:CreateTexture(nil, "BACKGROUND"); listTexture:SetAllPoints(); listTexture:SetTexture(0.04, 0.03, 0.02, 0.65)
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
    frame.metaText = makeLabel(frame.editor, ""); frame.metaText:SetPoint("TOPLEFT", frame.nameText, "BOTTOMLEFT", 0, -8); frame.metaText:SetPoint("RIGHT", 0, 0); frame.metaText:SetJustifyH("LEFT")
    local tagsLabel = makeLabel(frame.editor, "Tags (comma separated)"); tagsLabel:SetPoint("TOPLEFT", frame.metaText, "BOTTOMLEFT", 0, -18)
    frame.tagsBox = createEditBox(frame.editor); setSize(frame.tagsBox, 390, 28); frame.tagsBox:SetPoint("TOPLEFT", tagsLabel, "BOTTOMLEFT", 0, -3); frame.tagsBox:SetMaxLetters(300)
    frame.markerButton = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(frame.markerButton, 145, 25); frame.markerButton:SetPoint("TOPLEFT", frame.tagsBox, "BOTTOMLEFT", 0, -10)
    frame.markerButton:SetScript("OnClick", function() frame.marker = frame.marker == "neutral" and "positive" or (frame.marker == "positive" and "caution" or "neutral"); frame.markerButton:SetText("Marker: " .. WL.MARKERS[frame.marker]) end)
    frame.patternText = makeLabel(frame.editor, ""); frame.patternText:SetPoint("LEFT", frame.markerButton, "RIGHT", 10, 0); frame.patternText:SetTextColor(0.9, 0.65, 0.35)
    local noteLabel = makeLabel(frame.editor, "Private note"); noteLabel:SetPoint("TOPLEFT", frame.markerButton, "BOTTOMLEFT", 0, -14)
    local noteScroll = CreateFrame("ScrollFrame", nil, frame.editor, "UIPanelScrollFrameTemplate"); noteScroll:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -4); setSize(noteScroll, 370, 180)
    frame.noteBox = createEditBox(noteScroll, true); frame.noteBox:SetWidth(350); frame.noteBox:SetHeight(180); noteScroll:SetScrollChild(frame.noteBox)
    local save = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(save, 90, 25); save:SetPoint("TOPLEFT", noteScroll, "BOTTOMLEFT", 0, -10); save:SetText("Save"); save:SetScript("OnClick", function() saveEditor(); frame.status:SetText("Saved locally."); refresh() end)
    local forget = CreateFrame("Button", nil, frame.editor, "UIPanelButtonTemplate"); setSize(forget, 90, 25); forget:SetPoint("LEFT", save, "RIGHT", 8, 0); forget:SetText("Forget"); forget:SetScript("OnClick", function() StaticPopup_Show("WAYFARER_LEDGER_FORGET") end)
    frame.emptyText = makeLabel(frame, "Select a player to view or edit your private note."); frame.emptyText:SetPoint("CENTER", 205, 0); frame.emptyText:SetTextColor(0.7, 0.7, 0.7)
    frame.status = makeLabel(frame, ""); frame.status:SetPoint("BOTTOMLEFT", 24, 20); frame.status:SetTextColor(unpack(BRONZE))

    StaticPopupDialogs.WAYFARER_LEDGER_FORGET = {
        text = "Forget this player from the selected local scope? This cannot be undone.", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() if selectedKey then WL:Forget(selectedKey, selectedScope()); selectedKey = nil; refresh() end end,
    }
    WL.transferDialog = createTransferDialog()
    frame:SetScript("OnShow", refresh)
    frame:SetScript("OnHide", saveEditor)
    WL:RegisterCallback(refresh)
end

function WL:ToggleLedger()
    if not frame then createFrame() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

local function addTooltip(tooltip)
    if not WayfarerLedgerDB or not WayfarerLedgerDB.options.tooltip then return end
    local _, unit = tooltip:GetUnit()
    local key = unit and WL:NameFromUnit(unit)
    local record = key and WL:GetRecord(key)
    if record then
        local color = markerColors[record.marker] or markerColors.neutral
        tooltip:AddLine("Wayfarer Ledger: " .. color .. (WL.MARKERS[record.marker] or "Neutral") .. "|r", unpack(BRONZE))
        tooltip:AddLine("Last seen: " .. formatSeen(record.lastSeen) .. (record.context and (" · " .. record.context) or ""), 0.8, 0.8, 0.8, true)
        if record.tags and record.tags ~= "" then tooltip:AddLine("Tags: " .. record.tags, 0.8, 0.8, 0.8, true) end
        tooltip:Show()
    end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, addTooltip)
else
    GameTooltip:HookScript("OnTooltipSetUnit", addTooltip)
end
