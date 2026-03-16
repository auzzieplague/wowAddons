-- OrctionSettings.lua
-- Settings window for Orction (TurtleWoW / vanilla 1.12, Lua 5.0)
-- Opens via /orction slash command
-- NOTE: uses `this` / `event` / `arg1` globals in all script handlers (no `self`)

-------------------------------------------------------------------------------
-- Main frame
-------------------------------------------------------------------------------

OrctionFrame = CreateFrame("Frame", "OrctionFrame", UIParent)
OrctionFrame:SetWidth(520)
OrctionFrame:SetHeight(460)
OrctionFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
OrctionFrame:SetFrameStrata("DIALOG")
OrctionFrame:SetMovable(true)
OrctionFrame:EnableMouse(true)
OrctionFrame:SetToplevel(true)
OrctionFrame:Hide()

-- Drag support
OrctionFrame:SetScript("OnMouseDown", function()
    if arg1 == "LeftButton" then
        OrctionFrame:StartMoving()
    end
end)
OrctionFrame:SetScript("OnMouseUp", function()
    OrctionFrame:StopMovingOrSizing()
end)

-- Backdrop
OrctionFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true,
    tileSize = 32,
    edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 },
})

-------------------------------------------------------------------------------
-- Title bar texture + title text
-------------------------------------------------------------------------------

local titleBar = OrctionFrame:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetWidth(256)
titleBar:SetHeight(64)
titleBar:SetPoint("TOP", OrctionFrame, "TOP", 0, 12)

local titleText = OrctionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", OrctionFrame, "TOP", 0, -14)
titleText:SetText("Orction")

-------------------------------------------------------------------------------
-- Close button
-------------------------------------------------------------------------------

local closeButton = CreateFrame("Button", "OrctionFrameCloseButton", OrctionFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", OrctionFrame, "TOPRIGHT", -3, -3)
closeButton:SetScript("OnClick", function()
    OrctionFrame:Hide()
end)

-------------------------------------------------------------------------------
-- Tab content panels (created before tabs so tabs can reference them)
-------------------------------------------------------------------------------

-- Helper: create a content panel (child of OrctionFrame, fills the content area)
local function CreateContentPanel(name)
    local panel = CreateFrame("Frame", name, OrctionFrame)
    panel:SetPoint("TOPLEFT",     OrctionFrame, "TOPLEFT",  14, -80)
    panel:SetPoint("BOTTOMRIGHT", OrctionFrame, "BOTTOMRIGHT", -14, 14)
    panel:Hide()
    return panel
end

local auctionPanel    = CreateContentPanel("OrctionAuctionPanel")
local postPanel       = CreateContentPanel("OrctionPostPanel")
local inventoryPanel  = CreateContentPanel("OrctionInventoryPanel")
local dataPanel       = CreateContentPanel("OrctionDataPanel")
local creditsPanel    = CreateContentPanel("OrctionCreditsPanel")

-- Table for easy indexed access
local orctionPanels = { auctionPanel, postPanel, inventoryPanel, dataPanel, creditsPanel }

-------------------------------------------------------------------------------
-- Tab buttons
-------------------------------------------------------------------------------

local tabLabels = { "Auction", "Post", "Inventory", "Data", "Credits" }

OrctionFrame.numTabs = 5
PanelTemplates_SetNumTabs(OrctionFrame, 5)

for i = 1, 5 do
    local tab = CreateFrame("Button", "OrctionFrameTab"..i, OrctionFrame, "CharacterFrameTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(tabLabels[i])

    -- Resize tab to fit text (minimum 60 px)
    local textWidth = tab:GetTextWidth()
    local tabWidth  = math.max(textWidth + 24, 60)
    tab:SetWidth(tabWidth)

    if i == 1 then
        tab:SetPoint("TOPLEFT", OrctionFrame, "TOPLEFT", 10, -46)
    else
        local prevTab = getglobal("OrctionFrameTab"..(i-1))
        tab:SetPoint("LEFT", prevTab, "RIGHT", -14, 0)
    end

    tab:SetScript("OnClick", function()
        OrctionSettings_SelectTab(this:GetID())
    end)
end

-------------------------------------------------------------------------------
-- Tab selection function
-------------------------------------------------------------------------------

function OrctionSettings_SelectTab(id)
    -- Hide all panels
    for i = 1, 5 do
        orctionPanels[i]:Hide()
    end
    -- Show the selected panel
    if orctionPanels[id] then
        orctionPanels[id]:Show()
    end
    -- Highlight the correct tab button
    PanelTemplates_SetTab(OrctionFrame, id)
end

-------------------------------------------------------------------------------
-- TAB 1: Auction
-------------------------------------------------------------------------------

-- Enable checkbox
local auctionEnabledCheck = CreateFrame("CheckButton", "OrctionAuctionEnabledCheck", auctionPanel, "OptionsCheckButtonTemplate")
auctionEnabledCheck:SetPoint("TOPLEFT", auctionPanel, "TOPLEFT", 10, -10)
getglobal("OrctionAuctionEnabledCheckText"):SetText("Enable Auction Features")

auctionEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.auctionEnabled = (this:GetChecked() == 1)
    end
end)

local autoOpenTabCheck = CreateFrame("CheckButton", "OrctionAutoOpenTabCheck", auctionPanel, "OptionsCheckButtonTemplate")
autoOpenTabCheck:SetPoint("TOPLEFT", auctionEnabledCheck, "BOTTOMLEFT", 0, -6)
getglobal("OrctionAutoOpenTabCheckText"):SetText("Auto-open Orction tab when AH opens")

autoOpenTabCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.autoOpenTab = (this:GetChecked() == 1)
    end
end)

