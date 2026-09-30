local _, WL = ...

local panel
local appearanceButtons = {}
local function setVisible(region, visible) if visible then region:Show() else region:Hide() end end
local function setSize(region, width, height)
    if region.SetSize then region:SetSize(width, height) else region:SetWidth(width); region:SetHeight(height) end
end
local function checkbox(parent, label, description, y, getter, setter)
    local box = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    box:SetPoint("TOPLEFT", 20, y)
    local text = box.Text
    if not text then text = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); text:SetPoint("LEFT", box, "RIGHT", 2, 0) end
    text:SetText(label); box.tooltipText = label; box.tooltipRequirement = description
    box:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    box:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    return box
end

local function applyOptionsAppearance(appearance)
    if not panel then return end
    local bronze = appearance == "bronze"
    if panel.bronzeBackground then setVisible(panel.bronzeBackground, bronze) end
    if panel.title then panel.title:SetTextColor(bronze and 0.78 or 1, bronze and 0.55 or 0.82, bronze and 0.30 or 0) end
    for value, button in pairs(appearanceButtons) do button:SetChecked(value == appearance) end
end

local function appearanceChoice(parent, value, label, x)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, -112); setSize(button, 24, 24)
    local text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", button, "RIGHT", 2, 0); text:SetText(label)
    button:SetScript("OnClick", function() WL:SetAppearance(value) end)
    appearanceButtons[value] = button
end

local function savePatterns(edit)
    local patterns, seen = {}, {}
    local text = edit:GetText()
    if WL:IsSecretValue(text) or type(text) ~= "string" then return end
    for line in text:gmatch("[^\r\n]+") do
        local clean = WL:CleanText(line, 80)
        local folded = clean and clean:lower()
        if clean and not seen[folded] and #patterns < 50 then patterns[#patterns + 1] = clean; seen[folded] = true end
    end
    WayfarerLedgerDB.options.guildPatterns = patterns
    edit:SetText(table.concat(patterns, "\n"))
end

local function createOptions()
    panel = CreateFrame("Frame", "WayfarerLedgerOptionsPanel")
    panel.name = "Wayfarer Ledger"
    panel.bronzeBackground = panel:CreateTexture(nil, "BACKGROUND"); panel.bronzeBackground:SetAllPoints(); panel.bronzeBackground:SetTexture(0.055, 0.035, 0.018, 0.92)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -16); title:SetText("Wayfarer Ledger"); panel.title = title
    local privacy = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); privacy:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10); privacy:SetPoint("RIGHT", -24, 0); privacy:SetJustifyH("LEFT"); privacy:SetJustifyV("TOP")
    privacy:SetText("Privacy-first by design: data stays in SavedVariables on this computer. The addon records party/raid members and players you explicitly add from a target. It does not read or store chat, build public reputation scores, share accusations, collect real-world data, or automate targeting. Exported text leaves the addon only when you copy it.")

    local appearanceTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); appearanceTitle:SetPoint("TOPLEFT", 20, -88); appearanceTitle:SetText("Appearance (applies immediately)")
    appearanceChoice(panel, "blizzard", "Blizzard / native", 20)
    appearanceChoice(panel, "bronze", "Bronze / custom", 205)

    checkbox(panel, "Automatically remember party members", "Uses only the visible party roster.", -152, function() return WayfarerLedgerDB.options.recordParties end, function(v) WayfarerLedgerDB.options.recordParties = v end)
    checkbox(panel, "Automatically remember raid members", "Uses only the visible raid roster.", -184, function() return WayfarerLedgerDB.options.recordRaid end, function(v) WayfarerLedgerDB.options.recordRaid = v end)
    checkbox(panel, "Show ‘met before’ details in player tooltips", "Adds a quiet local tooltip line.", -216, function() return WayfarerLedgerDB.options.tooltip end, function(v) WayfarerLedgerDB.options.tooltip = v end)
    checkbox(panel, "Include private note text in tooltips", "Off by default to reduce shoulder-surfing risk.", -248, function() return WayfarerLedgerDB.options.tooltipNotes end, function(v) WayfarerLedgerDB.options.tooltipNotes = v end)
    checkbox(panel, "Notify once per session when targeting someone met before", "Off by default; never sends a message to others.", -280, function() return WayfarerLedgerDB.options.notifyTarget end, function(v) WayfarerLedgerDB.options.notifyTarget = v end)
    checkbox(panel, "Locally hide chat from known players whose recorded guild matches a pattern", "Optional assistance only. It affects your chat view, relies on your local ledger, and makes no public claim.", -312, function() return WayfarerLedgerDB.options.muteChat end, function(v) WayfarerLedgerDB.options.muteChat = v end)

    local patternTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); patternTitle:SetPoint("TOPLEFT", 20, -360); patternTitle:SetText("Guild name patterns (one literal, case-insensitive fragment per line)")
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", patternTitle, "BOTTOMLEFT", 0, -8); setSize(scroll, 430, 105)
    local edit = CreateFrame("EditBox", nil, scroll); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject("ChatFontNormal"); edit:SetWidth(405); edit:SetHeight(105); edit:SetMaxLetters(4096); scroll:SetScrollChild(edit); panel.patternEdit = edit
    local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); setSize(save, 120, 25); save:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10); save:SetText("Save patterns"); save:SetScript("OnClick", function() savePatterns(edit) end)
    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); hint:SetPoint("LEFT", save, "RIGHT", 10, 0); hint:SetText("Patterns are private and never broadcast.")
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); setSize(reset, 150, 25); reset:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -12); reset:SetText("Reset window position"); reset:SetScript("OnClick", function() WL:ResetWindowPosition() end)
    panel:SetScript("OnShow", function() edit:SetText(table.concat(WayfarerLedgerDB.options.guildPatterns, "\n")); applyOptionsAppearance(WL:GetAppearance()) end)
    applyOptionsAppearance(WL:GetAppearance())

    local registered = false
    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
        if ok and category then
            local added = pcall(Settings.RegisterAddOnCategory, category)
            local idOK, categoryID = false, nil
            if type(category.GetID) == "function" then idOK, categoryID = pcall(category.GetID, category) end
            if added then WL.optionsCategoryID = idOK and categoryID or nil; registered = true end
        end
    end
    if not registered and type(InterfaceOptions_AddCategory) == "function" then pcall(InterfaceOptions_AddCategory, panel) end
end

WL:RegisterAppearanceCallback(applyOptionsAppearance)

function WL:OpenOptions()
    if not panel then createOptions() end
    if Settings and type(Settings.OpenToCategory) == "function" and WL.optionsCategoryID then
        local ok = pcall(Settings.OpenToCategory, WL.optionsCategoryID)
        if ok then return end
    end
    if type(InterfaceOptionsFrame_OpenToCategory) == "function" then
        pcall(InterfaceOptionsFrame_OpenToCategory, panel)
        pcall(InterfaceOptionsFrame_OpenToCategory, panel)
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name) if name == "WayfarerLedger" then createOptions(); loader:UnregisterAllEvents() end end)