-- Feature description box (read-only)
local auctionDesc = CreateFrame("EditBox", nil, auctionPanel)
auctionDesc:SetMultiLine(true)
auctionDesc:SetWidth(460)
auctionDesc:SetHeight(60)
auctionDesc:SetPoint("TOPLEFT", autoOpenTabCheck, "BOTTOMLEFT", 0, -10)
auctionDesc:SetFontObject("GameFontHighlightSmall")
auctionDesc:EnableMouse(false)
auctionDesc:EnableKeyboard(false)
auctionDesc:SetAutoFocus(false)
auctionDesc:SetText("- Compare market price before posting\n- Automatic stack posting\n- Vendor profit snatching")

local titleCaseCheck = CreateFrame("CheckButton", "OrctionTitleCaseSearchCheck", auctionPanel, "OptionsCheckButtonTemplate")
titleCaseCheck:SetPoint("TOPLEFT", auctionDesc, "BOTTOMLEFT", 0, -10)
getglobal("OrctionTitleCaseSearchCheckText"):SetText("Title-case text search terms")

titleCaseCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.titleCaseSearch = (this:GetChecked() == 1)
    end
end)

-- "Pages to Scan" label
local pagesLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pagesLabel:SetPoint("TOPLEFT", titleCaseCheck, "BOTTOMLEFT", 0, -14)
pagesLabel:SetText("Pages to Scan")

-- Slider
local pagesSlider = CreateFrame("Slider", "OrctionPagesSlider", auctionPanel, "OptionsSliderTemplate")
pagesSlider:SetWidth(200)
pagesSlider:SetPoint("TOPLEFT", pagesLabel, "BOTTOMLEFT", 0, -6)
pagesSlider:SetMinMaxValues(1, 10)
pagesSlider:SetValueStep(1)
pagesSlider:SetValue(3)

-- Slider low/high labels (set via the template globals)
getglobal("OrctionPagesSliderLow"):SetText("1")
getglobal("OrctionPagesSliderHigh"):SetText("10")

-- Current value display next to slider
local pagesValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pagesValueText:SetPoint("LEFT", pagesSlider, "RIGHT", 10, 0)
pagesValueText:SetText("3")

pagesSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    pagesValueText:SetText(tostring(val))
    ORCTION_MAX_PAGES = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.maxPages = val
    end
end)

-- "Retry Delay" label
local retryDelayLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
retryDelayLabel:SetPoint("TOPLEFT", pagesSlider, "BOTTOMLEFT", 0, -16)
retryDelayLabel:SetText("Retry Delay (ms)")

-- Retry delay slider (200–2000 ms, step 100)
local retryDelaySlider = CreateFrame("Slider", "OrctionRetryDelaySlider", auctionPanel, "OptionsSliderTemplate")
retryDelaySlider:SetWidth(200)
retryDelaySlider:SetPoint("TOPLEFT", retryDelayLabel, "BOTTOMLEFT", 0, -6)
retryDelaySlider:SetMinMaxValues(200, 2000)
retryDelaySlider:SetValueStep(100)
retryDelaySlider:SetValue(500)

getglobal("OrctionRetryDelaySliderLow"):SetText("200")
getglobal("OrctionRetryDelaySliderHigh"):SetText("2000")

local retryDelayValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
retryDelayValueText:SetPoint("LEFT", retryDelaySlider, "RIGHT", 10, 0)
retryDelayValueText:SetText("500")

retryDelaySlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() / 100 + 0.5) * 100
    retryDelayValueText:SetText(tostring(val))
    ORCTION_RETRY_DELAY = val / 1000
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.retryDelay = val
    end
end)

-- "Max Retries" label
local maxRetriesLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
maxRetriesLabel:SetPoint("TOPLEFT", retryDelaySlider, "BOTTOMLEFT", 0, -16)
maxRetriesLabel:SetText("Max Retries")

-- Max retries slider (0–5, step 1)
local maxRetriesSlider = CreateFrame("Slider", "OrctionMaxRetriesSlider", auctionPanel, "OptionsSliderTemplate")
maxRetriesSlider:SetWidth(200)
maxRetriesSlider:SetPoint("TOPLEFT", maxRetriesLabel, "BOTTOMLEFT", 0, -6)
maxRetriesSlider:SetMinMaxValues(0, 5)
maxRetriesSlider:SetValueStep(1)
maxRetriesSlider:SetValue(2)

getglobal("OrctionMaxRetriesSliderLow"):SetText("0")
getglobal("OrctionMaxRetriesSliderHigh"):SetText("5")

local maxRetriesValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
maxRetriesValueText:SetPoint("LEFT", maxRetriesSlider, "RIGHT", 10, 0)
maxRetriesValueText:SetText("2")

maxRetriesSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    maxRetriesValueText:SetText(tostring(val))
    ORCTION_MAX_RETRIES = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.maxRetries = val
    end
end)


-------------------------------------------------------------------------------
-- TAB 2: Post
-------------------------------------------------------------------------------

local postEnabledCheck = CreateFrame("CheckButton", "OrctionPostEnabledCheck", postPanel, "OptionsCheckButtonTemplate")
postEnabledCheck:SetPoint("TOPLEFT", postPanel, "TOPLEFT", 10, -10)
getglobal("OrctionPostEnabledCheckText"):SetText("Enable Post Features")

postEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.postEnabled = (this:GetChecked() == 1)
    end
end)

-- "Mail Open Delay" label
local mailDelayLabel = postPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mailDelayLabel:SetPoint("TOPLEFT", postEnabledCheck, "BOTTOMLEFT", 0, -14)
mailDelayLabel:SetText("Mail Open Delay (ms)")

-- Slider: 100–2000 ms, step 100
local mailDelaySlider = CreateFrame("Slider", "OrctionMailDelaySlider", postPanel, "OptionsSliderTemplate")
mailDelaySlider:SetWidth(200)
mailDelaySlider:SetPoint("TOPLEFT", mailDelayLabel, "BOTTOMLEFT", 0, -6)
mailDelaySlider:SetMinMaxValues(100, 2000)
mailDelaySlider:SetValueStep(100)
mailDelaySlider:SetValue(500)

getglobal("OrctionMailDelaySliderLow"):SetText("100")
getglobal("OrctionMailDelaySliderHigh"):SetText("2000")

local mailDelayValueText = postPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mailDelayValueText:SetPoint("LEFT", mailDelaySlider, "RIGHT", 10, 0)
mailDelayValueText:SetText("500")

mailDelaySlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() / 100 + 0.5) * 100
    mailDelayValueText:SetText(tostring(val))
    ORCTION_MAIL_OPEN_DELAY = val / 1000
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.mailOpenDelay = val
    end
end)

-- "Mail Open Retries" label
local mailRetriesLabel = postPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mailRetriesLabel:SetPoint("TOPLEFT", mailDelaySlider, "BOTTOMLEFT", 0, -16)
mailRetriesLabel:SetText("Mail Open Retries")

-- Slider: 0–5, step 1
local mailRetriesSlider = CreateFrame("Slider", "OrctionMailRetriesSlider", postPanel, "OptionsSliderTemplate")
mailRetriesSlider:SetWidth(200)
mailRetriesSlider:SetPoint("TOPLEFT", mailRetriesLabel, "BOTTOMLEFT", 0, -6)
mailRetriesSlider:SetMinMaxValues(0, 5)
mailRetriesSlider:SetValueStep(1)
mailRetriesSlider:SetValue(2)

getglobal("OrctionMailRetriesSliderLow"):SetText("0")
getglobal("OrctionMailRetriesSliderHigh"):SetText("5")

local mailRetriesValueText = postPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mailRetriesValueText:SetPoint("LEFT", mailRetriesSlider, "RIGHT", 10, 0)
mailRetriesValueText:SetText("2")

mailRetriesSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    mailRetriesValueText:SetText(tostring(val))
    ORCTION_MAIL_OPEN_RETRIES = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.mailOpenRetries = val
    end
end)

-------------------------------------------------------------------------------
-- TAB 3: Inventory
-------------------------------------------------------------------------------

local inventoryEnabledCheck = CreateFrame("CheckButton", "OrctionInventoryEnabledCheck", inventoryPanel, "OptionsCheckButtonTemplate")
inventoryEnabledCheck:SetPoint("TOPLEFT", inventoryPanel, "TOPLEFT", 10, -10)
getglobal("OrctionInventoryEnabledCheckText"):SetText("Enable Inventory Features")

inventoryEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.inventoryEnabled = (this:GetChecked() == 1)
    end
end)

local tooltipEnabledCheck = CreateFrame("CheckButton", "OrctionTooltipEnabledCheck", inventoryPanel, "OptionsCheckButtonTemplate")
tooltipEnabledCheck:SetPoint("TOPLEFT", inventoryEnabledCheck, "BOTTOMLEFT", 0, -6)
getglobal("OrctionTooltipEnabledCheckText"):SetText("Show vendor price on item tooltip")

tooltipEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.tooltipEnabled = (this:GetChecked() == 1)
    end
end)

-------------------------------------------------------------------------------
-- TAB 4: Data
-------------------------------------------------------------------------------

local dataSearchText = ""
local dataPage = 1
local dataPageSize = 10
local dataRows = {}

local function OrctionSettings_GetDaySlot()
    local day = tonumber(date("%j")) or 1
    return math.mod(day, 7) + 1
end

local function OrctionSettings_GetDataKeys()
    local keys = {}
    if OrctionDB and OrctionDB.priceHistory then
        for k, v in pairs(OrctionDB.priceHistory) do
            local name = v and v.name or ""
            if dataSearchText == "" or string.find(string.lower(name), string.lower(dataSearchText), 1, true) then
                table.insert(keys, k)
            end
        end
    end
    table.sort(keys)
    return keys
end

local function OrctionSettings_RefreshData()
    local keys = OrctionSettings_GetDataKeys()
    local total = table.getn(keys)
    local maxPage = math.max(1, math.ceil(total / dataPageSize))
    if dataPage > maxPage then dataPage = maxPage end
    if dataPage < 1 then dataPage = 1 end

    local startIdx = (dataPage - 1) * dataPageSize + 1
    local slot = OrctionSettings_GetDaySlot()

    for i = 1, dataPageSize do
        local row = dataRows[i]
        local idx = startIdx + i - 1
        if row and idx <= total then
            local key = keys[idx]
            local entry = OrctionDB.priceHistory[key]
            local pKey = "day" .. slot .. "Price"
            local cKey = "day" .. slot .. "Count"
            row.name:SetText(entry.name or "")
            row.key:SetText(key)
            row.price:SetText(tostring(entry[pKey] or 0))
            row.count:SetText(tostring(entry[cKey] or 0))
            row.frame:Show()
        elseif row then
            row.frame:Hide()
        end
    end

    if OrctionDataPageText then
        OrctionDataPageText:SetText("Page " .. dataPage .. " / " .. maxPage)
    end
end

local dataSearchBox = CreateFrame("EditBox", "OrctionDataSearchBox", dataPanel, "InputBoxTemplate")
dataSearchBox:SetWidth(180)
dataSearchBox:SetHeight(22)
dataSearchBox:SetPoint("TOPLEFT", dataPanel, "TOPLEFT", 10, -10)
dataSearchBox:SetAutoFocus(false)
dataSearchBox:SetScript("OnEnterPressed", function()
    dataSearchText = this:GetText() or ""
    dataPage = 1
    OrctionSettings_RefreshData()
    this:ClearFocus()
end)

local dataSearchBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
dataSearchBtn:SetWidth(60)
dataSearchBtn:SetHeight(22)
dataSearchBtn:SetPoint("LEFT", dataSearchBox, "RIGHT", 6, 0)
dataSearchBtn:SetText("Search")
dataSearchBtn:SetScript("OnClick", function()
    dataSearchText = dataSearchBox:GetText() or ""
    dataPage = 1
    OrctionSettings_RefreshData()
end)

local purgeBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
purgeBtn:SetWidth(90)
purgeBtn:SetHeight(22)
purgeBtn:SetPoint("LEFT", dataSearchBtn, "RIGHT", 6, 0)
purgeBtn:SetText("Purge Data")
purgeBtn:SetScript("OnClick", function()
    if OrctionDB then OrctionDB.priceHistory = {} end
    OrctionSettings_RefreshData()
end)

local analyzeBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
analyzeBtn:SetWidth(90)
analyzeBtn:SetHeight(22)
analyzeBtn:SetPoint("LEFT", purgeBtn, "RIGHT", 6, 0)
analyzeBtn:SetText("Analyze")
analyzeBtn:SetScript("OnClick", function()
    DEFAULT_CHAT_FRAME:AddMessage("Orction: analyze data not implemented")
end)

local headerName = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerName:SetPoint("TOPLEFT", dataPanel, "TOPLEFT", 10, -42)
headerName:SetText("Name")

local headerKey = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerKey:SetPoint("LEFT", headerName, "RIGHT", 160, 0)
headerKey:SetText("Key")

local headerPrice = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerPrice:SetPoint("LEFT", headerKey, "RIGHT", 140, 0)
headerPrice:SetText("Day Price")

local headerCount = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerCount:SetPoint("LEFT", headerPrice, "RIGHT", 60, 0)
headerCount:SetText("Count")

local rowsFrame = CreateFrame("Frame", nil, dataPanel)
rowsFrame:SetWidth(480)
rowsFrame:SetHeight(240)
rowsFrame:SetPoint("TOPLEFT", dataPanel, "TOPLEFT", 10, -60)

for i = 1, dataPageSize do
    local row = CreateFrame("Frame", nil, rowsFrame)
    row:SetWidth(480)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", rowsFrame, "TOPLEFT", 0, -(i - 1) * 20)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetWidth(150)
    name:SetJustifyH("LEFT")

    local key = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    key:SetPoint("LEFT", name, "RIGHT", 10, 0)
    key:SetWidth(130)
    key:SetJustifyH("LEFT")

    local price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    price:SetPoint("LEFT", key, "RIGHT", 10, 0)
    price:SetWidth(60)
    price:SetJustifyH("RIGHT")

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", price, "RIGHT", 10, 0)
    count:SetWidth(40)
    count:SetJustifyH("RIGHT")

    row.name = name
    row.key = key
    row.price = price
    row.count = count
    row.frame = row
    row:Hide()
    dataRows[i] = row
end

local prevBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
prevBtn:SetWidth(60)
prevBtn:SetHeight(20)
prevBtn:SetPoint("TOPLEFT", rowsFrame, "BOTTOMLEFT", 0, -8)
prevBtn:SetText("Prev")
prevBtn:SetScript("OnClick", function()
    dataPage = dataPage - 1
    OrctionSettings_RefreshData()
end)

local nextBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
nextBtn:SetWidth(60)
nextBtn:SetHeight(20)
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
nextBtn:SetText("Next")
nextBtn:SetScript("OnClick", function()
    dataPage = dataPage + 1
    OrctionSettings_RefreshData()
end)

OrctionDataPageText = dataPanel:CreateFontString("OrctionDataPageText", "OVERLAY", "GameFontHighlightSmall")
OrctionDataPageText:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)
OrctionDataPageText:SetText("Page 1 / 1")

-------------------------------------------------------------------------------
-- TAB 5: Credits
-------------------------------------------------------------------------------

local creditsLine1 = creditsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
creditsLine1:SetPoint("TOPLEFT", creditsPanel, "TOPLEFT", 14, -14)
creditsLine1:SetText("Orction by q concerned citizen of Azeroth")

local creditsLine2 = creditsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
creditsLine2:SetPoint("TOPLEFT", creditsLine1, "BOTTOMLEFT", 0, -8)
creditsLine2:SetText("Vendor sell prices provided by SellValue")

local creditsLine3 = creditsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
creditsLine3:SetPoint("TOPLEFT", creditsLine2, "BOTTOMLEFT", 0, -4)
creditsLine3:SetText("github.com/anzz1/SellValue")

-------------------------------------------------------------------------------
-- Clear Cache button (bottom-left of main frame)
-------------------------------------------------------------------------------

local clearCacheBtn = CreateFrame("Button", "OrctionClearCacheButton", OrctionFrame, "UIPanelButtonTemplate")
clearCacheBtn:SetWidth(80)
clearCacheBtn:SetHeight(22)
clearCacheBtn:SetPoint("BOTTOMLEFT", OrctionFrame, "BOTTOMLEFT", 14, 12)
clearCacheBtn:SetText("Clear Cache")

clearCacheBtn:SetScript("OnClick", function()
    if OrctionDB then
        OrctionDB.vendorPrices = {}
    end
    DEFAULT_CHAT_FRAME:AddMessage("Orction: cache cleared")
end)

-------------------------------------------------------------------------------
-- Apply saved settings to UI controls (called on frame OnShow)
-------------------------------------------------------------------------------

local function OrctionSettings_ApplyToUI()
    if not (OrctionDB and OrctionDB.settings) then return end
    local s = OrctionDB.settings

    -- Checkboxes (SetChecked expects 1/nil in 1.12)
    if s.auctionEnabled   then OrctionAuctionEnabledCheck:SetChecked(1)   else OrctionAuctionEnabledCheck:SetChecked(nil)   end
    if s.autoOpenTab      then OrctionAutoOpenTabCheck:SetChecked(1)      else OrctionAutoOpenTabCheck:SetChecked(nil)      end
    if s.postEnabled      then OrctionPostEnabledCheck:SetChecked(1)      else OrctionPostEnabledCheck:SetChecked(nil)      end
    if s.inventoryEnabled then OrctionInventoryEnabledCheck:SetChecked(1) else OrctionInventoryEnabledCheck:SetChecked(nil) end
    if s.tooltipEnabled   then OrctionTooltipEnabledCheck:SetChecked(1)  else OrctionTooltipEnabledCheck:SetChecked(nil)  end
    if s.titleCaseSearch  then OrctionTitleCaseSearchCheck:SetChecked(1) else OrctionTitleCaseSearchCheck:SetChecked(nil) end

    -- Sliders
    local pages = s.maxPages or 3
    pagesSlider:SetValue(pages)
    pagesValueText:SetText(tostring(pages))

    local rd = s.retryDelay or 500
    retryDelaySlider:SetValue(rd)
    retryDelayValueText:SetText(tostring(rd))

    local mr = s.maxRetries or 2
    maxRetriesSlider:SetValue(mr)
    maxRetriesValueText:SetText(tostring(mr))

    local md = s.mailOpenDelay or 500
    mailDelaySlider:SetValue(md)
    mailDelayValueText:SetText(tostring(md))

    local mrt = s.mailOpenRetries or 2
    mailRetriesSlider:SetValue(mrt)
    mailRetriesValueText:SetText(tostring(mrt))
end

OrctionFrame:SetScript("OnShow", function()
    OrctionSettings_ApplyToUI()
    OrctionSettings_RefreshData()
end)

-------------------------------------------------------------------------------
-- ADDON_LOADED: initialise OrctionDB.settings with defaults
-------------------------------------------------------------------------------

local settingsEventFrame = CreateFrame("Frame")
settingsEventFrame:RegisterEvent("ADDON_LOADED")
settingsEventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        -- Ensure top-level table exists (Database.lua may have created it)
        if not OrctionDB then
            OrctionDB = {}
        end
        -- Initialise settings with defaults, preserving any already-saved values
        if not OrctionDB.settings then
            OrctionDB.settings = {}
        end
        local s = OrctionDB.settings
        if s.auctionEnabled   == nil then s.auctionEnabled   = true  end
        if s.autoOpenTab      == nil then s.autoOpenTab      = true  end
        if s.postEnabled      == nil then s.postEnabled      = true  end
        if s.inventoryEnabled == nil then s.inventoryEnabled = true  end
        if s.tooltipEnabled   == nil then s.tooltipEnabled   = true  end
        if s.titleCaseSearch  == nil then s.titleCaseSearch  = true  end
        if s.maxPages         == nil then s.maxPages         = 3     end
        if s.exactMatch       == nil then s.exactMatch       = true  end
        if s.retryDelay       == nil then s.retryDelay       = 500   end
        if s.maxRetries       == nil then s.maxRetries       = 2     end
        if s.mailOpenDelay    == nil then s.mailOpenDelay    = 500   end
        if s.mailOpenRetries  == nil then s.mailOpenRetries  = 2     end

        -- Sync exact match checkbox
        if OrctionExactMatchCheck then
            if s.exactMatch then OrctionExactMatchCheck:SetChecked(1)
            else                 OrctionExactMatchCheck:SetChecked(nil) end
        end

        -- Sync globals used by Orction.lua and OrctionPostbox.lua
        ORCTION_MAX_PAGES         = s.maxPages
        ORCTION_RETRY_DELAY       = s.retryDelay / 1000
        ORCTION_MAX_RETRIES       = s.maxRetries
        ORCTION_MAIL_OPEN_DELAY   = s.mailOpenDelay / 1000
        ORCTION_MAIL_OPEN_RETRIES = s.mailOpenRetries

        -- Ensure persistent tables exist
        if not OrctionDB.vendorPrices then OrctionDB.vendorPrices = {} end
        if not OrctionDB.watchlist     then OrctionDB.watchlist     = {} end
    end
end)

-------------------------------------------------------------------------------
-- Default to tab 1 on first open
-------------------------------------------------------------------------------

OrctionSettings_SelectTab(1)

-------------------------------------------------------------------------------
-- Slash command  /orction  — toggle the settings window
-------------------------------------------------------------------------------

SLASH_ORCTION1 = "/orction"
SlashCmdList["ORCTION"] = function()
    if OrctionFrame:IsShown() then
        OrctionFrame:Hide()
    else
        OrctionFrame:Show()
    end
end
